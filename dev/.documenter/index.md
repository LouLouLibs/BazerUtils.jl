
# BazerUtils.jl {#BazerUtils.jl}

Utility functions for everyday Julia.

## Features {#Features}
- **[Custom Logger](/man/logger_guide#Logging)**: Configurable logging with per-level file output, module filtering, and multiple format options (`pretty`, `log4j`, `syslog`).
  
- **[JSON Lines](/man/read_jsonl#Working-with-JSON-Lines-Files)** _(deprecated)_: Read/write JSONL files. Use [`JSON.jl`](https://github.com/JuliaIO/JSON.jl) v1 with `jsonlines=true` instead.
  

## Installation {#Installation}

```julia
using Pkg
pkg"registry add https://github.com/LouLouLibs/loulouJL.git"
Pkg.add("BazerUtils")
```


Or directly from GitHub:

```julia
Pkg.add(url="https://github.com/LouLouLibs/BazerUtils.jl")
```

