# ==================================================================================================
# CustomLogger.jl — Custom multi-sink logger with per-level filtering and pluggable formats
# ==================================================================================================


# --- Format types (multiple dispatch instead of if/elseif) ---

abstract type LogFormat end
struct PrettyFormat <: LogFormat end
struct OnelineFormat <: LogFormat end
struct SyslogFormat <: LogFormat end
struct JsonFormat <: LogFormat end
struct LogfmtFormat <: LogFormat end
struct Log4jStandardFormat <: LogFormat end

const VALID_FORMATS = "Valid options: :pretty, :oneline, :syslog, :json, :logfmt, :log4j_standard"

"""
    resolve_format(s::Symbol) -> LogFormat

Map a format symbol to its LogFormat type. `:log4j` is a deprecated alias for `:oneline`.
"""
function resolve_format(s::Symbol)::LogFormat
    s === :pretty && return PrettyFormat()
    s === :oneline && return OnelineFormat()
    s === :log4j && (Base.depwarn(
        ":log4j is deprecated, use :oneline for single-line format or :log4j_standard for Apache Log4j format. :log4j will be removed in a future major version.",
        :log4j); return OnelineFormat())
    s === :syslog && return SyslogFormat()
    s === :json && return JsonFormat()
    s === :logfmt && return LogfmtFormat()
    s === :log4j_standard && return Log4jStandardFormat()
    throw(ArgumentError("Unknown log_format: :$s. $VALID_FORMATS"))
end


# --- Helper functions ---

"""
    get_module_name(mod) -> String

Extract module name as a string, returning "unknown" for `nothing`.
"""
get_module_name(mod::Module) = string(nameof(mod))
get_module_name(::Nothing) = "unknown"

"""
    reformat_msg(log_record; displaysize=(50,100)) -> String

Convert log record message to a string. Strings pass through; other types
are rendered via `show` with display size limits.
"""
function reformat_msg(log_record; displaysize::Tuple{Int,Int}=(50,100))::String
    msg = log_record.message
    msg isa AbstractString && return String(msg)
    buf = IOBuffer()
    show(IOContext(buf, :limit => true, :compact => true, :displaysize => displaysize),
         "text/plain", msg)
    return String(take!(buf))
end

"""
    msg_to_singleline(message::AbstractString) -> String

Collapse a multi-line message to a single line, using ` | ` as separator.
"""
function msg_to_singleline(message::AbstractString)::String
    message |>
        str -> replace(str, r"\"\"\"[\r\n\s]*(.+?)[\r\n\s]*\"\"\""s => s"\1") |>
        str -> replace(str, r"\n\s*" => " | ") |>
        str -> replace(str, r"\|\s*\|" => "|") |>
        str -> replace(str, r"\s*\|\s*" => " | ") |>
        str -> replace(str, r"\|\s*$" => "") |>
        strip |> String
end

"""
    json_escape(s::AbstractString) -> String

Escape a string for inclusion in a JSON value (without surrounding quotes).
"""
function json_escape(s::AbstractString)::String
    s = replace(s, '\\' => "\\\\")
    s = replace(s, '"' => "\\\"")
    s = replace(s, '\n' => "\\n")
    s = replace(s, '\r' => "\\r")
    s = replace(s, '\t' => "\\t")
    return s
end

"""
    logfmt_escape(s::AbstractString) -> String

Format a value for logfmt output. Quotes the value if it contains spaces, equals, or quotes.
"""
function logfmt_escape(s::AbstractString)::String
    needs_quoting = contains(s, ' ') || contains(s, '"') || contains(s, '=')
    if needs_quoting
        return "\"" * replace(s, '"' => "\\\"") * "\""
    end
    return s
end


# --- LogSink infrastructure ---

abstract type LogSink end

# Keep the active sink alive so the finalizer does not close it prematurely
# while the global logger is still writing to its IO handles.
const _active_sink = Ref{Union{Nothing, LogSink}}(nothing)

"""
    get_log_filenames(filename; file_loggers, create_files) -> Vector{String}

Generate log file paths. When `create_files=true`, creates `filename_level.log` per level.
When `false`, repeats `filename` for all levels.
"""
function get_log_filenames(filename::AbstractString;
        file_loggers::Vector{Symbol}=[:error, :warn, :info, :debug],
        create_files::Bool=false)
    if create_files
        return [string(filename, "_", string(f), ".log") for f in file_loggers]
    else
        return repeat([filename], length(file_loggers))
    end
end

function get_log_filenames(files::Vector{<:AbstractString};
        file_loggers::Vector{Symbol}=[:error, :warn, :info, :debug])
    n = length(file_loggers)
    length(files) != n && throw(ArgumentError(
        "Expected exactly $n file paths (one per logger: $(join(file_loggers, ", "))), got $(length(files))"))
    return files
end

"""
    FileSink <: LogSink

File-based log sink with per-stream locking for thread safety.

When all files point to the same path (single-file mode), IO handles and locks are
deduplicated — one IO and one lock shared across all slots.
"""
mutable struct FileSink <: LogSink
    files::Vector{String}
    ios::Vector{IO}
    locks::Vector{ReentrantLock}

    function FileSink(filename::AbstractString;
            file_loggers::Vector{Symbol}=[:error, :warn, :info, :debug],
            create_files::Bool=false)
        files = get_log_filenames(filename; file_loggers=file_loggers, create_files=create_files)
        if create_files
            @info "Creating $(length(files)) log files:\n$(join(string.(" \u2B91 ", files), "\n"))"
        else
            @info "Single log sink: all levels writing to $filename"
        end
        # Deduplicate: open each unique path once, share IO + lock
        unique_paths = unique(files)
        path_to_io = Dict(p => open(p, "a") for p in unique_paths)
        path_to_lock = Dict(p => ReentrantLock() for p in unique_paths)
        ios = [path_to_io[f] for f in files]
        locks = [path_to_lock[f] for f in files]
        obj = new(files, ios, locks)
        finalizer(close, obj)
        return obj
    end

    function FileSink(files::Vector{<:AbstractString};
            file_loggers::Vector{Symbol}=[:error, :warn, :info, :debug])
        actual_files = get_log_filenames(files; file_loggers=file_loggers)
        unique_paths = unique(actual_files)
        path_to_io = Dict(p => open(p, "a") for p in unique_paths)
        path_to_lock = Dict(p => ReentrantLock() for p in unique_paths)
        ios = [path_to_io[f] for f in actual_files]
        locks = [path_to_lock[f] for f in actual_files]
        obj = new(actual_files, ios, locks)
        finalizer(close, obj)
        return obj
    end
end

function Base.close(sink::FileSink)
    for io in unique(sink.ios)
        io !== stdout && io !== stderr && isopen(io) && close(io)
    end
end
# --------------------------------------------------------------------------------------------------


# ==================================================================================================
# custom_format — dispatch hub. Called by FormatLogger callbacks.
# ==================================================================================================

"""
    custom_format(io, fmt::LogFormat, log_record::NamedTuple; kwargs...)

Format and write a log record to `io` using the given format. Generates a single
timestamp and delegates to the appropriate `format_log` method.
"""
function custom_format(io, fmt::LogFormat, log_record::NamedTuple;
        displaysize::Tuple{Int,Int}=(50,100),
        log_date_format::AbstractString="yyyy-mm-dd",
        log_time_format::AbstractString="HH:MM:SS",
        shorten_path::Symbol=:relative_path)

    timestamp = now()
    format_log(io, fmt, log_record, timestamp;
        displaysize=displaysize,
        log_date_format=log_date_format,
        log_time_format=log_time_format,
        shorten_path=shorten_path)
end


# ==================================================================================================
# create_demux_logger — builds the TeeLogger pipeline
# ==================================================================================================

function create_demux_logger(sink::FileSink,
        file_loggers::Vector{Symbol},
        module_absolute_message_filter,
        module_specific_message_filter,
        fmt_file::LogFormat,
        fmt_stdout::LogFormat,
        format_kwargs::NamedTuple;
        cascading_loglevels::Bool=false)

    logger_configs = Dict(
        :error => (module_absolute_message_filter, Logging.Error),
        :warn  => (module_absolute_message_filter, Logging.Warn),
        :info  => (module_specific_message_filter, Logging.Info),
        :debug => (module_absolute_message_filter, Logging.Debug)
    )

    logger_list = []

    for (io_index, logger_key) in enumerate(file_loggers)
        if !haskey(logger_configs, logger_key)
            @warn "Unknown logger type: $logger_key — skipping"
            continue
        end
        if io_index > length(sink.ios)
            error("Not enough IO streams in sink for logger: $logger_key")
        end

        message_filter, log_level = logger_configs[logger_key]
        io = sink.ios[io_index]
        lk = sink.locks[io_index]

        # Thread-safe format callback
        format_cb = (cb_io, log_record) -> lock(lk) do
            custom_format(cb_io, fmt_file, log_record; format_kwargs...)
        end

        inner = EarlyFilteredLogger(message_filter, FormatLogger(format_cb, io))

        if cascading_loglevels
            # Old behavior: MinLevelLogger catches this level and above
            push!(logger_list, MinLevelLogger(inner, log_level))
        else
            # New behavior: exact level only
            exact_filter = log -> log.level == log_level
            push!(logger_list, EarlyFilteredLogger(exact_filter, inner))
        end
    end

    # Stdout logger — always Info+, uses specific module filter, no file locking
    stdout_format_cb = (io, log_record) -> custom_format(io, fmt_stdout, log_record;
        format_kwargs...)
    stdout_logger = MinLevelLogger(
        EarlyFilteredLogger(module_specific_message_filter,
            FormatLogger(stdout_format_cb, stdout)),
        Logging.Info)
    push!(logger_list, stdout_logger)

    return TeeLogger(logger_list...)
end


# ==================================================================================================
# custom_logger — public API
# ==================================================================================================

"""
    custom_logger(filename; kw...)

Set up a custom global logger with per-level file output, module filtering, and configurable formatting.

When `create_log_files=true`, creates one log file per level (e.g. `filename_error.log`).
Otherwise all levels write to the same file.

# Arguments
- `filename::AbstractString`: base name for the log files
- `filtered_modules_specific::Union{Nothing, Vector{Symbol}}=nothing`: modules to filter from stdout and info-level file logs
- `filtered_modules_all::Union{Nothing, Vector{Symbol}}=nothing`: modules to filter from all logs
- `file_loggers::Union{Symbol, Vector{Symbol}}=[:error, :warn, :info, :debug]`: which levels to capture
- `log_date_format::AbstractString="yyyy-mm-dd"`: date format in timestamps
- `log_time_format::AbstractString="HH:MM:SS"`: time format in timestamps
- `displaysize::Tuple{Int,Int}=(50,100)`: display size for non-string messages
- `log_format::Symbol=:oneline`: file log format (`:pretty`, `:oneline`, `:syslog`, `:json`, `:logfmt`, `:log4j_standard`)
- `log_format_stdout::Symbol=:pretty`: stdout format (same options)
- `shorten_path::Symbol=:relative_path`: path shortening strategy (`:oneline` format only)
- `cascading_loglevels::Bool=false`: when `true`, each file captures its level and above; when `false`, each file captures only its exact level
- `create_log_files::Bool=false`: create separate files per level
- `overwrite::Bool=false`: overwrite existing log files
- `create_dir::Bool=false`: create log directory if missing
- `verbose::Bool=false`: warn about filtering non-imported modules

# Example
```julia
custom_logger("/tmp/myapp";
    filtered_modules_all=[:HTTP, :TranscodingStreams],
    create_log_files=true,
    overwrite=true,
    log_format=:oneline)
```
"""
function custom_logger(
        sink::LogSink;
        filtered_modules_specific::Union{Nothing, Vector{Symbol}}=nothing,
        filtered_modules_all::Union{Nothing, Vector{Symbol}}=nothing,
        file_loggers::Union{Symbol, Vector{Symbol}}=[:error, :warn, :info, :debug],
        log_date_format::AbstractString="yyyy-mm-dd",
        log_time_format::AbstractString="HH:MM:SS",
        displaysize::Tuple{Int,Int}=(50,100),
        log_format::Symbol=:oneline,
        log_format_stdout::Symbol=:pretty,
        shorten_path::Symbol=:relative_path,
        cascading_loglevels::Bool=false,
        verbose::Bool=false)

    # Resolve format types (validates symbols, handles :log4j deprecation)
    fmt_file = resolve_format(log_format)
    fmt_stdout = resolve_format(log_format_stdout)

    # Normalize file_loggers to Vector
    file_loggers_vec = file_loggers isa Symbol ? [file_loggers] : collect(file_loggers)

    # Warn about filtering non-imported modules
    if verbose
        imported_modules = filter(
            x -> isdefined(Main, x) && typeof(getfield(Main, x)) <: Module && x !== :Main,
            names(Main, imported=true))
        all_filters = Symbol[x for x in unique(vcat(
            something(filtered_modules_specific, Symbol[]),
            something(filtered_modules_all, Symbol[]))) if !isnothing(x)]
        if !isempty(all_filters)
            missing_mods = filter(x -> x ∉ imported_modules, all_filters)
            if !isempty(missing_mods)
                @warn "Filtering non-imported modules: $(join(string.(missing_mods), ", "))"
            end
        end
    end

    # Module filters
    module_absolute_filter = create_module_filter(filtered_modules_all)
    module_specific_filter = create_module_filter(filtered_modules_specific)

    format_kwargs = (displaysize=displaysize,
                     log_date_format=log_date_format,
                     log_time_format=log_time_format,
                     shorten_path=shorten_path)

    demux = create_demux_logger(sink, file_loggers_vec,
        module_absolute_filter, module_specific_filter,
        fmt_file, fmt_stdout, format_kwargs;
        cascading_loglevels=cascading_loglevels)

    # Keep sink alive to prevent GC from closing IO handles
    _active_sink[] = sink

    global_logger(demux)
    return demux
end

"""
    create_module_filter(modules) -> Function

Return a filter function that drops log messages from the specified modules.
Uses `startswith` to catch submodules (e.g. `:HTTP` catches `HTTP.ConnectionPool`).
"""
function create_module_filter(modules)
    return function(log)
        isnothing(modules) && return true
        mod = string(log._module)
        for m in modules
            startswith(mod, string(m)) && return false
        end
        return true
    end
end

# Convenience constructor: filename or vector of filenames
function custom_logger(
        filename::Union{AbstractString, Vector{<:AbstractString}};
        create_log_files::Bool=false,
        overwrite::Bool=false,
        create_dir::Bool=false,
        file_loggers::Union{Symbol, Vector{Symbol}}=[:error, :warn, :info, :debug],
        kwargs...)

    file_loggers_array = file_loggers isa Symbol ? [file_loggers] : collect(file_loggers)

    files = if filename isa AbstractString
        get_log_filenames(filename; file_loggers=file_loggers_array, create_files=create_log_files)
    else
        get_log_filenames(filename; file_loggers=file_loggers_array)
    end

    # Create directories if needed
    log_dirs = unique(dirname.(files))
    missing_dirs = filter(d -> !isempty(d) && !isdir(d), log_dirs)
    if !isempty(missing_dirs)
        if create_dir
            @warn "Creating log directories: $(join(missing_dirs, ", "))"
            mkpath.(missing_dirs)
        else
            @error "Log directories do not exist: $(join(missing_dirs, ", "))"
        end
    end

    overwrite && foreach(f -> rm(f, force=true), unique(files))

    sink = if filename isa AbstractString
        FileSink(filename; file_loggers=file_loggers_array, create_files=create_log_files)
    else
        FileSink(filename; file_loggers=file_loggers_array)
    end

    custom_logger(sink; file_loggers=file_loggers, kwargs...)
end

# Convenience for batch/script mode
function custom_logger(; kwargs...)
    if !isempty(PROGRAM_FILE)
        logbase = splitext(abspath(PROGRAM_FILE))[1]
        custom_logger(logbase; kwargs...)
    else
        @error "custom_logger() with no arguments requires a script context (PROGRAM_FILE is empty in the REPL)"
    end
end


# --- Helper: colors for pretty format ---

function get_color(level)
    RESET = "\033[0m"
    BOLD = "\033[1m"
    LIGHT_BLUE = "\033[94m"
    RED = "\033[31m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"

    return level == Logging.Debug ? LIGHT_BLUE :
           level == Logging.Info  ? GREEN :
           level == Logging.Warn  ? "$YELLOW$BOLD" :
           level == Logging.Error ? "$RED$BOLD" :
           RESET
end


# --------------------------------------------------------------------------------------------------
"""
    shorten_path_str(path::AbstractString; max_length::Int=40, strategy::Symbol=:truncate_middle)

Shorten a file path string to a specified maximum length using various strategies.

# Arguments
- `path::AbstractString`: The input path to be shortened
- `max_length::Int=40`: Maximum desired length of the output path
- `strategy::Symbol=:truncate_middle`: Strategy to use for shortening. Options:
  * `:no`: Return path unchanged
  * `:truncate_middle`: Truncate middle of path components while preserving start/end
  * `:truncate_to_last`: Keep only the last n components of the path
  * `:truncate_from_right`: Progressively remove characters from right side of components
  * `:truncate_to_unique`: Reduce components to unique prefixes

# Returns
- `String`: The shortened path

# Examples
```julia
# Using different strategies
julia> shorten_path_str("/very/long/path/to/file.txt", max_length=20)
"/very/…/path/to/file.txt"

julia> shorten_path_str("/usr/local/bin/program", strategy=:truncate_to_last, max_length=20)
"/bin/program"

julia> shorten_path_str("/home/user/documents/very_long_filename.txt", strategy=:truncate_middle)
"/home/user/doc…ents/very_…name.txt"
```
"""
function shorten_path_str(path::AbstractString;
    max_length::Int=40,
    strategy::Symbol=:truncate_middle
    )::AbstractString

    if strategy == :no
        return path
    elseif strategy == :relative_path
        return "./" * relpath(path, pwd())
    end

    # Return early if path is already short enough
    if length(path) ≤ max_length
        return path
    end

    # Split path into components
    parts = split(path, '/')
    is_absolute = startswith(path, '/')

    # Handle empty path or root directory
    if isempty(parts) || (length(parts) == 1 && isempty(parts[1]))
        return is_absolute ? "/" : ""
    end

    # Remove empty strings from split
    parts = filter(!isempty, parts)

    if strategy == :truncate_to_last
        # Keep only the last few components
        n = 2  # number of components to keep
        if length(parts) > n
            shortened = parts[end-n+1:end]
            result = join(shortened, "/")
            return is_absolute ? "/$result" : result
        end

    elseif strategy == :truncate_middle
        # For each component, truncate the middle if it's too long
        function shorten_component(comp::AbstractString; max_comp_len::Int=10)
            if length(comp) ≤ max_comp_len
                return comp
            end
            keep = max_comp_len ÷ 2 - 1
            return string(comp[1:keep], "…", comp[end-keep+1:end])
        end

        shortened = map(p -> shorten_component(p), parts)
        result = join(shortened, "/")
        if length(result) > max_length
            # If still too long, drop some middle directories
            middle_start = length(parts) ÷ 3
            middle_end = 2 * length(parts) ÷ 3
            shortened = [parts[1:middle_start]..., "…", parts[middle_end:end]...]
            result = join(shortened, "/")
        end
        return is_absolute ? "/$result" : result

    elseif strategy == :truncate_from_right
        # Start removing characters from right side of each component
        shortened = copy(parts)
        while join(shortened, "/") |> length > max_length && any(length.(shortened) .> 3)
            # Find longest component
            idx = argmax(length.(shortened))
            if length(shortened[idx]) > 3
                shortened[idx] = shortened[idx][1:end-1]
            end
        end
        result = join(shortened, "/")
        return is_absolute ? "/$result" : result

    elseif strategy == :truncate_to_unique
        # Simplified unique prefix strategy
        function unique_prefix(str::AbstractString, others::Vector{String}; min_len::Int=1)
            for len in min_len:length(str)
                prefix = str[1:len]
                if !any(s -> s != str && startswith(s, prefix), others)
                    return prefix
                end
            end
            return str
        end

        # Get unique prefixes for each component
        shortened = String[]
        for (i, part) in enumerate(parts)
            if i == 1 || i == length(parts)
                push!(shortened, part)
            else
                prefix = unique_prefix(part, String.(parts))
                push!(shortened, prefix)
            end
        end

        result = join(shortened, "/")
        return is_absolute ? "/$result" : result
    end

    # Default fallback: return truncated original path
    return string(path[1:max_length-3], "…")
end
# --------------------------------------------------------------------------------------------------


# --- Constants for format_log methods ---

const SYSLOG_SEVERITY = Dict(
    Logging.Info  => 6,
    Logging.Warn  => 4,
    Logging.Error => 3,
    Logging.Debug => 7
)

const JULIA_BIN = Base.julia_cmd().exec[1]


# ==================================================================================================
# format_log methods — one per LogFormat type
# All write directly to `io`. All accept a pre-computed `timestamp::DateTime`.
# ==================================================================================================

function format_log(io, ::PrettyFormat, log_record::NamedTuple, timestamp::Dates.DateTime;
        displaysize::Tuple{Int,Int}=(50,100),
        log_date_format::AbstractString="yyyy-mm-dd",
        log_time_format::AbstractString="HH:MM:SS",
        kwargs...)

    BOLD = "\033[1m"
    EMPH = "\033[2m"
    RESET = "\033[0m"

    date = format(timestamp, log_date_format)
    time_str = format(timestamp, log_time_format)
    ts = "$BOLD$(time_str)$RESET $EMPH$date$RESET"

    level_str = string(log_record.level)
    color = get_color(log_record.level)
    mod_name = get_module_name(log_record._module)
    source = " @ $mod_name[$(log_record.file):$(log_record.line)]"
    first_line = "┌ [$ts] $color$level_str$RESET | $source"

    formatted = reformat_msg(log_record; displaysize=displaysize)
    lines = split(formatted, "\n")

    println(io, first_line)
    for (i, line) in enumerate(lines)
        prefix = i < length(lines) ? "│ " : "└ "
        println(io, prefix, line)
    end
end

function format_log(io, ::OnelineFormat, log_record::NamedTuple, timestamp::Dates.DateTime;
        displaysize::Tuple{Int,Int}=(50,100),
        shorten_path::Symbol=:relative_path,
        kwargs...)

    ts = format(timestamp, "yyyy-mm-dd HH:MM:SS")
    level = rpad(uppercase(string(log_record.level)), 5)
    mod_name = get_module_name(log_record._module)
    file = shorten_path_str(log_record.file; strategy=shorten_path)
    prefix = shorten_path === :relative_path ? "[$(pwd())] " : ""
    msg = reformat_msg(log_record; displaysize=displaysize) |> msg_to_singleline

    println(io, "$prefix$ts $level $mod_name[$file:$(log_record.line)] $msg")
end

function format_log(io, ::SyslogFormat, log_record::NamedTuple, timestamp::Dates.DateTime;
        displaysize::Tuple{Int,Int}=(50,100),
        kwargs...)

    ts = Dates.format(timestamp, "yyyy-mm-ddTHH:MM:SS")
    severity = get(SYSLOG_SEVERITY, log_record.level, 6)
    pri = (1 * 8) + severity
    hostname = gethostname()
    pid = getpid()
    msg = reformat_msg(log_record; displaysize=displaysize) |> msg_to_singleline

    println(io, "<$pri>1 $ts $hostname $JULIA_BIN $pid - - $msg")
end

function format_log(io, ::JsonFormat, log_record::NamedTuple, timestamp::Dates.DateTime;
        displaysize::Tuple{Int,Int}=(50,100),
        kwargs...)

    ts = Dates.format(timestamp, "yyyy-mm-ddTHH:MM:SS")
    level = json_escape(string(log_record.level))
    mod_name = json_escape(get_module_name(log_record._module))
    file = json_escape(string(log_record.file))
    line = log_record.line
    msg = json_escape(reformat_msg(log_record; displaysize=displaysize))

    println(io, "{\"timestamp\":\"$ts\",\"level\":\"$level\",\"module\":\"$mod_name\",\"file\":\"$file\",\"line\":$line,\"message\":\"$msg\"}")
end

function format_log(io, ::LogfmtFormat, log_record::NamedTuple, timestamp::Dates.DateTime;
        displaysize::Tuple{Int,Int}=(50,100),
        kwargs...)

    ts = Dates.format(timestamp, "yyyy-mm-ddTHH:MM:SS")
    level = string(log_record.level)
    mod_name = get_module_name(log_record._module)
    file = logfmt_escape(string(log_record.file))
    msg = logfmt_escape(reformat_msg(log_record; displaysize=displaysize))

    println(io, "ts=$ts level=$level module=$mod_name file=$file line=$(log_record.line) msg=$msg")
end

function format_log(io, ::Log4jStandardFormat, log_record::NamedTuple, timestamp::Dates.DateTime;
        displaysize::Tuple{Int,Int}=(50,100),
        kwargs...)

    ts = format(timestamp, "yyyy-mm-dd HH:MM:SS")
    millis = lpad(Dates.millisecond(timestamp), 3, '0')
    level = rpad(uppercase(string(log_record.level)), 5)
    thread_id = Threads.threadid()
    mod_name = get_module_name(log_record._module)
    msg = reformat_msg(log_record; displaysize=displaysize) |> msg_to_singleline

    println(io, "$ts,$millis $level [$thread_id] $mod_name - $msg")
end
