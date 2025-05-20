
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


<Badge type="info" class="source-link" text="source"><a href="https://github.com/eloualiche/BazerUtils.jl/blob/336a72ee61a3176e8e8b4c1a2cc6382219d3b695/src/CustomLogger.jl#L72-L98" target="_blank" rel="noreferrer">source</a></Badge>

</details>

