# --------------------------------------------------------------------------------------------------
using BazerUtils
using Test

import Logging: global_logger
import LoggingExtras: ConsoleLogger, TeeLogger
import JSON
import CodecZlib
import HTTP
import Dates
import DataFrames

const testsuite = [
    "customlogger",
    "jsonlines",
    "html_tables"
]

# --------------------------------------------------------------------------------------------------


# --------------------------------------------------------------------------------------------------
printstyled("Running tests:\n", color=:blue, bold=true)

@testset verbose=true "BazerUtils.jl" begin
    for test in testsuite
        println("\033[1m\033[32m  → RUNNING\033[0m: $(test)")
        include("UnitTests/$test.jl")
        println("\033[1m\033[32m  PASSED\033[0m")
    end
end
# --------------------------------------------------------------------------------------------------
