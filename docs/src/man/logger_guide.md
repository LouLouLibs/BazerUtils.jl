# Logging

The function `custom_logger` is a wrapper over the `Logging.jl` and `LoggingExtras.jl` libraries.
I made them such that I could fine tune the type of log I use repeatedly across projects.

The things I find most useful:

1. four different log files for each different level of logging from *error* to *debug*
2. six output formats: `:pretty` for the REPL, `:oneline`, `:json`, `:logfmt`, `:syslog`, and `:log4j_standard` for files
3. filtering out messages of verbose packages (`TranscodingStreams`, etc...) which sometimes slows down julia because of excessive logging
4. exact-level filtering so each file gets only its own level (or cascading for the old behavior)
5. thread-safe writes via per-stream locking

There are still a few things that might be useful down the line:
(1) a catch-all log file where filters do not apply; (2) filtering out specific functions of packages;

Overall this is working fine for me.

## Basic usage

Say at the beginning of a script you would have something like:
```julia
using BazerUtils
custom_logger("/tmp/log_test";
    filtered_modules_all=[:StatsModels, :TranscodingStreams, :Parquet2],
    create_log_files=true,
    overwrite=true,
    log_format=:oneline);

┌ Info: Creating 4 log files:
│  ⮑ /tmp/log_test_error.log
│    /tmp/log_test_warn.log
│    /tmp/log_test_info.log
└    /tmp/log_test_debug.log
```

The REPL will see all messages above debug level:
```julia
> @error "This is an error level message"
┌ [08:28:08 2025-02-12] Error |  @ Main[REPL[17]:1]
└ This is an error level message

> @warn "This is an warn level message"
┌ [08:28:08 2025-02-12] Warn  |  @ Main[REPL[18]:1]
└ This is an warn level message

> @info "This is an info level message"
┌ [08:28:08 2025-02-12] Info  |  @ Main[REPL[19]:1]
└ This is an info level message

> @debug "This is an debug level message"

```
Then each of the respective log-levels will be redirected to the individual files. With the `:oneline` format they will look like:
```
[/home/user] 2025-02-12 08:28:08 ERROR Main[./REPL[17]:1] This is an error level message
[/home/user] 2025-02-12 08:28:08 WARN  Main[./REPL[18]:1] This is an warn level message
[/home/user] 2025-02-12 08:28:08 INFO  Main[./REPL[19]:1] This is an info level message
[/home/user] 2025-02-12 08:28:08 DEBUG Main[./REPL[20]:1] This is an debug level message
```


## Options

### Log Formats

The `log_format` kwarg controls how file logs are formatted. Default is `:oneline`.
The `log_format_stdout` kwarg controls REPL output. Default is `:pretty`.

All formats are available for both file and stdout.

| Format | Symbol | Best for |
|--------|--------|----------|
| Pretty | `:pretty` | Human reading in the REPL. Box-drawing characters + ANSI colors. |
| Oneline | `:oneline` | File logs. Single line with timestamp, level, module, file:line, message. |
| JSON | `:json` | Structured log aggregation (ELK, Datadog, Loki). One JSON object per line, zero external dependencies. |
| logfmt | `:logfmt` | Grep-friendly structured logs. `key=value` pairs, popular with Splunk/Heroku. |
| Syslog | `:syslog` | RFC 5424 syslog collectors. |
| Log4j Standard | `:log4j_standard` | Java tooling interop. Actual Apache Log4j PatternLayout with thread ID and milliseconds. |

Example:
```julia
# JSON logs for a data pipeline
custom_logger("/tmp/pipeline";
    log_format=:json,
    create_log_files=true,
    overwrite=true)

# logfmt for grep-friendly output
custom_logger("/tmp/pipeline";
    log_format=:logfmt,
    overwrite=true)
```

> **Deprecation note:** `:log4j` still works as an alias for `:oneline` but emits a deprecation warning. Use `:oneline` for the single-line format or `:log4j_standard` for the actual Apache Log4j format.


### Level Filtering: `cascading_loglevels`

By default (`cascading_loglevels=false`), each file gets only messages at its exact level:
- `app_error.log` — only errors
- `app_warn.log` — only warnings
- `app_info.log` — only info
- `app_debug.log` — only debug

With `cascading_loglevels=true`, each file gets its level **and everything above**:
- `app_error.log` — only errors
- `app_warn.log` — warnings + errors
- `app_info.log` — info + warnings + errors
- `app_debug.log` — everything

```julia
# Old cascading behavior
custom_logger("/tmp/log_test";
    create_log_files=true,
    cascading_loglevels=true,
    overwrite=true)
```


### Files

The default is to write all levels to a single file.
Set `create_log_files=true` to create one file per level:

```julia
# Single file (default)
custom_logger("/tmp/log_test"; overwrite=true)

# Separate files per level
custom_logger("/tmp/log_test";
    create_log_files=true, overwrite=true)
```

You can also select only specific levels:
```julia
custom_logger("/tmp/log_test";
    create_log_files=true,
    file_loggers=[:warn, :debug],   # only warn and debug files
    overwrite=true)
```

Use `overwrite=false` (the default) to append to existing log files across script runs.


### Filtering

- `filtered_modules_specific::Vector{Symbol}`: filter modules from stdout and info-level file logs only.
  Some packages write too much — filter them from info but still see them in debug.
- `filtered_modules_all::Vector{Symbol}`: filter modules from ALL logs.
  Use for extremely verbose packages like `TranscodingStreams` that can slow down I/O.

```julia
custom_logger("/tmp/log_test";
    filtered_modules_all=[:TranscodingStreams],
    filtered_modules_specific=[:HTTP],
    overwrite=true)
```


### Thread Safety

All file writes are wrapped in per-stream `ReentrantLock`s. Multiple threads can log concurrently without interleaving output. In single-file mode, all levels share one lock. In multi-file mode, each file has its own lock so writes to different files don't block each other.


## Other

For single-line formats (`:oneline`, `:logfmt`, `:syslog`, `:log4j_standard`), multi-line messages are collapsed to a single line: `\n` is replaced by ` | `. The `:json` format escapes newlines as `\n` in the JSON string.

There is also a path shortener (`shorten_path`) that reduces file paths. Options: `:relative_path` (default), `:truncate_middle`, `:truncate_to_last`, `:truncate_from_right`, `:truncate_to_unique`, `:no`.
