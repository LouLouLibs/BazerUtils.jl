
# Working with JSON Lines Files {#Working-with-JSON-Lines-Files}

JSON Lines (JSONL) is a convenient format for storing structured data that may be processed one record at a time. Each line is a valid JSON value, separated by a newline character. This format is ideal for large datasets and streaming applications.

For more details, see [jsonlines.org](https://jsonlines.org/).


---


## What is JSON Lines? {#What-is-JSON-Lines?}
- **UTF-8 Encoding:** Files must be UTF-8 encoded. Do not include a byte order mark (BOM).
  
- **One JSON Value Per Line:** Each line is a valid JSON value (object, array, string, number, boolean, or null). Blank lines are ignored.
  
- **Line Separator:** Each line ends with `\n` (or `\r\n`). The last line may or may not end with a newline.
  

**Example:**

```json
{"name": "Alice", "score": 42}
{"name": "Bob", "score": 17}
[1, 2, 3]
"hello"
null
```



---


## Reading JSON Lines Files {#Reading-JSON-Lines-Files}

You can use the `read_jsonl` and `stream_jsonl` functions to read JSONL files or streams.

### `read_jsonl` {#read_jsonl}

Reads the entire file or stream into memory and returns a vector of parsed JSON values.

```julia
data = read_jsonl("data.jsonl")
# or from an IOBuffer
buf = IOBuffer("{\"a\": 1}\n{\"a\": 2}\n")
data = read_jsonl(buf)
```

- **Arguments:** `source::Union{AbstractString, IO}`
  
- **Returns:** `Vector` of parsed JSON values
  
- **Note:** Loads all data into memory. For large files, use `stream_jsonl`.
  


---


### `stream_jsonl` {#stream_jsonl}

Creates a lazy iterator (Channel) that yields one parsed JSON value at a time, without loading the entire file into memory.

```julia
for record in stream_jsonl("data.jsonl")
    println(record)
end

# Collect the first 10 records
first10 = collect(Iterators.take(stream_jsonl("data.jsonl"), 10))
```

- **Arguments:** `source::Union{AbstractString, IO}`
  
- **Returns:** `Channel` (iterator) of parsed JSON values
  
- **Note:** Ideal for large files and streaming workflows.
  


---


## Writing JSON Lines Files {#Writing-JSON-Lines-Files}

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


## Example: Roundtrip with IOBuffer {#Example:-Roundtrip-with-IOBuffer}

Note that there is no stable roundtrip between read and write, because of the way `JSON3` processes record into dictionaries. 

```julia
data = [Dict("a"=>1), Dict("b"=>2)]
buf = IOBuffer()
for obj in data
    JSON3.write(buf, obj)
    write(buf, '\n')
end
seekstart(buf)
read_data = read_jsonl(buf)
@assert read_data == data
```



---


## See Also {#See-Also}
- [`JSON3.jl`](https://github.com/quinnj/JSON3.jl): Fast, flexible JSON parsing and serialization for Julia.
  
- [`CodecZlib.jl`](https://github.com/JuliaIO/CodecZlib.jl): Gzip compression support.
  


---


For more advanced usage and performance tips, see the main documentation and function docstrings.
