#!/usr/bin/env perl
use strict;
use warnings;
use lib 'lib';
use lib "$ENV{HOME}/perl5/lib/perl5";
use BART;
use Net::Patricia;
use Time::HiRes qw(time);

sub bench {
    my ($label, $count, $code) = @_;
    # Warm up
    $code->();

    # Time 3 runs, take the best
    my $best;
    for (1 .. 3) {
        my $start = time();
        $code->();
        my $elapsed = time() - $start;
        $best = $elapsed if !defined $best || $elapsed < $best;
    }
    my $ops_sec = $count / $best;
    printf "  %-35s %10.0f ops/sec  (%6.2f µs/op)\n",
        $label, $ops_sec, ($best / $count) * 1_000_000;
    return $ops_sec;
}

# --- Generate test data ---
srand(42);

sub gen_prefixes {
    my ($n) = @_;
    my @prefixes;
    for (1 .. $n) {
        my $len = 8 + int(rand(25));  # /8 .. /32, realistic range
        my @octets = map { int(rand(256)) } 1..4;
        my $bits = $len;
        for my $i (0..3) {
            if ($bits >= 8) { $bits -= 8; next }
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

print "=== BART vs Net::Patricia Benchmark ===\n";
print "    BART: pure Perl v$BART::VERSION\n";
print "    Net::Patricia: XS/C v$Net::Patricia::VERSION (libpatricia)\n\n";

for my $size (100, 1_000, 10_000, 100_000) {
    my @pfx = gen_prefixes($size);
    my @ips = gen_ips(50_000);
    my $label = sprintf("%s prefixes", $size >= 1000 ? sprintf("%dK", $size/1000) : $size);

    print "--- $label, 50K lookups ---\n";

    # Build BART table
    my $bart = BART->new;
    $bart->insert($_, 1) for @pfx;

    # Build Patricia trie
    my $pat = Net::Patricia->new;
    $pat->add_string($_, 1) for @pfx;

    my (%results_bart, %results_pat);

    print "  Net::Patricia (XS/C):\n";
    $results_pat{insert} = bench("Insert $size prefixes", $size, sub {
        my $t = Net::Patricia->new;
        $t->add_string($_, 1) for @pfx;
    });
    $results_pat{lookup} = bench("Lookup 50K IPs", 50_000, sub {
        $pat->match_string($_) for @ips;
    });
    $results_pat{exact} = bench("Exact-match $size prefixes", $size, sub {
        $pat->match_exact_string($_) for @pfx;
    });
    $results_pat{delete} = bench("Delete $size prefixes", $size, sub {
        my $t = Net::Patricia->new;
        $t->add_string($_, 1) for @pfx;
        $t->remove_string($_) for @pfx;
    });

    print "  BART (pure Perl):\n";
    $results_bart{insert} = bench("Insert $size prefixes", $size, sub {
        my $t = BART->new;
        $t->insert($_, 1) for @pfx;
    });
    $results_bart{lookup} = bench("Lookup 50K IPs", 50_000, sub {
        $bart->lookup($_) for @ips;
    });
    $results_bart{contains} = bench("Contains 50K IPs", 50_000, sub {
        $bart->contains($_) for @ips;
    });
    $results_bart{exact} = bench("Exact-match $size prefixes", $size, sub {
        $bart->get($_) for @pfx;
    });
    $results_bart{delete} = bench("Delete $size prefixes", $size, sub {
        my $t = BART->new;
        $t->insert($_, 1) for @pfx;
        $t->delete($_) for @pfx;
    });

    printf "\n  %-25s %12s %12s %8s\n", "Summary", "Patricia", "BART", "Ratio";
    printf "  %-25s %12s %12s %8s\n", "-" x 25, "-" x 12, "-" x 12, "-" x 8;
    for my $op (qw(insert lookup exact delete)) {
        my $p = $results_pat{$op} || 0;
        my $b = $results_bart{$op} || 0;
        my $ratio = $p > 0 ? sprintf("%.1fx", $p / $b) : "n/a";
        printf "  %-25s %9.0f/s %9.0f/s %8s\n",
            ucfirst($op), $p, $b, $ratio;
    }
    if ($results_bart{contains}) {
        printf "  %-25s %12s %9.0f/s\n", "Contains (BART only)", "n/a", $results_bart{contains};
    }
    print "\n";
}

# --- Correctness cross-check ---
print "--- Correctness cross-check ---\n";
{
    my @pfx = gen_prefixes(5_000);
    my @ips = gen_ips(10_000);

    my $bart = BART->new;
    my $pat  = Net::Patricia->new;
    $bart->insert($_, 1) for @pfx;
    $pat->add_string($_, 1) for @pfx;

    my $agree = 0;
    my $disagree = 0;
    for my $ip (@ips) {
        my $b = $bart->contains($ip);
        my $p = defined($pat->match_string($ip)) ? 1 : 0;
        if ($b == $p) { $agree++ } else { $disagree++ }
    }
    printf "  Checked 10K IPs: %d agree, %d disagree\n", $agree, $disagree;
    if ($disagree) {
        print "  WARNING: results differ!\n";
    } else {
        print "  Both implementations agree on all lookups.\n";
    }
}

print "\nDone.\n";
