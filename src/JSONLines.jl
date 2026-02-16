# --------------------------------------------------------------------------------------------------

# JSONLines.jl

# Function to naturally parse json lines files
# --------------------------------------------------------------------------------------------------


# --------------------------------------------------------------------------------------------------
# Exported function
# JSONLines
# --------------------------------------------------------------------------------------------------


# --------------------------------------------------------------------------------------------------
"""
    read_jsonl(source::Union{AbstractString, IO}; dict_of_json::Bool=false) -> Vector

!!! warning "Deprecated"
    `read_jsonl` is deprecated. Use `JSON.parse(source; jsonlines=true)` from
    [JSON.jl](https://github.com/JuliaIO/JSON.jl) v1 instead.

Read a JSON Lines (.jsonl) file or stream and return all records as a vector.

Each line is parsed as a separate JSON value. Empty lines are skipped.

# Arguments
- `source::Union{AbstractString, IO}`: Path to a JSONL file, or an IO stream.
- `dict_of_json::Bool=false`: If `true` and the parsed type is `JSON3.Object`, convert each record to a `Dict{Symbol,Any}`.

# Returns
- `Vector`: A vector of parsed JSON values.
"""
function read_jsonl(io::IO; dict_of_json::Bool=false)
    Base.depwarn("`read_jsonl` is deprecated. Use `JSON.parse(io; jsonlines=true)` from JSON.jl v1 instead.", :read_jsonl)
    lines = collect(eachline(io))
    nonempty_lines = filter(l -> !isempty(strip(l)), lines)
    isempty(nonempty_lines) && return []

    first_val = JSON3.read(nonempty_lines[1])
    T = typeof(first_val)
    results = Vector{T}(undef, length(nonempty_lines))
    results[1] = first_val

    for (i, line) in enumerate(nonempty_lines[2:end])
        results[i+1] = JSON3.read(line)
    end
    if dict_of_json && T <: JSON3.Object{}
        results = [_dict_of_json3(r) for r in results]
    end

    return results
end

function read_jsonl(filename::AbstractString; kwargs...)
    if !isfile(filename)
        throw(ArgumentError("File does not exist or is not a regular file: $filename"))
    end
    open(filename, "r") do io
        return read_jsonl(io; kwargs...)
    end
end
# --------------------------------------------------------------------------------------------------


# --------------------------------------------------------------------------------------------------
# Using lazy evaluation with generators
# For very large files, you can create a generator that yields records on demand:
"""
    stream_jsonl(source::Union{AbstractString, IO}; T::Type=JSON3.Object{}) -> Channel

!!! warning "Deprecated"
    `stream_jsonl` is deprecated. Use `JSON.parse(source; jsonlines=true)` from
    [JSON.jl](https://github.com/JuliaIO/JSON.jl) v1 instead.

Create a lazy Channel iterator for reading JSON Lines files record by record.

# Arguments
- `source::Union{AbstractString, IO}`: Path to a JSONL file, or an IO stream.
- `T::Type=JSON3.Object{}`: Expected type for each record. Use `T=Any` for mixed types.

# Returns
- `Channel{T}`: A channel yielding parsed JSON objects one at a time.
"""
function stream_jsonl(io::IO; T::Type=JSON3.Object{})
    Base.depwarn("`stream_jsonl` is deprecated. Use `JSON.parse(io; jsonlines=true)` from JSON.jl v1 instead.", :stream_jsonl)
    lines = Iterators.filter(l -> !isempty(strip(l)), eachline(io))
    return Channel{T}() do ch
        for line in lines
            val = JSON3.read(line)
            if !isa(val, T)
                throw(ArgumentError("Parsed value of type $(typeof(val)) does not match expected type $T;\nTry specifying T::Any"))
            end
            put!(ch, val)
        end
    end
end


function stream_jsonl(filename::AbstractString; T::Type=JSON3.Object{})
    Base.depwarn("`stream_jsonl` is deprecated. Use `JSON.parse(filename; jsonlines=true)` from JSON.jl v1 instead.", :stream_jsonl)
    if !isfile(filename)
        throw(ArgumentError("File does not exist or is not a regular file: $filename"))
    end
    return Channel{T}() do ch
        open(filename, "r") do io
            for line in eachline(io)
                if isempty(strip(line))
                    continue
                end
                val = JSON3.read(line)
                if !isa(val, T)
                    throw(ArgumentError("Parsed value of type $(typeof(val)) does not match expected type $T"))
                end
                put!(ch, val)
            end
        end
    end
end
# --------------------------------------------------------------------------------------------------


# --------------------------------------------------------------------------------------------------
abstract type IterationStyle end
struct TableIteration <: IterationStyle end
struct DirectIteration <: IterationStyle end

function iteration_style(x)
    # Only use table iteration for proper table types
    if (Tables.istable(x) && !isa(x, AbstractVector) && !isa(x, AbstractDict))
        TableIteration()
    else
        DirectIteration()
    end
end


function write_jsonl(filename::AbstractString, data; kwargs...)
    Base.depwarn("`write_jsonl` is deprecated. Use `JSON.json(filename, data; jsonlines=true)` from JSON.jl v1 instead.", :write_jsonl)
    write_jsonl(filename, data, iteration_style(data); kwargs...)
end

"""
    write_jsonl(filename, data; compress=false)

!!! warning "Deprecated"
    `write_jsonl` is deprecated. Use `JSON.json(filename, data; jsonlines=true)` from
    [JSON.jl](https://github.com/JuliaIO/JSON.jl) v1 instead.

Write an iterable of JSON-serializable values to a JSON Lines file.

# Arguments
- `filename`: Output file path (writes gzip-compressed if ends with `.gz` or `compress=true`)
- `data`: An iterable of JSON-serializable values
- `compress::Bool=false`: Force gzip compression

# Returns
The filename.
"""
function write_jsonl(filename::AbstractString, data, ::TableIteration; compress::Bool=false)
    dir = dirname(filename)
    if !isempty(dir) && !isdir(dir)
        throw(ArgumentError("Directory does not exist: $dir"))
    end
    isgz = compress || endswith(filename, ".gz")
    openf = isgz ? x->CodecZlib.GzipCompressorStream(open(x, "w")) : x->open(x, "w")
    io = openf(filename)
    try
        for value in Tables.namedtupleiterator(data)
            JSON3.write(io, value)
            write(io, '\n')
        end
    finally
        close(io)
    end
    return filename
end

function write_jsonl(filename::AbstractString, data, ::DirectIteration; compress::Bool=false)
    dir = dirname(filename)
    if !isempty(dir) && !isdir(dir)
        throw(ArgumentError("Directory does not exist: $dir"))
    end
    isgz = compress || endswith(filename, ".gz")
    openf = isgz ? x->CodecZlib.GzipCompressorStream(open(x, "w")) : x->open(x, "w")
    io = openf(filename)
    try
        for value in data
            JSON3.write(io, value)
            write(io, '\n')
        end
    finally
        close(io)
    end
    return filename
end
# --------------------------------------------------------------------------------------------------


# --------------------------------------------------------------------------------------------------
"""
    _dict_of_json3(obj::JSON3.Object) -> Dict{Symbol, Any}

Recursively convert a `JSON3.Object` (from JSON3.jl) into a standard Julia `Dict` with `Symbol` keys.

This function traverses the input `JSON3.Object`, converting all keys to `Symbol` and recursively converting any nested `JSON3.Object` values. Non-object values are left unchanged.

# Arguments
- `obj::JSON3.Object`: The JSON3 object to convert.

# Returns
- `Dict{Symbol, Any}`: A Julia dictionary with symbol keys and values converted recursively.

# Notes
- This function is intended for internal use and is not exported.
- Useful for converting parsed JSON3 objects into standard Julia dictionaries for easier manipulation.
"""
function _dict_of_json3(d::JSON3.Object{})
    result = Dict{Symbol, Any}()
    for (k, v) in d
        result[Symbol(k)] = v isa JSON3.Object{} ? _dict_of_json3(v) : v
    end
    return result
end
# --------------------------------------------------------------------------------------------------
