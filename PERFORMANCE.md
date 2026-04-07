# Performance Analysis

## Benchmark Environment

- Linux x86_64, single core
- Perl 5.40 with 64-bit integers
- Net::Patricia 1.24 (XS/C, libpatricia)
- Net::BART 0.01 (pure Perl)
- Net::BART::XS 0.01 (C with XS bindings, `__builtin_popcountll`/`__builtin_clzll`)
- Random IPv4 prefixes (/8../32), 50K random IP lookups per run
- Best of 3 runs reported

## Three-Way Comparison

### 100 Prefixes

| Operation | Net::Patricia (C) | Net::BART (Perl) | Net::BART::XS (C) | XS vs Perl | XS vs Patricia |
|-----------|-------------------:|-----------------:|-------------------:|-----------:|---------------:|
| Insert    |         441K ops/s |        96K ops/s |        2,231K ops/s |     23.2x |          5.1x |
| Lookup    |         629K ops/s |       266K ops/s |        2,785K ops/s |     10.5x |          4.4x |
| Contains  |                n/a |       346K ops/s |        2,921K ops/s |      8.4x |            n/a |
| Get/Exact |         457K ops/s |       126K ops/s |        2,330K ops/s |     18.5x |          5.1x |
| Delete    |         212K ops/s |        43K ops/s |        1,065K ops/s |     24.8x |          5.0x |

### 1K Prefixes

| Operation | Net::Patricia (C) | Net::BART (Perl) | Net::BART::XS (C) | XS vs Perl | XS vs Patricia |
|-----------|-------------------:|-----------------:|-------------------:|-----------:|---------------:|
| Insert    |         407K ops/s |        77K ops/s |        1,890K ops/s |     24.6x |          4.6x |
| Lookup    |         605K ops/s |       154K ops/s |        2,663K ops/s |     17.2x |          4.4x |
| Contains  |                n/a |       208K ops/s |        2,841K ops/s |     13.6x |            n/a |
| Get/Exact |         450K ops/s |       108K ops/s |        2,253K ops/s |     20.9x |          5.0x |
| Delete    |         210K ops/s |        37K ops/s |          993K ops/s |     26.7x |          4.7x |

### 10K Prefixes

| Operation | Net::Patricia (C) | Net::BART (Perl) | Net::BART::XS (C) | XS vs Perl | XS vs Patricia |
|-----------|-------------------:|-----------------:|-------------------:|-----------:|---------------:|
| Insert    |         383K ops/s |        82K ops/s |        2,048K ops/s |     24.9x |          5.3x |
| Lookup    |         567K ops/s |       129K ops/s |        2,410K ops/s |     18.6x |          4.3x |
| Contains  |                n/a |       215K ops/s |        2,825K ops/s |     13.1x |            n/a |
| Get/Exact |         414K ops/s |       101K ops/s |        2,246K ops/s |     22.2x |          5.4x |
| Delete    |         193K ops/s |        37K ops/s |          978K ops/s |     26.2x |          5.1x |

### 100K Prefixes

| Operation | Net::Patricia (C) | Net::BART (Perl) | Net::BART::XS (C) | XS vs Perl | XS vs Patricia |
|-----------|-------------------:|-----------------:|-------------------:|-----------:|---------------:|
| Insert    |         298K ops/s |        65K ops/s |        1,242K ops/s |     19.2x |          4.2x |
| Lookup    |         459K ops/s |        96K ops/s |        1,929K ops/s |     20.2x |          4.2x |
| Contains  |                n/a |       212K ops/s |        2,689K ops/s |     12.7x |            n/a |
| Get/Exact |         372K ops/s |        89K ops/s |        1,806K ops/s |     20.3x |          4.9x |
| Delete    |         164K ops/s |        31K ops/s |          748K ops/s |     24.4x |          4.6x |

### Per-Operation Latency at 100K Prefixes

| Operation | Net::Patricia | Net::BART | Net::BART::XS |
|-----------|:-------------:|:---------:|:--------------:|
| Insert    |     3.4 µs    |  15.5 µs  |     0.81 µs    |
| Lookup    |     2.2 µs    |  10.5 µs  |     0.52 µs    |
| Contains  |       n/a     |   4.7 µs  |     0.37 µs    |
| Get/Exact |     2.7 µs    |  11.3 µs  |     0.55 µs    |
| Delete    |     6.1 µs    |  32.6 µs  |     1.34 µs    |

### Correctness

All three implementations were cross-checked with 5,000 random prefixes and 10,000
random IP lookups: **10,000/10,000 results agree**.

## Why Net::BART::XS Is Faster Than Net::Patricia

Net::Patricia uses a traditional radix/patricia trie with one bit examined per node
in the worst case. Net::BART::XS uses an 8-bit stride multibit trie (BART algorithm),
which means:

1. **Fewer memory accesses per lookup.** IPv4 traverses at most 4 nodes (one per octet)
   vs up to 32 for a patricia trie. Each node visit involves a bitwise AND + popcount,
   both of which complete in a single CPU cycle via hardware intrinsics.

2. **Cache-friendly layout.** Popcount-compressed sparse arrays pack data tightly,
   reducing cache misses compared to pointer-chasing in a patricia trie.

3. **O(1) LPM per node.** The precomputed ancestor bitset table turns longest-prefix-match
   into a single bitwise AND + highest-bit-find operation, rather than walking parent pointers.

4. **Hardware popcount/clz.** `__builtin_popcountll` and `__builtin_clzll` compile to
   single instructions (POPCNT, LZCNT) on modern x86, making rank and bit-find nearly free.

## Net::BART (Pure Perl) Optimizations

The pure Perl implementation applies these optimizations to minimize the Perl/C gap:

1. **Byte lookup table for popcount** — constant-time via 256-entry table
2. **Array-based blessed objects** — `$self->[N]` vs `$self->{key}` (~30% faster)
3. **Inlined hot paths** — LPM test, child lookup bypass method dispatch
4. **Fast IPv4 parser** — `index`/`substr` instead of regex (3x faster)
5. **Non-method recursion** — plain functions avoid `$self->` dispatch
6. **Unrolled rank computation** — eliminates loop overhead

## Scaling Behavior

| Table size | Patricia lookup | BART::XS lookup | Ratio |
|------------|----------------:|-----------------:|------:|
| 100        |     629K ops/s |      2,785K ops/s |  4.4x |
| 1K         |     605K ops/s |      2,663K ops/s |  4.4x |
| 10K        |     567K ops/s |      2,410K ops/s |  4.3x |
| 100K       |     459K ops/s |      1,929K ops/s |  4.2x |

Both implementations scale gracefully. The BART::XS advantage remains consistent at
~4x across table sizes, with BART::XS's `contains()` staying above 2.6M ops/s even
at 100K prefixes.
