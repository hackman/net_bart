#!/usr/bin/env perl
use strict;
use warnings;
use lib 'lib';
use BART;
use Time::HiRes qw(time);

sub bench {
    my ($label, $count, $code) = @_;
    my $start = time();
    $code->();
    my $elapsed = time() - $start;
    my $ops_sec = $count / $elapsed;
    printf "%-30s %8d ops in %6.3fs = %10.0f ops/sec  (%.1f µs/op)\n",
        $label, $count, $elapsed, $ops_sec, ($elapsed / $count) * 1_000_000;
    return $elapsed;
}

# Generate random IPv4 prefixes
sub gen_prefixes {
    my ($n) = @_;
    my @prefixes;
    for (1 .. $n) {
        my $len = int(rand(33));  # 0..32
        my @octets = map { int(rand(256)) } 1..4;
        # mask to prefix length
        my $bits = $len;
        for my $i (0..3) {
            if ($bits >= 8) { $bits -= 8; next; }
            if ($bits > 0) {
                $octets[$i] &= (0xFF << (8 - $bits)) & 0xFF;
                $bits = 0;
            } else {
                $octets[$i] = 0;
            }
        }
        push @prefixes, join('.', @octets) . "/$len";
    }
    return @prefixes;
}

sub gen_ips {
    my ($n) = @_;
    return map { join('.', map { int(rand(256)) } 1..4) } 1..$n;
}

srand(42);

print "=== BART Performance Benchmark ===\n\n";

# --- Small table ---
print "--- Small table (100 prefixes) ---\n";
{
    my $t = BART->new;
    my @pfx = gen_prefixes(100);
    my @ips = gen_ips(10000);

    bench("Insert 100 prefixes", 100, sub {
        $t->insert($pfx[$_], $_) for 0..$#pfx;
    });

    bench("Lookup 10K IPs", 10000, sub {
        $t->lookup($_) for @ips;
    });

    bench("Contains 10K IPs", 10000, sub {
        $t->contains($_) for @ips;
    });

    bench("Get 100 prefixes", 100, sub {
        $t->get($_) for @pfx;
    });
}

# --- Medium table ---
print "\n--- Medium table (10K prefixes) ---\n";
{
    my @pfx = gen_prefixes(10_000);
    my @ips = gen_ips(50_000);

    my $t = BART->new;
    bench("Insert 10K prefixes", 10_000, sub {
        $t->insert($pfx[$_], $_) for 0..$#pfx;
    });

    bench("Lookup 50K IPs", 50_000, sub {
        $t->lookup($_) for @ips;
    });

    bench("Contains 50K IPs", 50_000, sub {
        $t->contains($_) for @ips;
    });

    bench("Get 10K prefixes", 10_000, sub {
        $t->get($_) for @pfx;
    });

    bench("Delete 10K prefixes", 10_000, sub {
        $t->delete($pfx[$_]) for 0..$#pfx;
    });
}

# --- Large table ---
print "\n--- Large table (100K prefixes) ---\n";
{
    my @pfx = gen_prefixes(100_000);
    my @ips = gen_ips(100_000);

    my $t = BART->new;
    bench("Insert 100K prefixes", 100_000, sub {
        $t->insert($pfx[$_], $_) for 0..$#pfx;
    });

    bench("Lookup 100K IPs", 100_000, sub {
        $t->lookup($_) for @ips;
    });

    bench("Contains 100K IPs", 100_000, sub {
        $t->contains($_) for @ips;
    });

    bench("Get 100K prefixes", 100_000, sub {
        $t->get($_) for @pfx;
    });

    bench("Delete 100K prefixes", 100_000, sub {
        $t->delete($pfx[$_]) for 0..$#pfx;
    });
}

# --- Profiling hotspots: isolate IP parsing vs trie ops ---
print "\n--- Isolating overhead: parse vs trie ---\n";
{
    my @pfx = gen_prefixes(10_000);
    my @ips = gen_ips(50_000);

    # Pre-parse all IPs
    my @parsed_ips;
    bench("Parse 50K IPs", 50_000, sub {
        for my $ip (@ips) {
            push @parsed_ips, [BART::_parse_ip($ip)];
        }
    });

    # Pre-parse prefixes and insert
    my $t = BART->new;
    my @parsed_pfx;
    bench("Parse+insert 10K prefixes", 10_000, sub {
        for my $i (0..$#pfx) {
            my @p = BART::_parse_prefix($pfx[$i]);
            push @parsed_pfx, \@p;
            $t->insert($pfx[$i], $i);
        }
    });

    # Lookup using string API (includes parsing)
    bench("Lookup 50K (string API)", 50_000, sub {
        $t->lookup($_) for @ips;
    });
}

# --- IPv6 ---
print "\n--- IPv6 (1K prefixes) ---\n";
{
    my $t = BART->new;
    my @pfx;
    for (1..1000) {
        my $len = int(rand(129));
        my @groups = map { sprintf("%x", int(rand(65536))) } 1..8;
        push @pfx, join(':', @groups) . "/$len";
    }
    my @ips;
    for (1..10000) {
        my @groups = map { sprintf("%x", int(rand(65536))) } 1..8;
        push @ips, join(':', @groups);
    }

    bench("Insert 1K IPv6 prefixes", 1000, sub {
        $t->insert($pfx[$_], $_) for 0..$#pfx;
    });

    bench("Lookup 10K IPv6 IPs", 10000, sub {
        $t->lookup($_) for @ips;
    });
}

print "\nDone.\n";
