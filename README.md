# grapheme_cell_width

Grapheme-cluster-based terminal cell-width measurement for clean text spans,
written in Crystal. Feed it spans of plain UTF-8 text and get back their width
in terminal cells, or stream zero-copy grapheme clusters with their widths.

- **Zero dependencies, zero allocations** — spans are read in place and never copied.
- **wcwidth-compatible** — the width model matches what most terminals assume.
- **UAX #29 extended grapheme clusters** (Unicode 17.0.0), including spacing
marks (GB9a), prepend (GB9b), and Indic conjuncts (GB9c): क्‍ष is one cluster.
- **Fast** — a SWAR fast path measures pure-ASCII runs eight bytes at a time.

## Requirements

- Crystal `>= 1.10.0`
- For regenerating the Unicode tables: an internet connection (data files are
fetched from unicode.org)
- For `make verify`: Python 3 with `unicodedata2` (`pip install unicodedata2`)

## Installation

Add the dependency to your `shard.yml`:

```yaml
dependencies:
  grapheme_cell_width:
    github: shpeckman/grapheme_cell_width
```

Then run `shards install`.

The width and grapheme tables in `src/grapheme_cell_width/` are generated from
the Unicode Character Database and are not checked in. A `postinstall` hook
runs `make gen-tables` automatically, so `shards install` leaves the shard
ready to use. The hook needs `make` and `crystal` on your `PATH` and network
access to unicode.org; if it cannot run, generate the tables manually with
`make gen-tables`.

## Usage

```crystal
require "grapheme_cell_width"

GraphemeCellWidth.measure("hello")        # => 5
GraphemeCellWidth.measure("日本語")         # => 6
GraphemeCellWidth.measure("👨‍👩‍👧‍👦")         # => 2
GraphemeCellWidth.measure("❤️")           # => 2  (narrow base + VS16)
GraphemeCellWidth.measure("🇺🇸")           # => 2  (regional-indicator pair)
GraphemeCellWidth.measure("e\u{301}")     # => 1  (combining mark is 0 cells)
GraphemeCellWidth.measure("Hello, 世界! 👋") # => 15
```

Single characters:

```crystal
GraphemeCellWidth.width('a')  # => 1
GraphemeCellWidth.width('日') # => 2
```

Stream zero-copy grapheme clusters (each yielded `Slice` points into the
original string — nothing is copied):

```crystal
GraphemeCellWidth.each_cluster("a👨‍👩‍👧‍👦b") do |cluster|
  puts String.new(cluster)
end
# prints "a", then "👨‍👩‍👧‍👦", then "b"
```

Clusters with their widths:

```crystal
GraphemeCellWidth.measure_each("ab日") do |cluster, width|
  puts "#{String.new(cluster)}: #{width}"
end
```

Whole collections of spans, as a block or as a lazy iterator:

```crystal
GraphemeCellWidth.each(["foo", "日本語"]) { |span, w| puts "#{span}: #{w}" }

GraphemeCellWidth.each(["ab", "日"]).to_a
# => [{"ab", 2}, {"日", 2}]
```

Lines from an IO:

```crystal
GraphemeCellWidth.each_line(STDIN) do |line, width|
  puts "#{width}\t#{line}"
end
```

`measure`, `each_cluster`, and `measure_each` also accept `Slice(UInt8)`
directly, measured without copying.

## Contract

Input spans must be valid UTF-8 containing **no ANSI escape sequences and no
control characters** (C0, DEL, C1). Under that contract, `measure` performs no
validation and never fails.

During development, compile with `-Dgrapheme_cell_width_debug` to validate the
contract and raise `ArgumentError` on violations:

```sh
crystal spec -Dgrapheme_cell_width_debug   # or: make spec-debug
```

## Width model

| Character class                                                 | Cells |
|-----------------------------------------------------------------|-------|
| East Asian Wide / Fullwidth                                     | 2     |
| Combining marks (Mn/Me), ZWSP/ZWNJ/ZWJ, word joiner, BOM,       | 0     |
| Hangul jamo vowels & final consonants, emoji skin-tone          |       |
| modifiers, variation selectors, tag characters                  |       |
| Emoji ZWJ sequence (👨‍👩‍👧‍👦), VS16-widened emoji base (❤️), | 2     |
| regional-indicator pair (🇺🇸) — one cluster                    |       |
| Everything else                                                 | 1     |

## Development

```sh
make gen-tables    # regenerate width/grapheme tables + break tests from the UCD
make spec          # run the spec suite
make spec-debug    # run specs with contract validation enabled
make bench         # run width and grapheme benchmarks
make verify        # cross-check widths against Python's unicodedata2
make clean         # remove widths.tsv and docs
```

`UNICODE_VERSION` pins the Unicode release used by `gen-tables` and `verify`
(default `17.0.0`):

```sh
make gen-tables UNICODE_VERSION=16.0.0
```

The spec suite covers the width model, table invariants (every scalar value
from U+0020 to U+10FFFF), and 555 official `GraphemeBreakTest.txt` cases.

## License

MIT — see [LICENSE](LICENSE).