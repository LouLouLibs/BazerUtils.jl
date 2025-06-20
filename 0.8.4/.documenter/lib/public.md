
# Public Interface {#Public-Interface}

## `BazerUtils` Module {#BazerUtils-Module}
<details class='jldocstring custom-block' open>
<summary><a id='BazerUtils.custom_logger-Tuple{BazerUtils.LogSink}' href='#BazerUtils.custom_logger-Tuple{BazerUtils.LogSink}'><span class="jlbinding">BazerUtils.custom_logger</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
custom_logger(filename; kw...)
```


**Arguments**
- `filename::AbstractString`: base name for the log files
  
- `output_dir::AbstractString=./log/`: name of directory where log files are written
  
- `filtered_modules_specific::Vector{Symbol}=nothing`: which modules do you want to filter out of logging (only for info and stdout) Some packages just write too much log ... filter them out but still be able to check them out in other logs
  
- `filtered_modules_all::Vector{Symbol}=nothing`: which modules do you want to filter out of logging (across all logs)  Examples could be TranscodingStreams (noticed that it writes so much to logs that it sometimes slows down I/O)
  
- `file_loggers::Union{Symbol, Vector{Symbol}}=[:error, :warn, :info, :debug]`: which file logger to register 
  
- `log_date_format::AbstractString="yyyy-mm-dd"`: time stamp format at beginning of each logged lines for dates
  
- `log_time_format::AbstractString="HH:MM:SS"`: time stamp format at beginning of each logged lines for times
  
- `displaysize::Tuple{Int,Int}=(50,100)`: how much to show on log (same for all logs for now!)
  
- `log_format::Symbol=:log4j`: how to format the log files; I have added an option for pretty (all or nothing for now)
  
- `log_format_stdout::Symbol=:pretty`: how to format the stdout; default is pretty
  
- `overwrite::Bool=false`: do we overwrite previously created log files
  

The custom_logger function creates four files in `output_dir`for four different levels of logging:     from least to most verbose:`filename.info.log.jl`,`filename.warn.log.jl`,`filename.debug.log.jl`,`filename.full.log.jl`The debug logging offers the option to filter messages from specific packages (some packages are particularly verbose) using the`filter` optional argument The full logging gets all of the debug without any of the filters. Info and warn log the standard info and warning level logging messages.

Note that the default **overwrites** old log files (specify overwrite=false to avoid this).


<Badge type="info" class="source-link" text="source"><a href="https://github.com/LouLouLibs/BazerUtils.jl/blob/fe00236d56bfb22fc2abb693a449dd3c03afb8ab/src/CustomLogger.jl#L72-L98" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='BazerUtils.read_jsonl-Tuple{IO}' href='#BazerUtils.read_jsonl-Tuple{IO}'><span class="jlbinding">BazerUtils.read_jsonl</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
read_jsonl(source::Union{AbstractString, IO}; dict_of_json::Bool=false) -> Vector
```


Read a JSON Lines (.jsonl) file or stream and return all records as a vector.

This function reads the entire file or IO stream into memory at once, parsing each line as a separate JSON value. Empty lines are automatically skipped.

**Arguments**
- `source::Union{AbstractString, IO}`: Path to the JSON Lines file to read, or an IO stream (e.g., IOBuffer, file handle).
  
- `dict_of_json::Bool=false`: If `true` and the parsed type is `JSON3.Object`, convert each record to a `Dict{Symbol,Any}`.
  

**Returns**
- `Vector`: A vector containing all parsed JSON values from the file or stream.
  

**Examples**

```julia
# Read all records from a JSONL file
data = read_jsonl("data.jsonl")

# Read from an IOBuffer
buf = IOBuffer("{"a":1}
{"a":2}
")
data = read_jsonl(buf)

# Convert JSON3.Object records to Dict
data = read_jsonl("data.jsonl"; dict_of_json=true)

# Access individual records
first_record = data[1]
println("First record ID: ", first_record.id)
```


**Notes**
- This function loads all data into memory, so it may not be suitable for very large files.
  
- For large files, consider using `stream_jsonl()` for streaming processing.
  
- The function will throw an error if the JSON on any line is malformed.
  
- The path must refer to an existing regular file.
  
- If `dict_of_json=true`, all records must be of type `JSON3.Object`.
  

**See Also**
- [`stream_jsonl`](/man/read_jsonl#stream_jsonl): For memory-efficient streaming of large JSONL files.
  


<Badge type="info" class="source-link" text="source"><a href="https://github.com/LouLouLibs/BazerUtils.jl/blob/fe00236d56bfb22fc2abb693a449dd3c03afb8ab/src/JSONLines.jl#L16-L59" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='BazerUtils.stream_jsonl-Tuple{IO}' href='#BazerUtils.stream_jsonl-Tuple{IO}'><span class="jlbinding">BazerUtils.stream_jsonl</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
stream_jsonl(source::Union{AbstractString, IO}; T::Type=JSON3.Object{}) -> Channel
```


Create a lazy iterator (Channel) for reading JSON Lines files record by record.

This function returns a Channel that yields JSON objects one at a time without loading the entire file into memory. This is memory-efficient for processing large JSONL files. Each parsed record is checked to match the specified type `T` (default: `JSON3.Object{}`). If a record does not match `T`, an error is thrown.

**Arguments**
- `source::Union{AbstractString, IO}`: Path to the JSON Lines file to read, or an IO stream (e.g., IOBuffer, file handle).
  
- `T::Type=JSON3.Object{}`: The expected type for each parsed record. Use `T=Any` to allow mixed types.
  

**Returns**
- `Channel{T}`: A channel that yields parsed JSON objects one at a time.
  

**Examples**

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
buf = IOBuffer("{"a":1}
{"a":2}
")
for record in stream_jsonl(buf)
    @show record
end

# Allow mixed types
for record in stream_jsonl("data.jsonl"; T=Any)
    @show record
end
```


**Notes**
- This is a lazy iterator: records are only read and parsed when requested.
  
- Memory usage remains constant regardless of file size.
  
- Empty lines are automatically skipped.
  
- The Channel is automatically closed when the file or stream is fully read or an error occurs.
  
- If JSON parsing fails on any line, the Channel will close and propagate the error.
  
- For file paths, the file remains open for the lifetime of the channel.
  
- For IO streams, the user is responsible for keeping the IO open while consuming the channel.
  
- If a parsed record does not match `T`, an error is thrown. Use `T=Any` to allow mixed types.
  

**See Also**
- [`read_jsonl`](/man/read_jsonl#read_jsonl): For loading entire JSONL files into memory at once.
  


<Badge type="info" class="source-link" text="source"><a href="https://github.com/LouLouLibs/BazerUtils.jl/blob/fe00236d56bfb22fc2abb693a449dd3c03afb8ab/src/JSONLines.jl#L93-L149" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='BazerUtils.write_jsonl-Tuple{AbstractString, Any, BazerUtils.TableIteration}' href='#BazerUtils.write_jsonl-Tuple{AbstractString, Any, BazerUtils.TableIteration}'><span class="jlbinding">BazerUtils.write_jsonl</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
write_jsonl(filename, data; compress=false)
```


Write an iterable of JSON-serializable values to a JSON Lines file.
- `filename`: Output file path (if ends with `.gz` or `compress=true`, writes gzip-compressed)
  
- `data`: An iterable (e.g., Vector, generator) of values (Dict, Array, String, Number, Bool, nothing, etc.)
  

Returns the filename.

**Example**

```julia
write_jsonl("out.jsonl", [Dict("a"=>1), Dict("b"=>2)])
write_jsonl("out.jsonl.gz", (Dict("i"=>i) for i in 1:10^6))
```



<Badge type="info" class="source-link" text="source"><a href="https://github.com/LouLouLibs/BazerUtils.jl/blob/fe00236d56bfb22fc2abb693a449dd3c03afb8ab/src/JSONLines.jl#L203-L218" target="_blank" rel="noreferrer">source</a></Badge>

</details>

