# BazerUtils.jl


[![CI](https://github.com/louloulibs/BazerUtils.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/louloulibs/BazerUtils.jl/actions/workflows/CI.yml)
[![Lifecycle:Experimental](https://img.shields.io/badge/Lifecycle-Experimental-339999)](https://github.com/louloulibs/BazerUtils.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/louloulibs/BazerUtils.jl/graph/badge.svg?token=53QO3HSSRT)](https://codecov.io/gh/louloulibs/BazerUtils.jl)



`BazerUtils.jl` is a package that assembles various functionality that I use on a frequent basis in julia.
It is a more mature version of [`Prototypes.jl`](https://github.com/louloulibs/Prototypes.jl) where I try a bunch of things out (there is overlap).


The package provides:

   - [`custom_logger`](#custom-logging): configurable logging with per-level file output, module filtering, and multiple format options (`:pretty`, `:oneline`, `:json`, `:logfmt`, `:syslog`, `:log4j_standard`)
   - ~~`read_jsonl` / `stream_jsonl` / `write_jsonl`~~: **deprecated** — use [`JSON.jl`](https://github.com/JuliaIO/JSON.jl) v1 with `jsonlines=true` instead


## Installation

`BazerUtils.jl` is a registered package.
You can install from the my julia registry [`loulouJL`](https://github.com/LouLouLibs/loulouJL) via the julia package manager:
```julia
> using Pkg, LocalRegistry
> pkg"registry add https://github.com/LouLouLibs/loulouJL.git"
> Pkg.add("BazerUtils")
```

If you don't want to add a new registry, you can install it directly from github:
```julia
> import Pkg; Pkg.add("https://github.com/louloulibs/BazerUtils.jl#main")
```


## Usage


### Custom Logging

A configurable logger that lets you filter messages from specific modules and redirect them to different files, with a format that is easy to read and control.

```julia
custom_logger(
    "./log/build_stable_sample_multiplier";
    file_loggers=[:warn, :debug],                             # which file loggers to deploy

    filtered_modules_all=[:HTTP],                             # filter across all loggers
    filtered_modules_specific=[:TranscodingStreams],           # filter for stdout and info only

    displaysize=(50,100),                                     # how much to show for non-string messages
    log_format=:oneline,                                      # format for files (see formats below)
    log_format_stdout=:pretty,                                # format for REPL

    cascading_loglevels=false,                                # false = each file gets only its level
                                                              # true  = each file gets its level and above

    create_log_files=true,                                    # separate file per level
    overwrite=true,
    );
```

#### Log Formats

| Format | Symbol | Description |
|--------|--------|-------------|
| **Pretty** | `:pretty` | Box-drawing + ANSI colors — default for stdout |
| **Oneline** | `:oneline` | Single-line with timestamp, level, module, file:line — default for files |
| **JSON** | `:json` | One JSON object per line — for log aggregation (ELK, Datadog, Loki) |
| **logfmt** | `:logfmt` | `key=value` pairs — grep-friendly, popular with Splunk/Heroku |
| **Syslog** | `:syslog` | RFC 5424 syslog format |
| **Log4j Standard** | `:log4j_standard` | Apache Log4j PatternLayout — for Java tooling interop |

Example output for each:

```
# :pretty (stdout default)
┌ [08:28:08 2025-02-12] Info |  @ Main[script.jl:42]
└ Processing batch 5 of 10

# :oneline (file default)
[/home/user/project] 2025-02-12 08:28:08 INFO  Main[./script.jl:42] Processing batch 5 of 10

# :json
{"timestamp":"2025-02-12T08:28:08","level":"INFO","module":"Main","file":"script.jl","line":42,"message":"Processing batch 5 of 10"}

# :logfmt
ts=2025-02-12T08:28:08 level=info module=Main file=script.jl line=42 msg="Processing batch 5 of 10"

# :syslog
<14>1 2025-02-12T08:28:08 hostname julia 12345 - - Processing batch 5 of 10

# :log4j_standard
2025-02-12 08:28:08,000 INFO  [1] Main - Processing batch 5 of 10
```

> **Note:** `:log4j` still works as a deprecated alias for `:oneline` and will be removed in a future version.


### JSON Lines (deprecated)

The JSONL functions (`read_jsonl`, `stream_jsonl`, `write_jsonl`) are deprecated.
Use [`JSON.jl`](https://github.com/JuliaIO/JSON.jl) v1 instead:
```julia
using JSON
data = JSON.parse("data.jsonl"; jsonlines=true)       # read
JSON.json("out.jsonl", data; jsonlines=true)           # write
```


## Other stuff


See my other package
  - [BazerData.jl](https://github.com/louloulibs/BazerData.jl) which groups together data wrangling functions.
  - [FinanceRoutines.jl](https://github.com/louloulibs/FinanceRoutines.jl) which is more focused and centered on working with financial data.
  - [TigerFetch.jl](https://github.com/louloulibs/TigerFetch.jl) which simplifies downloading shape files from the Census.
