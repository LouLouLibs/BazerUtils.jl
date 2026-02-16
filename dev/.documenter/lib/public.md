
# Public Interface {#Public-Interface}

## `BazerUtils` Module {#BazerUtils-Module}
<details class='jldocstring custom-block' open>
<summary><a id='BazerUtils.custom_logger-Tuple{BazerUtils.LogSink}' href='#BazerUtils.custom_logger-Tuple{BazerUtils.LogSink}'><span class="jlbinding">BazerUtils.custom_logger</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
custom_logger(filename; kw...)
```


Set up a custom global logger with per-level file output, module filtering, and configurable formatting.

When `create_log_files=true`, creates one log file per level (e.g. `filename_error.log`, `filename_warn.log`, etc.). Otherwise all levels write to the same file.

**Arguments**
- `filename::AbstractString`: base name for the log files
  
- `filtered_modules_specific::Union{Nothing, Vector{Symbol}}=nothing`: modules to filter out of stdout and info-level file logs only (e.g. `[:TranscodingStreams]`)
  
- `filtered_modules_all::Union{Nothing, Vector{Symbol}}=nothing`: modules to filter out of all logs (e.g. `[:HTTP]`)
  
- `file_loggers::Union{Symbol, Vector{Symbol}}=[:error, :warn, :info, :debug]`: which file loggers to register
  
- `log_date_format::AbstractString="yyyy-mm-dd"`: date format in log timestamps
  
- `log_time_format::AbstractString="HH:MM:SS"`: time format in log timestamps
  
- `displaysize::Tuple{Int,Int}=(50,100)`: display size for non-string log messages
  
- `log_format::Symbol=:log4j`: format for file logs (`:log4j`, `:pretty`, or `:syslog`)
  
- `log_format_stdout::Symbol=:pretty`: format for stdout
  
- `shorten_path::Symbol=:relative_path`: path shortening strategy for log4j format
  
- `create_log_files::Bool=false`: create separate files per log level
  
- `overwrite::Bool=false`: overwrite existing log files
  
- `create_dir::Bool=false`: create the log directory if it doesn&#39;t exist
  
- `verbose::Bool=false`: warn about filtering non-imported modules
  

**Example**

```julia
custom_logger("/tmp/myapp";
    filtered_modules_all=[:HTTP, :TranscodingStreams],
    create_log_files=true,
    overwrite=true,
    log_format=:log4j)
```



<Badge type="info" class="source-link" text="source"><a href="https://github.com/LouLouLibs/BazerUtils.jl/blob/e10c53c945a2da1f1886ed0804c3b88037c65eca/src/CustomLogger.jl#L72-L104" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='BazerUtils.read_jsonl-Tuple{IO}' href='#BazerUtils.read_jsonl-Tuple{IO}'><span class="jlbinding">BazerUtils.read_jsonl</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
read_jsonl(source::Union{AbstractString, IO}; dict_of_json::Bool=false) -> Vector
```


::: warning Deprecated

`read_jsonl` is deprecated. Use `JSON.parse(source; jsonlines=true)` from [JSON.jl](https://github.com/JuliaIO/JSON.jl) v1 instead.

:::

Read a JSON Lines (.jsonl) file or stream and return all records as a vector.

Each line is parsed as a separate JSON value. Empty lines are skipped.

**Arguments**
- `source::Union{AbstractString, IO}`: Path to a JSONL file, or an IO stream.
  
- `dict_of_json::Bool=false`: If `true` and the parsed type is `JSON3.Object`, convert each record to a `Dict{Symbol,Any}`.
  

**Returns**
- `Vector`: A vector of parsed JSON values.
  


<Badge type="info" class="source-link" text="source"><a href="https://github.com/LouLouLibs/BazerUtils.jl/blob/e10c53c945a2da1f1886ed0804c3b88037c65eca/src/JSONLines.jl#L16-L33" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='BazerUtils.stream_jsonl-Tuple{IO}' href='#BazerUtils.stream_jsonl-Tuple{IO}'><span class="jlbinding">BazerUtils.stream_jsonl</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
stream_jsonl(source::Union{AbstractString, IO}; T::Type=JSON3.Object{}) -> Channel
```


::: warning Deprecated

`stream_jsonl` is deprecated. Use `JSON.parse(source; jsonlines=true)` from [JSON.jl](https://github.com/JuliaIO/JSON.jl) v1 instead.

:::

Create a lazy Channel iterator for reading JSON Lines files record by record.

**Arguments**
- `source::Union{AbstractString, IO}`: Path to a JSONL file, or an IO stream.
  
- `T::Type=JSON3.Object{}`: Expected type for each record. Use `T=Any` for mixed types.
  

**Returns**
- `Channel{T}`: A channel yielding parsed JSON objects one at a time.
  


<Badge type="info" class="source-link" text="source"><a href="https://github.com/LouLouLibs/BazerUtils.jl/blob/e10c53c945a2da1f1886ed0804c3b88037c65eca/src/JSONLines.jl#L69-L84" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='BazerUtils.write_jsonl-Tuple{AbstractString, Any, BazerUtils.TableIteration}' href='#BazerUtils.write_jsonl-Tuple{AbstractString, Any, BazerUtils.TableIteration}'><span class="jlbinding">BazerUtils.write_jsonl</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
write_jsonl(filename, data; compress=false)
```


::: warning Deprecated

`write_jsonl` is deprecated. Use `JSON.json(filename, data; jsonlines=true)` from [JSON.jl](https://github.com/JuliaIO/JSON.jl) v1 instead.

:::

Write an iterable of JSON-serializable values to a JSON Lines file.

**Arguments**
- `filename`: Output file path (writes gzip-compressed if ends with `.gz` or `compress=true`)
  
- `data`: An iterable of JSON-serializable values
  
- `compress::Bool=false`: Force gzip compression
  

**Returns**

The filename.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/LouLouLibs/BazerUtils.jl/blob/e10c53c945a2da1f1886ed0804c3b88037c65eca/src/JSONLines.jl#L143-L159" target="_blank" rel="noreferrer">source</a></Badge>

</details>

