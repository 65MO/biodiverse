#!/usr/bin/perl -w
#

use 5.010;
use strict;
use warnings;
use Carp;

use FindBin qw/$Bin/;
use rlib;
use List::Util qw /first sum0/;

use Test::More;
use Test::Deep;

use English qw / -no_match_vars /;
local $| = 1;

use Data::Section::Simple qw(get_data_section);

use Test::More; # tests => 2;
use Test::Exception;

use Biodiverse::TestHelpers qw /:cluster :element_properties :tree/;
use Biodiverse::Cluster;

my $default_prng_seed = 2345;

use Devel::Symdump;
my $obj = Devel::Symdump->rnew(__PACKAGE__); 
my @subs = grep {$_ =~ 'main::test_'} $obj->functions();

exit main( @ARGV );

sub main {
    my @args  = @_;

    if (@args) {
        for my $name (@args) {
            die "No test method test_$name\n"
                if not my $func = (__PACKAGE__->can( 'test_' . $name ) || __PACKAGE__->can( $name ));
            $func->();
        }
        done_testing;
        return 0;
    }
    
    foreach my $sub (sort @subs) {
        no strict 'refs';
        $sub->();
    }

    done_testing;
    return 0;
}


sub test_rand_structured_richness_same {
    my $c = 100000;
    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [$c, $c]);

    #  add some empty groups - need enough to trigger issue #543
    foreach my $i (1 .. 20) {
        my $x = $i * -$c + $c / 2;
        my $y = -$c / 2;
        my $gp = "$x:$y";
        $bd->add_element (group => $gp, allow_empty_groups => 1);
    }

    #  name is short for test_rand_calc_per_node_uses_orig_bd
    my $sp = $bd->add_spatial_output (name => 'sp');

    $sp->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations => [qw /calc_richness/],
    );

    my $prng_seed = 2345;

    my $rand_name = 'rand_structured';

    my $rand = $bd->add_randomisation_output (name => $rand_name);
    my $rand_bd_array = $rand->run_analysis (
        function   => 'rand_structured',
        iterations => 3,
        seed       => $prng_seed,
        return_rand_bd_array => 1,
    );

    subtest 'richness scores match' => sub {
        foreach my $rand_bd (@$rand_bd_array) {
            foreach my $group (sort $rand_bd->get_groups) {
                my $bd_richness = $bd->get_richness(element => $group) // 0;
                is ($rand_bd->get_richness (element => $group) // 0,
                    $bd_richness,
                    "richness for $group matches ($bd_richness)",
                );
            }
        }
    };
    subtest 'range scores match' => sub {
        foreach my $rand_bd (@$rand_bd_array) {
            foreach my $label ($rand_bd->get_labels) {
                is ($rand_bd->get_range (element => $label),
                    $bd->get_range (element => $label),
                    "range for $label matches",
                );
            }
        }
    };

    return;
}

sub test_rand_structured_subset_richness_same_with_defq {
    my $defq = '$y > 1050000';
    my ($rand_object, $bd, $rand_bd_array) = test_rand_structured_subset_richness_same ($defq);

    my $sp = $rand_object->get_param ('SUBSET_SPATIAL_OUTPUT');
    my $failed_defq = $sp->get_groups_that_failed_def_query;

    subtest 'groups that failed def query are unchanged' => sub {
        my $i = -1;
        foreach my $rand_bd (@$rand_bd_array) {
            $i++;
            foreach my $gp (sort keys %$failed_defq) {
                my $expected = $bd->get_labels_in_group_as_hash(group => $gp);
                my $observed = $rand_bd->get_labels_in_group_as_hash(group => $gp);
                is_deeply (
                    $observed,
                    $expected,
                    "defq check: $gp labels are same for rand_bd $i",
                );
            }
        }
    };

    #  now try with a def query but no spatial condition
    #  - we should get the same result as condition sp_select_all()
    my $rand_object2 = $bd->add_randomisation_output (name => 'defq but no sp_cond');
    $rand_object2->run_analysis (
        function   => 'rand_structured',
        iterations => 1,
        seed       => 2345,
        definition_query => $defq,
    );
    my $sp2 = $rand_object2->get_param ('SUBSET_SPATIAL_OUTPUT');
    my $sp_conditions = $sp2->get_spatial_conditions_arr;
    ok (
        $sp_conditions->[0]->get_conditions_unparsed eq 'sp_select_all()',
        'got expected default condition when defq specified without spatial condition',
    );
    
    return;
}

sub test_rand_structured_subset_richness_same {
    my $def_query = shift;

    my $c = 100000;
    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [$c, $c]);

    #  add some empty groups - need enough to trigger issue #543
    foreach my $i (1 .. 20) {
        my $x = $i * -$c + $c / 2;
        my $y = -$c / 2;
        my $gp = "$x:$y";
        $bd->add_element (group => $gp, allow_empty_groups => 1);
    }

    $bd->build_spatial_index (resolutions => [100000, 100000]);

    #  name is short for test_rand_calc_per_node_uses_orig_bd
    my $sp = $bd->add_spatial_output (name => 'sp');

    $sp->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations       => [qw /calc_richness/],
    );

    my $prng_seed = 2345;

    my $rand_name = 'rand_structured_subset';

    my $rand_object = $bd->add_randomisation_output (name => $rand_name);
    my $rand_bd_array = $rand_object->run_analysis (
        function   => 'rand_structured',
        iterations => 3,
        seed       => $prng_seed,
        return_rand_bd_array => 1,
        spatial_condition => 'sp_block(size => 1000000)',
        definition_query     => $def_query,
    );

    subtest "group and label sets match" => sub {
        my @obs_gps = sort $bd->get_groups;
        my @obs_lbs = sort $bd->get_labels;
        my $i = -1;
        foreach my $rand_bd (@$rand_bd_array) {
            $i++;
            my @rand_gps = sort $rand_bd->get_groups;
            my @rand_lbs = sort $rand_bd->get_labels;
            is_deeply (\@rand_gps, \@obs_gps, "group sets match for iteration $i");
            is_deeply (\@rand_lbs, \@obs_lbs, "label sets match for iteration $i");
        }
    };

    check_randomisation_results_differ ($rand_object, $bd, $rand_bd_array);

    return ($rand_object, $bd, $rand_bd_array);
}

sub test_rand_constant_labels {

    my $c  = 100000;
    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [$c, $c]);

    #  add a couple of empty groups
    foreach my $i (1 .. 2) {
        my $x = $i * -$c + $c / 2;
        my $y = -$c / 2;
        my $gp = "$x:$y";
        $bd->add_element (group => $gp, allow_empty_groups => 1);
    }

    $bd->build_spatial_index (resolutions => [$c, $c]);

    #  name is short for test_rand_calc_per_node_uses_orig_bd
    my $sp = $bd->add_spatial_output (name => 'sp');

    $sp->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations       => [qw /calc_richness/],
    );

    my $prng_seed = 2345;

    my $rand_name = 'rand_labels_held_constant';

    my $labels_not_to_randomise = [qw/Genus:sp22 Genus:sp28 Genus:sp31 Genus:sp16 Genus:sp18/];

    my $rand_object = $bd->add_randomisation_output (name => $rand_name);
    my $rand_bd_array = $rand_object->run_analysis (
        function   => 'rand_structured',
        iterations => 2,
        seed       => $prng_seed,
        return_rand_bd_array => 1,
        spatial_condition => 'sp_block(size => 1000000)',
        labels_not_to_randomise => $labels_not_to_randomise,
    );

    #  check ranges are identical for the constants
    subtest 'Constant label ranges are unchanged' => sub {
        my $i = -1;
        foreach my $rand_bd (@$rand_bd_array) {
            $i++;
            foreach my $label (@$labels_not_to_randomise) {
                my $old_range = $bd->get_groups_with_label (label => $label);
                my $new_range = $rand_bd->get_groups_with_label (label => $label);
                is_deeply ($new_range, $old_range, "Range matches for $label, randomisation $i");

                my $orig_list = $bd->get_labels_ref->get_list_ref (
                    element => $label,
                    list => 'SUBELEMENTS',
                    autovivify => 0,
                );
                my $new_list = $rand_bd->get_labels_ref->get_list_ref (
                    element => $label,
                    list => 'SUBELEMENTS',
                    autovivify => 0,
                );
                no autovivification;
                is_deeply (
                    $orig_list,
                    $new_list,
                    "sample counts match for $label, randomisation $i",
                );
            }
        }
    };

    check_randomisation_results_differ ($rand_object, $bd, $rand_bd_array);
    
    return ($rand_object, $bd, $rand_bd_array);
}


#  Are the differing input methods for constant labels stable?
sub test_rand_constant_labels_differing_input_methods {

    my $c  = 100000;
    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [$c, $c]);

    #  add a couple of empty groups
    foreach my $i (1 .. 2) {
        my $x = $i * -$c + $c / 2;
        my $y = -$c / 2;
        my $gp = "$x:$y";
        $bd->add_element (group => $gp, allow_empty_groups => 1);
    }

    $bd->build_spatial_index (resolutions => [$c, $c]);

    #  name is short for test_rand_calc_per_node_uses_orig_bd
    my $sp = $bd->add_spatial_output (name => 'sp');

    $sp->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations       => [qw /calc_richness/],
    );

    my $prng_seed = 2345;

    my $rand_name = 'rand_labels_held_constant';

    my $labels_not_to_randomise_array = [qw/Genus:sp22 Genus:sp28 Genus:sp31 Genus:sp16 Genus:sp18/];
    my $labels_not_to_randomise_text = join "\n", @$labels_not_to_randomise_array;
    my %labels_not_to_randomise_hash;
    @labels_not_to_randomise_hash{@$labels_not_to_randomise_array}
      = (1) x scalar @$labels_not_to_randomise_array;
    my $labels_not_to_randomise_text_h = join "\n", %labels_not_to_randomise_hash;
    
    my %args = (
        function   => 'rand_structured',
        iterations => 1,
        seed       => $prng_seed,
        return_rand_bd_array => 1,
        spatial_condition => 'sp_block(size => 1000000)',
    );

    my $rand_object_a = $bd->add_randomisation_output (name => $rand_name . '_a');
    my $rand_bd_array_a = $rand_object_a->run_analysis (
        %args,
        labels_not_to_randomise => $labels_not_to_randomise_array,
    );

    my $rand_object_t = $bd->add_randomisation_output (name => $rand_name . '_t');
    my $rand_bd_array_t = $rand_object_t->run_analysis (
        %args,
        labels_not_to_randomise => $labels_not_to_randomise_text,
    );
    
    my $rand_object_th = $bd->add_randomisation_output (name => $rand_name . '_th');
    my $rand_bd_array_th = $rand_object_th->run_analysis (
        %args,
        labels_not_to_randomise => $labels_not_to_randomise_text_h,
    );

    subtest "array and text variants result in same labels held constant" => sub {
        my $bd_a  = $rand_bd_array_a->[0];
        my $bd_t  = $rand_bd_array_t->[0];
        my $bd_th = $rand_bd_array_th->[0];

        for my $gp ($bd->get_groups) {
            my $expected = scalar $bd_a->get_labels_in_group_as_hash (group => $gp);
            is_deeply (
                scalar $bd_t->get_labels_in_group_as_hash (group => $gp),
                $expected,
                $gp,
            );
            is_deeply (
                scalar $bd_th->get_labels_in_group_as_hash (group => $gp),
                $expected,
                $gp,
            );
        }
    }

}

sub check_randomisation_results_differ {
    my ($rand_object, $bd, $rand_bd_array) = @_;
    
    my $rand_name = $rand_object->get_name;
    
    #  need to refactor these subtests
    subtest "Labels in groups differ $rand_name" => sub {
        my $i = 0;
        foreach my $rand_bd (@$rand_bd_array) {
            my $match_count = 0;
            my $expected_count = 0;
            foreach my $group (sort $rand_bd->get_groups) {
                my $labels      = $bd->get_labels_in_group_as_hash (group => $group);
                my $rand_labels = $rand_bd->get_labels_in_group_as_hash (group => $group);
                $match_count    += grep {exists $labels->{$_}} keys %$rand_labels;
                $expected_count += scalar keys %$labels;
            }
            isnt ($match_count, $expected_count, "contents differ, rand_bd $i");
        }
        $i++;
    };

    subtest "richness scores match for $rand_name" => sub {
        foreach my $rand_bd (@$rand_bd_array) {
            foreach my $group (sort $rand_bd->get_groups) {
                my $bd_richness = $bd->get_richness(element => $group) // 0;
                is ($rand_bd->get_richness (element => $group) // 0,
                    $bd_richness,
                    "richness for $group matches",
                );
            }
        }
    };
    subtest "range scores match for $rand_name" => sub {
        foreach my $rand_bd (@$rand_bd_array) {
            foreach my $label ($rand_bd->get_labels) {
                is ($rand_bd->get_range (element => $label),
                    $bd->get_range (element => $label),
                    "range for $label matches",
                );
            }
        }
    };
    
}

#  need to implement this for randomisations
sub check_order_is_same_given_same_prng {
    my %args = @_;
    my $bd = $args{basedata_ref};
    
    my $prng_seed = $args{prng_seed} || $default_prng_seed;
    
}


#  Should get same result for two iterations run in one go as we do for
#  two run sequentially (first, pause, second)
#  Need to rename this sub
sub test_same_results_given_same_prng_seed {
    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [200000, 200000]);

    #  name is short for test_rand_calc_per_node_uses_orig_bd
    my $sp = $bd->add_spatial_output (name => 'sp');
    
    $sp->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations => [qw /calc_richness calc_element_lists_used calc_elements_used/],
    );

    my $prng_seed = 2345;

    my $rand_name_2in1 = '2in1';
    my $rand_name_1x1 = '1x1';

    my $rand_2in1 = $bd->add_randomisation_output (name => $rand_name_2in1);
    $rand_2in1->run_analysis (
        function   => 'rand_csr_by_group',
        iterations => 3,
        seed       => $prng_seed,
    );

    my $rand_1x1 = $bd->add_randomisation_output (name => $rand_name_1x1);
    for my $i (0..2) {
        $rand_1x1->run_analysis (
            function   => 'rand_csr_by_group',
            iterations => 1,
            seed       => $prng_seed,
        );
    }

    #  these should be the same as the PRNG sequence will be maintained across iterations
    my $table_2in1 = $sp->to_table (list => $rand_name_2in1 . '>>SPATIAL_RESULTS');
    my $table_1x1  = $sp->to_table (list => $rand_name_1x1  . '>>SPATIAL_RESULTS');

    is_deeply (
        $table_2in1,
        $table_1x1,
        'Results same when init PRNG seed same and iteration counts same'
    );

    #  now we should see a difference if we run another
    $rand_1x1->run_analysis (
        function   => 'rand_csr_by_group',
        iterations => 1,
        seed       => $prng_seed,
    );
    $table_1x1 = $sp->to_table (list => $rand_name_1x1  . '>>SPATIAL_RESULTS');
    isnt (
        eq_deeply (
            $table_2in1,
            $table_1x1,
        ),
        'Results different when init PRNG seed same but iteration counts differ',
    );

    #  Now catch up the other one, but change some more args.
    #  Most should be ignored.
    $rand_2in1->run_analysis (
        function   => 'rand_nochange',
        iterations => 1,
        seed       => $prng_seed,
    );
    $table_2in1 = $sp->to_table (list => $rand_name_2in1 . '>>SPATIAL_RESULTS');

    is_deeply (
        $table_2in1,
        $table_1x1,
        'Changed function arg ignored in analysis with an iter completed'
    );
    
    return;
}



sub test_rand_calc_per_node_uses_orig_bd {
    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [100000, 100000]);

    #  name is short for test_rand_calc_per_node_uses_orig_bd
    my $cl = $bd->add_cluster_output (name => 't_r_c_p_n_u_o_b');
    
    $cl->run_analysis (
        spatial_calculations => [qw /calc_richness calc_element_lists_used calc_elements_used/],
    );

    my $rand_name = 'xxx';

    my $rand = $bd->add_randomisation_output (name => $rand_name);
    my $rand_bd_array = $rand->run_analysis (
        function   => 'rand_csr_by_group',
        iterations => 1,
        retain_outputs => 1,
        return_rand_bd_array => 1,
    );

    my $rand_bd1 = $rand_bd_array->[0];
    my @refs = $rand_bd1->get_cluster_output_refs;
    my $rand_cl = first {$_->get_param ('NAME') =~ m/rand sp_calc/} @refs;  #  bodgy way of getting at it

    my $sub_ref = sub {
        node_calcs_used_same_element_sets (
            orig_tree => $cl,
            rand_tree => $rand_cl,
        );
    };
    subtest 'Calcs per node used the same element sets' => $sub_ref;
    
    my $sub_ref2 = sub {
        node_calcs_gave_expected_results (
            cluster_output => $cl,
            rand_name      => $rand_name,
        );
    };
    subtest 'Calcs per node used the same element sets' => $sub_ref2;

    return;
}

#  iterate over all the nodes and check they have the same
#  element lists and counts, but that the richness scores are not the same    
sub node_calcs_used_same_element_sets {
    my %args = @_;
    my $orig_tree = $args{orig_tree};
    my $rand_tree = $args{rand_tree};

    my %orig_nodes = $orig_tree->get_node_hash;
    my %rand_nodes = $rand_tree->get_node_hash;

    is (scalar keys %orig_nodes, scalar keys %rand_nodes, 'same number of nodes');

    my $count_richness_same = 0;

    foreach my $name (sort keys %orig_nodes) {  #  always test in same order for repeatability
        my $o_node_ref = $orig_nodes{$name};
        my $r_node_ref = $rand_nodes{$name};

        my $o_element_list = $o_node_ref->get_list_ref (list => 'EL_LIST_SET1');
        my $r_element_list = $r_node_ref->get_list_ref (list => 'EL_LIST_SET1');
        is_deeply ($o_element_list, $r_element_list, "$name used same element lists");
        
        my $o_sp_res = $o_node_ref->get_list_ref (list => 'SPATIAL_RESULTS');
        my $r_sp_res = $r_node_ref->get_list_ref (list => 'SPATIAL_RESULTS');
        if ($o_sp_res->{RICHNESS_ALL} == $r_sp_res->{RICHNESS_ALL}) {
            $count_richness_same ++;
        }
    }

    isnt ($count_richness_same, scalar keys %orig_nodes, 'richness scores differ between orig and rand nodes');

    return;
}


#  rand results should be zero for all el_list P and C results, 1 for Q
sub node_calcs_gave_expected_results {
    my %args = @_;
    my $cl          = $args{cluster_output};
    my $list_prefix = $args{rand_name};
    
    my $list_name = $list_prefix . '>>SPATIAL_RESULTS';
    
    my %nodes = $cl->get_node_hash;
    foreach my $node_ref (sort {$a->get_name cmp $b->get_name} values %nodes) {
        my $list_ref = $node_ref->get_list_ref (list => $list_name);
        my $node_name = $node_ref->get_name;

        KEY:
        while (my ($key, $value) = each %$list_ref) {
            my $expected
              = ($key =~ /^[TQ]_EL/) ? 1
              : ($key =~ /^[CP]_EL/) ? 0
              : next KEY;
            is ($value, $expected, "$key score for $node_name is $expected")
        }
        
    }
    
}


sub test_group_properties_reassigned_subset_rand {
    my %args = (
        spatial_condition => 'sp_block (size => 1000000)',
    );

    #  get a basedata aftr we have run some tests on it first
    my $bd = test_group_properties_reassigned(%args);

    my @sp_outputs = $bd->get_spatial_output_refs;
    my $sp = $sp_outputs[0];

    subtest 'Spatial analysis results are all tied for subset matching spatial condition' => sub {
        my @lists = grep {$_ =~ />>GP/} $sp->get_lists_across_elements;
        foreach my $element ($sp->get_element_list) {
            foreach my $list (@lists) {
                my $list_ref = $sp->get_list_ref (
                    element => $element,
                    list    => $list,
                    autovivify => 0,
                );
                my @keys = sort grep {$_ =~ /^T_/} keys %$list_ref;
                foreach my $key (@keys) {
                    is ($list_ref->{$key}, 1, "$list $element $key")
                }
            }
        }
    };

}

sub test_group_properties_reassigned {
    my %args = @_;

    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [100000, 100000]);

    my $rand_func   = 'rand_csr_by_group';
    my $object_name = 't_g_p_r';
    
    my $gp_props = get_group_properties_site_data_object();

    eval { $bd->assign_element_properties (
        type              => 'groups',
        properties_object => $gp_props,
    ) };
    my $e = $EVAL_ERROR;
    note $e if $e;
    ok (!$e, 'Group properties assigned without eval error');

    #  name is short for sub name
    my $sp = $bd->add_spatial_output (name => 't_g_p_r');

    $sp->run_analysis (
        calculations => [qw /calc_gpprop_stats/],
        spatial_conditions => [$args{spatial_condition} // 'sp_self_only()'],
    );

    my %prop_handlers = (
        no_change => 0,
        by_set    => 1,
        by_item   => 1,
    );
    
    while (my ($props_func, $negate_expected) = each %prop_handlers) {

        my $rand_name   = 'r' . $object_name . $props_func;

        my $rand = $bd->add_randomisation_output (name => $rand_name);
        my $rand_bd_array = $rand->run_analysis (
            function   => $rand_func,
            iterations => 1,
            retain_outputs        => 1,
            return_rand_bd_array  => 1,
            randomise_group_props_by => $props_func,
        );
    
        my $rand_bd = $rand_bd_array->[0];
        my @refs = $rand_bd->get_spatial_output_refs;
        my $rand_sp = first {$_->get_param ('NAME') =~ m/^$object_name/} @refs;
    
        my $sub_same = sub {
            basedata_group_props_are_same (
                object1 => $bd,
                object2 => $rand_bd,
                negate  => $negate_expected,
            );
        };

        subtest "$props_func checks" => $sub_same;
    }

    return $bd;
}

sub test_randomise_tree_ref_args {
    my $rand_func   = 'rand_csr_by_group';
    my $object_name = 't_r_t_r_f';

    my $bd = get_basedata_object_from_site_data(CELL_SIZES => [100000, 100000]);
    my $tree  = get_tree_object_from_sample_data();
    my $tree2 = $tree->clone;
    $tree2->shuffle_terminal_names;  # just to make it different
    $tree2->rename (new_name => 'tree2');

    
    #  name is short for sub name
    my $sp_self_only = $bd->add_spatial_output (name => 'self_only');
    $sp_self_only->run_analysis (
        calculations       => [qw /calc_pd/],
        spatial_conditions => ['sp_self_only()'],
        tree_ref           => $tree,
    );
    my $sp_select_all = $bd->add_spatial_output (name => 'select_all');
    $sp_select_all->run_analysis (
        calculations       => [qw /calc_pd/],
        spatial_conditions => ['sp_select_all()'],
        tree_ref           => $tree,
    );
    my $sp_tree2 = $bd->add_spatial_output (name => 'tree2');
    $sp_tree2->run_analysis (
        calculations       => [qw /calc_pd/],
        spatial_conditions => ['sp_self_only()'],
        tree_ref           => $tree2,
    );

    my $iter_count = 2;
    my %shuffle_method_hash = $tree->get_subs_with_prefix (prefix => 'shuffle');

    #  need to handle abbreviated forms
    my @tmp = sort keys %shuffle_method_hash;
    my @tmp2 = map {(my $x = $_) =~ s/^shuffle_//; $x} @tmp;
    my @shuffle_method_array = (@tmp, @tmp2);
    
    #diag 'testing tree shuffle methods: ' . join ' ', @shuffle_method_array;

    foreach my $shuffle_method (@shuffle_method_array) {
        my $use_is_or_isnt = ($shuffle_method !~ /no_change$/) ? 'isnt' : 'is';
        my $not_text = $use_is_or_isnt eq 'isnt' ? 'not' : ' ';
        my $notnot_text = $use_is_or_isnt eq 'isnt' ? '' : ' not';
        my $rand_name = 't_r_t_r_f_rand' . $shuffle_method;
        my $rand = $bd->add_randomisation_output (name => $rand_name);
        my $rand_bd_array = $rand->run_analysis (
            function             => 'rand_nochange',
            randomise_trees_by   => $shuffle_method,
            iterations           => $iter_count,
            retain_outputs       => 1,
            return_rand_bd_array => 1,
        );

        #  sp_self_only should be different, but sp_select_all should be the same
        my @groups = sort $sp_self_only->get_element_list;
        my $list_name = $rand_name . '>>SPATIAL_RESULTS';
        my %count_same;
        foreach my $gp (@groups) {
            my $list_ref_self_only = $sp_self_only->get_list_ref (
                element => $gp,
                list    => $list_name,
            );
            my $list_ref_select_all = $sp_select_all->get_list_ref (
                element => $gp,
                list    => $list_name,
            );
            my $list_ref_tree2 = $sp_tree2->get_list_ref (
                element => $gp,
                list    => $list_name,
            );

            $count_same{self_only}  += $list_ref_self_only->{T_PD} // 0;
            $count_same{select_all} += $list_ref_select_all->{T_PD} // 0;
            $count_same{tree2}      += $list_ref_tree2->{T_PD} // 0;
        }

        my $expected = $iter_count * scalar @groups;
        is ($count_same{select_all}, $expected, $shuffle_method . ': Global PD scores are same for orig and rand');
        my $check = is_or_isnt (
            $count_same{self_only},
            $expected,
            "$shuffle_method: Local PD scores $notnot_text same between orig and rand",
            $use_is_or_isnt,
        );
        $check = is_or_isnt (
            $count_same{tree2},
            $expected,
            "$shuffle_method: Local PD with tree2 scores $notnot_text same between orig and rand",
            $use_is_or_isnt,
        );

        my @analysis_args_array;

        #  and check we haven't overridden the original tree_ref
        for my $i (0 .. $#$rand_bd_array) {
            my $track_hash = {};
            push @analysis_args_array, $track_hash;
            my $rand_bd = $rand_bd_array->[$i];
            my @rand_sp_refs = $rand_bd->get_spatial_output_refs;
            for my $ref (@rand_sp_refs) {
                my $sp_name = $ref->get_param ('NAME');
                my @tmp = split ' ', $sp_name;  #  the first part of the name is the original
                my $sp_pfx = $tmp[0];

                my $analysis_args = $ref->get_param ('SP_CALC_ARGS');
                $track_hash->{$sp_pfx} = $analysis_args;

                my $rand_tree_ref = $analysis_args->{tree_ref};
                my $tree_ref_to_compare = $sp_pfx eq 'tree2' ? $tree2 : $tree;
                my $orig_tree_name = $tree_ref_to_compare->get_param ('NAME');

                is_or_isnt (
                    $tree_ref_to_compare,
                    $rand_tree_ref,
                    "$shuffle_method: Tree refs $not_text same, orig & " . $ref->get_param ('NAME'),
                    $use_is_or_isnt,
                );
            }
        }
        #diag $tree . ' ' . $tree->get_param ('NAME');
        #diag $tree2 . ' ' . $tree2->get_param ('NAME');

        is (
            $analysis_args_array[0]->{self_only}->{tree_ref},
            $analysis_args_array[0]->{select_all}->{tree_ref},
            "$shuffle_method: Shuffled tree refs $notnot_text same across randomisation iter 1",
        );
        is (
            $analysis_args_array[1]->{self_only}->{tree_ref},
            $analysis_args_array[1]->{select_all}->{tree_ref},
            "$shuffle_method: Shuffled tree refs $notnot_text same across randomisation iter 2",
        );

        is_or_isnt (
            $analysis_args_array[0]->{self_only}->{tree_ref},
            $analysis_args_array[1]->{self_only}->{tree_ref},
            "$shuffle_method: Shuffled tree refs $not_text same for different randomisation iter",
            $use_is_or_isnt,
        );
    }

    return;
}


sub basedata_group_props_are_same {
    my %args = @_;
    my $bd1 = $args{object1};
    my $bd2 = $args{object2};
    my $negate_check = $args{negate};

    my $gp1 = $bd1->get_groups_ref;
    my $gp2 = $bd2->get_groups_ref;

    my %groups1 = $gp1->get_element_hash;
    my %groups2 = $gp2->get_element_hash;

    is (scalar keys %groups1, scalar keys %groups2, 'basedata objects have same number of groups');

    my $check_count;

    #  should also check we get the same number of defined values
    my $defined_count1 = my $defined_count2 = 0;
    my $sum1 = my $sum2 = 0;

    foreach my $gp_name (sort keys %groups1) {
        my $list1 = $gp1->get_list_ref (element => $gp_name, list => 'PROPERTIES');
        my $list2 = $gp2->get_list_ref (element => $gp_name, list => 'PROPERTIES');

        my @tmp;
        @tmp = grep {defined $_} values %$list1;
        $defined_count1 += @tmp;
        $sum1 += sum0 @tmp;
        @tmp = grep {defined $_} values %$list2;
        $defined_count2 += @tmp;
        $sum2 += sum0 @tmp;

        if (eq_deeply ($list1, $list2)) {
            $check_count ++;
        }
    }

    my $text = 'Group property sets ';
    $text .= $negate_check ? 'differ' : 'are the same';

    if ($negate_check) {
        isnt ($check_count, scalar keys %groups1, $text);
    }
    else {
        is ($check_count, scalar keys %groups1, $text);
    }

    #  useful so long as we guarantee randomised basedata will have the same groups as the orig
    is ($defined_count1, $defined_count2, 'Same number of properties with defined values');
    is ($sum1, $sum2, 'Sum of properties is the same');

    return;
}




#   Does the PRNG state vector work or throw a trapped exception
#  This is needed because Math::Random::MT::Auto uses state vectors with
#  differing bit sizes, depending on whether 32 or 64 bit ints are used by perl.
#  #  skip it for now
sub _test_prng_state_vector {
    use Config;

    #  will this work on non-windows systems? 
    my $bit_size = $Config{archname} =~ /x86/ ? 32 : 64;  #  will 128 bits ever be needed for this work?
    my $wrong_bit_size = $Config{archname} =~ /x86/ ? 64 : 32;
    my $bd = Biodiverse::BaseData->new(NAME => 'PRNG tester', CELL_SIZES => [1, 1]);

    my $data_section_name = "PRNG_STATE_${bit_size}BIT";
    my $state_vector = get_data_section ($data_section_name);
    $state_vector = eval $state_vector;
    diag "Problem with data section $data_section_name: $EVAL_ERROR" if $EVAL_ERROR;
    my ($err, $prng);

    eval {
        $prng = $bd->initialise_rand (state => $state_vector);
    };
    $err = $@ ? 0 : 1;
    ok ($err, "Initialise PRNG with $bit_size bit vector and did not received an error");
    
    my $other_data_section_name = "PRNG_STATE_${wrong_bit_size}BIT";
    my $wrong_state_vector = get_data_section ($other_data_section_name);
    $wrong_state_vector = eval $wrong_state_vector;

    eval {
        $prng = $bd->initialise_rand (state => $wrong_state_vector);
    };
    my $e = $EVAL_ERROR;
    $err = Biodiverse::PRNG::InvalidStateVector->caught ? 1 : 0;
    #diag $e;
    ok ($err, "Initialise PRNG with $wrong_bit_size bit vector and caught the error as expected");

}

######################################

sub test_metadata {
    my $bd = Biodiverse::BaseData->new(CELL_SIZES => [1,1]);
    my $object = eval {Biodiverse::Randomise->new(BASEDATA_REF => $bd)};

    my $pfx = 'get_metadata_rand_';  #  but avoid export subs
    my $x = $object->get_subs_with_prefix (prefix => $pfx);
    
    my %meta_keys;

    my (%descr, %parameters);
    foreach my $meta_sub (keys %$x) {
        my $calc = $meta_sub;
        $calc =~ s/^get_metadata_//;

        my $metadata = $object->get_metadata (sub => $calc);

        $descr{$metadata->get_description}{$meta_sub}++;
        
        @meta_keys{keys %$metadata} = (1) x scalar keys %$metadata;
    }

    subtest 'No duplicate descriptions' => sub {
        check_duplicates (\%descr);
    };
}

sub check_duplicates {
    my $hashref = shift;
    foreach my $key (sort keys %$hashref) {
        my $count = scalar keys %{$hashref->{$key}};
        my $res = is ($count, 1, "$key is unique");
        if (!$res) {
            diag "Source calcs for $key are: " . join ' ', sort keys %{$hashref->{$key}};
        }
    }
    foreach my $null_key (qw /no_name no_description/) {
        my $res = ok (!exists $hashref->{$null_key}, "hash does not contain $null_key");
        if (exists $hashref->{$null_key}) {
            diag "Source calcs for $null_key are: " . join ' ', sort keys %{$hashref->{$null_key}};
        }
    }    
    
}



1;

__DATA__

@@ PRNG_STATE_64BIT
[
    '9223372036854775808',
    '4958489735850631625',
    '3619538152624353803',
    '17619357754638794221',
    '3408623266403198899',
    '3035490222614631823',
    '271946905883112210',
    '16298790926339482536',
    '630676991166359904',
    '14788619200023795801',
    '14177757664934255970',
    '13312478727237553858',
    '15476291270995261633',
    '5464336263206175489',
    '3143797466762002238',
    '5582226352878082351',
    '9355217794169585449',
    '14954185062673067088',
    '13522961949994510900',
    '14585430878973889682',
    '15924956595200372592',
    '12957488009475900218',
    '3752159734236408285',
    '8369919639039867954',
    '10795054750735369199',
    '8642694099373695299',
    '11272165358781081802',
    '8095615318554781864',
    '16164398991258853417',
    '10214091818020347210',
    '13153307184336129803',
    '13714936695152479161',
    '14484154332356276242',
    '2577462502853318753',
    '10892102228724345544',
    '15649984586148205750',
    '1752911930694051119',
    '14256522304070138671',
    '1152514005473346248',
    '8878671455732451000',
    '4207011014252715669',
    '13652367961887395862',
    '5611121218550033658',
    '8410402991626261946',
    '8233552525575717271',
    '6292412120693398487',
    '9947060654524186474',
    '16452782021149028831',
    '1853809132293241168',
    '15295782352943437746',
    '12182836555484474747',
    '3552537677350983349',
    '4772066490831483028',
    '12530387288245283208',
    '2890677614665248002',
    '2667778419916946144',
    '13498338834241598773',
    '3154952819132335662',
    '13136666044524597473',
    '892231094817090569',
    '6585118713301352248',
    '4930807954933263060',
    '393610034222314258',
    '9558892454914352311',
    '30391966624547120',
    '5737918409669945728',
    '4721863252461715725',
    '17822207361415571270',
    '9577190201430126402',
    '1668742975331543542',
    '15098079975897000051',
    '9241685836129752967',
    '307391855222642978',
    '3304579349183387324',
    '11536685329583252079',
    '5331993793107319461',
    '5113958467189033722',
    '18047865119982959952',
    '6112450261981011688',
    '10497757696563184785',
    '749432990441663821',
    '10185360822522782666',
    '13454434027282212678',
    '8125745829336032455',
    '14578461652467528442',
    '9025987670267739720',
    '17704075490770296829',
    '10343467620534394694',
    '9867154291727482127',
    '2573568889838705240',
    '496072485004533342',
    '8499502629657380215',
    '1639931171450583369',
    '13149339736314161754',
    '4509242601634876170',
    '17086167746054763781',
    '1466208730962794210',
    '12558159049585594774',
    '14228643326355589021',
    '16816774882560166758',
    '5362869153989396529',
    '6649026195586597463',
    '2832638462722326548',
    '15771554561130648152',
    '15182170535546589898',
    '1541713252841628024',
    '9744675815954163941',
    '8180333156316991695',
    '2624783631851392728',
    '6642975270114609940',
    '4972071798944670000',
    '15841513508277459488',
    '588709670153485747',
    '7085330046324581946',
    '16603019887526878011',
    '4801164143465887004',
    '3997253492253168259',
    '17211327089365224247',
    '11793831301662350681',
    '8135626700252115563',
    '18173415094141338016',
    '5512542829692575457',
    '709091886933108421',
    '7928604951070279249',
    '15240575422913751071',
    '18306141964501345053',
    '16334960027211470821',
    '3998691902608686113',
    '13299894194976580456',
    '6706267612186690863',
    '15163430571254651907',
    '16212811501888570899',
    '4278032876639688811',
    '11967866805397329675',
    '8264417510725672387',
    '14651307437899294260',
    '5647624225666950973',
    '3957567384005933380',
    '9366323499722880371',
    '3128213604362951206',
    '3741646501934840613',
    '8714663898836549487',
    '14093434233595461889',
    '4367208835592170128',
    '11635918534111679335',
    '5521363475906617593',
    '3603525324242875832',
    '6215692381355809233',
    '14905568142005052977',
    '11923988872476621110',
    '3839765323127405824',
    '1726494672043031059',
    '1826046517924485331',
    '949980670827882141',
    '16243826921596841486',
    '1854042729235477350',
    '13530891740661473592',
    '9644281674066925572',
    '14247280631769143765',
    '5626502556766574951',
    '1197448132108257968',
    '15553409925595149925',
    '845565928621523794',
    '15653846230542429524',
    '13430817514199604511',
    '18355820233222203385',
    '13326758935638574278',
    '3322902917203750159',
    '11058297162745705933',
    '13685287326600736054',
    '4975206220742183364',
    '9272608019685092152',
    '4418791405556974337',
    '18308885101215662544',
    '15033949912219345853',
    '15828581325838662108',
    '4360364515778590425',
    '11702117311272622689',
    '8542874060716897202',
    '5619994636706585426',
    '13524161066520536811',
    '1746470960343741172',
    '3531265041003896570',
    '3995081388934980117',
    '6577196340494974021',
    '15275042596192483519',
    '6827660007664537371',
    '16359148473932034636',
    '4693269007065785862',
    '2055942548310402289',
    '3306973392177435307',
    '8885676876713467323',
    '123232717042594303',
    '4502342331337891748',
    '796002772112309291',
    '16989567407422764658',
    '14140202457285991249',
    '511126236207995051',
    '2231381755807086633',
    '14759202368433450769',
    '14268630037802571672',
    '16127995917298181352',
    '4257094582362774157',
    '13718937944161154150',
    '15574632344931054546',
    '17568296358285794238',
    '15814740056907455357',
    '2754381637012837762',
    '10971758354728748345',
    '17978722194350293215',
    '8789861672429286038',
    '2439542666188438170',
    '8301466673235813057',
    '3643512247605284412',
    '4436083969860293654',
    '18371712049370376120',
    '10637949931237583118',
    '17893539985208907837',
    '1066237739928500862',
    '14156708587432031543',
    '13615225987990216763',
    '7283247406530837402',
    '2111187868559797529',
    '11549095055615633',
    '2752872151769161189',
    '1378768029093311875',
    '14312716280922030608',
    '3472762984889093538',
    '15243871077328415303',
    '5552728439719826078',
    '9171008763536371397',
    '13258436119504186596',
    '13935139201816073370',
    '11708466127754837424',
    '3530501252464415944',
    '16405297613033794944',
    '9461323638638219051',
    '17913179250313811241',
    '5522351720644862414',
    '17939147238430738425',
    '7425254055749549770',
    '2996817804278770640',
    '3639720715771962284',
    '7342833789716583460',
    '3939692440815867923',
    '5793177902942873760',
    '7889251406034625535',
    '12027682794968924782',
    '7473162259413693557',
    '5902766307954538646',
    '1054514130676152720',
    '3526318720263317215',
    '4744409711556217067',
    '15586453980780606424',
    '14099819196631825335',
    '12588916030955628229',
    '16999573623451727010',
    '14363959110907741881',
    '13912995043889359794',
    '1660320477576151633',
    '10498772740867116048',
    '8587782089193412281',
    '6330055719003701726',
    '6106755009128474114',
    '15199192819216086862',
    '9428961975819435544',
    '11753192895609522086',
    '2254708887958278538',
    '8908622203162264336',
    '16470497220365505546',
    '6859474912248889588',
    '3729284384146531861',
    '17795814995734737903',
    '1739807018854509111',
    '141841629084657134',
    '15799707411113924853',
    '16470050430558885352',
    '18313334590623953187',
    '10381849194204436741',
    '1662635747659353856',
    '233531108326825474',
    '17321807425262294057',
    '11199633038658781350',
    '3705324290200321279',
    '8008402009107947927',
    '3382650032952973365',
    '9458323089377501764',
    '443933754741086859',
    '3731560780752305844',
    '10750393312508752809',
    '4847718944411104861',
    '7558201115683960412',
    '12961046778350711287',
    '5173640531882988475',
    '16982602287904553549',
    '3767654102597339454',
    '3292197666531931384',
    '6146214751488526354',
    '12326423421046367389',
    '83606547911329582',
    '5298648767564049355',
    '4929960039345324290',
    '725972229785092910',
    '3461770916530250884',
    '6519175775616021953',
    '13441797420822857380',
    '12609256409874483017',
    '14835947449239278156',
    '2988665059323180544',
    '16688745117641562169',
    '6864698702038266417',
    '18305469821403178820',
    1,
    0,
    '0',
    '-1',
    '0',
    '0',
    '0',
    -1,
    '0',
    '-1',
    '0',
    '0'
]

@@ PRNG_STATE_32BIT
[
    '2147483648',
    1677077075,
    1758109997,
    2012160848,
    541988062,
    1491988274,
    861106406,
    1566399065,
    8399150,
    '3653577899',
    643613788,
    '3190612274',
    1968445455,
    '3597414494',
    27366164,
    '3807984804',
    '2961650050',
    1095935393,
    2057921854,
    '3844081538',
    '3808215560',
    '3665327674',
    '3154689857',
    '4074052117',
    264797845,
    '3444667108',
    '2457594059',
    '2543739205',
    '4047572148',
    '3913095671',
    359469328,
    '4044373318',
    '4260334795',
    '3870111269',
    1380853497,
    '3409740945',
    834981438,
    '3851028554',
    '3708093871',
    '2419194234',
    1838010339,
    1218711391,
    2143585409,
    810295178,
    775538859,
    619166428,
    1721351432,
    '2853170012',
    '2823038809',
    1200346205,
    '2571814779',
    '2695584565',
    1943042846,
    125318786,
    474996257,
    '4273536737',
    '3297986018',
    '2847578188',
    '4016719928',
    310222596,
    1772343889,
    651342332,
    659919392,
    879798211,
    '4242066878',
    '3336056086',
    974561553,
    '2360829145',
    '3332093856',
    1690614989,
    1574718338,
    '3898599013',
    310740436,
    '2837563447',
    '4253968177',
    123043939,
    '4265883017',
    1429754345,
    1077543482,
    2022472232,
    '3914348998',
    '2456980012',
    1849573422,
    318324867,
    '2497574290',
    '2453249265',
    1956598125,
    '3354332622',
    '2369709084',
    196343112,
    '3817402382',
    '2454585865',
    711011270,
    1278169532,
    '3743942819',
    315959216,
    13745920,
    '3869711192',
    94072664,
    '2543114506',
    1713177570,
    1302295864,
    1147649475,
    '3160148454',
    '2532903929',
    '2179620859',
    1791008302,
    '2522372456',
    '3234395645',
    517360176,
    357143889,
    '2551663970',
    173404412,
    '4176235229',
    720910917,
    1033360796,
    '3977741845',
    238565813,
    '4269084290',
    1207925072,
    '2306853653',
    '2787468199',
    1362176947,
    '3846242617',
    1119378922,
    '2760292638',
    '3482959318',
    453733715,
    '3771139002',
    383625843,
    '3190936523',
    911865079,
    '3305494017',
    221775475,
    41190502,
    1701676081,
    94894038,
    1428337978,
    990520943,
    '2883026377',
    1688032536,
    '2378241773',
    1352550018,
    '3552786783',
    181781467,
    2023661600,
    '2809034476',
    704505374,
    '2966742551',
    156498589,
    2064531489,
    888468256,
    1357347558,
    554690418,
    1636078621,
    '3369268327',
    '3664945445',
    19648325,
    82799825,
    1771068982,
    511091015,
    '3571123319',
    '3438126311',
    '3661938871',
    1706789258,
    '2956788664',
    '4245670276',
    '3237385365',
    370667213,
    '3709283992',
    '2370742082',
    1950669983,
    '2655238100',
    400553867,
    186980899,
    1728139078,
    '2736486759',
    872117973,
    '3405136580',
    '3332402259',
    1513563402,
    '3619941441',
    '3114457879',
    '4280622303',
    '3520408390',
    '2218505367',
    1428631288,
    176881348,
    '3861027368',
    '3040966652',
    1207471436,
    2050843637,
    1235960653,
    1635977073,
    '3372261755',
    1563409159,
    1057153661,
    '3959746947',
    407100025,
    2112376632,
    1852250762,
    '3033945476',
    1930484162,
    '2911947295',
    291129345,
    215710207,
    '3229187417',
    '3608885029',
    '4024745543',
    '3481631602',
    1240125151,
    '2542300655',
    '2303768742',
    '3970585528',
    '3235791980',
    2124107529,
    2127809371,
    '3980895990',
    658478289,
    1985483584,
    2125518148,
    1755314322,
    '3608173197',
    '3307764668',
    1001125987,
    1663888474,
    '3379980706',
    510066840,
    '2261081708',
    845846249,
    '2372234061',
    '3813873977',
    '4162013056',
    '3583925722',
    '3681369617',
    '2473245255',
    '2914355745',
    '3245714238',
    1461543414,
    '2222432154',
    299657994,
    '2760697132',
    2144521010,
    '3576174561',
    624078225,
    1179789139,
    751450160,
    '2430910709',
    996660321,
    1726350207,
    681167225,
    '3404354175',
    '3541298993',
    1527151717,
    215196658,
    2058309805,
    367288306,
    482191886,
    '2719738481',
    '3687879469',
    2011658176,
    '3673421311',
    256687523,
    1321402152,
    500434563,
    '3084733401',
    '3777007962',
    1832729659,
    170561099,
    1291094876,
    '3285509430',
    '2330805488',
    '4190545328',
    '3572323711',
    '2990731708',
    '2783759473',
    '3228789738',
    '3337887961',
    '3209478371',
    453056885,
    '3656621525',
    1674735023,
    '3852531767',
    '2303553300',
    461261806,
    '3810216323',
    '3891950745',
    '3944349790',
    '2981723146',
    558261335,
    '2193851585',
    1728978049,
    1439780019,
    '2692247461',
    153662856,
    1682927135,
    768019756,
    1071298666,
    390094931,
    1324671548,
    679944036,
    '2951799623',
    307080840,
    1989915016,
    '3355360669',
    '2190742070',
    '4001648064',
    '2946737490',
    1175363852,
    '4120422185',
    '3551353241',
    703421331,
    1982847225,
    1049041361,
    '3113602733',
    90905874,
    '2384387870',
    '3571219233',
    '2568318801',
    1809317448,
    1604586371,
    1289359819,
    '3418104240',
    '2327541803',
    '4211251087',
    958119447,
    '2420788922',
    210884563,
    551488406,
    '2981006692',
    1670189473,
    698564066,
    1275767274,
    '3447279485',
    '2491362403',
    1892880956,
    '2553644149',
    1467286560,
    1789712716,
    567231049,
    209672888,
    691269149,
    857522438,
    1204934600,
    '4193584119',
    2112095742,
    '2233081135',
    '3703960613',
    '3019546719',
    '3130901579',
    283861596,
    '2522212414',
    361344581,
    '3767118053',
    90269672,
    '3458230827',
    '3315884714',
    '3055923814',
    '2939326823',
    1191182474,
    1598592619,
    '2558724810',
    1379433533,
    340036856,
    675121704,
    '2363109837',
    '2599147383',
    1757057248,
    189932069,
    1772256814,
    81139113,
    '3393178502',
    '2628697401',
    '2243846625',
    1059753573,
    1141264240,
    '3786795514',
    '2537499270',
    '4131123762',
    1889202801,
    1928010468,
    '2678221564',
    '4285514789',
    '3388106141',
    1181529161,
    '3477052321',
    '3167813135',
    '2731612244',
    '3502032657',
    '3024269639',
    '4293497130',
    178873438,
    '2306558312',
    '2681635899',
    1409631267,
    '3730008093',
    1539667032,
    469103802,
    '3714414244',
    1256496507,
    49726331,
    1196496278,
    '2254673486',
    '2616194588',
    '2913676193',
    '3771315025',
    831600480,
    856036283,
    931089289,
    1067488796,
    621127148,
    '4186773930',
    79200085,
    1224577464,
    1448613087,
    265939919,
    '2734764249',
    1322332244,
    '2258199796',
    '4043886394',
    '3250361079',
    652506151,
    '4050119269',
    1121013754,
    1487690368,
    174910517,
    2080699189,
    500182609,
    1907929587,
    '2336982549',
    1848029343,
    1720305830,
    '3352718148',
    2017870985,
    '4119152966',
    98874327,
    '2275154281',
    '2728836238',
    '2739221183',
    '4208634290',
    839469737,
    '2204035092',
    861779247,
    '3020117410',
    '3811586227',
    1083752271,
    '2632500877',
    2064464734,
    1223489974,
    '4231271968',
    '2161457305',
    '4033289528',
    '2725981375',
    '3880033764',
    1584244498,
    77169859,
    '3710211721',
    1753652476,
    '2371711264',
    552327740,
    620234649,
    '3782113180',
    7094471,
    1178275216,
    314159994,
    1855575460,
    '3418731089',
    1993903680,
    1375702040,
    569055171,
    312801413,
    1328683220,
    1859267194,
    '4155738754',
    '3725584127',
    '2791098181',
    '2202738539',
    '2430518177',
    '3002223855',
    '3056626238',
    1296446562,
    '3143183546',
    403521171,
    5574345,
    1272499576,
    '3612999707',
    862605819,
    '3902668435',
    1976242083,
    '3421909576',
    '4072205345',
    1101089483,
    '3634645108',
    '3593435097',
    '4214862138',
    '2945197444',
    1905071366,
    '2886243662',
    '2666574082',
    1328849297,
    1591296963,
    '2404594922',
    184651244,
    1292408003,
    '3387572634',
    '4033574830',
    '2459339412',
    1664014900,
    1374308289,
    1468475088,
    1573852822,
    922667999,
    1280923547,
    '3021619528',
    1488029181,
    '2425321602',
    '3640227055',
    '4178174582',
    1984264796,
    '4051218800',
    '3026504657',
    1168036688,
    911499036,
    '3169769690',
    135707006,
    1732743467,
    '3783981500',
    '3385068710',
    626307059,
    796196419,
    1782343302,
    2144987656,
    '3879301279',
    '3771447229',
    '2737189808',
    '3098115217',
    998624938,
    1134611930,
    2116635688,
    '2976675899',
    '2796507349',
    1703329175,
    '3476461418',
    '3986021453',
    '4253525679',
    '3816617809',
    837546434,
    1024083870,
    873615206,
    1878513390,
    967949642,
    '3331131437',
    1143453313,
    1882383991,
    '2812888243',
    620101474,
    '3945532232',
    '2761244178',
    811678387,
    '2628806911',
    2126948101,
    '2937581680',
    '3123037283',
    1020209609,
    790939510,
    1811696483,
    1567435215,
    929198790,
    '2526351098',
    '3433986147',
    86188443,
    '3111795319',
    236939197,
    '4220147808',
    1491830407,
    1265865222,
    '4172245229',
    1567930920,
    '3748438821',
    '2253672863',
    '2752088551',
    1152037285,
    156239109,
    2063958262,
    221698901,
    '2757702229',
    '3396008522',
    '3430512944',
    298160590,
    '2597277585',
    332914467,
    '2206710419',
    '3232972895',
    '2194860009',
    '2639109027',
    1479300577,
    1474228869,
    325255300,
    2030350608,
    '2898382680',
    955802572,
    '3191949399',
    '2816630605',
    '2392252636',
    1108976688,
    '2896064359',
    '2281008697',
    '3761712436',
    1457704355,
    1371617016,
    '3806379767',
    1868430205,
    '4245349427',
    1300725116,
    1141939922,
    '3783835862',
    2086057536,
    213198119,
    611329641,
    '2346418543',
    551304162,
    362542212,
    48666851,
    344974075,
    1,
    0,
    0,
    -1,
    0,
    0,
    0,
    -1,
    0,
    -1,
    0,
    0
]
