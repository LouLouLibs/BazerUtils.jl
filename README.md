# BazerUtils.jl


[![CI](https://github.com/louloulibs/BazerUtils.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/louloulibs/BazerUtils.jl/actions/workflows/CI.yml)
[![Lifecycle:Experimental](https://img.shields.io/badge/Lifecycle-Experimental-339999)](https://github.com/louloulibs/BazerUtils.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/louloulibs/BazerUtils.jl/graph/badge.svg?token=53QO3HSSRT)](https://codecov.io/gh/louloulibs/BazerUtils.jl)



`BazerUtils.jl` is a package that assembles various functionality that I use on a frequent basis in julia.
It is a more mature version of [`Prototypes.jl`](https://github.com/louloulibs/Prototypes.jl) where I try a bunch of things out (there is overlap).


So far the package provides a two sets of functions:

   - [`custom_logger`](#custom-logging) is a custom logging output that builds on the standard julia logger
   - [`read_jsonl`](#json-lines) provides utilities to read and write json-lines files


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

This one is a little niche.
I wanted to have a custom logger that would allow me to filter messages from specific modules and redirect them to different files, which I find useful to monitor long jobs in a format that is easy to read and that I can control.
The formatter is hard-coded to what I like but I guess I could change it easily and make it an option.

Here is an example where you can create a custom logger and redirect logging to different files.
See the doc for more [examples](https://louloulibs.github.io/BazerUtils.jl/dev/man/logger_guide)
```julia
custom_logger(
    "./log/build_stable_sample_multiplier";                   # prefix of log-file being generated
    file_loggers=[:warn, :debug],                             # which file logger to deploy 

    filtered_modules_all=[:HTTP],                             # filtering messages across all loggers from specific modules
    filtered_modules_specific=[:TranscodingStreams],          # filtering messages for stdout and info from specific modules

    displaysize=(50,100),                                     # how much to show
    log_format=:log4j,                                        # how to format the log for files
    log_format_stdout = :pretty,                              # how to format the log for the repl

    create_log_files=true,                                    # if false all logs are written to a single file    
    overwrite=true,                                            # overwrite old logs    
    
    );
```


### JSON Lines

A easy way to read json lines files into julia leaning on `JSON3` reader.


## Other stuff


See my other package 
  - [BazerData.jl](https://github.com/louloulibs/BazerData.jl) which groups together data wrangling functions.
  - [FinanceRoutines.jl](https://github.com/louloulibs/FinanceRoutines.jl) which is more focused and centered on working with financial data.
  - [TigerFetch.jl](https://github.com/louloulibs/TigerFetch.jl) which simplifies downloading shape files from the Census.
