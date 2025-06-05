#!/usr/bin/env julia


push!(LOAD_PATH, "../src/")
# Pkg.develop("../") to make sure its the correct version of package installed
# julia --project -e 'using Pkg; Pkg.instantiate(); include("make.jl")'

# --------------------------------------------------------------------------------------------------
# --
using BazerUtils
using Documenter
using DocumenterVitepress

# --
DocMeta.setdocmeta!(BazerUtils, :DocTestSetup, :(using BazerUtils);
    recursive=true)

# --
makedocs(
    # format = Documenter.HTML(),
    format = MarkdownVitepress(
        repo = "https://github.com/louloulibs/BazerUtils.jl",
        devurl = "dev",
        devbranch = "build",
        deploy_url = "louloulibs.github.io/BazerUtils.jl",
        description = "BazerUtils.jl",
    ),
    sitename = "BazerUtils.jl",
    modules  = [BazerUtils],
    authors = "Erik Loualiche",
    repo = Remotes.GitHub("louloulibs", "BazerUtils.jl"),
    pages=[
        "Home" => "index.md",
        "Manual" => [
            "man/logger_guide.md",
            "man/read_jsonl.md",
        ],
        "Library" => [
            "lib/public.md",
            "lib/internals.md"
        ]
    ],
)


deploydocs(
    repo="github.com/louloulibs/BazerUtils.jl",
    target = "build",
)

deploydocs(;
    repo="github.com/louloulibs/BazerUtils.jl",
    target = "build",
    branch = "gh-pages",
    devbranch = "main",  # or "master"
)


# --------------------------------------------------------------------------------------------------
