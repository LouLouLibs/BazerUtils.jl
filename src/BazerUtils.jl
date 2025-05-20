module BazerUtils


# --------------------------------------------------------------------------------------------------
import Dates: format, now, Dates, ISODateTimeFormat 
import Logging: global_logger, Logging, Logging.Debug, Logging.Info, Logging.Warn, AbstractLogger
import LoggingExtras: ConsoleLogger, EarlyFilteredLogger, FileLogger, FormatLogger, 
    MinLevelLogger, TeeLogger, TransformerLogger

# --------------------------------------------------------------------------------------------------


# --------------------------------------------------------------------------------------------------
# Import functions
include("CustomLogger.jl")
# --------------------------------------------------------------------------------------------------


# --------------------------------------------------------------------------------------------------
# List of exported functions
export custom_logger
# --------------------------------------------------------------------------------------------------


end
