# Net::BART - Balanced Routing Tables for Perl

Fast IPv4/IPv6 longest-prefix-match (LPM) routing table lookups for Perl, available in two flavors:

- **Net::BART** — pure Perl, zero dependencies
- **Net::BART::XS** — C implementation via XS, **4-5x faster than Net::Patricia**

Based on the Go implementation [gaissmai/bart](https://github.com/gaissmai/bart), which builds on Knuth's ART (Allotment Routing Tables) algorithm.

## Synopsis

```perl
# Pure Perl — works everywhere, no compiler needed
use Net::BART;
my $table = Net::BART->new;

# XS/C — same API, maximum performance
use Net::BART::XS;
my $table = Net::BART::XS->new;

# Insert prefixes with associated values
$table->insert("10.0.0.0/8",       "private-rfc1918");
$table->insert("10.1.0.0/16",      "office-network");
$table->insert("10.1.42.0/24",     "dev-team");
$table->insert("0.0.0.0/0",        "default-gw");
$table->insert("2001:db8::/32",    "documentation");

# Longest-prefix match
my ($val, $ok) = $table->lookup("10.1.42.7");
# $val = "dev-team", $ok = 1

my ($val, $ok) = $table->lookup("10.1.99.1");
# $val = "office-network", $ok = 1

# Exact match
my ($val, $ok) = $table->get("10.1.0.0/16");
# $val = "office-network", $ok = 1

# Fast containment check
$table->contains("10.1.42.7");  # 1
$table->contains("172.16.0.1"); # 1 (matches default route)

# Delete
my ($old, $ok) = $table->delete("10.1.42.0/24");
# $old = "dev-team", $ok = 1

# Walk all prefixes (Net::BART only)
$table->walk(sub {
    my ($prefix, $value) = @_;
    print "$prefix => $value\n";
});

# Counts
printf "Total: %d (IPv4: %d, IPv6: %d)\n",
    $table->size, $table->size4, $table->size6;
```

## Installation

**Net::BART** (pure Perl) requires no installation — add `lib/` to `@INC`:

```bash
perl -Ilib your_script.pl
```

**Net::BART::XS** requires a C compiler:

```bash
cd lib/Net/BART && perl Makefile.PL && make && make test
```

Then add both `lib/` and the blib paths to `@INC`:

```bash
perl -Ilib -Ilib/Net/BART/blib/arch -Ilib/Net/BART/blib/lib your_script.pl
```

Requires Perl 5.10+ with 64-bit integer support.

## API

Both `Net::BART` and `Net::BART::XS` share the same API:

| Method | Description | Returns |
|--------|-------------|---------|
| `->new` | Create empty routing table | object |
| `->insert($prefix, $val)` | Insert/update a CIDR prefix | 1 if new, 0 if updated |
| `->lookup($ip)` | Longest-prefix match | `($value, 1)` or `(undef, 0)` |
| `->contains($ip)` | Any prefix contains this IP? | 1 or 0 |
| `->get($prefix)` | Exact prefix match | `($value, 1)` or `(undef, 0)` |
| `->delete($prefix)` | Remove a prefix | `($old_value, 1)` or `(undef, 0)` |
| `->size` / `->size4` / `->size6` | Prefix count | integer |
| `->walk($cb)` | Iterate all prefixes (Net::BART only) | void |

**Prefix formats:** `"10.0.0.0/8"`, `"2001:db8::/32"`, `"0.0.0.0/0"`, `"::/0"`

**IP formats:** `"10.1.2.3"`, `"2001:db8::1"` (for lookup/contains)

## Performance

### Net::BART::XS vs Net::Patricia vs Net::BART

Benchmarked with random IPv4 prefixes, 50K lookups per run, best of 3.

#### Lookup (longest-prefix match) — ops/sec

| Table size | Net::Patricia (C) | Net::BART (Perl) | Net::BART::XS (C) |
|:----------:|-------------------:|-----------------:|-------------------:|
| 100        |            629K    |           266K   |          **2,785K** |
| 1K         |            605K    |           154K   |          **2,663K** |
| 10K        |            567K    |           129K   |          **2,410K** |
| 100K       |            459K    |            96K   |          **1,929K** |

#### All operations at 100K prefixes

| Operation | Net::Patricia | Net::BART | Net::BART::XS | XS vs Patricia |
|-----------|:-------------:|:---------:|:--------------:|:--------------:|
| Insert    |     298K/s    |    65K/s  |   **1,242K/s** |      4.2x      |
| Lookup    |     459K/s    |    96K/s  |   **1,929K/s** |      4.2x      |
| Contains  |       n/a     |   212K/s  |   **2,689K/s** |       n/a      |
| Get/Exact |     372K/s    |    89K/s  |   **1,806K/s** |      4.9x      |
| Delete    |     164K/s    |    31K/s  |     **748K/s** |      4.6x      |

#### Per-operation latency at 100K prefixes

| Operation | Net::Patricia | Net::BART | Net::BART::XS |
|-----------|:-------------:|:---------:|:--------------:|
| Insert    |     3.4 µs    |  15.5 µs  |   **0.81 µs**  |
| Lookup    |     2.2 µs    |  10.5 µs  |   **0.52 µs**  |
| Contains  |       n/a     |   4.7 µs  |   **0.37 µs**  |
| Get/Exact |     2.7 µs    |  11.3 µs  |   **0.55 µs**  |
| Delete    |     6.1 µs    |  32.6 µs  |   **1.34 µs**  |

All three implementations produce **identical results** on 10,000 random lookups against 5,000 random prefixes.

See [PERFORMANCE.md](PERFORMANCE.md) for detailed analysis.

### Why Net::BART::XS Is Faster Than Net::Patricia

- **8-bit stride multibit trie** — IPv4 traverses at most 4 nodes vs up to 32 in a patricia trie
- **O(1) LPM per node** — precomputed ancestor bitsets + bitwise AND, not pointer-chasing
- **Hardware intrinsics** — `POPCNT` and `LZCNT` instructions for rank/bit-find in single cycles
- **Cache-friendly** — popcount-compressed sparse arrays pack data tightly

### Choosing Between the Three

| | Net::Patricia | Net::BART | Net::BART::XS |
|-|:---:|:---:|:---:|
| **Speed** | Fast | Moderate | Fastest |
| **Dependencies** | C compiler + libpatricia | None | C compiler |
| **IPv6** | Separate trie object | Native, same API | Native, same API |
| **Values** | Integers (closures for complex) | Any Perl scalar | Any Perl scalar |
| **walk()** | Callback | Yes | Not yet |
| **Best for** | Existing codebases | Portability | Maximum throughput |

## How It Works

BART is a **multibit trie** with a fixed stride of 8 bits. Each IP address is decomposed into octets, and each octet indexes one level of the trie:

- **IPv4**: at most 4 trie levels (one per octet)
- **IPv6**: at most 16 trie levels (one per octet)

### ART Index Mapping

Within each trie node, prefixes of length /0 through /7 (relative to the stride) are stored in a **complete binary tree** with indices 1-255:

```
Index 1:         /0 (default route within stride)
Indices 2-3:     /1 prefixes
Indices 4-7:     /2 prefixes
Indices 8-15:    /3 prefixes
Indices 16-31:   /4 prefixes
Indices 32-63:   /5 prefixes
Indices 64-127:  /6 prefixes
Indices 128-255: /7 prefixes
```

### O(1) Longest-Prefix Match Per Node

A precomputed lookup table maps each index to its ancestor set in the binary tree. LPM at a node becomes a bitwise AND of the node's prefix bitset with the ancestor bitset, followed by finding the highest set bit — all O(1) operations.

### Memory Efficiency

**Popcount-compressed sparse arrays** store only occupied slots. A 256-bit bitset tracks which indices are present, and a compact array holds only the values. Lookup is O(1): test the bit, compute rank via popcount, index into the array.

### Path Compression

- **LeafNode**: non-stride-aligned prefixes stored directly when no child exists
- **FringeNode**: stride-aligned prefixes (/8, /16, /24, /32) stored without prefix data

## Project Structure

```
lib/
  Net/
    BART.pm                    # Pure Perl implementation
    BART/
      Art.pm                   # ART index mapping functions
      BitSet256.pm             # 256-bit bitset (4 x uint64)
      LPM.pm                   # Precomputed ancestor lookup table
      Node.pm                  # BartNode, LeafNode, FringeNode
      SparseArray256.pm        # Popcount-compressed sparse array
      bart.h                   # C implementation of BART algorithm
      XS.xs                    # XS bindings
      XS.pm                    # XS Perl wrapper
      Makefile.PL              # Build script for XS module
t/
    01-bitset256.t             # BitSet256 unit tests
    02-sparse-array.t          # SparseArray256 unit tests
    03-art.t                   # ART index mapping tests
    04-table.t                 # Integration tests
```

## Running Tests

```bash
# Pure Perl tests
prove -Ilib t/

# Build and test XS module
cd lib/Net/BART && perl Makefile.PL && make && make test

# Run three-way benchmark (requires Net::Patricia)
perl bench_all.pl
```

## References

- [gaissmai/bart](https://github.com/gaissmai/bart) — Go implementation this port is based on
- Knuth, D. E. — *The Art of Computer Programming, Volume 4, Fascicle 7* — Allotment Routing Tables (ART)

## License

Same terms as Perl itself.
