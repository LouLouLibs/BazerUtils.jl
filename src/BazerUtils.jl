module BazerUtils


# --------------------------------------------------------------------------------------------------
import Dates: format, now, Dates
import Logging: global_logger, Logging, Logging.Debug, Logging.Info, Logging.Warn, Logging.Error
import LoggingExtras: EarlyFilteredLogger, FormatLogger, MinLevelLogger, TeeLogger
import JSON: JSON
import Tables: Tables
import CodecZlib: CodecZlib
# --------------------------------------------------------------------------------------------------


# --------------------------------------------------------------------------------------------------
# Import functions
include("CustomLogger.jl")
include("JSONLines.jl")
include("HTMLTables.jl")
# --------------------------------------------------------------------------------------------------


# --------------------------------------------------------------------------------------------------
# List of exported functions
export custom_logger
export read_jsonl, stream_jsonl, write_jsonl
export read_html_tables
# --------------------------------------------------------------------------------------------------


end
