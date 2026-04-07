#!/usr/bin/env perl
use strict;
use warnings;
use lib 'lib';
use lib 'lib/Net/BART/blib/arch';
use lib 'lib/Net/BART/blib/lib';
use lib "$ENV{HOME}/perl5/lib/perl5";
use Net::BART;
use Net::BART::XS;
use Net::Patricia;
use Time::HiRes qw(time);

sub bench {
    my ($label, $count, $code) = @_;
    $code->();  # warm up
    my $best;
    for (1 .. 3) {
        my $start = time();
        $code->();
        my $elapsed = time() - $start;
        $best = $elapsed if !defined $best || $elapsed < $best;
    }
    my $ops_sec = $count / $best;
    my $us_op = ($best / $count) * 1_000_000;
    return ($ops_sec, $us_op);
}

srand(42);

sub gen_prefixes {
    my ($n) = @_;
    my @prefixes;
    for (1 .. $n) {
        my $len = 8 + int(rand(25));
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

print "=== Three-Way Benchmark: Net::Patricia vs Net::BART vs Net::BART::XS ===\n\n";

for my $size (100, 1_000, 10_000, 100_000) {
    my @pfx = gen_prefixes($size);
    my @ips = gen_ips(50_000);
    my $label = $size >= 1000 ? sprintf("%dK", $size/1000) : $size;

    # Pre-build tables
    my $pat = Net::Patricia->new;
    $pat->add_string($_, 1) for @pfx;

    my $bart = Net::BART->new;
    $bart->insert($_, 1) for @pfx;

    my $xs = Net::BART::XS->new;
    $xs->insert($_, 1) for @pfx;

    printf("--- %s prefixes ---\n", $label);
    printf("  %-12s %14s %14s %14s %10s %10s\n",
           "Operation", "Patricia(C)", "BART(Perl)", "BART::XS(C)", "XS/Perl", "XS/Pat");
    printf("  %-12s %14s %14s %14s %10s %10s\n",
           "-" x 12, "-" x 14, "-" x 14, "-" x 14, "-" x 10, "-" x 10);

    # Insert
    {
        my ($po) = bench("", $size, sub { my $t = Net::Patricia->new; $t->add_string($_, 1) for @pfx });
        my ($bo) = bench("", $size, sub { my $t = Net::BART->new; $t->insert($_, 1) for @pfx });
        my ($xo) = bench("", $size, sub { my $t = Net::BART::XS->new; $t->insert($_, 1) for @pfx });
        printf("  %-12s %11.0f/s %11.0f/s %11.0f/s %9.1fx %9.1fx\n",
               "Insert", $po, $bo, $xo, $xo/$bo, $xo/$po);
    }

    # Lookup
    {
        my ($po) = bench("", 50_000, sub { $pat->match_string($_) for @ips });
        my ($bo) = bench("", 50_000, sub { $bart->lookup($_) for @ips });
        my ($xo) = bench("", 50_000, sub { $xs->lookup($_) for @ips });
        printf("  %-12s %11.0f/s %11.0f/s %11.0f/s %9.1fx %9.1fx\n",
               "Lookup", $po, $bo, $xo, $xo/$bo, $xo/$po);
    }

    # Contains (BART only + XS)
    {
        my ($bo) = bench("", 50_000, sub { $bart->contains($_) for @ips });
        my ($xo) = bench("", 50_000, sub { $xs->contains($_) for @ips });
        printf("  %-12s %14s %11.0f/s %11.0f/s %9.1fx %10s\n",
               "Contains", "n/a", $bo, $xo, $xo/$bo, "n/a");
    }

    # Exact match
    {
        my ($po) = bench("", $size, sub { $pat->match_exact_string($_) for @pfx });
        my ($bo) = bench("", $size, sub { $bart->get($_) for @pfx });
        my ($xo) = bench("", $size, sub { $xs->get($_) for @pfx });
        printf("  %-12s %11.0f/s %11.0f/s %11.0f/s %9.1fx %9.1fx\n",
               "Get/Exact", $po, $bo, $xo, $xo/$bo, $xo/$po);
    }

    # Delete
    {
        my ($po) = bench("", $size, sub {
            my $t = Net::Patricia->new; $t->add_string($_, 1) for @pfx; $t->remove_string($_) for @pfx;
        });
        my ($bo) = bench("", $size, sub {
            my $t = Net::BART->new; $t->insert($_, 1) for @pfx; $t->delete($_) for @pfx;
        });
        my ($xo) = bench("", $size, sub {
            my $t = Net::BART::XS->new; $t->insert($_, 1) for @pfx; $t->delete($_) for @pfx;
        });
        printf("  %-12s %11.0f/s %11.0f/s %11.0f/s %9.1fx %9.1fx\n",
               "Delete", $po, $bo, $xo, $xo/$bo, $xo/$po);
    }

    print "\n";
}

# Correctness cross-check
print "--- Correctness cross-check (5K prefixes, 10K IPs) ---\n";
{
    my @pfx = gen_prefixes(5_000);
    my @ips = gen_ips(10_000);

    my $pat = Net::Patricia->new;
    my $bart = Net::BART->new;
    my $xs = Net::BART::XS->new;
    $pat->add_string($_, 1) for @pfx;
    $bart->insert($_, 1) for @pfx;
    $xs->insert($_, 1) for @pfx;

    my ($agree_all, $disagree) = (0, 0);
    for my $ip (@ips) {
        my $p = defined($pat->match_string($ip)) ? 1 : 0;
        my $b = $bart->contains($ip);
        my $x = $xs->contains($ip);
        if ($p == $b && $b == $x) { $agree_all++ } else { $disagree++ }
    }
    printf("  All three agree: %d/%d", $agree_all, $agree_all + $disagree);
    if ($disagree) { print " (WARNING: $disagree disagree!)" }
    print "\n";
}

print "\nDone.\n";
