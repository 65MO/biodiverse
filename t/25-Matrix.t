#!/usr/bin/perl -w
#
#  tests for both normal and lowmem matrices, where they overlap in methods
use 5.010;
use strict;
use warnings;

use FindBin qw/$Bin/;
use rlib;
use Scalar::Util qw /blessed/;

use Test::More;

use English qw / -no_match_vars /;
local $| = 1;

use Data::Section::Simple qw(get_data_section);

use Test::More; # tests => 2;
use Test::Exception;

use Biodiverse::TestHelpers qw /:matrix :basedata/;


use Biodiverse::Matrix;
use Biodiverse::Matrix::LowMem;

my @classes = qw /
    Biodiverse::Matrix
    Biodiverse::Matrix::LowMem
/;

foreach my $class (@classes) {
    run_main_tests($class);
}

foreach my $class (@classes) {
    run_with_site_data ($class);
}

#  now check with lower precision
{
    my $class = 'Biodiverse::Matrix';
    my $precision = '%.1f';
    run_with_site_data ($class, VAL_INDEX_PRECISION => $precision);
}

#  can one class substitute for the other?
{
    my $normal_class = 'Biodiverse::Matrix';
    my $lowmem_class = 'Biodiverse::Matrix::LowMem';

    my $mx = create_matrix_object ($normal_class);
    
    $mx->to_lowmem;

    is (blessed ($mx), $lowmem_class, "class is now $lowmem_class");

    run_main_tests (undef, $mx);

    $mx->to_normal;

    is (blessed ($mx), $normal_class, "class is now $normal_class");

    run_main_tests (undef, $mx);

}


#  NEED TO TEST EFFECT OF DELETIONS
foreach my $class (@classes) {
    run_deletions($class);
}

{
    test_cluster_analysis();
}


done_testing();

sub run_deletions {
    my ($class, $mx) = @_;
    
    $class //= blessed $mx;

    note "\nUsing class $class\n\n";

    my $e;  #  for errors

    $mx //= create_matrix_object ($class);

    ok (!$e, 'imported data');
    
    my $element_pair_count = $mx->get_element_pair_count;
    
    my $success;
    
    $success = eval {
        $mx->delete_element (element1 => undef, element2 => undef);
    };
    ok (defined $@, "exception on attempted deletion of non-existant pair, $class");
    
    $success = eval {
        $mx->delete_element (element1 => 'barry', element2 => 'the wonder dog');
    };
    ok (!$success, "non-deletion of non-existant pair, $class");

    $success = eval {
        $mx->delete_element (element1 => 'b', element2 => 'c');
    };
    ok ($success, "successful deletion of element pair, $class");
    
    my $expected = $element_pair_count - 1;
    is ($mx->get_element_pair_count, $expected, 'matrix element pair count decreased by 1');
    
    my $min_val = $mx->get_min_value;
    
    #  now delete the lowest three values
    eval {
        $mx->delete_element (element1 => 'b', element2 => 'a');
        $mx->delete_element (element1 => 'e', element2 => 'a');
        $mx->delete_element (element1 => 'f', element2 => 'a');
    };

    $expected = $element_pair_count - 4;
    is ($mx->get_element_pair_count, $expected, 'matrix element pair count decreased by 3');
    my $new_min_val = $mx->get_min_value;
    isnt ($min_val, $new_min_val, 'min value changed');
    is ($new_min_val, 2, 'min value correct');
    
    #  now add a value that will be snapped
    my $new_val_with_zeroes = 1.0000000001;
    $mx->add_element (element1 => 'aa', element2 => 'bb', value => $new_val_with_zeroes);
    $new_min_val = $mx->get_min_value;
    is ($new_min_val, $new_val_with_zeroes, 'got expected new min value');
    $mx->delete_element (element1 => 'aa', element2 => 'bb');
    $new_min_val = $mx->get_min_value;
    is ($new_min_val, 2, 'got expected new min value');
}

sub run_main_tests {
    my ($class, $mx) = @_;
    
    $class //= blessed $mx;

    note "\nUsing class $class\n\n";

    my $e;  #  for errors

    $mx //= create_matrix_object ($class);

    ok (!$e, 'imported data');
    
    eval {
        $mx->element_pair_exists();
    };
    $e = Exception::Class->caught;
    ok (defined $e, 'Raised exception for missing argument: ' . $e->error);

    my @elements_in_mx = qw /a b c d e f/;
    foreach my $element (@elements_in_mx) {
        my $in_mx = $mx->element_is_in_matrix (element => $element);
        ok ($in_mx, "element $element is in the matrix");
    }

    my @elements_not_in_mx = qw /x y z/;
    foreach my $element (@elements_not_in_mx) {
        my $in_mx = $mx->element_is_in_matrix (element => $element);
        ok (!$in_mx, "element $element is not in the matrix");
    }
    
    #  now we check some of the values
    my %expected = (
        a => {
            b => 1,
            d => 4,
            f => 1,
        },
        d => {
            f => undef,
            e => 4,
        },
    );

    while (my ($el1, $hash1) = each %expected) {
        while (my ($el2, $exp_val) = each %$hash1) {
            my $val;

            #  check the pair exists
            $val = $mx->element_pair_exists (element1 => $el1, element2 => $el2);
            if ($el1 eq 'd' && $el2 eq 'f') {
                $val = !$val;
            }
            ok ($val, "element pair existence: $el1 => $el2");

            my $exp_txt = $exp_val // 'undef';
            $val = $mx->get_value (element1 => $el1, element2 => $el2);
            is ($val, $exp_val, "got $exp_txt for pair $el1 => $el2");
            
            #  now the reverse
            $val = $mx->get_value (element2 => $el1, element1 => $el2);
            is ($val, $exp_val, "got $exp_txt for pair $el2 => $el1");
        }
    }
    
    #  check the extreme values
    my $expected_min = 1;
    my $expected_max = 6;
    is ($mx->get_min_value, $expected_min, "Got correct min value, $class");
    is ($mx->get_max_value, $expected_max, "Got correct max value, $class");

    #  get the element count
    my $expected_el_count = 6;
    is ($mx->get_element_count, $expected_el_count, "Got correct element count");

    #  get the element count
    my $expected = 11;
    is ($mx->get_element_pair_count, $expected, "Got correct element pair count");
    
    my $check_val = 3;
    my %expected_pairs = (
        c => {
            b => 1,
        },
        e => {
            c => 1,
        },
    );

    foreach my $method (qw /get_element_pairs_with_value get_elements_with_value/) {
        my %pairs = $mx->get_element_pairs_with_value (value => $check_val);
        is_deeply (
            \%pairs,
            \%expected_pairs,
            "Got expected element pairs with value $check_val, $class"
        );
    }

    my @expected_element_array = qw /a b c d e f/;
    my @array = sort @{$mx->get_elements_as_array};
    is_deeply (\@array, \@expected_element_array, 'Got correct element array');
}


sub run_with_site_data {
    my ($class, %args) = @_;

    note "\nUsing class $class\n\n";

    my $e;  #  for errors

    my $mx = get_matrix_object_from_sample_data($class, %args);
    ok (defined $mx, "created $class object");
    
    #  get the element count
    my $expected = 68;
    is ($mx->get_element_count, $expected, "Got correct element count, $class");

    #  get the element pair count
    $expected = 2346;
    is ($mx->get_element_pair_count, $expected, "Got correct element pair count, $class");    
    
    #  check the extreme values
    my $expected_min = 0.00063;
    my $expected_max = 0.0762;
    
    is ($mx->get_min_value, $expected_min, "Got correct min value, $class");
    is ($mx->get_max_value, $expected_max, "Got correct max value, $class");
    
    my %expected_pairs = (
        'Genus:sp68' => {
            'Genus:sp11' => 1,
        },
    );

    foreach my $method (qw /get_element_pairs_with_value get_elements_with_value/) {
        my %pairs = $mx->$method (value => $expected_min);
        is_deeply (
            \%pairs,
            \%expected_pairs,
            "$method returned expected element pairs with value $expected_min, $class"
        );
    }
    
    $mx->delete_element (element1 => 'Genus:sp68', element2 => 'Genus:sp11');

    $expected_min = 0.00065;
    is ($mx->get_min_value, $expected_min, "Got correct min value, $class");
    
    #$mx->save_to_yaml (filename => $mx =~ /LowMem/ ? 'xx_LowMem.bmy' : 'xx_normal.bmy');
}

sub test_cluster_analysis {
    #  make sure we get the same cluster result using each type of matrix
    #my $data = get_cluster_mini_data();
    #my $bd   = get_basedata_object (data => $data, CELL_SIZES => [1,1]);
    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [200000, 200000]);

    my $prng_seed = 123456;

    my $class1 = 'Biodiverse::Matrix';
    my $cl1 = $bd->add_cluster_output (
        name => $class1,
        CLUSTER_TIE_BREAKER => [ENDW_WE => 'max'],
        MATRIX_CLASS        => $class1,
    );
    $cl1->run_analysis (
        prng_seed => $prng_seed,
    );
    my $nwk1 = $cl1->to_newick;

    #  make sure we build a new matrix
    $bd->delete_all_outputs();

    my $class2 = 'Biodiverse::Matrix::LowMem';
    my $cl2 = $bd->add_cluster_output (
        name => $class2,
        CLUSTER_TIE_BREAKER => [ENDW_WE => 'max'],
        MATRIX_CLASS        => $class2,
    );
    $cl2->run_analysis (
        prng_seed => $prng_seed,
    );
    my $nwk2 = $cl2->to_newick;

    
    is (
        $nwk1,
        $nwk2,
        "Cluster analyses using matrices of classes $class1 and $class2 are the same"
    );
}


sub create_matrix_object {
    my $class = shift // 'Biodiverse::Matrix';

    my $e;

    my $tmp_mx_file = write_data_to_temp_file (get_matrix_data());
    my $fname = $tmp_mx_file->filename;
    my $mx = eval {
        $class->new (
            NAME            => "test matrix $class",
            ELEMENT_COLUMNS => [0],
        );
     };    
    $e = $EVAL_ERROR;
    diag $e if $e;

    ok (!$e, "created $class object without error");
    
    eval {
        $mx->import_data (
            file => $fname,
        );
    };
    $e = $EVAL_ERROR;
    diag $e if $e;

    return $mx;
}




######################################

sub get_matrix_data {
    return get_data_section('MATRIX_DATA');
}


1;

__DATA__

@@ MATRIX_DATA
x -
a -
b 1 -
c 2 3 -
d 4 5 6 -
e 1 2 3 4 -
f 1

@@ placeholder
- a b c d e

