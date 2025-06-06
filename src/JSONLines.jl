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

Read a JSON Lines (.jsonl) file or stream and return all records as a vector.

This function reads the entire file or IO stream into memory at once, parsing each line as a separate
JSON value. Empty lines are automatically skipped.

# Arguments
- `source::Union{AbstractString, IO}`: Path to the JSON Lines file to read, or an IO stream (e.g., IOBuffer, file handle).
- `dict_of_json::Bool=false`: If `true` and the parsed type is `JSON3.Object`, convert each record to a `Dict{Symbol,Any}`.

# Returns
- `Vector`: A vector containing all parsed JSON values from the file or stream.

# Examples
```julia
# Read all records from a JSONL file
data = read_jsonl("data.jsonl")

# Read from an IOBuffer
buf = IOBuffer("$(JSON3.write(Dict(:a=>1)))\n$(JSON3.write(Dict(:a=>2)))\n")
data = read_jsonl(buf)

# Convert JSON3.Object records to Dict
data = read_jsonl("data.jsonl"; dict_of_json=true)

# Access individual records
first_record = data[1]
println("First record ID: ", first_record.id)
```

# Notes
- This function loads all data into memory, so it may not be suitable for very large files.
- For large files, consider using `stream_jsonl()` for streaming processing.
- The function will throw an error if the JSON on any line is malformed.
- The path must refer to an existing regular file.
- If `dict_of_json=true`, all records must be of type `JSON3.Object`.

# See Also
- [`stream_jsonl`](@ref): For memory-efficient streaming of large JSONL files.
"""
function read_jsonl(io::IO; dict_of_json::Bool=false)
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
    @show T
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

Create a lazy iterator (Channel) for reading JSON Lines files record by record.

This function returns a Channel that yields JSON objects one at a time without loading
the entire file into memory. This is memory-efficient for processing large JSONL files.
Each parsed record is checked to match the specified type `T` (default: `JSON3.Object{}`).
If a record does not match `T`, an error is thrown.

# Arguments
- `source::Union{AbstractString, IO}`: Path to the JSON Lines file to read, or an IO stream (e.g., IOBuffer, file handle).
- `T::Type=JSON3.Object{}`: The expected type for each parsed record. Use `T=Any` to allow mixed types.

# Returns
- `Channel{T}`: A channel that yields parsed JSON objects one at a time.

# Examples
```julia
# Process records one at a time (memory efficient)
for record in stream_jsonl("large_file.jsonl")
    println("Processing record: ", record.id)
end

# Collect first N records
first_10 = collect(Iterators.take(stream_jsonl("data.jsonl"), 10))

# Filter and process
filtered_records = [r for r in stream_jsonl("data.jsonl") if r.score > 0.5]

# Stream from an IOBuffer
buf = IOBuffer("$(JSON3.write(Dict(:a=>1)))\n$(JSON3.write(Dict(:a=>2)))\n")
for record in stream_jsonl(buf)
    @show record
end

# Allow mixed types
for record in stream_jsonl("data.jsonl"; T=Any)
    @show record
end
```

# Notes
- This is a lazy iterator: records are only read and parsed when requested.
- Memory usage remains constant regardless of file size.
- Empty lines are automatically skipped.
- The Channel is automatically closed when the file or stream is fully read or an error occurs.
- If JSON parsing fails on any line, the Channel will close and propagate the error.
- For file paths, the file remains open for the lifetime of the channel.
- For IO streams, the user is responsible for keeping the IO open while consuming the channel.
- If a parsed record does not match `T`, an error is thrown. Use `T=Any` to allow mixed types.

# See Also
- [`read_jsonl`](@ref): For loading entire JSONL files into memory at once.
"""
function stream_jsonl(io::IO; T::Type=JSON3.Object{})
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
"""
    write_jsonl(filename, data; compress=false)

Write an iterable of JSON-serializable values to a JSON Lines file.

- `filename`: Output file path (if ends with `.gz` or `compress=true`, writes gzip-compressed)
- `data`: An iterable (e.g., Vector, generator) of values (Dict, Array, String, Number, Bool, nothing, etc.)

Returns the filename.

# Example
```julia
write_jsonl("out.jsonl", [Dict("a"=>1), Dict("b"=>2)])
write_jsonl("out.jsonl.gz", (Dict("i"=>i) for i in 1:10^6))
```
"""
function write_jsonl(filename::AbstractString, data; compress::Bool=false)
    dir = dirname(filename)
    if !isdir(dir)
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
