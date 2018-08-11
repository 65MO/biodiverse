#!/usr/bin/perl -w
use 5.010;
use strict;
use warnings;

use strict;
use warnings;
use English qw { -no_match_vars };
use Carp;
use Scalar::Util qw /blessed/;

use Test::Lib;
use rlib;

use Data::Section::Simple qw(
    get_data_section
);

local $| = 1;

#use Test::More tests => 5;
use Test::More;

use Biodiverse::BaseData;
use Biodiverse::TestHelpers qw /:basedata/;

use Devel::Symdump;
my $obj = Devel::Symdump->rnew(__PACKAGE__); 
my @test_subs = grep {$_ =~ 'main::test_'} $obj->functions();


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

    foreach my $sub (sort @test_subs) {
        no strict 'refs';
        $sub->();
    }

    done_testing;
    return 0;
}



#  check the metadata
#  we just want no warnings raised here?
sub test_metadata {
    my $bd = Biodiverse::BaseData->new (CELL_SIZES => [1, 1]);
    $bd->add_element (group => '0.5:0.5', label => 'a');
    
    my $metadata = $bd->get_groups_ref->get_metadata (sub => 'export');
    #  not a very good test...
    ok (blessed ($metadata), 'basestruct export metadata is blessed');
}


# delimited text
sub test_delimited_text {
    my $e;  #  for eval errors;

    #  need to test array lists - need numeric labels data set for those
    my $num_bd = get_basedata_object (
        CELL_SIZES => [2, 2],
        x_spacing => 1,
        y_spacing => 1,
        x_max     => 10,
        y_max     => 10,
        x_min     => 0,
        y_min     => 1,
        numeric_labels => 1,
    );
    my $num_sp = $num_bd->add_spatial_output (name => 'Numeric blah blah');
    $num_sp->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations       => ['calc_numeric_label_data'],
    );
    
    my $gp = $num_bd->get_groups_ref;

    #  now make a basestruct with a symmetric list to export
    my $sp = $num_bd->add_spatial_output (name => 'Blahblah');
    $sp->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations       => ['calc_richness'],
    );
    
    
    my @arg_combinations;
    foreach my $symmetric (0, 1) {
        foreach my $one_value_per_line (0, 1) {
            foreach my $no_element_array (0, 1) {
                foreach my $quote_element_name (0, 1) {
                    push @arg_combinations,
                        {
                            symmetric           => $symmetric,
                            one_value_per_line  => $one_value_per_line,
                            no_element_array    => $no_element_array,
                            quote_element_names => $quote_element_name,
                        };
                }
            }
        }
    }
    
    foreach my $args_hash (@arg_combinations) {
        #  asymmetric list
        run_basestruct_export_to_table (
            basestruct => $gp,
            list       => 'SUBELEMENTS',
            %$args_hash,
        );
        #  symmetric list
        run_basestruct_export_to_table (
            basestruct => $sp,
            list       => 'SPATIAL_RESULTS',
            %$args_hash,
        );
        run_basestruct_export_to_table (
            basestruct => $num_sp,
            list       => 'NUM_DATA_ARRAY',
            %$args_hash,
        );
    }
}



sub test_quoting {
    my $bd = get_basedata_object (
        CELL_SIZES => [2, 2],
        x_spacing => 1,
        y_spacing => 1,
        x_max     => 10,
        y_max     => 10,
        x_min     => 0,
        y_min     => 1,
    );
    my $gps = $bd->get_groups_ref;

    #  now make a basestruct with a symmetric list to export
    my $sp = $bd->add_spatial_output (name => 'Blahblah');
    $sp->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations       => ['calc_richness'],
    );

    my $table;

    $table = $gps->to_table (
        list   => 'SUBELEMENTS',
        quote_element_names_and_headers => 1,
    );
    table_headers_and_elements_are_quoted($table, 'SUBELEMENTS');

    $table = $gps->to_table (
        list   => 'SUBELEMENTS',
        symmetric => 0,  #  export defaults to symmetric, so override to test
        quote_element_names_and_headers => 1,
    );
    table_headers_and_elements_are_quoted($table, 'SUBELEMENTS');

    $table = $sp->to_table (
        list   => 'SPATIAL_RESULTS',
        quote_element_names_and_headers => 1,
    );
    table_headers_and_elements_are_quoted($table, 'SPATIAL_RESULTS');

}


sub test_multiple_lists {
    my $bd = get_basedata_object (
        CELL_SIZES => [2, 2],
        x_spacing => 1,
        y_spacing => 1,
        x_max     => 6,
        y_max     => 6,
        x_min     => 0,
        y_min     => 1,
    );
    my $gps = $bd->get_groups_ref;

    #  now make a basestruct with a symmetric list to export
    my $sp = $bd->add_spatial_output (name => 'Blahblah');
    $sp->run_analysis (
        spatial_conditions => ['sp_square_cell(size => 3)'],
        calculations       => [qw /calc_richness calc_element_lists_used/],
    );

    my $table = $sp->to_table (
        list_names => [qw /EL_LIST_SET1 SPATIAL_RESULTS/],
    );
    my @expected
      = map {[split ',', $_]}
        split "\n",
        get_data_section ('asym_table_two_lists');
    is_deeply($table, \@expected, 'asymmetric table matches for two lists');

}

sub table_headers_and_elements_are_quoted {
    my ($table, $extra_feedback) = @_;
    $extra_feedback //= '';

    my $re_is_quoted = qr /^'[^']+'$/;
    
    subtest 'Headers and element names are quoted' => sub {
        my $header = $table->[0];
        foreach my $field_name (@$header) {  #  first three are not quoted - should we?
            ok ($field_name =~ $re_is_quoted, "$field_name is quoted, $extra_feedback");
        }
        foreach my $line (@$table[1..$#$table]) {
            ok ($line->[0] =~ $re_is_quoted, "element name $line->[0] is quoted, $extra_feedback");
        }
    };

    return;
}


sub run_basestruct_export_to_table {
    my %args = @_;

    my $gp = $args{basestruct};

    my $e;

    my $symmetric_feedback = $args{symmetric} ? 'symmetric' : 'non-symmetric';
    my %feedback = %args;
    delete @feedback{qw /basestruct/};
    my $feedback_text;
    foreach my $key (sort keys %feedback) {
        my $val = $feedback{$key};
        $feedback_text .= "$key => $val, ";
    }
    $feedback_text =~ s/, $//;
    
    my $filename1 = get_temp_file_path('biodiverse_export_test_XXXXX.csv');

    eval {
        $gp->export_table_delimited_text (
            %args,
            file => $filename1,
        );
    };
    $e = $EVAL_ERROR;
    note $e if $e;

    ok (!$e, "Exported file without raising exception, using file handle, $feedback_text");
    
    my $filename2 = get_temp_file_path('biodiverse_export_test_XXXXX.csv');

    eval {
        $gp->export_table_delimited_text (
            %args,
            file   => $filename2,
            _no_fh => 1,
        );
    };
    $e = $EVAL_ERROR;
    note $e if $e;

    ok (!$e, "Exported to file without raising exception, not using file handle, $feedback_text");

    #  Now compare the two files.  They should be identical.  
    {
        local $/ = undef;  #  slurp mode
        open my $fh1, '<', $filename1 or croak "Could not open $filename1";
        open my $fh2, '<', $filename2 or croak "Could not open $filename2";
        
        my $file1 = <$fh1>;
        my $file2 = <$fh2>;
        
        is ($file1, $file2, 'Exported files match');
        
        if (0) {
            print STDERR "\n\n$feedback_text\n";
            foreach my $string ($file1, $file2) {
                my @array = split "\n", $file2, 4;
                pop @array;
                print STDERR "\n\n---\n" . join ("\n", @array) . "\n\n---\n";
            }
        }
    }
}

done_testing();

1;

__DATA__

@@ asym_to_sym_table_two_lists
ELEMENT,Axis_0,Axis_1,Value


@@ asym_table_two_lists
ELEMENT,Axis_0,Axis_1,Value
1:1,1,1,1:1,1,1:3,1,3:1,1,3:3,1,RICHNESS_ALL,12,RICHNESS_SET1,12
1:3,1,3,1:1,1,1:3,1,1:5,1,3:1,1,3:3,1,3:5,1,RICHNESS_ALL,20,RICHNESS_SET1,20
1:5,1,5,1:3,1,1:5,1,1:7,1,3:3,1,3:5,1,3:7,1,RICHNESS_ALL,20,RICHNESS_SET1,20
1:7,1,7,1:5,1,1:7,1,3:5,1,3:7,1,RICHNESS_ALL,12,RICHNESS_SET1,12
3:1,3,1,1:1,1,1:3,1,3:1,1,3:3,1,5:1,1,5:3,1,RICHNESS_ALL,18,RICHNESS_SET1,18
3:3,3,3,1:1,1,1:3,1,1:5,1,3:1,1,3:3,1,3:5,1,5:1,1,5:3,1,5:5,1,RICHNESS_ALL,30,RICHNESS_SET1,30
3:5,3,5,1:3,1,1:5,1,1:7,1,3:3,1,3:5,1,3:7,1,5:3,1,5:5,1,5:7,1,RICHNESS_ALL,30,RICHNESS_SET1,30
3:7,3,7,1:5,1,1:7,1,3:5,1,3:7,1,5:5,1,5:7,1,RICHNESS_ALL,18,RICHNESS_SET1,18
5:1,5,1,3:1,1,3:3,1,5:1,1,5:3,1,7:1,1,7:3,1,RICHNESS_ALL,15,RICHNESS_SET1,15
5:3,5,3,3:1,1,3:3,1,3:5,1,5:1,1,5:3,1,5:5,1,7:1,1,7:3,1,7:5,1,RICHNESS_ALL,25,RICHNESS_SET1,25
5:5,5,5,3:3,1,3:5,1,3:7,1,5:3,1,5:5,1,5:7,1,7:3,1,7:5,1,7:7,1,RICHNESS_ALL,25,RICHNESS_SET1,25
5:7,5,7,3:5,1,3:7,1,5:5,1,5:7,1,7:5,1,7:7,1,RICHNESS_ALL,15,RICHNESS_SET1,15
7:1,7,1,5:1,1,5:3,1,7:1,1,7:3,1,RICHNESS_ALL,9,RICHNESS_SET1,9
7:3,7,3,5:1,1,5:3,1,5:5,1,7:1,1,7:3,1,7:5,1,RICHNESS_ALL,15,RICHNESS_SET1,15
7:5,7,5,5:3,1,5:5,1,5:7,1,7:3,1,7:5,1,7:7,1,RICHNESS_ALL,15,RICHNESS_SET1,15
7:7,7,7,5:5,1,5:7,1,7:5,1,7:7,1,RICHNESS_ALL,9,RICHNESS_SET1,9

