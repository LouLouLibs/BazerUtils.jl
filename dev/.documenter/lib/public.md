
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


<Badge type="info" class="source-link" text="source"><a href="https://github.com/LouLouLibs/BazerUtils.jl/blob/b22675888ad7af975c9597aa5a1da4df67626d3e/src/CustomLogger.jl#L72-L98" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='BazerUtils.read_jsonl-Tuple{IO}' href='#BazerUtils.read_jsonl-Tuple{IO}'><span class="jlbinding">BazerUtils.read_jsonl</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
read_jsonl(source::Union{AbstractString, IO}) -> Vector
```


Read a JSON Lines (.jsonl) file or stream and return all records as a vector.

This function reads the entire file or IO stream into memory at once, parsing each line as a separate JSON value. Empty lines are automatically skipped.

**Arguments**
- `source::Union{AbstractString, IO}`: Path to the JSON Lines file to read, or an IO stream (e.g., IOBuffer, file handle).
  

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

# Access individual records
first_record = data[1]
println("First record ID: ", first_record.id)
```


**Notes**
- This function loads all data into memory, so it may not be suitable for very large files.
  
- For large files, consider using `stream_jsonl()` for streaming processing.
  
- The function will throw an error if the JSON on any line is malformed.
  
- The path must refer to an existing regular file.
  

**See Also**
- [`stream_jsonl`](/man/read_jsonl#stream_jsonl): For memory-efficient streaming of large JSONL files.
  


<Badge type="info" class="source-link" text="source"><a href="https://github.com/LouLouLibs/BazerUtils.jl/blob/b22675888ad7af975c9597aa5a1da4df67626d3e/src/JSONLines.jl#L16-L54" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='BazerUtils.write_jsonl-Tuple{AbstractString, Any}' href='#BazerUtils.write_jsonl-Tuple{AbstractString, Any}'><span class="jlbinding">BazerUtils.write_jsonl</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



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



<Badge type="info" class="source-link" text="source"><a href="https://github.com/LouLouLibs/BazerUtils.jl/blob/b22675888ad7af975c9597aa5a1da4df67626d3e/src/JSONLines.jl#L172-L187" target="_blank" rel="noreferrer">source</a></Badge>

</details>

