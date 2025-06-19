# Working with JSON Lines Files


---

## From the website: what is JSON Lines?

> JSON Lines (JSONL) is a convenient format for storing structured data that may be processed one record at a time. Each line is a valid JSON value, separated by a newline character. This format is ideal for large datasets and streaming applications.

- **UTF-8 Encoding:** Files must be UTF-8 encoded. Do not include a byte order mark (BOM).
- **One JSON Value Per Line:** Each line is a valid JSON value (object, array, string, number, boolean, or null). Blank lines are ignored.
- **Line Separator:** Each line ends with `\n` (or `\r\n`). The last line may or may not end with a newline.


For more details, see [jsonlines.org](https://jsonlines.org/).

This is a personal implementation and is not tested for any sort of standard. 
It works fine for my usecase and I try to fix things as I encounter them, but ymmv. 

---

## Reading JSON Lines Files

You can use the `read_jsonl` and `stream_jsonl` functions to read JSONL files or streams.

### `read_jsonl`

Reads the entire file or stream into memory and returns a vector of parsed JSON values.

```julia
using BazerUtils
import JSON3
data = read_jsonl("data.jsonl")
# or from an IOBuffer
buf = 
data = read_jsonl(IOBuffer("{\"a\": 1}\n{\"a\": 2}\n"))
data = read_jsonl(IOBuffer("{\"a\": 1}\n{\"a\": 2}\n"); dict_of_json=true)
```


- **Arguments:** `source::Union{AbstractString, IO}`
- **Returns:** `Vector` of parsed JSON values
- **Note:** Loads all data into memory. For large files, use `stream_jsonl`.

---


### `stream_jsonl`

Creates a lazy iterator (Channel) that yields one parsed JSON value at a time, without loading the entire file into memory.

```julia
stream = stream_jsonl(IOBuffer("{\"a\": 1}\n{\"a\": 2}\n"))
data = collect(stream)
BazerUtils._dict_of_json3.(data)

stream = stream_jsonl(IOBuffer("{\"a\": 1}\n{\"a\": 2}\n[1,2,3]"))
collect(stream) # error because types of vector elements are not all JSON3.Object{}
stream = stream_jsonl(IOBuffer("{\"a\": 1}\n{\"a\": 2}\n[1,2,3]"), T=Any)
collect(stream) # default to Vector{Any}

stream = stream_jsonl(IOBuffer("[4,5,6]\n[1,2,3]"), T= JSON3.Array{})
collect(stream)
stream = stream_jsonl(IOBuffer("4\n1"), T=Int)
collect(stream)
```

Allows iterators
```julia
first10 = collect(Iterators.take(stream_jsonl("data.jsonl"), 10)) # Collect the first 10 records
# see tests for other iterators ...
```


- **Arguments:** `source::Union{AbstractString, IO}`
- **Returns:** `Channel` (iterator) of parsed JSON values
- **Note:** Ideal for large files and streaming workflows.

---

## Writing JSON Lines Files

Use `write_jsonl` to write an iterable of JSON-serializable values to a JSONL file.

```julia
write_jsonl("out.jsonl", [Dict("a"=>1), Dict("b"=>2)])
write_jsonl("out.jsonl.gz", (Dict("i"=>i) for i in 1:100); compress=true)
```

- **Arguments:** 
    - `filename::AbstractString`
    - `data`: iterable of JSON-serializable values
    - `compress::Bool=false`: write gzip-compressed if true or filename ends with `.gz`
- **Returns:** The filename

---


## Example: Roundtrip with IOBuffer

Note that there is no stable roundtrip between read and write, because of the way `JSON3` processes record into dictionaries and even when we add the dict flag it is `Symbol => Any`

```julia
data_string = [Dict("a"=>1), Dict("b"=>2)]
data_symbol = [Dict(:a=>1), Dict(:b=>2)]

function roundtrip(data)
    buf = IOBuffer()
    for obj in data
        JSON3.write(buf, obj)
        write(buf, '\n')
    end
    seekstart(buf)
    return read_jsonl(buf; dict_of_json=true)
end

roundtrip(data_string) == data_string
roundtrip(data_symbol) == data_symbol
```

---

## See Also

- [`JSON3.jl`](https://github.com/quinnj/JSON3.jl): Fast, flexible JSON parsing and serialization for Julia.
- [`CodecZlib.jl`](https://github.com/JuliaIO/CodecZlib.jl): Gzip compression support.

---

For more advanced usage, see the function docstrings or the test suite. 