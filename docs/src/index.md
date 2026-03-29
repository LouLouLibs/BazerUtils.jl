# BazerUtils.jl

Utility functions for everyday Julia.

## Features

- **[Custom Logger](@ref Logging)**: Configurable logging with per-level file output, module filtering, thread safety, and six format options (`pretty`, `oneline`, `json`, `logfmt`, `syslog`, `log4j_standard`).
- **[HTML Tables](@ref "Reading HTML Tables")**: Parse HTML tables from URLs or strings into DataFrames — a Julia-native replacement for pandas' `read_html`.
- **[JSON Lines](@ref "Working with JSON Lines Files")** *(deprecated)*: Read/write JSONL files. Use [`JSON.jl`](https://github.com/JuliaIO/JSON.jl) v1 with `jsonlines=true` instead.

## Installation

```julia
using Pkg
pkg"registry add https://github.com/LouLouLibs/loulouJL.git"
Pkg.add("BazerUtils")
```

Or directly from GitHub:
```julia
Pkg.add(url="https://github.com/LouLouLibs/BazerUtils.jl")
```

