# Log Rotation Design

**Date:** 2026-03-24
**Scope:** Size-based log rotation for FileSink
**Version target:** v0.11.1 (non-breaking, additive)

## Summary

Add opt-in size-based log rotation to `FileSink`. When a log file exceeds `max_size` bytes, it is closed, renamed with a timestamp suffix, and a fresh file is opened. Old rotated files can be automatically cleaned up via `max_files`.

## Public API

Two new kwargs on the convenience constructors of `custom_logger` (the `filename` and batch-mode methods). These kwargs are threaded into `FileSink` — the core `custom_logger(sink::LogSink; ...)` method does not need them since they live on the sink.

| Kwarg | Type | Default | Description |
|-------|------|---------|-------------|
| `max_size` | `Int` | `0` (disabled) | Max bytes per log file before rotation |
| `max_files` | `Int` | `0` (no limit) | Max rotated files to keep per log path. `0` = keep all |

Rotation is opt-in — `max_size=0` means no rotation (current behavior unchanged).

**Validation:** `max_size < 0` or `max_files < 0` throws `ArgumentError`. No minimum `max_size` enforced, but values under 1024 emit a warning.

```julia
custom_logger("/tmp/myapp";
    create_log_files=true,
    max_size=10_000_000,   # 10 MB
    max_files=5)           # keep 5 rotated + 1 current
```

## RotatableIO Wrapper

**Problem:** `FormatLogger` from LoggingExtras.jl captures its IO handle at construction time. After rotation replaces `sink.ios[i]`, the `FormatLogger` would still write to the old closed IO. Additionally, `format_cb` never sees the formatted output string, so there is no natural place to count bytes.

**Solution:** A thin IO wrapper that solves both problems:

```julia
mutable struct RotatableIO <: IO
    sink::FileSink
    index::Int
    bytes::Ref{Int}  # shared counter (deduplicated like ios/locks)
end

function Base.write(rio::RotatableIO, data::Union{UInt8, AbstractVector{UInt8}})
    n = write(rio.sink.ios[rio.index], data)
    rio.bytes[] += n
    # Check rotation after write
    if rio.sink.max_size > 0 && rio.bytes[] > rio.sink.max_size
        rotate!(rio.sink, rio.index)
    end
    return n
end

# Forward other IO methods needed by FormatLogger
Base.flush(rio::RotatableIO) = flush(rio.sink.ios[rio.index])
Base.isopen(rio::RotatableIO) = isopen(rio.sink.ios[rio.index])
```

**How it works:**
- `FormatLogger` holds a `RotatableIO` instead of the raw file IO
- Every `write` delegates to `sink.ios[rio.index]` — always the current handle
- Byte counting is exact (counts actual bytes flowing through `write`)
- Rotation check happens in `write`, inside the existing lock
- No changes needed to `format_cb` or `custom_format` or any `format_log` method

## Byte Tracking

Byte counting is exact — `RotatableIO.write` counts every byte as it flows through. No `stat()` calls, no approximation.

In single-file mode (IO deduplication), all `RotatableIO` wrappers that share the same file path share the same `Ref{Int}` counter. This mirrors the existing deduplication pattern for `ios` and `locks`: a `Dict(path => Ref{Int}(initial_size))` is built in the constructor, and each slot maps to its shared counter.

On construction, each counter is initialized to the current file size via `stat(path).size` (one-time cost at startup, handles append mode correctly).

## FileSink Changes

```julia
mutable struct FileSink <: LogSink
    files::Vector{String}
    ios::Vector{IO}
    locks::Vector{ReentrantLock}
    rios::Vector{RotatableIO}    # wrapper IOs passed to FormatLogger
    max_size::Int
    max_files::Int
end
```

The constructor builds `rios` after `ios` and `locks`:

```julia
# Deduplicated byte counters (one per unique path)
path_to_bytes = Dict(p => Ref{Int}(stat(p).size) for p in unique_paths)
rios = [RotatableIO(obj, i, path_to_bytes[files[i]]) for i in eachindex(files)]
```

`create_demux_logger` passes `sink.rios[io_index]` to `FormatLogger` instead of `sink.ios[io_index]`.

## Rotation Mechanics

### rotate! function

```julia
function rotate!(sink::FileSink, trigger_index::Int)
    path = sink.files[trigger_index]

    # 1. Close the current IO for this path
    old_io = sink.ios[trigger_index]
    isopen(old_io) && close(old_io)

    # 2. Rename to timestamp suffix
    rotated_name = make_rotated_name(path)
    mv(path, rotated_name)

    # 3. Open fresh file
    new_io = open(path, "a")

    # 4. Update ALL slots sharing this path (handles IO dedup)
    for j in eachindex(sink.ios)
        if sink.files[j] == path
            sink.ios[j] = new_io
        end
    end

    # 5. Reset the shared byte counter
    sink.rios[trigger_index].bytes[] = 0

    # 6. Cleanup old files (done inline — fast for typical file counts)
    if sink.max_files > 0
        cleanup_rotated_files!(path, sink.max_files)
    end
end
```

### Thread safety

Rotation happens inside the existing `lock(sink.locks[i]) do ... end` block (via the `RotatableIO.write` method, which is called from within the locked `format_cb` closure). Since the lock is already held, rotation is atomic with respect to concurrent writers on the same stream.

For single-file mode, all streams share one lock, so rotation of the shared file is safe. The `rotate!` function updates ALL slots sharing the same path, preventing stale IO references.

### Cleanup

`cleanup_rotated_files!(path, max_files)`:
1. Extract base name and extension from `path`
2. Glob for `base.*.ext` in the same directory
3. Sort by filename (timestamp suffix sorts chronologically)
4. Delete oldest files until count <= `max_files`

## Timestamp Suffix Format

| State | Filename |
|-------|----------|
| Current | `app.log` |
| Rotated | `app.2026-03-24T14-30-00-123.log` |

Pattern: insert timestamp before the final extension. Format `yyyy-mm-ddTHH-MM-SS-sss` (includes milliseconds to avoid sub-second collisions). Uses hyphens instead of colons for filesystem compatibility.

For files without an extension (e.g., `myapp`), the suffix is appended: `myapp.2026-03-24T14-30-00-123`.

For multi-level extensions (e.g., `app_error.log`), the timestamp is inserted before `.log`: `app_error.2026-03-24T14-30-00-123.log`.

## Testing Plan

### Unit tests
- `RotatableIO`: write bytes, verify counter incremented correctly
- `rotate!` on a FileSink: verify old file renamed with timestamp, new file opened, counter reset
- `rotate!` in single-file mode: verify all slots updated, shared counter reset
- `rotate!` with `max_files=2`: verify only 2 rotated files kept after 3 rotations
- `rotate!` with `max_files=0`: verify all rotated files kept
- `make_rotated_name`: correct timestamp insertion for `.log`, no-extension, multi-extension
- Validation: `max_size=-1` throws `ArgumentError`, `max_files=-1` throws `ArgumentError`

### Integration tests
- Create logger with `max_size=500`, write enough messages to trigger rotation, verify multiple files exist with timestamp suffixes
- Verify current log file is always the original filename
- Verify content continuity: messages before and after rotation are all present across files
- Verify log format is preserved after rotation (e.g., JSON lines still valid)

### Edge cases
- `max_size=0`: no rotation (current behavior)
- Single-file mode with rotation: all levels rotate together since they share one IO
- Append to existing file: byte counter initialized to current file size, rotation triggers correctly
- Sub-second rotation: millisecond suffix prevents filename collisions

## Out of Scope

- Time-based rotation
- Compression of rotated files (could be a future addition)
- Remote/network log sinks
