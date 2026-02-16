
# Logging {#Logging}

The function `custom_logger` is a wrapper over the `Logging.jl` and `LoggingExtras.jl` libraries. I made them such that I could fine tune the type of log I use repeatedly across projects. 

The things I find most useful:
1. four different log files for each different level of logging from _error_ to _debug_
  
2. pretty (to me) formatting for stdout but also an option to have `log4j` style formatting in the files
  
3. filtering out messages of verbose packages (`TranscodingStreams`, etc...) which sometimes slows down julia because of excessive logging.
  

There are still a few things that might be useful down the line: (1) a catch-all log file where filters do not apply; (2) filtering out specific functions of packages; 

Overall this is working fine for me.

## Basic usage {#Basic-usage}

Say at the beginning of a script you would have something like:

```julia
using BazerUtils
custom_logger("/tmp/log_test"; 
    filtered_modules_all=[:StatsModels, :TranscodingStreams, :Parquet2], 
    create_log_files=true, 
    overwrite=true, 
    log_format = :log4j);
  
┌ Info: Creating four different files for logging ...
│  ⮑  /tmp/log_test_error.log
│      /tmp/log_test_warn.log
│      /tmp/log_test_info.log
└      /tmp/log_test_debug.log
```


The REPL will see all messages above debug level:

```julia
> @error "This is an error level message"
┌ [08:28:08 2025-02-12] ERROR |  @ Main[REPL[17]:1]
└ This is an error level message

> @warn "This is an warn level message"
┌ [08:28:08 2025-02-12] WARN  |  @ Main[REPL[18]:1]
└ This is an warn level message

> @info "This is an info level message"
┌ [08:28:08 2025-02-12] INFO  |  @ Main[REPL[19]:1]
└ This is an info level message

> @debug "This is an debug level message"

```


Then each of the respective log-levels will be redirected to the individual files and if the log4j option was specified they will look like something like this

```log4j
2025-02-12 08:28:08 ERROR Main[REPL[17]:1] - This is an error level message
2025-02-12 08:28:08 WARN  Main[REPL[18]:1] - This is an warn level message
2025-02-12 08:28:08 INFO  Main[REPL[19]:1] - This is an info level message
2025-02-12 08:28:08 DEBUG Main[REPL[20]:1] - This is an debug level message
```


## Options {#Options}

### Formatting {#Formatting}

The `log_format` is `log4j` by default (only for the files).  The only other option for now is `pretty` which uses the format I wrote for the REPL; note that it is a little cumbersome for files especially since you have to make sure your editor has the ansi interpreter on. 

### Files {#Files}

The default is to create one file for each level.  There is an option to only create one file for each level and keep things a little tidier in your directories:

```julia
> custom_logger("/tmp/log_test";  
    create_log_files=false, overwrite=true, log_format = :log4j);

> @error "This is an error level message" 
> @warn "This is an warn level message"
> @info "This is an info level message"
> @debug "This is an debug level message"
```


And then the file `/tmp/log_test` has the following:

```log4j
2025-02-12 08:37:29 ERROR Main[REPL[22]:1] - This is an error level message
2025-02-12 08:37:29 WARN  Main[REPL[23]:1] - This is an warn level message
2025-02-12 08:37:29 INFO  Main[REPL[24]:1] - This is an info level message
2025-02-12 08:37:29 DEBUG Main[REPL[25]:1] - This is an debug level message
```


Now imagine you want to keep the same log file but for a different script.  You can use the same logger option with the `overwrite=false` option:

```julia
> custom_logger("/tmp/log_test";  
    create_log_files=false, overwrite=false, log_format = :log4j);

> @error "This is an error level message from a different script and new logger" 
```


### Filtering {#Filtering}
- `filtered_modules_specific::Vector{Symbol}=nothing`: which modules do you want to filter out of logging (only for info and stdout) Some packages just write too much log ... filter them out but still be able to check them out in other logs
  
- `filtered_modules_all::Vector{Symbol}=nothing`: which modules do you want to filter out of logging (across all logs)  Examples could be TranscodingStreams (noticed that it writes so much to logs that it sometimes slows down I/O)
  

## Other {#Other}

For `log4j` the message string is modified to fit on one line: `\n` is replaced by `|`.

There is also a path shortener (`shorten_path_str`) that reduces file paths to a fixed size. The cost is that paths will no longer be clickable, but log messages will start at the same column.
