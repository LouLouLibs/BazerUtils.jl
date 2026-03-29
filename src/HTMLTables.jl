# --------------------------------------------------------------------------------------------------
# HTML Table Parsing
#
# Parse HTML tables into DataFrames, handling colspan/rowspan and multi-level headers.
# Replaces PyCall/pandas read_html for Julia-native HTML scraping.
#
# Public API:
#   read_html_tables(source; match=nothing, flatten=nothing) -> Vector{DataFrame}
#
# Future extension points (not implemented):
#   - attrs kwarg: filter tables by HTML attributes (id, class)
#   - header kwarg: explicit row indices for headers (override auto-detection)
#   - skiprows kwarg: skip specific rows
#   - displayed_only kwarg: filter out display:none elements
#   - Type inference: auto-detect numeric columns
# --------------------------------------------------------------------------------------------------

using Gumbo
using Cascadia
using HTTP
using DataFrames


# --------------------------------------------------------------------------------------------------
# Text extraction
# --------------------------------------------------------------------------------------------------

"""Extract text from an HTML node, converting <br> to spaces and stripping <style> content."""
function _cell_text(node)::String
    if node isa HTMLText
        return node.text
    elseif node isa HTMLElement
        tag = Gumbo.tag(node)
        tag == :br && return " "
        tag == :style && return ""
        return join((_cell_text(c) for c in Gumbo.children(node)), "")
    end
    return ""
end


# --------------------------------------------------------------------------------------------------
# Row classification
# --------------------------------------------------------------------------------------------------

"""
A parsed cell: text content + HTML attributes needed for span expansion.
"""
struct ParsedCell
    text::String
    is_header::Bool
    colspan::Int
    rowspan::Int
end

"""Extract ParsedCells from a <tr> element."""
function _parse_row(tr)::Vector{ParsedCell}
    cells = ParsedCell[]
    for child in Gumbo.children(tr)
        child isa HTMLElement || continue
        t = Gumbo.tag(child)
        (t == :th || t == :td) || continue
        text = strip(_cell_text(child))
        cs = parse(Int, get(child.attributes, "colspan", "1"))
        rs = parse(Int, get(child.attributes, "rowspan", "1"))
        push!(cells, ParsedCell(text, t == :th, cs, rs))
    end
    return cells
end

"""
Classify table rows into header rows and body rows.

Rules:
- <thead> rows -> header
- <tbody> rows -> body (multiple <tbody> concatenated)
- <tfoot> rows -> appended to body
- No <thead>: consecutive all-<th> rows from top of body -> moved to header
"""
function _classify_rows(table_elem)
    header_rows = Vector{Vector{ParsedCell}}()
    body_rows = Vector{Vector{ParsedCell}}()
    has_thead = false

    for child in Gumbo.children(table_elem)
        child isa HTMLElement || continue
        t = Gumbo.tag(child)
        if t == :thead
            has_thead = true
            for tr in Gumbo.children(child)
                tr isa HTMLElement && Gumbo.tag(tr) == :tr && push!(header_rows, _parse_row(tr))
            end
        elseif t == :tbody
            for tr in Gumbo.children(child)
                tr isa HTMLElement && Gumbo.tag(tr) == :tr && push!(body_rows, _parse_row(tr))
            end
        elseif t == :tfoot
            for tr in Gumbo.children(child)
                tr isa HTMLElement && Gumbo.tag(tr) == :tr && push!(body_rows, _parse_row(tr))
            end
        elseif t == :tr
            # bare <tr> not inside thead/tbody/tfoot
            push!(body_rows, _parse_row(child))
        end
    end

    # If no <thead>, scan top of body for consecutive all-<th> rows
    if !has_thead
        while !isempty(body_rows) && all(c -> c.is_header, body_rows[1])
            push!(header_rows, popfirst!(body_rows))
        end
    end

    return header_rows, body_rows
end


# --------------------------------------------------------------------------------------------------
# Span expansion
# --------------------------------------------------------------------------------------------------

"""
Expand colspan/rowspan into a filled text grid.

Takes a flat vector of ParsedCell rows, returns a Matrix{Union{String,Nothing}}
where spanned cells are duplicated into all positions they cover.
"""
function _expand_spans(rows::Vector{Vector{ParsedCell}})
    isempty(rows) && return Matrix{Union{String,Nothing}}(nothing, 0, 0)

    # Use a Dict-based sparse grid that grows as needed
    grid = Dict{Tuple{Int,Int}, String}()
    max_row = 0
    max_col = 0

    for (ri, row) in enumerate(rows)
        col = 1
        for cell in row
            # Find next empty slot in this row
            while haskey(grid, (ri, col))
                col += 1
            end
            # Fill the rowspan x colspan rectangle
            for dr in 0:(cell.rowspan - 1)
                for dc in 0:(cell.colspan - 1)
                    r, c = ri + dr, col + dc
                    grid[(r, c)] = cell.text
                    max_row = max(max_row, r)
                    max_col = max(max_col, c)
                end
            end
            col += cell.colspan
        end
    end

    # Convert to dense matrix
    result = Matrix{Union{String,Nothing}}(nothing, max_row, max_col)
    for ((r, c), text) in grid
        result[r, c] = text
    end

    return result
end


# --------------------------------------------------------------------------------------------------
# Table parsing
# --------------------------------------------------------------------------------------------------

"""Deduplicate column names by appending .1, .2, etc."""
function _dedup_names(names_vec)
    seen = Dict{String,Int}()
    result = Vector{String}(undef, length(names_vec))
    for (i, name) in enumerate(names_vec)
        if haskey(seen, name)
            seen[name] += 1
            result[i] = "$(name).$(seen[name])"
        else
            seen[name] = 0
            result[i] = name
        end
    end
    return result
end

"""
Parse a single <table> element into a DataFrame.

Returns nothing if the table has no data rows.
"""
function _parse_table(table_elem; flatten::Union{Nothing,Symbol}=nothing)
    header_rows, body_rows = _classify_rows(table_elem)

    # Combine all rows for span expansion, then split back
    all_rows = vcat(header_rows, body_rows)
    isempty(all_rows) && return nothing

    grid = _expand_spans(all_rows)
    nrows_total, ncols = size(grid)
    ncols == 0 && return nothing

    n_header = length(header_rows)
    n_body = nrows_total - n_header

    n_body <= 0 && return nothing

    # Build column names
    if n_header == 0
        col_names = ["Column$i" for i in 1:ncols]
    elseif n_header == 1
        col_names = [something(grid[1, c], "Column$c") for c in 1:ncols]
    else
        # Multi-level headers: build tuple representation then convert to strings
        raw_tuples = [Tuple(something(grid[r, c], "") for r in 1:n_header) for c in 1:ncols]

        if flatten == :join
            col_names = [join(filter(!isempty, t), "_") for t in raw_tuples]
        elseif flatten == :last
            col_names = [String(t[end]) for t in raw_tuples]
        else
            # Default: string representation of tuple, e.g. "(A, a)"
            col_names = ["(" * join(t, ", ") * ")" for t in raw_tuples]
        end
    end

    # Apply flatten for single-level headers (no-op, already strings)

    # Deduplicate
    col_names = _dedup_names(col_names)

    # Build DataFrame from body rows
    cols = Vector{Vector{Union{String,Missing}}}(undef, ncols)
    for c in 1:ncols
        vals = Vector{Union{String,Missing}}(undef, n_body)
        for (idx, r) in enumerate((n_header + 1):nrows_total)
            val = grid[r, c]
            vals[idx] = (val === nothing || val == "") ? missing : val
        end
        cols[c] = vals
    end

    # Construct DataFrame preserving column order
    df = DataFrame()
    for (c, name) in enumerate(col_names)
        df[!, name] = cols[c]
    end

    return df
end


# --------------------------------------------------------------------------------------------------
# Public API
# --------------------------------------------------------------------------------------------------

"""
    read_html_tables(source::String; match=nothing, flatten=nothing) -> Vector{DataFrame}

Parse all HTML tables from a URL or raw HTML string into DataFrames.

# Arguments
- `source`: URL (starting with "http") or raw HTML string
- `match`: optional `Regex` -- only return tables whose text content matches
- `flatten`: controls multi-level header column names (DataFrames requires String column names)
  - `nothing` (default): string representation of tuples, e.g. `"(A, a)"`
  - `:join`: join levels with `"_"`, e.g. `"A_a"`
  - `:last`: last header level only, e.g. `"a"`

# Returns
Vector of DataFrames with String/Missing columns. Empty tables are skipped.

# Examples
```julia
dfs = read_html_tables("https://en.wikipedia.org/wiki/List_of_Alabama_state_parks")
dfs = read_html_tables(html_string; match=r"Name"i, flatten=:last)
```
"""
function read_html_tables(source::String; match::Union{Nothing,Regex}=nothing,
                          flatten::Union{Nothing,Symbol}=nothing)
    # Fetch HTML
    html = if startswith(source, "http://") || startswith(source, "https://")
        String(HTTP.get(source).body)
    else
        source
    end

    doc = parsehtml(html)
    tables = eachmatch(Selector("table"), doc.root)

    dfs = DataFrame[]
    for table_elem in tables
        df = _parse_table(table_elem; flatten=flatten)
        df === nothing && continue

        # Filter by match regex if provided
        if match !== nothing
            table_text = _cell_text(table_elem)
            occursin(match, table_text) || continue
        end

        push!(dfs, df)
    end

    return dfs
end
# --------------------------------------------------------------------------------------------------
