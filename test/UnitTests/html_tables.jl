using Test
using BazerUtils
using DataFrames

@testset "HTMLTables" begin

# ==================================================================================
# Tier 1: Core table parsing
# ==================================================================================

@testset "Tier 1: Core parsing" begin

@testset "basic table with thead/tbody" begin
    html = """
    <table>
      <thead><tr><th>A</th><th>B</th></tr></thead>
      <tbody><tr><td>1</td><td>2</td></tr>
             <tr><td>3</td><td>4</td></tr></tbody>
    </table>"""
    dfs = read_html_tables(html)
    @test length(dfs) == 1
    df = dfs[1]
    @test names(df) == ["A", "B"]
    @test size(df) == (2, 2)
    @test df[1, "A"] == "1"
    @test df[2, "B"] == "4"
end

@testset "table without thead (auto-detect from th rows)" begin
    html = """
    <table>
      <tr><th>X</th><th>Y</th></tr>
      <tr><td>a</td><td>b</td></tr>
    </table>"""
    dfs = read_html_tables(html)
    @test length(dfs) == 1
    @test names(dfs[1]) == ["X", "Y"]
    @test dfs[1][1, "X"] == "a"
end

@testset "multiple tbody elements concatenated" begin
    html = """
    <table>
      <thead><tr><th>A</th><th>B</th></tr></thead>
      <tbody><tr><td>1</td><td>2</td></tr></tbody>
      <tbody><tr><td>3</td><td>4</td></tr></tbody>
    </table>"""
    dfs = read_html_tables(html)
    @test size(dfs[1]) == (2, 2)
    @test dfs[1][2, "A"] == "3"
end

@testset "tfoot with data appended to body" begin
    html = """
    <table>
      <thead><tr><th>A</th><th>B</th></tr></thead>
      <tbody><tr><td>1</td><td>2</td></tr></tbody>
      <tfoot><tr><td>foot1</td><td>foot2</td></tr></tfoot>
    </table>"""
    dfs = read_html_tables(html)
    @test size(dfs[1]) == (2, 2)
    @test dfs[1][2, "A"] == "foot1"
end

@testset "mixed th/td in body row" begin
    html = """
    <table>
      <thead><tr><th>Country</th><th>City</th><th>Year</th></tr></thead>
      <tbody><tr><td>Ukraine</td><th>Odessa</th><td>1944</td></tr></tbody>
    </table>"""
    dfs = read_html_tables(html)
    @test dfs[1][1, "City"] == "Odessa"
end

@testset "single column table" begin
    html = """
    <table>
      <tr><th>Only</th></tr>
      <tr><td>val</td></tr>
    </table>"""
    dfs = read_html_tables(html)
    @test size(dfs[1]) == (1, 1)
    @test names(dfs[1]) == ["Only"]
end

@testset "empty table skipped" begin
    html = """
    <table><tbody></tbody></table>
    <table>
      <tr><th>A</th></tr>
      <tr><td>1</td></tr>
    </table>"""
    dfs = read_html_tables(html)
    @test length(dfs) == 1
    @test names(dfs[1]) == ["A"]
end

@testset "multiple tables in document" begin
    html = """
    <table><tr><th>T1</th></tr><tr><td>a</td></tr></table>
    <table><tr><th>T2</th></tr><tr><td>b</td></tr></table>
    <table><tr><th>T3</th></tr><tr><td>c</td></tr></table>"""
    dfs = read_html_tables(html)
    @test length(dfs) == 3
    @test names(dfs[2]) == ["T2"]
end

@testset "match kwarg filters tables" begin
    html = """
    <table><tr><th>Name</th></tr><tr><td>park</td></tr></table>
    <table><tr><th>Other</th></tr><tr><td>data</td></tr></table>"""
    dfs = read_html_tables(html; match=r"park"i)
    @test length(dfs) == 1
    @test names(dfs[1]) == ["Name"]
end

end # Tier 1


# ==================================================================================
# Tier 2: Colspan/rowspan
# ==================================================================================

@testset "Tier 2: Colspan/rowspan" begin

@testset "colspan=1 and rowspan=1 are no-ops" begin
    html = """
    <table>
      <tr><th>A</th><th colspan="1">B</th><th rowspan="1">C</th></tr>
      <tr><td>a</td><td>b</td><td>c</td></tr>
    </table>"""
    dfs = read_html_tables(html)
    @test names(dfs[1]) == ["A", "B", "C"]
    @test dfs[1][1, "B"] == "b"
end

@testset "colspan=2 in header" begin
    html = """
    <table>
      <tr><th colspan="2">Wide</th><th>Narrow</th></tr>
      <tr><td>a</td><td>b</td><td>c</td></tr>
    </table>"""
    dfs = read_html_tables(html)
    @test size(dfs[1], 2) == 3
    @test dfs[1][1, 1] == "a"
    @test dfs[1][1, 3] == "c"
end

@testset "colspan=2 in body" begin
    html = """
    <table>
      <tr><th>A</th><th>B</th><th>C</th></tr>
      <tr><td colspan="2">wide</td><td>c</td></tr>
    </table>"""
    dfs = read_html_tables(html)
    @test dfs[1][1, "A"] == "wide"
    @test dfs[1][1, "B"] == "wide"
    @test dfs[1][1, "C"] == "c"
end

@testset "rowspan=2 in body" begin
    html = """
    <table>
      <tr><th>A</th><th>B</th></tr>
      <tr><td rowspan="2">tall</td><td>1</td></tr>
      <tr><td>2</td></tr>
    </table>"""
    dfs = read_html_tables(html)
    @test size(dfs[1]) == (2, 2)
    @test dfs[1][1, "A"] == "tall"
    @test dfs[1][2, "A"] == "tall"
    @test dfs[1][2, "B"] == "2"
end

@testset "rowspan at end of row" begin
    html = """
    <table>
      <tr><th>A</th><th>B</th></tr>
      <tr><td>x</td><td rowspan="2">y</td></tr>
      <tr><td>z</td></tr>
    </table>"""
    dfs = read_html_tables(html)
    @test dfs[1][2, "B"] == "y"
    @test dfs[1][2, "A"] == "z"
end

@testset "both rowspan and colspan on same cell" begin
    html = """
    <table>
      <tr><th>A</th><th>B</th><th>C</th><th>D</th><th>E</th></tr>
      <tr><td rowspan="2">a</td><td rowspan="2" colspan="3">block</td><td>e1</td></tr>
      <tr><td>e2</td></tr>
    </table>"""
    dfs = read_html_tables(html)
    @test size(dfs[1]) == (2, 5)
    @test dfs[1][1, "B"] == "block"
    @test dfs[1][1, "C"] == "block"
    @test dfs[1][1, "D"] == "block"
    @test dfs[1][2, "B"] == "block"
    @test dfs[1][2, "D"] == "block"
    @test dfs[1][2, "A"] == "a"
    @test dfs[1][1, "E"] == "e1"
    @test dfs[1][2, "E"] == "e2"
end

@testset "rowspan spanning header into body" begin
    html = """
    <table>
      <tr><th rowspan="2">A</th><th>B</th></tr>
      <tr><td>1</td></tr>
      <tr><td>C</td><td>2</td></tr>
    </table>"""
    dfs = read_html_tables(html)
    @test names(dfs[1]) == ["A", "B"]
    @test dfs[1][1, "A"] == "A"
    @test dfs[1][1, "B"] == "1"
    @test dfs[1][2, "A"] == "C"
    @test dfs[1][2, "B"] == "2"
end

@testset "rowspan-only rows" begin
    html = """
    <table>
      <tr><th>A</th><th>B</th></tr>
      <tr><td rowspan="3">x</td><td rowspan="3">y</td></tr>
    </table>"""
    dfs = read_html_tables(html)
    @test size(dfs[1]) == (3, 2)
    @test dfs[1][3, "A"] == "x"
    @test dfs[1][3, "B"] == "y"
end

end # Tier 2


# ==================================================================================
# Tier 3: Multi-level headers + flatten
# ==================================================================================

@testset "Tier 3: Multi-level headers" begin

@testset "two th rows give string-tuple column names" begin
    html = """
    <table>
      <tr><th>A</th><th>B</th></tr>
      <tr><th>a</th><th>b</th></tr>
      <tr><td>1</td><td>2</td></tr>
    </table>"""
    dfs = read_html_tables(html)
    @test names(dfs[1]) == ["(A, a)", "(B, b)"]
end

@testset "flatten=:join joins with underscore" begin
    html = """
    <table>
      <tr><th>A</th><th>B</th></tr>
      <tr><th>a</th><th>b</th></tr>
      <tr><td>1</td><td>2</td></tr>
    </table>"""
    dfs = read_html_tables(html; flatten=:join)
    @test names(dfs[1]) == ["A_a", "B_b"]
end

@testset "flatten=:last takes last level" begin
    html = """
    <table>
      <tr><th>A</th><th>B</th></tr>
      <tr><th>a</th><th>b</th></tr>
      <tr><td>1</td><td>2</td></tr>
    </table>"""
    dfs = read_html_tables(html; flatten=:last)
    @test names(dfs[1]) == ["a", "b"]
end

@testset "Wikipedia-style colspan grouping with sub-headers" begin
    html = """
    <table>
      <tr><th rowspan="2">Name</th><th colspan="2">Size</th><th rowspan="2">Year</th></tr>
      <tr><th>acres</th><th>ha</th></tr>
      <tr><td>Park A</td><td>100</td><td>40</td><td>1920</td></tr>
    </table>"""
    dfs = read_html_tables(html)
    @test names(dfs[1]) == ["(Name, Name)", "(Size, acres)", "(Size, ha)", "(Year, Year)"]
    @test dfs[1][1, "(Size, acres)"] == "100"

    dfs2 = read_html_tables(html; flatten=:last)
    @test names(dfs2[1]) == ["Name", "acres", "ha", "Year"]
end

end # Tier 3


# ==================================================================================
# Tier 4: Data quality
# ==================================================================================

@testset "Tier 4: Data quality" begin

@testset "empty cells become missing" begin
    html = """
    <table>
      <tr><th>A</th><th>B</th></tr>
      <tr><td></td><td>val</td></tr>
    </table>"""
    dfs = read_html_tables(html)
    @test ismissing(dfs[1][1, "A"])
    @test dfs[1][1, "B"] == "val"
end

@testset "ragged rows padded with missing" begin
    html = """
    <table>
      <tr><th>A</th><th>B</th><th>C</th></tr>
      <tr><td>1</td></tr>
    </table>"""
    dfs = read_html_tables(html)
    @test dfs[1][1, "A"] == "1"
    @test ismissing(dfs[1][1, "B"])
    @test ismissing(dfs[1][1, "C"])
end

@testset "br inside cell becomes space" begin
    html = """
    <table>
      <tr><th>A</th></tr>
      <tr><td>word1<br>word2</td></tr>
    </table>"""
    dfs = read_html_tables(html)
    @test dfs[1][1, "A"] == "word1 word2"
end

@testset "style tag stripped from header" begin
    html = """
    <table>
      <tr><th><style>.x{color:red}</style>Name</th><th>B</th></tr>
      <tr><td>a</td><td>b</td></tr>
    </table>"""
    dfs = read_html_tables(html)
    @test strip(names(dfs[1])[1]) == "Name" || names(dfs[1])[1] == "Name"
end

@testset "whitespace normalization" begin
    html = """
    <table>
      <tr><th>  A  </th></tr>
      <tr><td>  val  </td></tr>
    </table>"""
    dfs = read_html_tables(html)
    @test names(dfs[1]) == ["A"]
    @test dfs[1][1, "A"] == "val"
end

end # Tier 4

end # HTMLTables
