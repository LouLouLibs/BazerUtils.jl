#!/usr/bin/env julia


# push!(LOAD_PATH, "../src/")
# import Pkg; Pkg.develop("../src")
# locally : julia --color=yes --project make.jl


# --------------------------------------------------------------------------------------------------
# --
using BazerUtils
using Documenter
using DocumenterVitepress

# --
makedocs(
    format = Documenter.HTML(
        size_threshold = 512_000,          # KiB — raise above your largest file
        size_threshold_warn = 256_000,     # optional
        example_size_threshold = 200_000,  # bytes — for large @example blocks
    ),
    # format = DocumenterVitepress.MarkdownVitepress(
    #     repo = "https://github.com/eloualiche/BazerUtils.jl",
    # ),
    repo = Remotes.GitHub("eloualiche", "BazerUtils.jl"),
    sitename = "BazerUtils.jl",
    modules  = [BazerUtils],
    authors = "Erik Loualiche",
    pages=[
        "Home" => "index.md",
        "Manual" => [
            "man/logger_guide.md",
            "man/read_jsonl.md",
        ],
        # "Demos" => [
        # ],
        "Library" => [
            "lib/public.md",
            "lib/internals.md"
        ]
    ]
)


deploydocs(;
    repo = "github.com/eloualiche/BazerUtils.jl",
    target = "build", # this is where Vitepress stores its output
    devbranch = "main",
    branch = "gh-pages",
    push_preview = true,
)
# --------------------------------------------------------------------------------------------------
