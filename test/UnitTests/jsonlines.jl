@testset "JSONLines" begin



    @testset "stream_jsonl" begin

    data = [
        Dict("a" => 1, "b" => "foo"),
        Dict("a" => 2, "b" => "bar"),
        Dict("a" => 3, "b" => "baz")
    ]
    jsonl_file = tempname()
    open(jsonl_file, "w") do io
        for obj in data
            JSON.json(io, obj)
            write(io, '\n')
        end
    end


    # --- iterate
    stream = stream_jsonl(jsonl_file)
    @test !(stream isa AbstractArray)

    first_obj = iterate(stream)[1]
    @test first_obj["a"] == 1
    @test first_obj["b"] == "foo"

    # Test that the iterator yields the next element correctly
    second_obj = iterate(stream)[1]
    @test second_obj["a"] == 2
    @test second_obj["b"] == "bar"

    third_obj = iterate(stream)[1]
    @test third_obj["a"] == 3
    @test third_obj["b"] == "baz"

    @test isnothing(iterate(stream))
    @test !isopen(stream)

    # --- iterators
    stream = stream_jsonl(jsonl_file)
    stateful_stream = Iterators.Stateful(stream)
    first_obj = popfirst!(stateful_stream)
    @test first_obj["a"] == 1
    @test first_obj["b"] == "foo"
    second_obj = popfirst!(stateful_stream)
    @test second_obj["a"] == 2
    @test second_obj["b"] == "bar"
    third_obj = popfirst!(stateful_stream)
    @test third_obj["a"] == 3
    @test third_obj["b"] == "baz"
    @test_throws EOFError popfirst!(stateful_stream)

    # --- collect
    # Test that the iterator can be collected fully
    results = collect(stream_jsonl(jsonl_file))
    @test length(results) == 3
    @test results[3]["b"] == "baz"

    # Test with empty file
    empty_file = tempname()
    open(empty_file, "w") do io end
    @test collect(stream_jsonl(empty_file)) == []
    @test !isopen(stream)

    # Test wrong types
    stream = stream_jsonl(IOBuffer("{\"a\": 1}\n{\"a\": 2}\n[1,2,3]"))
    @test_throws TaskFailedException collect(stream)
    stream = stream_jsonl(IOBuffer("{\"a\": 1}\n{\"a\": 2}\n[1,2,3]"), T=Any)
    @test collect(stream)[3] == [1,2,3]

    rm(jsonl_file)
    rm(empty_file)
end



@testset "read_jsonl" begin
    data = [
        Dict("x" => 10, "y" => "baz"),
        Dict("x" => 20, "y" => "qux"),
        Dict("x" => 30, "y" => "zap")
    ]
    jsonl_file = tempname()
    open(jsonl_file, "w") do io
        for obj in data
            JSON.json(io, obj)
            write(io, '\n')
        end
    end

    results = read_jsonl(jsonl_file)
    @test length(results) == 3
    @test results[1]["x"] == 10
    @test results[2]["y"] == "qux"
    @test results[3]["x"] == 30
    @test results[3]["y"] == "zap"

    results = read_jsonl(jsonl_file; dict_of_json=true)
    @test results isa Vector{Dict{Symbol, Any}}

    # Test with empty file
    empty_file = tempname()
    open(empty_file, "w") do io end
    @test read_jsonl(empty_file) == []

    # Test with malformed JSON line
    bad_file = tempname()
    open(bad_file, "w") do io
        JSON.json(io, Dict("a" => 1))
        write(io, '\n')
        write(io, "{bad json}\n")
    end
    @test_throws Exception read_jsonl(bad_file)

    rm(jsonl_file)
    rm(empty_file)
    rm(bad_file)
end
# --------------------------------------------------------------------------------------------------


# --------------------------------------------------------------------------------------------------
@testset "Writing" begin


    function test_jsonlines_roundtrip(data)

        buf = IOBuffer()
        # Write each value as a JSON line
        for obj in data
            JSON.json(buf, obj)
            write(buf, '\n')
        end
        seekstart(buf)

        # Read all at once
        read_data = read_jsonl(buf)

        # Stream and collect
        seekstart(buf)
        streamed = collect(stream_jsonl(buf, T=Any))
        @test streamed == read_data
    end

    data_dict = [Dict(:a=>1, :b => Dict(:c => "bar")), Dict(:c=>2)]
    test_jsonlines_roundtrip(data_dict)

    data_array = [[1,2,3], [4,5,6]]
    test_jsonlines_roundtrip(data_array)

    # Test gzip
    jsonl_file = tempname() * ".jsonl.gz"
    write_jsonl(jsonl_file, data_dict)

    gz_data = read_jsonl(CodecZlib.GzipDecompressorStream(open(jsonl_file)))
    @test BazerUtils._dict_of_json.(gz_data) == data_dict
    # @assert gz_data == data

    jsonl_file = tempname() * ".jsonl"
    simple_table = [
        (id=1, name="Alice", age=30),
        (id=2, name="Bob", age=25),
        (id=3, name="Charlie", age=35)
    ]
    write_jsonl(jsonl_file, simple_table)
    simple_dict = read_jsonl(jsonl_file)
    @test BazerUtils._dict_of_json.(simple_dict) == map(row -> Dict(pairs(row)), simple_table)

end
# --------------------------------------------------------------------------------------------------



# --------------------------------------------------------------------------------------------------
@testset "compare speed: stream_jsonl vs read_jsonl for first 10 elements" begin
    large_file = tempname()
    open(large_file, "w") do io
        for i in 1:10^6
            JSON.json(io, Dict("i" => i))
            write(io, '\n')
        end
    end

    # Time to get first 10 elements with stream_jsonl
    t_stream = @elapsed begin
        stream = stream_jsonl(large_file)
        first10 = collect(Iterators.take(stream, 10))
    end

    # Time to get first 10 elements with read_jsonl (loads all)
    t_read = @elapsed begin
        all = read_jsonl(large_file)
        first10_read = all[1:10]
    end

    @test t_stream < t_read / 10  # streaming should be much faster for first 10
    @test first10 == first10_read

    rm(large_file)
end
# --------------------------------------------------------------------------------------------------


# --------------------------------------------------------------------------------------------------
@testset "Robustness" begin

    @testset "File not found" begin
    # Test that both functions throw an error when the file does not exist
    @test_throws Exception stream_jsonl("does_not_exist.jsonl")
    @test_throws Exception read_jsonl("does_not_exist.jsonl")
    end

    @testset "trailing newlines and empty lines" begin
    file = tempname()
    open(file, "w") do io
        JSON.json(io, Dict("a" => 1))
        write(io, "\n\n")  # two trailing newlines (one empty line)
        JSON.json(io, Dict("a" => 2))
        write(io, "\n\n\n")  # three trailing newlines (two empty lines)
    end
    result_stream = collect(stream_jsonl(file))
    result_read = read_jsonl(file)
    @test length(result_stream) == 2
    @test length(result_read) == 2
    @test result_stream[1]["a"] == 1
    @test result_stream[2]["a"] == 2
    @test result_read[1]["a"] == 1
    @test result_read[2]["a"] == 2
    rm(file)
    end

    @testset "comments or non-JSON lines" begin
    file = tempname()
    open(file, "w") do io
        write(io, "# this is a comment\n")
        JSON.json(io, Dict("a" => 1))
        write(io, "\n")
        write(io, "// another comment\n")
        JSON.json(io, Dict("a" => 2))
        write(io, "\n")
    end
    # Should throw, since comments are not valid JSON
    @test_throws Exception collect(stream_jsonl(file))
    @test_throws Exception read_jsonl(file)
    rm(file)
    end

end



end
