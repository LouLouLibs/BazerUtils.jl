# Reading HTML Tables

Parse HTML tables into DataFrames — a Julia-native replacement for pandas' `read_html`.

---

## Quick Start

```julia
using BazerUtils

# From a URL
dfs = read_html_tables("https://en.wikipedia.org/wiki/List_of_Alabama_state_parks")

# From a raw HTML string
dfs = read_html_tables("<table><tr><th>A</th></tr><tr><td>1</td></tr></table>")
```

`read_html_tables` returns a `Vector{DataFrame}` — one per `<table>` element found.

---

## API

```@docs
read_html_tables
```

---

## Keyword Arguments

### `match`

Pass a `Regex` to keep only tables whose text content matches:

```julia
dfs = read_html_tables(url; match=r"Population"i)
```

### `flatten`

Controls how multi-level headers (multiple `<thead>` rows) become column names.
DataFrames requires `String` column names, so multi-level tuples are flattened:

| Value | Column name example | Description |
|:------|:--------------------|:------------|
| `nothing` (default) | `"(Region, Name)"` | Tuple string representation |
| `:join` | `"Region_Name"` | Levels joined with `_` |
| `:last` | `"Name"` | Last header level only |

```julia
dfs = read_html_tables(html; flatten=:join)
```

---

## How It Works

1. **Fetch**: URLs (starting with `http`) are downloaded via `HTTP.jl`; raw strings are parsed directly.
2. **Parse**: HTML is parsed with `Gumbo.jl`; `<table>` elements are selected with `Cascadia.jl`.
3. **Classify rows**: `<thead>` rows become headers, `<tbody>`/`<tfoot>` rows become body data. Without an explicit `<thead>`, consecutive all-`<th>` rows at the top are promoted to headers.
4. **Expand spans**: `colspan` and `rowspan` attributes are expanded into a dense grid (same algorithm as pandas' `_expand_colspan_rowspan`).
5. **Build DataFrame**: Empty cells become `missing`. Duplicate column names get `.1`, `.2` suffixes.

---

## Examples

### Filter tables by content

```julia
# Only tables mentioning "GDP"
dfs = read_html_tables(url; match=r"GDP"i)
```

### Multi-level headers

```julia
html = """
<table>
  <thead>
    <tr><th colspan="2">Region</th></tr>
    <tr><th>Name</th><th>Pop</th></tr>
  </thead>
  <tbody>
    <tr><td>East</td><td>100</td></tr>
  </tbody>
</table>
"""

read_html_tables(html; flatten=:join)
# 1×2 DataFrame: columns "Region_Name", "Region_Pop"
```

### Tables with colspan/rowspan

Spanned cells are duplicated into every position they cover, so the resulting DataFrame has a regular rectangular shape with no gaps.

---

## See Also

- [`Gumbo.jl`](https://github.com/JuliaWeb/Gumbo.jl): HTML parser
- [`Cascadia.jl`](https://github.com/Algocircle/Cascadia.jl): CSS selector engine
- [`HTTP.jl`](https://github.com/JuliaWeb/HTTP.jl): HTTP client
- [`DataFrames.jl`](https://github.com/JuliaData/DataFrames.jl): Tabular data
