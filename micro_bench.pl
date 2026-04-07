#!/usr/bin/env perl
use strict;
use warnings;
use Time::HiRes qw(time);

use BART::BitSet256;
use BART::SparseArray256;
use BART::LPM qw(@LOOKUP_TBL);
use BART::Art qw(pfx_to_idx octet_to_idx);
use BART::Node;
use BART;

my $ITERS = 100_000;

# Utility: run a benchmark and return elapsed seconds
sub bench {
    my ($name, $code) = @_;
    # Warmup
    $code->();
    my $start = time();
    $code->();
    my $elapsed = time() - $start;
    return $elapsed;
}

sub fmt {
    my ($elapsed) = @_;
    my $ns_per_op = ($elapsed / $ITERS) * 1_000_000_000;
    return sprintf("%10.3f ms total  |  %8.1f ns/op", $elapsed * 1000, $ns_per_op);
}

my @results;

sub record {
    my ($section, $name, $elapsed) = @_;
    push @results, [$section, $name, $elapsed];
}

print "BART Micro-Benchmark  ($ITERS iterations each)\n";
print "=" x 78, "\n\n";

###############################################################################
# 1. BitSet256 operations
###############################################################################
{
    my $bs = BART::BitSet256->new;
    $bs->set(42);
    $bs->set(100);
    $bs->set(200);

    my $other = BART::BitSet256->new;
    $other->set(42);
    $other->set(150);
    $other->set(200);

    # set
    record("BitSet256", "set", bench("set", sub {
        my $b = BART::BitSet256->new;
        for (1 .. $ITERS) {
            $b->set($_ & 255);
        }
    }));

    # test
    record("BitSet256", "test", bench("test", sub {
        for (1 .. $ITERS) {
            $bs->test($_ & 255);
        }
    }));

    # rank
    record("BitSet256", "rank", bench("rank", sub {
        for (1 .. $ITERS) {
            $bs->rank($_ & 255);
        }
    }));

    # intersection_top
    record("BitSet256", "intersection_top", bench("intersection_top", sub {
        for (1 .. $ITERS) {
            $bs->intersection_top($other);
        }
    }));

    # popcnt (whole bitset)
    record("BitSet256", "popcnt", bench("popcnt", sub {
        for (1 .. $ITERS) {
            $bs->popcnt();
        }
    }));
}

###############################################################################
# 2. SparseArray256 operations
###############################################################################
{
    # SparseArray256 is array-based: [$bitset, $items_arrayref]
    my $sa = BART::SparseArray256->new;
    for my $i (0, 10, 42, 100, 150, 200, 255) {
        $sa->insert_at($i, "val_$i");
    }

    # get (existing key)
    record("SparseArray256", "get (existing key)", bench("get_existing", sub {
        for (1 .. $ITERS) {
            $sa->get(42);
        }
    }));

    # get (missing key)
    record("SparseArray256", "get (missing key)", bench("get_missing", sub {
        for (1 .. $ITERS) {
            $sa->get(77);
        }
    }));

    # insert_at (update existing)
    record("SparseArray256", "insert_at (update)", bench("insert_update", sub {
        for (1 .. $ITERS) {
            $sa->insert_at(42, "new_val");
        }
    }));

    # insert_at (new key, on fresh array each time to avoid growing forever)
    record("SparseArray256", "insert_at (new, fresh)", bench("insert_new", sub {
        for (1 .. $ITERS) {
            my $s = BART::SparseArray256->new;
            $s->insert_at(42, "v");
        }
    }));
}

###############################################################################
# 3. IP parsing: _parse_ipv4 vs manual split vs inline index
###############################################################################
{
    my $ip_str = "192.168.1.42";

    # Library _parse_ipv4_fast (no validation, index-based)
    record("IP Parsing", "_parse_ipv4_fast (library)", bench("parse_ipv4", sub {
        for (1 .. $ITERS) {
            BART::_parse_ipv4_fast($ip_str);
        }
    }));

    # Manual split-based (no validation)
    record("IP Parsing", "manual split (no validation)", bench("manual_split", sub {
        for (1 .. $ITERS) {
            my @p = split /\./, $ip_str;
            my $bytes = [int($p[0]), int($p[1]), int($p[2]), int($p[3])];
        }
    }));

    # Inline index-based (as used by optimized lookup)
    record("IP Parsing", "inline index (lookup style)", bench("inline_index", sub {
        for (1 .. $ITERS) {
            my $d1 = index($ip_str, '.');
            my $d2 = index($ip_str, '.', $d1 + 1);
            my $d3 = index($ip_str, '.', $d2 + 1);
            my $bytes = [
                substr($ip_str, 0, $d1) + 0,
                substr($ip_str, $d1 + 1, $d2 - $d1 - 1) + 0,
                substr($ip_str, $d2 + 1, $d3 - $d2 - 1) + 0,
                substr($ip_str, $d3 + 1) + 0,
            ];
        }
    }));

    # Full _parse_ip (with IPv4/v6 dispatch)
    record("IP Parsing", "_parse_ip (full dispatch)", bench("parse_ip", sub {
        for (1 .. $ITERS) {
            BART::_parse_ip($ip_str);
        }
    }));

    # IPv6 parsing
    my $ip6_str = "2001:db8:85a3:0:0:8a2e:370:7334";
    record("IP Parsing", "_parse_ipv6", bench("parse_ipv6", sub {
        for (1 .. $ITERS) {
            BART::_parse_ipv6($ip6_str);
        }
    }));
}

###############################################################################
# 4. _popcount64 with various inputs
###############################################################################
{
    # Zero
    record("popcount64", "input = 0", bench("pc_zero", sub {
        for (1 .. $ITERS) {
            BART::BitSet256::_popcount64(0);
        }
    }));

    # Sparse (1 bit set)
    record("popcount64", "input = 1 bit set", bench("pc_one", sub {
        for (1 .. $ITERS) {
            BART::BitSet256::_popcount64(1 << 32);
        }
    }));

    # Medium (8 bits set)
    my $med = 0;
    for my $b (0, 8, 16, 24, 32, 40, 48, 56) { $med |= (1 << $b); }
    record("popcount64", "input = 8 bits set", bench("pc_eight", sub {
        for (1 .. $ITERS) {
            BART::BitSet256::_popcount64($med);
        }
    }));

    # Dense (32 bits set)
    my $dense = (1 << 32) - 1;  # low 32 bits
    record("popcount64", "input = 32 bits set", bench("pc_32", sub {
        for (1 .. $ITERS) {
            BART::BitSet256::_popcount64($dense);
        }
    }));

    # All bits
    record("popcount64", "input = ~0 (64 bits set)", bench("pc_all", sub {
        for (1 .. $ITERS) {
            BART::BitSet256::_popcount64(~0);
        }
    }));
}

###############################################################################
# 5. Method call overhead
###############################################################################
{
    my $sa = BART::SparseArray256->new;
    $sa->insert_at(42, "val");

    # Method call: $sa->bitset (accessor method)
    record("Method Overhead", "\$sa->bitset (method call)", bench("method_call", sub {
        for (1 .. $ITERS) {
            $sa->bitset();
        }
    }));

    # Direct field: $sa->[0] (SparseArray256 is array-based: [bitset, items])
    record("Method Overhead", "\$sa->[0] (direct array slot)", bench("field_access", sub {
        for (1 .. $ITERS) {
            my $x = $sa->[0];
        }
    }));

    # Method call: $bs->test(42)
    my $bs = $sa->[0];  # bitset
    record("Method Overhead", "\$bs->test(42) (method call)", bench("method_test", sub {
        for (1 .. $ITERS) {
            $bs->test(42);
        }
    }));

    # Inline equivalent of test (no method dispatch)
    record("Method Overhead", "inline test logic (no method)", bench("inline_test", sub {
        for (1 .. $ITERS) {
            my $word = 42 >> 6;
            my $r = ($bs->[$word] & (1 << (42 & 63))) ? 1 : 0;
        }
    }));

    # Chained method: $sa->get(42) which calls bitset->test then bitset->rank
    record("Method Overhead", "\$sa->get(42) (chained methods)", bench("chained", sub {
        for (1 .. $ITERS) {
            $sa->get(42);
        }
    }));

    # Direct inline of the entire get logic
    record("Method Overhead", "inline get(42) (no methods)", bench("inline_get", sub {
        my $items = $sa->[1];
        for (1 .. $ITERS) {
            # Inline test + rank + array access
            if ($bs->[42 >> 6] & (1 << (42 & 63))) {
                my $rank = $bs->rank(42);
                my $val = $items->[$rank - 1];
            }
        }
    }));
}

###############################################################################
# 6. Lookup: pre-parsed vs string IPs
###############################################################################
{
    my $table = BART->new;
    $table->insert("10.0.0.0/8", "ten");
    $table->insert("10.1.0.0/16", "ten-one");
    $table->insert("10.1.2.0/24", "ten-one-two");
    $table->insert("192.168.0.0/16", "private");
    $table->insert("172.16.0.0/12", "private-172");

    my $ip_str = "10.1.2.99";

    # Full lookup with string IP (includes parsing)
    record("Lookup", "lookup(\$ip_str) [parse + trie walk]", bench("lookup_str", sub {
        for (1 .. $ITERS) {
            $table->lookup($ip_str);
        }
    }));

    # Pre-parse the IP, then measure just the trie walk
    my ($bytes, $is_ipv6) = BART::_parse_ip($ip_str);
    my $root = $table->{root4};

    record("Lookup", "trie walk only (pre-parsed IP)", bench("lookup_preparsed", sub {
        for (1 .. $ITERS) {
            # Replicate the lookup trie-walk with pre-parsed bytes
            my (@nodes, @octets);
            my $node = $root;
            my $sp = 0;
            my $found;

            for my $depth (0 .. 3) {
                my $octet = $bytes->[$depth];
                $nodes[$sp] = $node;
                $octets[$sp] = $octet;
                $sp++;

                my $chd = $node->[1];  # children sparse array
                my $chd_bs = $chd->[0];  # children bitset
                unless ($chd_bs->[$octet >> 6] & (1 << ($octet & 63))) {
                    last;
                }
                my $child = $chd->[1][$chd_bs->rank($octet) - 1];
                my $ref = ref($child);
                if ($ref eq 'BART::Node::Fringe') {
                    $found = $child->[0];
                    last;
                }
                if ($ref eq 'BART::Node::Leaf') {
                    if ($child->contains_ip($bytes)) {
                        $found = $child->[2];
                    }
                    last;
                }
                $node = $child;
            }

            unless (defined $found) {
                for (my $i = $sp - 1; $i >= 0; $i--) {
                    my ($val, $ok) = $nodes[$i]->lpm($octets[$i]);
                    if ($ok) {
                        $found = $val;
                        last;
                    }
                }
            }
        }
    }));

    # Measure just the IP parse portion
    record("Lookup", "_parse_ip only (for comparison)", bench("parse_only", sub {
        for (1 .. $ITERS) {
            BART::_parse_ip($ip_str);
        }
    }));

    # LPM at a single node (the core inner operation)
    my $bart_node = BART::Node::Bart->new;
    $bart_node->insert_prefix(pfx_to_idx(10, 8), "ten");
    $bart_node->insert_prefix(pfx_to_idx(192, 8), "priv");

    record("Lookup", "single node lpm(octet)", bench("lpm_single", sub {
        for (1 .. $ITERS) {
            $bart_node->lpm(10);
        }
    }));

    # Verify correctness
    my ($v, $ok) = $table->lookup($ip_str);
    print "Lookup verification: lookup('$ip_str') = ('$v', $ok)\n\n" if $ok;
}

###############################################################################
# Print results table
###############################################################################

printf "%-20s | %-38s | %s\n", "Section", "Operation", "Timing";
print "-" x 20, "-+-", "-" x 38, "-+-", "-" x 35, "\n";

my $current_section = "";
for my $r (@results) {
    my ($section, $name, $elapsed) = @$r;
    if ($section ne $current_section) {
        if ($current_section ne "") {
            print "-" x 20, "-+-", "-" x 38, "-+-", "-" x 35, "\n";
        }
        $current_section = $section;
    }
    printf "%-20s | %-38s | %s\n", $section, $name, fmt($elapsed);
}
print "-" x 20, "-+-", "-" x 38, "-+-", "-" x 35, "\n";

###############################################################################
# Summary: top hotspots
###############################################################################

print "\n";
print "TOP HOTSPOTS (sorted by ns/op, slowest first):\n";
print "=" x 78, "\n";

my @sorted = sort { ($b->[2] / $ITERS) <=> ($a->[2] / $ITERS) } @results;
my $rank = 1;
for my $r (@sorted) {
    my ($section, $name, $elapsed) = @$r;
    my $ns_per_op = ($elapsed / $ITERS) * 1_000_000_000;
    printf "%2d. [%-20s] %-38s %8.1f ns/op\n", $rank, $section, $name, $ns_per_op;
    $rank++;
}

print "\nDone.\n";
