# BazerUtils.jl Logger Cleanup & Format Expansion

**Date:** 2026-03-24
**Scope:** CustomLogger.jl rewrite — robustness, new formats, breaking changes
**Version target:** v0.11.0 (breaking)

## Summary

Rewrite the logging subsystem to fix robustness issues, add three new output formats (JSON, logfmt, log4j_standard), rename the misleading `:log4j` symbol to `:oneline`, introduce exact-level file filtering, and refactor the format dispatch from if/elseif chains to multiple dispatch on format types.

## Format Lineup

Six active formats plus one deprecated alias:

| Symbol | Description | Use case |
|--------|-------------|----------|
| `:pretty` | Box-drawing + ANSI colors | Stdout, human reading |
| `:oneline` | Single-line with timestamp, level, module, file:line, message | File logs, simple grep |
| `:syslog` | RFC 5424 syslog | Syslog collectors |
| `:json` | One JSON object per line (hand-rolled, no JSON.jl dependency) | Structured log aggregation (ELK, Datadog, Loki) |
| `:logfmt` | `key=value` pairs | Splunk, Heroku, grep-friendly structured |
| `:log4j_standard` | Actual Apache Log4j PatternLayout (`%d %-5p [%t] %c - %m%n`) | Java tooling interop |
| `:log4j` | **Deprecated alias** for `:oneline` — emits one-time `Base.depwarn` | Backwards compat only |

### JSON format (zero-dependency)

Hand-rolled serializer. Log records are flat with known types (strings, ints, symbols), so we only need string escaping + concatenation. No JSON.jl required.

Output:
```json
{"timestamp":"2024-01-15T14:30:00","level":"ERROR","module":"MyApp","file":"src/app.jl","line":42,"message":"Something failed"}
```

### logfmt format

```
ts=2024-01-15T14:30:00 level=error module=MyApp file=src/app.jl line=42 msg="Something failed"
```

### log4j_standard format

Follows Apache Log4j PatternLayout convention:
```
2024-01-15 14:30:00,123 ERROR [1] MyApp - Something failed
```

Where `[1]` is the Julia thread ID (analogous to Java's `[%t]` thread name).

### Deprecation timeline

- **v0.11.0 (now):** `:log4j` = deprecated alias for `:oneline`, `:log4j_standard` = real Apache format
- **~March 2027:** Remove `:log4j` alias, rename `:log4j_standard` to `:log4j`, bump major version

## Bug Fixes & Robustness

### 1. FileSink finalizer

Register `finalizer(close, obj)` in the `FileSink` constructor so GC cleans up leaked file handles. The `close` method must guard against closing `stdout`/`stderr` (defensive check: `if io !== stdout && io !== stderr`).

### 2. Thread safety

Add `locks::Vector{ReentrantLock}` to `FileSink`. When `create_files=false` (all streams write to the same file), use a **single shared lock** for all streams. When `create_files=true` (separate files), use one lock per stream. Wrap all `println(io, ...)` calls in `lock(lk) do ... end`. `ReentrantLock` (not `SpinLock`) to handle re-entrant logging from `show` methods.

Implementation: deduplicate IO handles when all files point to the same path — open the file once and share the IO + lock across all slots. This eliminates the aliased-file race condition.

### 3. `_module=nothing` in all formats

All six format methods must defensively handle `log_record._module === nothing`, falling back to `"unknown"`. Currently only `format_log4j` has this fix (v0.10.1). The three new formats (json, logfmt, log4j_standard) must include it from the start, and `format_pretty` needs the same fix applied.

### 4. Unknown log_format throws

`custom_format` will `throw(ArgumentError("Unknown log_format: :$log_format. Valid options: :pretty, :oneline, :syslog, :json, :logfmt, :log4j_standard"))` instead of silently producing no output.

### 5. reformat_msg double-call

Remove the dead `reformat_msg` call at top of `custom_format` (line 292). Each format function already calls it independently.

### 6. get_log_filenames(::Vector) inconsistency

Require exactly `length(file_loggers)` files. Throw `ArgumentError` for any other count. Remove the warn-for->4-then-truncate path.

### 7. Single timestamp per log entry

Call `now()` once in `custom_format` and pass the resulting `DateTime` to each format function. All three existing format functions (`format_pretty` line 370, `format_log4j` line 397, `format_syslog` line 425) currently call `now()` independently — these internal calls must all be removed and replaced with the passed-in timestamp parameter. Eliminates timestamp drift between capture and format.

## Breaking Changes

### cascading_loglevels

New kwarg `cascading_loglevels::Bool=false`:

- **`false` (new default):** Each file logger captures only its exact level. The error file gets errors only, the warn file gets warns only, etc. Implemented by replacing `MinLevelLogger` with an `EarlyFilteredLogger` that checks `log.level == target_level`. Non-standard log levels (arbitrary integers) are silently dropped under exact filtering — this is acceptable since custom levels are rare and users who need them can use `cascading_loglevels=true`.
- **`true` (old behavior):** Uses `MinLevelLogger` so each file captures its level and above (debug file gets everything, info gets info+warn+error, etc.).

### log_format default symbol

Default value changes from `:log4j` to `:oneline`. Functionally identical — same format, different name.

## Architecture: Multiple Dispatch Refactor

Replace the if/elseif chain in `custom_format` with dispatch on format types:

```julia
abstract type LogFormat end
struct PrettyFormat <: LogFormat end
struct OnelineFormat <: LogFormat end
struct SyslogFormat <: LogFormat end
struct JsonFormat <: LogFormat end
struct LogfmtFormat <: LogFormat end
struct Log4jStandardFormat <: LogFormat end
```

A `resolve_format` function maps symbols to types (handling the `:log4j` deprecation here):

```julia
function resolve_format(s::Symbol)::LogFormat
    s == :pretty && return PrettyFormat()
    s == :oneline && return OnelineFormat()
    s == :log4j && (Base.depwarn("...", :log4j); return OnelineFormat())
    s == :syslog && return SyslogFormat()
    s == :json && return JsonFormat()
    s == :logfmt && return LogfmtFormat()
    s == :log4j_standard && return Log4jStandardFormat()
    throw(ArgumentError("Unknown log_format: :$s"))
end
```

Each format implements a method that **writes directly to `io`** (not returns a string):
```julia
format_log(io, fmt::PrettyFormat, log_record, timestamp; kwargs...)
```

All format methods write directly to `io` so that the thread-safe lock wraps the entire format+write. The pretty format's multi-line box-drawing output (header + continuation lines + last line) is written as multiple `println` calls within the same locked block.

**`reformat_msg` refactor:** The current `reformat_msg` has a format-aware branch (`:color=>true` for pretty). Under the new dispatch, `reformat_msg` becomes format-unaware — it always returns a plain string. Pretty format adds color via ANSI codes in its own `format_log` method, not via `IOContext(:color=>true)` in `reformat_msg`.

**`shorten_path` applicability:** Only `:oneline` uses `shorten_path` (as the current `:log4j` does). The new formats (`:json`, `:logfmt`, `:log4j_standard`) use the raw file path. All formats are available for both `log_format` (file) and `log_format_stdout`.

**Deprecation warning text:** `":log4j is deprecated, use :oneline for single-line format or :log4j_standard for Apache Log4j format. :log4j will be removed in a future major version."`

**File organization:** All format types, `resolve_format`, and `format_log` methods stay in `CustomLogger.jl`. The file is small enough that splitting is unnecessary.

Shared logic (timestamp formatting, message reformatting, single-lining) lives in helper functions called by the format methods, not in a shared preamble.

## Thread Safety Architecture

The locking must happen at the `FormatLogger` callback level, since that's where `println(io, ...)` occurs. The `FileSink` owns the locks, and the format callback closures capture both the IO stream and its corresponding lock:

```julia
format_log_file = (io, log_record) -> lock(sink.locks[i]) do
    custom_format(io, fmt, log_record, now(); kwargs...)
end
```

This ensures the entire format+write is atomic per stream.

## Testing Plan

### New format tests
- `:json` — verify output parses as valid JSON, all expected keys present, string escaping works (newlines, quotes, backslashes in messages)
- `:logfmt` — verify key=value structure, quoted values with spaces, no unescaped quotes
- `:log4j_standard` — verify matches `%d %-5p [%t] %c - %m%n` pattern
- `:oneline` — existing tests adapted to use new symbol name

### Behavior tests
- `cascading_loglevels=false` — each file has only its level's messages; **negative assertions** that error file does NOT contain warn/info/debug, warn file does NOT contain error/info/debug, etc.
- `cascading_loglevels=true` — old cascading behavior preserved; error file has errors only, warn file has warn+error, info has info+warn+error, debug has everything
- Unknown format symbol — throws `ArgumentError`
- `:log4j` symbol — works but emits deprecation warning
- `_module=nothing` — works in all six formats

### Thread safety test
- Spawn N tasks each logging M messages concurrently
- Read the log file, verify no interleaved partial lines (every line is a complete log entry)

### Robustness tests
- FileSink finalizer — verify files are closeable after GC (hard to test deterministically, but verify `close(sink)` works)

## Out of Scope (Future PRs)

- **Log rotation** — file size limits, file renaming, count limits
- **`:log4j` alias removal** — ~March 2027, rename `:log4j_standard` to `:log4j`
