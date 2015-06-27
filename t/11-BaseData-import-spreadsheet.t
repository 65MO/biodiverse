#!/usr/bin/perl -w

#  Tests for basedata import
#  Need to add tests for the number of elements returned,
#  amongst the myriad of other things that a basedata object does.

use 5.010;
use strict;
use warnings;
use English qw { -no_match_vars };
use Data::Dumper;
use Path::Class;

use rlib;

use Data::Section::Simple qw(
    get_data_section
);

local $| = 1;

#use Test::More tests => 5;
use Test::Most;

use Biodiverse::BaseData;
use Biodiverse::ElementProperties;
use Biodiverse::TestHelpers qw /:basedata/;

#  this needs work to loop around more of the expected variations
my @setup = (
    {
        args => {
            CELL_SIZES => [1, 1],
            is_lat     => [1, 0],
            is_lon     => [0, 1],
        },
        expected => 'fail',
        message  => 'lat/lon out of bounds',
    },
    {
        args => {
            CELL_SIZES => [1, 1],
            is_lat     => [1, 0],
        },
        expected => 'fail',
        message  => 'lat out of bounds',
    },
    {
        args => {
            CELL_SIZES => [1, 1],
            is_lon     => [1, 0],
        },
        expected => 'fail',
        message  => 'lon out of bounds',
    },
    {
        args => {
            CELL_SIZES => [100000, 100000],
        },
        expected => 'pass',
    },
    {
        args => {
            CELL_SIZES => [100, 100],
        },
        expected => 'pass',
    },
);

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

    foreach my $sub (@test_subs) {
        no strict 'refs';
        $sub->();
    }
    
    done_testing;
    return 0;
}



sub test_import_spreadsheet {
    my %bd_args = (
        NAME => 'test import spreadsheet',
        CELL_SIZES => [10000,100000],
    );

    my $bd1 = Biodiverse::BaseData->new (%bd_args);
    my $e;

    #  an empty input_files array
    eval {
        $bd1->import_data_spreadsheet(
            input_files   => [undef],
            group_field_names => [qw /x y/],
            label_field_names => [qw /genus species/],
        );
    };
    $e = $EVAL_ERROR;
    note $e if $e;
    ok ($e, 'import spreadsheet failed when no or undef file passed');
    
    #  a non-existent file
    eval {
        $bd1->import_data_spreadsheet(
            input_files   => ['blongordia.xlsx'],
            group_field_names => [qw /x y/],
            label_field_names => [qw /genus species/],
        );
    };
    $e = $EVAL_ERROR;
    note $e if $e;
    ok ($e, 'import spreadsheet failed when no or undef file passed');
    
    foreach my $extension (qw /xlsx ods xls/) {
        my $tmp_file = Path::Class::File->new (
            Path::Class::File->new($0)->dir,
            "test_spreadsheet_import.$extension",
        );
        my $fname = $tmp_file->stringify;
        say "testing filename $fname";
        _test_import_spreadsheet($fname, "filetype $extension");
    }

    _test_import_spreadsheet_matrix_form ();
}

sub _test_import_spreadsheet {
    my ($fname, $feedback) = @_;


    my %bd_args = (
        NAME => 'test import spreadsheet' . $fname,
        CELL_SIZES => [100000,100000],
    );

    my $bd1 = Biodiverse::BaseData->new (%bd_args);
    my $e;

    eval {
        $bd1->import_data_spreadsheet(
            input_files   => [$fname],
            group_field_names => [qw /x y/],
            label_field_names => [qw /genus species/],
        );
    };
    $e = $EVAL_ERROR;
    note $e if $e;
    ok (!$e, "import spreadsheet with no exceptions raised, $feedback");
    
    my $lb = $bd1->get_labels_ref;
    my $gp = $bd1->get_groups_ref;
    
    my $bd2 = Biodiverse::BaseData->new (%bd_args);
    eval {
        $bd2->import_data_spreadsheet(
            input_files   => [$fname],
            sheet_ids     => [1],
            group_field_names => [qw /x y/],
            label_field_names => [qw /genus species/],
        );
    };
    $e = $EVAL_ERROR;
    note $e if $e;
    ok (!$e, "no errors for import spreadsheet with sheet id specified, $feedback");
    
    is_deeply ($bd2, $bd1, "same contents when sheet_id specified as default, $feedback");
    
    is ($bd1->get_group_count, 19, "Group count is correct, $feedback");

    eval {
        $bd2->import_data_spreadsheet(
            input_files   => [$fname, $fname],
            sheet_ids     => [1, 2],
            group_field_names => [qw /x y/],
            label_field_names => [qw /genus species/],
        );
    };
    $e = $EVAL_ERROR;
    note $e if $e;
    ok (!$e, "no errors for import spreadsheet with two sheet ids specified, $feedback");
    
    #  label counts in $bd2 should be double that of $bd1
    #  $bd2 should also have Genus2:sp1 etc
    subtest "Label counts are doubled, $feedback" => sub {
        foreach my $lb ($bd1->get_labels) {
            is (
                $bd2->get_label_sample_count (element => $lb),
                $bd1->get_label_sample_count (element => $lb) * 2,
                "Label sample count doubled: $lb",
            );
        }
    };
    subtest "Additional labels imported, $feedback" => sub {
        foreach my $lb ($bd1->get_labels) {
            #  second label set should be Genus2:Sp1 etc
            my $alt_label = $lb;
            $alt_label =~ s/Genus:/Genus2:/;
            ok ($bd2->exists_label (label => $alt_label), "bd2 contains $alt_label");
        }
    };
    
    my $bd3 = Biodiverse::BaseData->new (%bd_args);
    eval {
        $bd3->import_data_spreadsheet(
            input_files   => [$fname],
            sheet_ids     => ['Example_site_data'],
            group_field_names => [qw /x y/],
            label_field_names => [qw /genus species/],
        );
    };
    $e = $EVAL_ERROR;
    note $e if $e;
    ok (!$e, "no errors for import spreadsheet with sheet id specified as name, $feedback");
    
    is_deeply ($bd3, $bd1, "data matches for sheet id as name and number, $feedback");
}

sub _test_import_spreadsheet_matrix_form {
    #my ($fname, $feedback) = @_;
    my $feedback = 'matrix form';
    
    my $fname_mx   = 'test_spreadsheet_import_matrix_form.xlsx';
    my $fname_norm = 'test_spreadsheet_import.xlsx';

    $fname_mx = Path::Class::File->new (
        Path::Class::File->new($0)->dir,
        $fname_mx,
    );
    $fname_norm = Path::Class::File->new (
        Path::Class::File->new($0)->dir,
        $fname_norm,
    );
    
    my %bd_args = (
        NAME => 'test import spreadsheet',
        CELL_SIZES => [100000,100000],
    );

    my $bd1 = Biodiverse::BaseData->new (%bd_args);
    my $e;

    eval {
        $bd1->import_data_spreadsheet(
            input_files   => [$fname_mx],
            group_field_names => [qw /x y/],
            label_start_col   => [3],
            data_in_matrix_form => 1,
        );
    };
    $e = $EVAL_ERROR;
    note $e if $e;
    ok (!$e, "import spreadsheet with no exceptions raised, $feedback");
    
    my $bd2 = Biodiverse::BaseData->new (%bd_args);
    eval {
        $bd2->import_data_spreadsheet(
            input_files   => [$fname_norm],
            sheet_ids     => [1],
            group_field_names => [qw /x y/],
            label_field_names => [qw /genus species/],
        );
    };
    $e = $EVAL_ERROR;
    note $e if $e;
    
    is ($bd1->get_group_count, $bd2->get_group_count, 'group counts match');
    is ($bd1->get_label_count, $bd2->get_label_count, 'label counts match');

    is_deeply ($bd1, $bd2, "same contents matrix form and non-matrix form, $feedback");
}

1;
