#!/usr/bin/perl -w
use strict;
use warnings;
use English qw { -no_match_vars };

use FindBin qw/$Bin/;
use rlib;

#use Test::More tests => 35;
use Test::More;

use Data::Section::Simple qw(get_data_section);

use Biodiverse::TestHelpers qw /:tree/;


local $| = 1;

use Biodiverse::ReadNexus;
use Biodiverse::Tree;

#  from Statistics::Descriptive
sub is_between
{
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    
    my ($have, $want_bottom, $want_top, $blurb) = @_;

    ok (
        (($have >= $want_bottom) &&
        ($want_top >= $have)),
        $blurb
    );
}


our $tol = 1E-13;

#  clean read of 'neat' nexus file
{
    my $nex_tree = get_nexus_tree_data();

    my $trees = Biodiverse::ReadNexus->new;
    my $result = eval {
        $trees->import_data (data => $nex_tree);
    };

    is ($result, 1, 'import nexus trees, no remap');

    my @trees = $trees->get_tree_array;

    is (scalar @trees, 2, 'two trees extracted');

    my $tree = $trees[0];

    run_tests ($tree);
}


#  clean read of working newick file
{
    my $data = get_newick_tree_data();

    my $trees = Biodiverse::ReadNexus->new;
    my $result = eval {
        $trees->import_data (data => $data);
    };

    is ($result, 1, 'import clean newick trees, no remap');

    my @trees = $trees->get_tree_array;

    is (scalar @trees, 1, 'one tree extracted');

    my $tree = $trees[0];

    run_tests ($tree);
}

{
    my $data = get_tabular_tree_data();

    my $trees = Biodiverse::ReadNexus->new;
    my $result = eval {
        $trees->import_data (data => $data);
    };
    my $e = $EVAL_ERROR;
    note $e if $e;

    is ($result, 1, 'import clean tabular tree, no remap');

    my @trees = $trees->get_tree_array;

    is (scalar @trees, 1, 'one tree extracted from tabular tree data');

    my $tree = $trees[0];

    #local $tol = 1E-8;
    run_tests ($tree);
}

{
    my $data = get_tabular_tree_data_x2();

    my $trees = Biodiverse::ReadNexus->new;
    my $result = eval {
        $trees->import_data (data => $data);
    };
    note $EVAL_ERROR if $EVAL_ERROR;

    is ($result, 1, 'import clean tabular trees, no remap');

    my @trees = $trees->get_tree_array;

    is (scalar @trees, 2, 'two trees extracted from tabular tree data');

    foreach my $tree (@trees) {
        run_tests ($tree);
    }
}

{
    my $data = get_tabular_tree_data();

    my $phylogeny_ref = Biodiverse::ReadNexus->new;

    #  Messy.  Need to use temp files which are cleaned up on scope exit.
    use FindBin;
    my $read_file   = $FindBin::Bin . '/tabular_export.csv';
    my $output_file = $FindBin::Bin . '/test_tabular_export.csv';

    # define map to read sample file
    my $field_map = {
        TREENAME_COL       => 9, 
        LENGTHTOPARENT_COL => 3,
        NODENUM_COL        => 5,
        NODENAME_COL       => 4,
        PARENT_COL         => 6,
    };

    # import tree from file
    
    my $result = eval {
        $phylogeny_ref->import_tabular_tree (
            file => $read_file,
            column_map => $field_map
        );
    };
    diag $EVAL_ERROR if $EVAL_ERROR;
    is ($result, 1, 'import tabular tree');

    # check some properties of imported tree(s)
    
    my $phylogeny_array = $phylogeny_ref->get_tree_array;
    
    my $tree_count = scalar @$phylogeny_array;
    is ($tree_count, 1, 'import tabular tree, count trees');

    foreach my $tree (@$phylogeny_array) {
        is ($tree->get_param ('NAME'), 'Example_tree', 'Check tree name');
    }

    # perform export
    my $export_tree = $phylogeny_array->[0]; 
    $result = eval {
        $export_tree->export_tabular_tree(file => $output_file);
    };
    my $e = $EVAL_ERROR;
    diag $e if $e;
    is ($result, 1, 'export tabular tree without an exception');

    # re-import
    my $reimport_ref = Biodiverse::ReadNexus->new;
    my $reimport_map = {
        TREENAME_COL       => 6, 
        LENGTHTOPARENT_COL => 2,
        NODENUM_COL        => 4,
        NODENAME_COL       => 3,
        PARENT_COL         => 5,
    };

    $result = eval {
        $reimport_ref->import_tabular_tree (
            file => $output_file,
            column_map => $reimport_map,
        );
    };
    $e = $EVAL_ERROR;
    diag $e if $e;
    is ($result, 1, 're-import tabular tree without an exception');

    # check re-import properties    
    my $reimport_array = $reimport_ref->get_tree_array;    
    $tree_count = scalar @$reimport_array;
    is ($tree_count, 1, 're-import tabular tree, count trees');

    foreach my $tree (@$reimport_array) {
        is ($tree->get_param ('NAME'), 'Example_tree', 'Check tree name');
    }

    # compare re-imported tree with exported one
    my $reimport_tree = $reimport_array->[0];

    my $trees_compare;
    $result = eval {
        $trees_compare = $export_tree->trees_are_same(
            comparison => $reimport_tree
        );
    };
    if ($EVAL_ERROR) { print "error $EVAL_ERROR\n"; }
    is ($result, 1, 'perform tree compare');
    is ($trees_compare, 1, 'tabular trip round-trip comparison');
    
    unlink $output_file;
}




#  read of a 'messy' nexus file with no newlines
SKIP:
{
    skip 'No system parses nexus trees with no newlines', 2;
    my $data = get_nexus_tree_data();

    #  eradicate newlines
    $data =~ s/[\r\n]+//gs;
    #print $data;
  TODO:
    {
        local $TODO = 'issue 149 - http://code.google.com/p/biodiverse/issues/detail?id=149';

        my $trees = Biodiverse::ReadNexus->new;
        my $result = eval {
            $trees->import_data (data => $data);
        };
    
        is ($result, 1, 'import nexus trees, no newlines, no remap');
    
        my @trees = $trees->get_tree_array;
    
        is (scalar @trees, 2, 'two trees extracted');
    
        my $tree = $trees[0];

        #run_tests ($tree);
    }
}

done_testing();


sub run_tests {
    my $tree = shift;

    my @tests = (
        {sub => 'get_node_count',    ex => 61,},
        {sub => 'get_tree_depth',    ex => 12,},
        {sub => 'get_tree_length',   ex => 0.992769230769231,},
        {sub => 'get_length_to_tip', ex => 0.992769230769231,},

        {sub => 'get_total_tree_length',  ex => 21.1822419987155,},    
    );

    foreach my $test (@tests) {
        my $sub   = $test->{sub};
        my $upper = $test->{ex} + $tol;
        my $lower = $test->{ex} - $tol;
        my $msg = "$sub expected $test->{ex} +/- $tol";

        my $val = $tree->$sub;
        #diag "$msg, $val\n";

        is_between (eval {$tree->$sub}, $lower, $upper, $msg);
    }

    return;    
}

