@testset "CustomLogger" begin

    function get_log_names(logger_in)
        log_paths = map(l -> l.logger.logger.stream, logger_in.loggers) |>
          (s -> filter(x -> x isa IOStream, s)) |>
          (s -> map(x -> x.name, s)) |>
          (s -> filter(x -> contains(x, "<file "), s)) |>
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

    @testset "resolve_format" begin
        @test BazerUtils.resolve_format(:pretty) isa BazerUtils.PrettyFormat
        @test BazerUtils.resolve_format(:oneline) isa BazerUtils.OnelineFormat
        @test BazerUtils.resolve_format(:syslog) isa BazerUtils.SyslogFormat
        @test BazerUtils.resolve_format(:json) isa BazerUtils.JsonFormat
        @test BazerUtils.resolve_format(:logfmt) isa BazerUtils.LogfmtFormat
        @test BazerUtils.resolve_format(:log4j_standard) isa BazerUtils.Log4jStandardFormat
        @test_throws ArgumentError BazerUtils.resolve_format(:invalid_format)
        # :log4j is deprecated alias for :oneline
        @test BazerUtils.resolve_format(:log4j) isa BazerUtils.OnelineFormat
    end

    @testset "get_module_name" begin
        @test BazerUtils.get_module_name(nothing) == "unknown"
        @test BazerUtils.get_module_name(Base) == "Base"
        @test BazerUtils.get_module_name(Main) == "Main"
    end

    @testset "json_escape" begin
        @test BazerUtils.json_escape("hello") == "hello"
        @test BazerUtils.json_escape("line1\nline2") == "line1\\nline2"
        @test BazerUtils.json_escape("say \"hi\"") == "say \\\"hi\\\""
        @test BazerUtils.json_escape("back\\slash") == "back\\\\slash"
        @test BazerUtils.json_escape("tab\there") == "tab\\there"
    end

    @testset "logfmt_escape" begin
        @test BazerUtils.logfmt_escape("simple") == "simple"
        @test BazerUtils.logfmt_escape("has space") == "\"has space\""
        @test BazerUtils.logfmt_escape("has\"quote") == "\"has\\\"quote\""
        @test BazerUtils.logfmt_escape("has=equals") == "\"has=equals\""
    end

    @testset "FileSink" begin
        tmp = tempname()
        # Single file mode: deduplicates IO handles
        sink = BazerUtils.FileSink(tmp; create_files=false)
        @test length(sink.ios) == 4
        @test length(unique(objectid.(sink.ios))) == 1  # all same IO
        @test length(sink.locks) == 4
        @test length(unique(objectid.(sink.locks))) == 1  # all same lock
        @test all(io -> io !== stdout && io !== stderr, sink.ios)
        close(sink)
        rm(tmp, force=true)

        # Multi file mode: separate IO handles
        sink2 = BazerUtils.FileSink(tmp; create_files=true)
        @test length(sink2.ios) == 4
        @test length(unique(objectid.(sink2.ios))) == 4  # all different IO
        @test length(unique(objectid.(sink2.locks))) == 4  # all different locks
        close(sink2)
        rm.(BazerUtils.get_log_filenames(tmp; create_files=true), force=true)

        # close guard: closing twice doesn't error
        sink3 = BazerUtils.FileSink(tempname(); create_files=false)
        close(sink3)
        @test_nowarn close(sink3)  # second close is safe

        # Count mismatch throws ArgumentError
        @test_throws ArgumentError BazerUtils.get_log_filenames(["a.log", "b.log"])
        @test_throws ArgumentError BazerUtils.get_log_filenames(["a.log", "b.log", "c.log", "d.log", "e.log"])
    end

    @testset "format_log methods" begin
        T = Dates.DateTime(2024, 1, 15, 14, 30, 0)
        log_record = (level=Base.CoreLogging.Info, message="test message",
            _module=BazerUtils, file="/src/app.jl", line=42, group=:test, id=:test)
        nothing_record = (level=Base.CoreLogging.Info, message="nothing mod",
            _module=nothing, file="test.jl", line=1, group=:test, id=:test)

        @testset "PrettyFormat" begin
            buf = IOBuffer()
            BazerUtils.format_log(buf, BazerUtils.PrettyFormat(), log_record, T;
                displaysize=(50,100))
            output = String(take!(buf))
            @test contains(output, "test message")
            @test contains(output, "14:30:00")
            @test contains(output, "BazerUtils")
            @test contains(output, "┌")
            @test contains(output, "└")
        end

        @testset "PrettyFormat _module=nothing" begin
            buf = IOBuffer()
            BazerUtils.format_log(buf, BazerUtils.PrettyFormat(), nothing_record, T;
                displaysize=(50,100))
            output = String(take!(buf))
            @test contains(output, "unknown")
        end

        @testset "OnelineFormat" begin
            buf = IOBuffer()
            BazerUtils.format_log(buf, BazerUtils.OnelineFormat(), log_record, T;
                displaysize=(50,100), shorten_path=:no)
            output = String(take!(buf))
            @test contains(output, "INFO")
            @test contains(output, "2024-01-15 14:30:00")
            @test contains(output, "BazerUtils")
            @test contains(output, "test message")
        end

        @testset "OnelineFormat _module=nothing" begin
            buf = IOBuffer()
            BazerUtils.format_log(buf, BazerUtils.OnelineFormat(), nothing_record, T;
                displaysize=(50,100), shorten_path=:no)
            output = String(take!(buf))
            @test contains(output, "unknown")
        end

        @testset "SyslogFormat" begin
            buf = IOBuffer()
            BazerUtils.format_log(buf, BazerUtils.SyslogFormat(), log_record, T;
                displaysize=(50,100))
            output = String(take!(buf))
            @test contains(output, "<14>")  # facility=1, severity=6 -> (1*8)+6=14
            @test contains(output, "2024-01-15T14:30:00")
            @test contains(output, "test message")
        end

        @testset "SyslogFormat _module=nothing" begin
            buf = IOBuffer()
            BazerUtils.format_log(buf, BazerUtils.SyslogFormat(), nothing_record, T;
                displaysize=(50,100))
            output = String(take!(buf))
            @test contains(output, "nothing mod")
            @test !contains(output, "nothing[")
        end

        @testset "JsonFormat" begin
            buf = IOBuffer()
            BazerUtils.format_log(buf, BazerUtils.JsonFormat(), log_record, T;
                displaysize=(50,100))
            output = strip(String(take!(buf)))
            @test startswith(output, "{")
            @test endswith(output, "}")
            @test contains(output, "\"timestamp\":\"2024-01-15T14:30:00\"")
            @test contains(output, "\"level\":\"INFO\"")
            @test contains(output, "\"module\":\"BazerUtils\"")
            @test contains(output, "\"message\":\"test message\"")
            @test contains(output, "\"line\":42")
            parsed = JSON.parse(output)
            @test parsed["level"] == "INFO"
            @test parsed["line"] == 42
        end

        @testset "JsonFormat escaping" begin
            escape_record = (level=Base.CoreLogging.Warn, message="line1\nline2 \"quoted\"",
                _module=nothing, file="test.jl", line=1, group=:test, id=:test)
            buf = IOBuffer()
            BazerUtils.format_log(buf, BazerUtils.JsonFormat(), escape_record, T;
                displaysize=(50,100))
            output = strip(String(take!(buf)))
            parsed = JSON.parse(output)
            @test parsed["message"] == "line1\nline2 \"quoted\""
            @test parsed["module"] == "unknown"
        end

        @testset "LogfmtFormat" begin
            buf = IOBuffer()
            BazerUtils.format_log(buf, BazerUtils.LogfmtFormat(), log_record, T;
                displaysize=(50,100))
            output = strip(String(take!(buf)))
            @test contains(output, "ts=2024-01-15T14:30:00")
            @test contains(output, "level=info")
            @test contains(output, "module=BazerUtils")
            @test contains(output, "msg=\"test message\"")
        end

        @testset "LogfmtFormat _module=nothing" begin
            buf = IOBuffer()
            BazerUtils.format_log(buf, BazerUtils.LogfmtFormat(), nothing_record, T;
                displaysize=(50,100))
            output = strip(String(take!(buf)))
            @test contains(output, "module=unknown")
        end

        @testset "Log4jStandardFormat" begin
            buf = IOBuffer()
            BazerUtils.format_log(buf, BazerUtils.Log4jStandardFormat(), log_record, T;
                displaysize=(50,100))
            output = strip(String(take!(buf)))
            @test contains(output, "2024-01-15 14:30:00,000")
            @test contains(output, "INFO ")
            @test contains(output, "BazerUtils")
            @test contains(output, " - ")
            @test contains(output, "test message")
        end

        @testset "Log4jStandardFormat _module=nothing" begin
            buf = IOBuffer()
            BazerUtils.format_log(buf, BazerUtils.Log4jStandardFormat(), nothing_record, T;
                displaysize=(50,100))
            output = strip(String(take!(buf)))
            @test contains(output, "unknown")
            @test contains(output, "nothing mod")
        end
    end

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
        log_format=:oneline,
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
        log_format=:oneline,
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

    # -- logger with _module=nothing (issue #10)
    logger_single = custom_logger(
        log_path;
        log_format=:oneline,
        overwrite=true)
    log_record = (level=Base.CoreLogging.Info, message="test nothing module",
        _module=nothing, file="test.jl", line=1, group=:test, id=:test)
    buf = IOBuffer()
    BazerUtils.custom_format(buf, BazerUtils.OnelineFormat(), log_record;
        shorten_path=:no)
    output = String(take!(buf))
    @test contains(output, "unknown")
    @test contains(output, "test nothing module")
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
    @test contains.(log_content, r"INFO .* INFO MESSAGE") == [false, true]
    close_logger(logger_single, remove_files=true)

    # -- exact level filtering (default: cascading_loglevels=false)
    log_path_cl = joinpath(tempdir(), "log_cascading")
    logger_exact = custom_logger(
        log_path_cl;
        overwrite=true, create_log_files=true)
    @error "ONLY_ERROR"
    @warn "ONLY_WARN"
    @info "ONLY_INFO"
    @debug "ONLY_DEBUG"
    log_files_exact = get_log_names(logger_exact)
    content_exact = read.(log_files_exact, String)
    @test contains(content_exact[1], "ONLY_ERROR")
    @test contains(content_exact[2], "ONLY_WARN")
    @test contains(content_exact[3], "ONLY_INFO")
    @test contains(content_exact[4], "ONLY_DEBUG")
    @test !contains(content_exact[1], "ONLY_WARN")
    @test !contains(content_exact[1], "ONLY_INFO")
    @test !contains(content_exact[1], "ONLY_DEBUG")
    @test !contains(content_exact[2], "ONLY_ERROR")
    @test !contains(content_exact[2], "ONLY_INFO")
    @test !contains(content_exact[2], "ONLY_DEBUG")
    @test !contains(content_exact[3], "ONLY_ERROR")
    @test !contains(content_exact[3], "ONLY_WARN")
    @test !contains(content_exact[3], "ONLY_DEBUG")
    @test !contains(content_exact[4], "ONLY_ERROR")
    @test !contains(content_exact[4], "ONLY_WARN")
    @test !contains(content_exact[4], "ONLY_INFO")
    close_logger(logger_exact, remove_files=true)

    # -- cascading level filtering (cascading_loglevels=true, old behavior)
    logger_cascade = custom_logger(
        log_path_cl;
        overwrite=true, create_log_files=true,
        cascading_loglevels=true)
    @error "CASCADE_ERROR"
    @warn "CASCADE_WARN"
    @info "CASCADE_INFO"
    @debug "CASCADE_DEBUG"
    log_files_cascade = get_log_names(logger_cascade)
    content_cascade = read.(log_files_cascade, String)
    @test contains(content_cascade[1], "CASCADE_ERROR")
    @test !contains(content_cascade[1], "CASCADE_WARN")
    @test contains(content_cascade[2], "CASCADE_WARN")
    @test contains(content_cascade[2], "CASCADE_ERROR")
    @test contains(content_cascade[3], "CASCADE_INFO")
    @test contains(content_cascade[3], "CASCADE_WARN")
    @test contains(content_cascade[3], "CASCADE_ERROR")
    @test contains(content_cascade[4], "CASCADE_DEBUG")
    @test contains(content_cascade[4], "CASCADE_INFO")
    @test contains(content_cascade[4], "CASCADE_WARN")
    @test contains(content_cascade[4], "CASCADE_ERROR")
    close_logger(logger_cascade, remove_files=true)

    # -- JSON format logger
    log_path_fmt = joinpath(tempdir(), "log_fmt")
    logger_json = custom_logger(
        log_path_fmt;
        log_format=:json, overwrite=true)
    @error "JSON_ERROR"
    @info "JSON_INFO"
    log_file_json = get_log_names(logger_json)[1]
    json_lines = filter(!isempty, split(read(log_file_json, String), "\n"))
    for line in json_lines
        parsed = JSON.parse(line)
        @test haskey(parsed, "timestamp")
        @test haskey(parsed, "level")
        @test haskey(parsed, "module")
        @test haskey(parsed, "message")
    end
    close_logger(logger_json, remove_files=true)

    # -- logfmt format logger
    logger_logfmt = custom_logger(
        log_path_fmt;
        log_format=:logfmt, overwrite=true)
    @error "LOGFMT_ERROR"
    @info "LOGFMT_INFO"
    log_file_logfmt = get_log_names(logger_logfmt)[1]
    logfmt_content = read(log_file_logfmt, String)
    @test contains(logfmt_content, "level=error")
    @test contains(logfmt_content, "level=info")
    @test contains(logfmt_content, r"ts=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}")
    @test contains(logfmt_content, "msg=")
    close_logger(logger_logfmt, remove_files=true)

    # -- log4j_standard format logger
    logger_l4js = custom_logger(
        log_path_fmt;
        log_format=:log4j_standard, overwrite=true)
    @error "L4JS_ERROR"
    @info "L4JS_INFO"
    log_file_l4js = get_log_names(logger_l4js)[1]
    l4js_content = read(log_file_l4js, String)
    @test contains(l4js_content, r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2},\d{3} ERROR")
    @test contains(l4js_content, r"INFO .* - L4JS_INFO")
    @test contains(l4js_content, " - ")
    close_logger(logger_l4js, remove_files=true)

    # -- unknown format throws
    @test_throws ArgumentError custom_logger(
        joinpath(tempdir(), "log_bad"); log_format=:banana, overwrite=true)

    # -- :log4j deprecated alias still works
    logger_deprecated = custom_logger(
        log_path_fmt;
        log_format=:log4j, overwrite=true)
    @info "DEPRECATED_TEST"
    log_file_dep = get_log_names(logger_deprecated)[1]
    dep_content = read(log_file_dep, String)
    @test contains(dep_content, "DEPRECATED_TEST")
    close_logger(logger_deprecated, remove_files=true)

    # -- thread safety: concurrent logging produces complete lines
    log_path_thread = joinpath(tempdir(), "log_thread")
    logger_thread = custom_logger(
        log_path_thread;
        log_format=:json, overwrite=true)
    n_tasks = 10
    n_msgs = 50
    @sync for t in 1:n_tasks
        Threads.@spawn begin
            for m in 1:n_msgs
                @info "task=$t msg=$m"
            end
        end
    end
    log_file_thread = get_log_names(logger_thread)[1]
    # Flush all file streams
    for lg in logger_thread.loggers
        try
            s = lg.logger.logger.stream
            s isa IOStream && flush(s)
        catch; end
    end
    thread_lines = filter(!isempty, split(read(log_file_thread, String), "\n"))
    # Every line should be valid JSON (no interleaving)
    for line in thread_lines
        @test startswith(line, "{")
        @test endswith(line, "}")
        parsed = JSON.parse(line)
        @test haskey(parsed, "message")
    end
    close_logger(logger_thread, remove_files=true)

end
