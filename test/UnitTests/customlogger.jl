@testset "CustomLogger" begin

    function get_log_names(logger_in)
        log_paths = map(l -> l.logger.logger.stream, logger_in.loggers) |>
          (s -> filter(x -> x isa IOStream, s)) |>
          (s -> map(x -> x.name, s)) |>
          (s -> map(x -> match(r"<file (.+)>", x)[1], s))
        return unique(string.(log_paths))
    end

    function close_logger(logger::TeeLogger; remove_files::Bool=false)
        # Get filenames before closing
        filenames = get_log_names(logger)        
        
        # Close all IOStreams
        for min_logger in logger.loggers
            stream = min_logger.logger.logger.stream
            if stream isa IOStream
                close(stream)
            end
        end
        remove_files && rm.(filenames)         # Optionally remove the files

        # Reset to default logger
        global_logger(ConsoleLogger(stderr))
    end

    log_path = joinpath.(tempdir(), "log")

    # -- logger with everything in one place ... 
    logger_single = custom_logger(
        log_path;
        overwrite=true) 
    @error "ERROR MESSAGE"
    @warn "WARN MESSAGE"
    @info "INFO MESSAGE"
    @debug "DEBUG MESSAGE"
    log_file = get_log_names(logger_single)[1]
    log_content = read(log_file, String)
    @test contains(log_content, "ERROR MESSAGE")
    @test contains(log_content, "WARN MESSAGE")
    @test contains(log_content, "INFO MESSAGE")
    @test contains(log_content, "DEBUG MESSAGE")
    close_logger(logger_single, remove_files=true)

    # -- logger across multiple files ... 
    logger_multiple = custom_logger(
        log_path;
        overwrite=true, create_log_files=true) 
    log_files = get_log_names(logger_multiple)
    @error "ERROR MESSAGE"
    @warn "WARN MESSAGE"
    @info "INFO MESSAGE"
    @debug "DEBUG MESSAGE"
    log_content = read.(log_files, String)
    @test contains(log_content[1], "ERROR MESSAGE")
    @test contains(log_content[2], "WARN MESSAGE")
    @test contains(log_content[3], "INFO MESSAGE")
    @test contains(log_content[4], "DEBUG MESSAGE")
    close_logger(logger_multiple, remove_files=true)

    # -- logger with absolute filtering
    logger_multiple = custom_logger(
        log_path;
        overwrite=true, create_log_files=true,
        filtered_modules_all=[:HTTP],
        ) ;
    log_files = get_log_names(logger_multiple)
    HTTP.get("http://example.com");
    log_content = read.(log_files, String)
    @test countlines(log_files[1]) == 0
    @test countlines(log_files[2]) == 0
    @test countlines(log_files[3]) == 0
    @test countlines(log_files[4]) != 0 # TranscodingStreams write here
    @test !contains(log_content[4], r"HTTP"i)
    close_logger(logger_multiple, remove_files=true)

    # -- logger with specific filtering
    logger_multiple = custom_logger(
        log_path;
        overwrite=true, create_log_files=true,
        filtered_modules_specific=[:HTTP],
        filtered_modules_all=[:TranscodingStreams],
        ) ;
    log_files = get_log_names(logger_multiple)
    HTTP.get("http://example.com");
    log_content = read.(log_files, String)
    @test countlines(log_files[1]) == 0
    @test countlines(log_files[2]) == 0
    @test countlines(log_files[3]) == 0; # this is getting filtered out
    @test countlines(log_files[4]) != 0  # TranscodingStreams write here
    @test contains(log_content[4], r"HTTP"i)
    close_logger(logger_multiple, remove_files=true)

    # -- logger with formatting
    logger_single = custom_logger(
        log_path;
        log_format=:log4j,
        overwrite=true) 
    @error "ERROR MESSAGE"
    @warn "WARN MESSAGE"
    @info "INFO MESSAGE"
    @debug "DEBUG MESSAGE"
    log_file = get_log_names(logger_single)[1]
    log_content = read(log_file, String)
    @test contains(log_content, r"ERROR .* ERROR MESSAGE")
    @test contains(log_content, r"WARN .* WARN MESSAGE")
    @test contains(log_content, r"INFO .* INFO MESSAGE")
    @test contains(log_content, r"DEBUG .* DEBUG MESSAGE")
    close_logger(logger_single, remove_files=true)

    # -- logger with formatting and truncation
    logger_single = custom_logger(
        log_path;
        log_format=:log4j,
        shorten_path=:truncate_middle,
        overwrite=true) 
    @error "ERROR MESSAGE"
    @warn "WARN MESSAGE"
    @info "INFO MESSAGE"
    @debug "DEBUG MESSAGE"
    HTTP.get("http://example.com");
    log_file = get_log_names(logger_single)[1]
    log_content = read(log_file, String)
    # println(log_content)
    @test contains(log_content, r"ERROR .* ERROR MESSAGE")
    @test contains(log_content, r"WARN .* WARN MESSAGE")
    @test contains(log_content, r"INFO .* INFO MESSAGE")
    @test contains(log_content, r"DEBUG .* DEBUG MESSAGE")
    @test contains(log_content, "…")
    close_logger(logger_single, remove_files=true)

    # -- syslog logger
    logger_single = custom_logger(
        log_path;
        log_format=:syslog,
        shorten_path=:truncate_middle,
        overwrite=true) 
    @error "ERROR MESSAGE"
    @warn "WARN MESSAGE"
    @info "INFO MESSAGE"
    @debug "DEBUG MESSAGE"
    HTTP.get("http://example.com");
    log_file = get_log_names(logger_single)[1]
    log_content = read(log_file, String)
    # println(log_content)
    # we should test for the lines 
    log_lines = split(log_content, "\n")
    @test all(map(contains("ERROR"), filter(contains("<11>"), log_lines)))
    @test all(map(contains("WARN"), filter(contains("<12>"), log_lines)))
    @test all(map(contains("INFO"), filter(contains("<14>"), log_lines)))
    @test any(map(contains("DEBUG"), filter(contains("<15>"), log_lines)))
    close_logger(logger_single, remove_files=true)

   # -- logger to only one file sink 
    log_path = joinpath.(tempdir(), "log")
    logger_single = custom_logger(
        log_path;
        create_log_files=true, overwrite=true, 
        file_loggers = [:debug, :info])
    @debug "DEBUG MESSAGE"
    @info "INFO MESSAGE"
    log_file = get_log_names(logger_single)
    log_content = read.(log_file, String)
    @test contains.(log_content, r"DEBUG .* DEBUG MESSAGE") == [true, false]
    @test contains.(log_content, r"INFO .* INFO MESSAGE") == [true, true]
    close_logger(logger_single, remove_files=true)

end









