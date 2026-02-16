# Working with JSON Lines Files

!!! warning "Deprecated"
    The JSONL functions in BazerUtils (`read_jsonl`, `stream_jsonl`, `write_jsonl`) are deprecated.
    Use [JSON.jl](https://github.com/JuliaIO/JSON.jl) v1 instead, which has native support:
    ```julia
    using JSON
    data = JSON.parse("data.jsonl"; jsonlines=true)       # read
    JSON.json("out.jsonl", data; jsonlines=true)           # write
    ```

---

## From the website: what is JSON Lines?

> JSON Lines (JSONL) is a convenient format for storing structured data that may be processed one record at a time. Each line is a valid JSON value, separated by a newline character. This format is ideal for large datasets and streaming applications.

For more details, see [jsonlines.org](https://jsonlines.org/).

---

## Legacy API (deprecated)

### `read_jsonl`

Reads the entire file or stream into memory and returns a vector of parsed JSON values.

```julia
using BazerUtils
data = read_jsonl("data.jsonl")
data = read_jsonl(IOBuffer("{\"a\": 1}\n{\"a\": 2}\n"))
data = read_jsonl(IOBuffer("{\"a\": 1}\n{\"a\": 2}\n"); dict_of_json=true)
```

### `stream_jsonl`

Creates a lazy iterator (Channel) that yields one parsed JSON value at a time.

```julia
for record in stream_jsonl("data.jsonl")
    println(record)
end
first10 = collect(Iterators.take(stream_jsonl("data.jsonl"), 10))
```

### `write_jsonl`

Write an iterable of JSON-serializable values to a JSONL file.

```julia
write_jsonl("out.jsonl", [Dict("a"=>1), Dict("b"=>2)])
write_jsonl("out.jsonl.gz", (Dict("i"=>i) for i in 1:100); compress=true)
```

---

## See Also

- [`JSON.jl`](https://github.com/JuliaIO/JSON.jl): The recommended replacement. Use `jsonlines=true` for JSONL support.
- [`CodecZlib.jl`](https://github.com/JuliaIO/CodecZlib.jl): Gzip compression support.