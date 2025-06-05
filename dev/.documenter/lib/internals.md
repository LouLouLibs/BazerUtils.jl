
# Package Internals {#Package-Internals}

## `BazerUtils` Module {#BazerUtils-Module}
<details class='jldocstring custom-block' open>
<summary><a id='BazerUtils.reformat_msg-Tuple{Any}' href='#BazerUtils.reformat_msg-Tuple{Any}'><span class="jlbinding">BazerUtils.reformat_msg</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
reformat_msg
# we view strings as simple and everything else as complex
```



<Badge type="info" class="source-link" text="source"><a href="https://github.com/LouLouLibs/BazerUtils.jl/blob/b22675888ad7af975c9597aa5a1da4df67626d3e/src/CustomLogger.jl#L362-L365" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='BazerUtils.shorten_path_str-Tuple{AbstractString}' href='#BazerUtils.shorten_path_str-Tuple{AbstractString}'><span class="jlbinding">BazerUtils.shorten_path_str</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



```julia
shorten_path_str(path::AbstractString; max_length::Int=40, strategy::Symbol=:truncate_middle)
```


Shorten a file path string to a specified maximum length using various strategies.

**Arguments**
- `path::AbstractString`: The input path to be shortened
  
- `max_length::Int=40`: Maximum desired length of the output path
  
- `strategy::Symbol=:truncate_middle`: Strategy to use for shortening. Options:
  - `:no`: Return path unchanged
    
  - `:truncate_middle`: Truncate middle of path components while preserving start/end
    
  - `:truncate_to_last`: Keep only the last n components of the path
    
  - `:truncate_from_right`: Progressively remove characters from right side of components
    
  - `:truncate_to_unique`: Reduce components to unique prefixes
    
  

**Returns**
- `String`: The shortened path
  

**Examples**

```julia
# Using different strategies
julia> shorten_path_str("/very/long/path/to/file.txt", max_length=20)
"/very/…/path/to/file.txt"

julia> shorten_path_str("/usr/local/bin/program", strategy=:truncate_to_last, max_length=20)
"/bin/program"

julia> shorten_path_str("/home/user/documents/very_long_filename.txt", strategy=:truncate_middle)
"/home/user/doc…ents/very_…name.txt"
```



<Badge type="info" class="source-link" text="source"><a href="https://github.com/LouLouLibs/BazerUtils.jl/blob/b22675888ad7af975c9597aa5a1da4df67626d3e/src/CustomLogger.jl#L511-L541" target="_blank" rel="noreferrer">source</a></Badge>

</details>

