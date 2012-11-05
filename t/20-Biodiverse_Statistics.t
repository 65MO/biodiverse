#!/usr/bin/perl
use strict;
use warnings;
use English qw { -no_match_vars };

use FindBin qw/$Bin/;

use rlib;

use Test::More;

local $| = 1;

BEGIN { use_ok('Biodiverse::Statistics') };

use Biodiverse::Statistics;


{
    my $stat = Biodiverse::Statistics->new();

    $stat->add_data(1 .. 9);

    my %pctls = (
        0   => 1,
        1   => 1,
        30  => 3,
        42  => 4,
        49  => 5,
        50  => 5,
        100 => 9,
    );

    while (my ($key, $val) = each %pctls) {
        is ($stat->percentile ($key),
            $val,
            "Percentile $key is $val",
        );
    }
}

{
    my $stat = Biodiverse::Statistics->new();

    $stat->add_data (1 .. 9);

    my %pctls = (
        0   => undef,
        30  => 3,
        42  => 4,
        49  => 5,
        50  => 5,
        100 => 9,
    );

    while (my ($key, $val) = each %pctls) {
        my $text = $val // 'undef';
        is ($stat->percentile_RFC2330 ($key),
            $val,
            "Percentile RFC2330 $key is $text",
        );
    }
}


done_testing();
