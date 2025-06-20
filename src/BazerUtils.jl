module BazerUtils


# --------------------------------------------------------------------------------------------------
import Dates: format, now, Dates, ISODateTimeFormat
import Logging: global_logger, Logging, Logging.Debug, Logging.Info, Logging.Warn, AbstractLogger
import LoggingExtras: ConsoleLogger, EarlyFilteredLogger, FileLogger, FormatLogger,
    MinLevelLogger, TeeLogger, TransformerLogger
import JSON3: JSON3
import Tables: Tables
import CodecZlib: CodecZlib
# --------------------------------------------------------------------------------------------------


# --------------------------------------------------------------------------------------------------
# Import functions
include("CustomLogger.jl")
include("JSONLines.jl")
# --------------------------------------------------------------------------------------------------


# --------------------------------------------------------------------------------------------------
# List of exported functions
export custom_logger
export read_jsonl, stream_jsonl, write_jsonl
# --------------------------------------------------------------------------------------------------


end
