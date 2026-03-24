# Logger Cleanup & Format Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite CustomLogger.jl to fix robustness issues, add JSON/logfmt/log4j_standard formats, rename :log4j to :oneline, add exact-level filtering, and refactor to multiple dispatch.

**Architecture:** Replace if/elseif format dispatch with Julia multiple dispatch on `LogFormat` subtypes. Each format implements `format_log(io, fmt, log_record, timestamp; kwargs...)`. FileSink gains per-stream `ReentrantLock`s with IO deduplication for single-file mode. `cascading_loglevels` kwarg controls `MinLevelLogger` vs exact `EarlyFilteredLogger`.

**Tech Stack:** Julia 1.10+, LoggingExtras.jl (EarlyFilteredLogger, FormatLogger, MinLevelLogger, TeeLogger), Dates

**Spec:** `docs/superpowers/specs/2026-03-24-logger-cleanup-design.md`

---

### Task 1: Format types, resolve_format, and helper functions

**Files:**
- Modify: `src/CustomLogger.jl` (replace lines 1-17 with new infrastructure, add helpers before format functions)
- Test: `test/UnitTests/customlogger.jl`

- [ ] **Step 1: Write failing tests for resolve_format and helpers**

Add at the **top** of the `@testset "CustomLogger"` block in `test/UnitTests/customlogger.jl`:

```julia
    @testset "resolve_format" begin
        @test BazerUtils.resolve_format(:pretty) isa BazerUtils.PrettyFormat
        @test BazerUtils.resolve_format(:oneline) isa BazerUtils.OnelineFormat
        @test BazerUtils.resolve_format(:syslog) isa BazerUtils.SyslogFormat
        @test BazerUtils.resolve_format(:json) isa BazerUtils.JsonFormat
        @test BazerUtils.resolve_format(:logfmt) isa BazerUtils.LogfmtFormat
        @test BazerUtils.resolve_format(:log4j_standard) isa BazerUtils.Log4jStandardFormat
        @test_throws ArgumentError BazerUtils.resolve_format(:invalid_format)
        # :log4j is deprecated alias for :oneline
        @test BazerUtils.resolve_format(:log4j) isa BazerUtils.OnelineFormat
    end

    @testset "get_module_name" begin
        @test BazerUtils.get_module_name(nothing) == "unknown"
        @test BazerUtils.get_module_name(Base) == "Base"
        @test BazerUtils.get_module_name(Main) == "Main"
    end

    @testset "json_escape" begin
        @test BazerUtils.json_escape("hello") == "hello"
        @test BazerUtils.json_escape("line1\nline2") == "line1\\nline2"
        @test BazerUtils.json_escape("say \"hi\"") == "say \\\"hi\\\""
        @test BazerUtils.json_escape("back\\slash") == "back\\\\slash"
        @test BazerUtils.json_escape("tab\there") == "tab\\there"
    end

    @testset "logfmt_escape" begin
        @test BazerUtils.logfmt_escape("simple") == "simple"
        @test BazerUtils.logfmt_escape("has space") == "\"has space\""
        @test BazerUtils.logfmt_escape("has\"quote") == "\"has\\\"quote\""
        @test BazerUtils.logfmt_escape("has=equals") == "\"has=equals\""
    end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/loulou/Dropbox/projects_code/julia_packages/BazerUtils.jl && julia --project -e 'using Pkg; Pkg.test()'`
Expected: FAIL — `resolve_format`, `get_module_name`, `json_escape`, `logfmt_escape` not defined

- [ ] **Step 3: Implement format types, resolve_format, and helpers**

Replace lines 1–15 of `src/CustomLogger.jl` (everything ABOVE `abstract type LogSink end` on line 16 — keep `LogSink` and everything after it intact until Task 2) with:

```julia
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/loulou/Dropbox/projects_code/julia_packages/BazerUtils.jl && julia --project -e 'using Pkg; Pkg.test()'`
Expected: The new testsets pass. Existing tests may fail because old code was replaced — that's OK, we fix it in subsequent tasks.

- [ ] **Step 5: Commit**

```bash
git add src/CustomLogger.jl test/UnitTests/customlogger.jl
git commit -m "feat: add format types, resolve_format, and helper functions"
```

---

### Task 2: Refactor FileSink (finalizer, locks, IO deduplication)

**Files:**
- Modify: `src/CustomLogger.jl` (the `FileSink` struct and related functions)
- Test: `test/UnitTests/customlogger.jl`

- [ ] **Step 1: Write failing tests for FileSink**

Add after the `logfmt_escape` testset:

```julia
    @testset "FileSink" begin
        tmp = tempname()
        # Single file mode: deduplicates IO handles
        sink = BazerUtils.FileSink(tmp; create_files=false)
        @test length(sink.ios) == 4
        @test length(unique(objectid.(sink.ios))) == 1  # all same IO
        @test length(sink.locks) == 4
        @test length(unique(objectid.(sink.locks))) == 1  # all same lock
        @test all(io -> io !== stdout && io !== stderr, sink.ios)
        close(sink)
        rm(tmp, force=true)

        # Multi file mode: separate IO handles
        sink2 = BazerUtils.FileSink(tmp; create_files=true)
        @test length(sink2.ios) == 4
        @test length(unique(objectid.(sink2.ios))) == 4  # all different IO
        @test length(unique(objectid.(sink2.locks))) == 4  # all different locks
        close(sink2)
        rm.(BazerUtils.get_log_filenames(tmp; create_files=true), force=true)

        # close guard: closing twice doesn't error
        sink3 = BazerUtils.FileSink(tempname(); create_files=false)
        close(sink3)
        @test_nowarn close(sink3)  # second close is safe
    end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/loulou/Dropbox/projects_code/julia_packages/BazerUtils.jl && julia --project -e 'using Pkg; Pkg.test()'`
Expected: FAIL — `sink.locks` doesn't exist, IO dedup not implemented

- [ ] **Step 3: Implement refactored FileSink**

Replace the `get_log_filenames` functions and `FileSink` struct (from after the helpers to the `Base.close` function) with:

```julia
# --- LogSink infrastructure ---

abstract type LogSink end

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
struct FileSink <: LogSink
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/loulou/Dropbox/projects_code/julia_packages/BazerUtils.jl && julia --project -e 'using Pkg; Pkg.test()'`
Expected: FileSink tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/CustomLogger.jl test/UnitTests/customlogger.jl
git commit -m "feat: refactor FileSink with locks, IO dedup, finalizer, close guard"
```

---

### Task 3: Implement format_log methods for all 6 formats

**Files:**
- Modify: `src/CustomLogger.jl` (ADD new `format_log` methods AFTER the old format functions — keep old functions in place until Task 7 cleanup)
- Modify: `src/BazerUtils.jl` (add `Logging.Error` import needed for `get_color`)
- Test: `test/UnitTests/customlogger.jl`

- [ ] **Step 1: Write failing tests for format_log**

Add after the `FileSink` testset:

```julia
    @testset "format_log methods" begin
        T = Dates.DateTime(2024, 1, 15, 14, 30, 0)
        log_record = (level=Base.CoreLogging.Info, message="test message",
            _module=BazerUtils, file="/src/app.jl", line=42, group=:test, id=:test)
        nothing_record = (level=Base.CoreLogging.Info, message="nothing mod",
            _module=nothing, file="test.jl", line=1, group=:test, id=:test)

        @testset "PrettyFormat" begin
            buf = IOBuffer()
            BazerUtils.format_log(buf, BazerUtils.PrettyFormat(), log_record, T;
                displaysize=(50,100))
            output = String(take!(buf))
            @test contains(output, "test message")
            @test contains(output, "14:30:00")
            @test contains(output, "BazerUtils")
            @test contains(output, "┌")
            @test contains(output, "└")
        end

        @testset "PrettyFormat _module=nothing" begin
            buf = IOBuffer()
            BazerUtils.format_log(buf, BazerUtils.PrettyFormat(), nothing_record, T;
                displaysize=(50,100))
            output = String(take!(buf))
            @test contains(output, "unknown")
        end

        @testset "OnelineFormat" begin
            buf = IOBuffer()
            BazerUtils.format_log(buf, BazerUtils.OnelineFormat(), log_record, T;
                displaysize=(50,100), shorten_path=:no)
            output = String(take!(buf))
            @test contains(output, "INFO")
            @test contains(output, "2024-01-15 14:30:00")
            @test contains(output, "BazerUtils")
            @test contains(output, "test message")
        end

        @testset "OnelineFormat _module=nothing" begin
            buf = IOBuffer()
            BazerUtils.format_log(buf, BazerUtils.OnelineFormat(), nothing_record, T;
                displaysize=(50,100), shorten_path=:no)
            output = String(take!(buf))
            @test contains(output, "unknown")
        end

        @testset "SyslogFormat" begin
            buf = IOBuffer()
            BazerUtils.format_log(buf, BazerUtils.SyslogFormat(), log_record, T;
                displaysize=(50,100))
            output = String(take!(buf))
            @test contains(output, "<14>")  # facility=1, severity=6 -> (1*8)+6=14
            @test contains(output, "2024-01-15T14:30:00")
            @test contains(output, "test message")
        end

        @testset "JsonFormat" begin
            buf = IOBuffer()
            BazerUtils.format_log(buf, BazerUtils.JsonFormat(), log_record, T;
                displaysize=(50,100))
            output = strip(String(take!(buf)))
            @test startswith(output, "{")
            @test endswith(output, "}")
            @test contains(output, "\"timestamp\":\"2024-01-15T14:30:00\"")
            @test contains(output, "\"level\":\"Info\"")
            @test contains(output, "\"module\":\"BazerUtils\"")
            @test contains(output, "\"message\":\"test message\"")
            @test contains(output, "\"line\":42")
            # Verify it parses as valid JSON
            parsed = JSON.parse(output)
            @test parsed["level"] == "Info"
            @test parsed["line"] == 42
        end

        @testset "JsonFormat escaping" begin
            escape_record = (level=Base.CoreLogging.Warn, message="line1\nline2 \"quoted\"",
                _module=nothing, file="test.jl", line=1, group=:test, id=:test)
            buf = IOBuffer()
            BazerUtils.format_log(buf, BazerUtils.JsonFormat(), escape_record, T;
                displaysize=(50,100))
            output = strip(String(take!(buf)))
            parsed = JSON.parse(output)
            @test parsed["message"] == "line1\nline2 \"quoted\""
            @test parsed["module"] == "unknown"
        end

        @testset "LogfmtFormat" begin
            buf = IOBuffer()
            BazerUtils.format_log(buf, BazerUtils.LogfmtFormat(), log_record, T;
                displaysize=(50,100))
            output = strip(String(take!(buf)))
            @test contains(output, "ts=2024-01-15T14:30:00")
            @test contains(output, "level=Info")
            @test contains(output, "module=BazerUtils")
            @test contains(output, "msg=\"test message\"")
        end

        @testset "LogfmtFormat _module=nothing" begin
            buf = IOBuffer()
            BazerUtils.format_log(buf, BazerUtils.LogfmtFormat(), nothing_record, T;
                displaysize=(50,100))
            output = strip(String(take!(buf)))
            @test contains(output, "module=unknown")
        end

        @testset "SyslogFormat _module=nothing" begin
            buf = IOBuffer()
            BazerUtils.format_log(buf, BazerUtils.SyslogFormat(), nothing_record, T;
                displaysize=(50,100))
            output = String(take!(buf))
            @test contains(output, "nothing mod")
            @test !contains(output, "nothing[")  # should not show "nothing" as module in brackets
        end

        @testset "Log4jStandardFormat" begin
            buf = IOBuffer()
            BazerUtils.format_log(buf, BazerUtils.Log4jStandardFormat(), log_record, T;
                displaysize=(50,100))
            output = strip(String(take!(buf)))
            # Pattern: timestamp LEVEL [threadid] module - message
            @test contains(output, "2024-01-15 14:30:00,000")
            @test contains(output, "INFO ")
            @test contains(output, "BazerUtils")
            @test contains(output, " - ")
            @test contains(output, "test message")
        end

        @testset "Log4jStandardFormat _module=nothing" begin
            buf = IOBuffer()
            BazerUtils.format_log(buf, BazerUtils.Log4jStandardFormat(), nothing_record, T;
                displaysize=(50,100))
            output = strip(String(take!(buf)))
            @test contains(output, "unknown")
            @test contains(output, "nothing mod")
        end
    end
```

**IMPORTANT:** Also add `import Dates` to `test/runtests.jl` imports (after `import HTTP`).

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/loulou/Dropbox/projects_code/julia_packages/BazerUtils.jl && julia --project -e 'using Pkg; Pkg.test()'`
Expected: FAIL — `format_log` not defined

- [ ] **Step 3: Implement all format_log methods**

Add to `src/CustomLogger.jl` AFTER the `shorten_path_str` function (at the end of the file). Keep old format functions (`format_pretty`, `format_log4j`, `format_syslog`, `get_color`, etc.) in place for now — they will be removed in Task 7:

```julia
# --- Constants ---

const SYSLOG_SEVERITY = Dict(
    Logging.Info  => 6,  # Informational
    Logging.Warn  => 4,  # Warning
    Logging.Error => 3,  # Error
    Logging.Debug => 7   # Debug
)

const JULIA_BIN = Base.julia_cmd().exec[1]

# --- ANSI color helpers (for PrettyFormat) ---

function get_color(level)
    BOLD = "\033[1m"
    LIGHT_BLUE = "\033[94m"
    RED = "\033[31m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    return level == Logging.Debug ? LIGHT_BLUE :
           level == Logging.Info  ? GREEN :
           level == Logging.Warn  ? "$YELLOW$BOLD" :
           level == Logging.Error ? "$RED$BOLD" :
           "\033[0m"
end


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

    ts = Dates.format(timestamp, ISODateTimeFormat)
    severity = get(SYSLOG_SEVERITY, log_record.level, 6)
    pri = (1 * 8) + severity  # facility=1 (user-level)
    hostname = gethostname()
    pid = getpid()
    msg = reformat_msg(log_record; displaysize=displaysize) |> msg_to_singleline

    println(io, "<$pri>1 $ts $hostname $JULIA_BIN $pid - - $msg")
end

function format_log(io, ::JsonFormat, log_record::NamedTuple, timestamp::Dates.DateTime;
        displaysize::Tuple{Int,Int}=(50,100),
        kwargs...)

    ts = Dates.format(timestamp, ISODateTimeFormat)
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

    ts = Dates.format(timestamp, ISODateTimeFormat)
    level = string(log_record.level)
    mod_name = get_module_name(log_record._module)
    file = logfmt_escape(string(log_record.file))
    msg = logfmt_escape(reformat_msg(log_record; displaysize=displaysize))

    println(io, "ts=$ts level=$level module=$mod_name file=$file line=$(log_record.line) msg=$msg")
end

function format_log(io, ::Log4jStandardFormat, log_record::NamedTuple, timestamp::Dates.DateTime;
        displaysize::Tuple{Int,Int}=(50,100),
        kwargs...)

    # Apache Log4j PatternLayout: %d{yyyy-MM-dd HH:mm:ss,SSS} %-5p [%t] %c - %m%n
    ts = format(timestamp, "yyyy-mm-dd HH:MM:SS")
    millis = lpad(Dates.millisecond(timestamp), 3, '0')
    level = rpad(uppercase(string(log_record.level)), 5)
    thread_id = Threads.threadid()
    mod_name = get_module_name(log_record._module)
    msg = reformat_msg(log_record; displaysize=displaysize) |> msg_to_singleline

    println(io, "$ts,$millis $level [$thread_id] $mod_name - $msg")
end
```

- [ ] **Step 4: Update BazerUtils.jl imports**

Add `Logging.Error` to the Logging import line in `src/BazerUtils.jl`:

```julia
import Logging: global_logger, Logging, Logging.Debug, Logging.Info, Logging.Warn, Logging.Error
```

- [ ] **Step 5: Run tests to verify format_log tests pass**

Run: `cd /Users/loulou/Dropbox/projects_code/julia_packages/BazerUtils.jl && julia --project -e 'using Pkg; Pkg.test()'`
Expected: All `format_log methods` tests pass.

- [ ] **Step 6: Commit**

```bash
git add src/CustomLogger.jl src/BazerUtils.jl test/UnitTests/customlogger.jl test/runtests.jl
git commit -m "feat: implement format_log methods for all 6 formats"
```

---

### Task 4: Rewrite custom_format, create_demux_logger, and custom_logger

This task replaces the core orchestration. `custom_format` uses dispatch instead of if/elseif. `create_demux_logger` gains `cascading_loglevels` and thread-safe locking. `custom_logger` gets updated kwargs.

**Files:**
- Modify: `src/CustomLogger.jl` (replace `custom_format`, `create_demux_logger`, `custom_logger`)

**IMPORTANT: Steps 1-4 below are ATOMIC.** Apply all four before running tests. The intermediate states between steps will not compile because they reference each other's new signatures.

- [ ] **Step 1: Rewrite custom_format**

Replace the old `custom_format` function (the one with the if/elseif chain) with:

```julia
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
```

- [ ] **Step 2: Rewrite create_demux_logger**

Replace the old `create_demux_logger` with:

```julia
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
```

- [ ] **Step 3: Rewrite custom_logger (main method)**

Replace the old `custom_logger(sink::LogSink; ...)` with:

```julia
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
            x -> typeof(getfield(Main, x)) <: Module && x !== :Main,
            names(Main, imported=true))
        all_filters = Symbol[x for x in unique(vcat(
            something(filtered_modules_specific, Symbol[]),
            something(filtered_modules_all, Symbol[]))) if !isnothing(x)]
        if !isempty(all_filters)
            missing = filter(x -> x ∉ imported_modules, all_filters)
            if !isempty(missing)
                @warn "Filtering non-imported modules: $(join(string.(missing), ", "))"
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
```

- [ ] **Step 4: Rewrite convenience constructors**

Replace the old convenience constructors:

```julia
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
```

- [ ] **Step 5: Run full test suite**

Run: `cd /Users/loulou/Dropbox/projects_code/julia_packages/BazerUtils.jl && julia --project -e 'using Pkg; Pkg.test()'`
Expected: The new unit tests pass. Some existing integration tests may fail due to the `:log4j` → `:oneline` default change and `cascading_loglevels=false` default. That's expected — we fix those in Task 6.

- [ ] **Step 6: Commit**

```bash
git add src/CustomLogger.jl
git commit -m "feat: rewrite custom_format, create_demux_logger, custom_logger with dispatch and cascading_loglevels"
```

---

### Task 5: Write tests for new features (cascading_loglevels, new formats, thread safety)

**Files:**
- Modify: `test/UnitTests/customlogger.jl`

- [ ] **Step 1: Add cascading_loglevels tests**

Add after existing integration tests:

```julia
    # -- exact level filtering (default: cascading_loglevels=false)
    log_path_cl = joinpath(tempdir(), "log_cascading")
    logger_exact = custom_logger(
        log_path_cl;
        overwrite=true, create_log_files=true)
    @error "ONLY_ERROR"
    @warn "ONLY_WARN"
    @info "ONLY_INFO"
    @debug "ONLY_DEBUG"
    log_files_exact = get_log_names(logger_exact)
    content_exact = read.(log_files_exact, String)
    # Positive: each file has its own level
    @test contains(content_exact[1], "ONLY_ERROR")
    @test contains(content_exact[2], "ONLY_WARN")
    @test contains(content_exact[3], "ONLY_INFO")
    @test contains(content_exact[4], "ONLY_DEBUG")
    # Negative: each file does NOT have other levels
    @test !contains(content_exact[1], "ONLY_WARN")
    @test !contains(content_exact[1], "ONLY_INFO")
    @test !contains(content_exact[1], "ONLY_DEBUG")
    @test !contains(content_exact[2], "ONLY_ERROR")
    @test !contains(content_exact[2], "ONLY_INFO")
    @test !contains(content_exact[2], "ONLY_DEBUG")
    @test !contains(content_exact[3], "ONLY_ERROR")
    @test !contains(content_exact[3], "ONLY_WARN")
    @test !contains(content_exact[3], "ONLY_DEBUG")
    @test !contains(content_exact[4], "ONLY_ERROR")
    @test !contains(content_exact[4], "ONLY_WARN")
    @test !contains(content_exact[4], "ONLY_INFO")
    close_logger(logger_exact, remove_files=true)

    # -- cascading level filtering (cascading_loglevels=true, old behavior)
    logger_cascade = custom_logger(
        log_path_cl;
        overwrite=true, create_log_files=true,
        cascading_loglevels=true)
    @error "CASCADE_ERROR"
    @warn "CASCADE_WARN"
    @info "CASCADE_INFO"
    @debug "CASCADE_DEBUG"
    log_files_cascade = get_log_names(logger_cascade)
    content_cascade = read.(log_files_cascade, String)
    # Error file: only errors
    @test contains(content_cascade[1], "CASCADE_ERROR")
    @test !contains(content_cascade[1], "CASCADE_WARN")
    # Warn file: warn + error
    @test contains(content_cascade[2], "CASCADE_WARN")
    @test contains(content_cascade[2], "CASCADE_ERROR")
    # Info file: info + warn + error
    @test contains(content_cascade[3], "CASCADE_INFO")
    @test contains(content_cascade[3], "CASCADE_WARN")
    @test contains(content_cascade[3], "CASCADE_ERROR")
    # Debug file: everything
    @test contains(content_cascade[4], "CASCADE_DEBUG")
    @test contains(content_cascade[4], "CASCADE_INFO")
    @test contains(content_cascade[4], "CASCADE_WARN")
    @test contains(content_cascade[4], "CASCADE_ERROR")
    close_logger(logger_cascade, remove_files=true)
```

- [ ] **Step 2: Add integration tests for new formats**

```julia
    # -- JSON format logger
    log_path_fmt = joinpath(tempdir(), "log_fmt")
    logger_json = custom_logger(
        log_path_fmt;
        log_format=:json, overwrite=true)
    @error "JSON_ERROR"
    @info "JSON_INFO"
    log_file_json = get_log_names(logger_json)[1]
    json_lines = filter(!isempty, split(read(log_file_json, String), "\n"))
    for line in json_lines
        parsed = JSON.parse(line)
        @test haskey(parsed, "timestamp")
        @test haskey(parsed, "level")
        @test haskey(parsed, "module")
        @test haskey(parsed, "message")
    end
    close_logger(logger_json, remove_files=true)

    # -- logfmt format logger
    logger_logfmt = custom_logger(
        log_path_fmt;
        log_format=:logfmt, overwrite=true)
    @error "LOGFMT_ERROR"
    @info "LOGFMT_INFO"
    log_file_logfmt = get_log_names(logger_logfmt)[1]
    logfmt_content = read(log_file_logfmt, String)
    @test contains(logfmt_content, "level=Error")
    @test contains(logfmt_content, "level=Info")
    @test contains(logfmt_content, r"ts=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}")
    @test contains(logfmt_content, "msg=")
    close_logger(logger_logfmt, remove_files=true)

    # -- log4j_standard format logger
    logger_l4js = custom_logger(
        log_path_fmt;
        log_format=:log4j_standard, overwrite=true)
    @error "L4JS_ERROR"
    @info "L4JS_INFO"
    log_file_l4js = get_log_names(logger_l4js)[1]
    l4js_content = read(log_file_l4js, String)
    # Pattern: timestamp,millis LEVEL [threadid] module - message
    @test contains(l4js_content, r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2},\d{3} ERROR")
    @test contains(l4js_content, r"INFO .* - L4JS_INFO")
    @test contains(l4js_content, " - ")
    close_logger(logger_l4js, remove_files=true)
```

- [ ] **Step 3: Add unknown format and deprecation tests**

```julia
    # -- unknown format throws
    @test_throws ArgumentError custom_logger(
        joinpath(tempdir(), "log_bad"); log_format=:banana, overwrite=true)

    # -- :log4j deprecated alias still works
    logger_deprecated = custom_logger(
        log_path_fmt;
        log_format=:log4j, overwrite=true)
    @info "DEPRECATED_TEST"
    log_file_dep = get_log_names(logger_deprecated)[1]
    dep_content = read(log_file_dep, String)
    @test contains(dep_content, "DEPRECATED_TEST")
    close_logger(logger_deprecated, remove_files=true)
```

- [ ] **Step 4: Add thread safety test**

```julia
    # -- thread safety: concurrent logging produces complete lines
    log_path_thread = joinpath(tempdir(), "log_thread")
    logger_thread = custom_logger(
        log_path_thread;
        log_format=:json, overwrite=true)
    n_tasks = 10
    n_msgs = 50
    @sync for t in 1:n_tasks
        Threads.@spawn begin
            for m in 1:n_msgs
                @info "task=$t msg=$m"
            end
        end
    end
    log_file_thread = get_log_names(logger_thread)[1]
    flush(logger_thread.loggers[end].logger.logger.stream)  # flush stdout logger is irrelevant
    # Flush all file streams
    for lg in logger_thread.loggers
        s = lg.logger.logger.stream
        s isa IOStream && flush(s)
    end
    thread_lines = filter(!isempty, split(read(log_file_thread, String), "\n"))
    # Every line should be valid JSON (no interleaving)
    for line in thread_lines
        @test startswith(line, "{")
        @test endswith(line, "}")
        parsed = JSON.parse(line)
        @test haskey(parsed, "message")
    end
    close_logger(logger_thread, remove_files=true)
```

- [ ] **Step 5: Run tests (with threads for thread safety test)**

Run: `cd /Users/loulou/Dropbox/projects_code/julia_packages/BazerUtils.jl && julia --threads=4 --project -e 'using Pkg; Pkg.test()'`
Expected: New tests pass. Some old integration tests may still need updating (Task 6). **Note:** `--threads=4` is required so the thread safety test actually exercises concurrent writes.

- [ ] **Step 6: Commit**

```bash
git add test/UnitTests/customlogger.jl
git commit -m "test: add tests for cascading_loglevels, new formats, thread safety"
```

---

### Task 6: Update existing tests for breaking changes

The `cascading_loglevels=false` default changes behavior of the `[:debug, :info]` partial-loggers test. The `:log4j` format references in existing tests should use `:oneline` (or keep `:log4j` for the deprecation test, already covered).

**Files:**
- Modify: `test/UnitTests/customlogger.jl`

- [ ] **Step 1: Fix the partial file_loggers test**

The test at the end that uses `file_loggers = [:debug, :info]` expects cascading behavior where the debug file contains INFO messages. With `cascading_loglevels=false`, each file is exact-level. Update the test:

Old assertion:
```julia
@test contains.(log_content, r"INFO .* INFO MESSAGE") == [true, true]
```

Change to:
```julia
@test contains.(log_content, r"DEBUG .* DEBUG MESSAGE") == [true, false]
@test contains.(log_content, r"INFO .* INFO MESSAGE") == [false, true]
```

- [ ] **Step 2: Update existing format tests to use :oneline**

In the "logger with formatting" test block, change `log_format=:log4j` to `log_format=:oneline`.
In the "logger with formatting and truncation" test block, change `log_format=:log4j` to `log_format=:oneline`.

- [ ] **Step 3: Update _module=nothing test to use :oneline**

Change `log_format=:log4j` to `log_format=:oneline` in the `_module=nothing` test. Also update the `custom_format` call to use the new dispatch signature:

```julia
    # -- logger with _module=nothing (issue #10)
    logger_single = custom_logger(
        log_path;
        log_format=:oneline,
        overwrite=true)
    log_record = (level=Base.CoreLogging.Info, message="test nothing module",
        _module=nothing, file="test.jl", line=1, group=:test, id=:test)
    buf = IOBuffer()
    BazerUtils.custom_format(buf, BazerUtils.OnelineFormat(), log_record;
        shorten_path=:no)
    output = String(take!(buf))
    @test contains(output, "unknown")
    @test contains(output, "test nothing module")
    close_logger(logger_single, remove_files=true)
```

- [ ] **Step 4: Run full test suite**

Run: `cd /Users/loulou/Dropbox/projects_code/julia_packages/BazerUtils.jl && julia --project -e 'using Pkg; Pkg.test()'`
Expected: ALL tests pass.

- [ ] **Step 5: Commit**

```bash
git add test/UnitTests/customlogger.jl
git commit -m "test: update existing tests for :oneline rename and cascading_loglevels=false default"
```

---

### Task 7: Clean up dead code and update docstrings

**Files:**
- Modify: `src/CustomLogger.jl` — remove any leftover old code
- Modify: `src/BazerUtils.jl` — verify imports are clean

- [ ] **Step 1: Remove old format functions and dead code**

DELETE from `src/CustomLogger.jl`:
- Old `format_pretty` function (was kept alongside new `format_log` methods since Task 3)
- Old `format_log4j` function
- Old `format_syslog` function
- Old `custom_format` with if/elseif chain (replaced in Task 4)
- Old `create_demux_logger` signature (replaced in Task 4)
- Old `reformat_msg` with `log_format` kwarg (replaced in Task 1)
- Old `syslog_severity_map` dict with string keys (replaced by `SYSLOG_SEVERITY`)
- Old `julia_bin` const (replaced by `JULIA_BIN`)
- Old `get_color` function (replaced by new `get_color` in Task 3 — verify no duplication)
- Commented-out blocks in old `format_syslog`
- Orphaned section-separator comment blocks (`# ----...`)

- [ ] **Step 2: Verify BazerUtils.jl imports**

Ensure `src/BazerUtils.jl` imports include `Logging.Error` and that no unused imports remain:

```julia
import Dates: format, now, Dates, ISODateTimeFormat
import Logging: global_logger, Logging, Logging.Debug, Logging.Info, Logging.Warn, Logging.Error
import LoggingExtras: EarlyFilteredLogger, FormatLogger, MinLevelLogger, TeeLogger
import JSON: JSON
import Tables: Tables
import CodecZlib: CodecZlib
```

- [ ] **Step 3: Run full test suite**

Run: `cd /Users/loulou/Dropbox/projects_code/julia_packages/BazerUtils.jl && julia --project -e 'using Pkg; Pkg.test()'`
Expected: ALL tests pass.

- [ ] **Step 4: Commit**

```bash
git add src/CustomLogger.jl src/BazerUtils.jl
git commit -m "chore: remove dead code and clean up imports"
```

---

### Task 8: Version bump to v0.11.0

**Files:**
- Modify: `Project.toml`

- [ ] **Step 1: Bump version**

Change `version = "0.10.1"` to `version = "0.11.0"` in `Project.toml`.

- [ ] **Step 2: Add TODO comment for log4j deprecation timeline**

Add a comment in `src/CustomLogger.jl` near the `resolve_format` function:

```julia
# TODO (March 2027): Remove :log4j alias for :oneline. Rename :log4j_standard to :log4j.
# This is a breaking change requiring a major version bump.
```

- [ ] **Step 3: Run full test suite one final time**

Run: `cd /Users/loulou/Dropbox/projects_code/julia_packages/BazerUtils.jl && julia --project -e 'using Pkg; Pkg.test()'`
Expected: ALL tests pass.

- [ ] **Step 4: Commit**

```bash
git add Project.toml src/CustomLogger.jl
git commit -m "chore: bump version to v0.11.0 (breaking: cascading_loglevels default, :log4j renamed)"
```
