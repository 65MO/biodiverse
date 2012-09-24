#!/usr/bin/perl -w

use strict;
use warnings;

local $| = 1;

use rlib;
use Test::More;

use Biodiverse::TestHelpers qw{
    :runners
};

run_indices_test1 (
    calcs_to_test  => [qw/
        calc_hierarchical_label_ratios
    /],
    calc_topic_to_test => 'Hierarchical Labels',
);

ok(0, 'Is this enough data for this test?');

done_testing;

1;

__DATA__

@@ RESULTS_2_NBR_LISTS
{
  'HIER_A0' => 2,
  'HIER_A1' => 2,
  'HIER_ARAT1_0' => '1',
  'HIER_ASUM0' => 18,
  'HIER_ASUM1' => 18,
  'HIER_ASUMRAT1_0' => 0,
  'HIER_B0' => 0,
  'HIER_B1' => 0,
  'HIER_BRAT1_0' => undef,
  'HIER_C0' => 12,
  'HIER_C1' => 12,
  'HIER_CRAT1_0' => '1'
}

@@ RESULTS_1_NBR_LISTS
{
}
