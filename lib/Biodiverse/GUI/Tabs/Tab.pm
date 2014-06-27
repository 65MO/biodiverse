package Biodiverse::GUI::Tabs::Tab;
use strict;
use warnings;

our $VERSION = '0.99_001';

use Gtk2;
use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::Project;
use Carp;


sub add_to_notebook {
    my $self = shift;
    my %args = @_;

    my $page  = $args{page};
    my $label = $args{label};
    my $label_widget = $args{label_widget};

    $self->{notebook}   = $self->{gui}->get_notebook();
    $self->{notebook}->append_page_menu($page, $label, $label_widget);
    $self->{page}       = $page;
    $self->{gui}->add_tab($self);
    $self->set_tab_reorderable($page);

    return;
}

sub get_page_index {
    my $self = shift;
    my $page = shift || $self->{page};
    my $index = $self->{notebook}->page_num($page);
    return $index >= 0 ? $index : undef;
}

sub set_page_index {
    my $self = shift;
    
    #  no-op now
    #$self->{page_index} = shift;
    
    return;
}

sub get_base_ref {
    my $self = shift;

    #  check all possibilities
    #  should really just have one
    foreach my $key (qw /base_ref basedata_ref selected_basedata_ref/) {
        if (exists $self->{$key}) {
            return $self->{$key};
        }
    }

    croak "Unable to access the base ref\n";
}

sub get_current_registration {
    my $self = shift;
    return $self->{current_registration};
}

sub update_current_registration {
    my $self = shift;
    my $object = shift;
    $self->{current_registration} = $object;
}

sub update_name {
    my $self = shift;
    my $new_name = shift;
    #$self->{current_registration} = $new_name;
    eval {$self->{label_widget}->set_text ($new_name)};
    eval {$self->{title_widget}->set_text ($new_name)};
    eval {$self->{tab_menu_label}->set_text ($new_name)};
    return;
}

sub remove {
    my $self = shift;

    if (exists $self->{current_registration}) {  #  deregister if necessary
        #$self->{project}->register_in_outputs_model($self->{current_registration}, undef);
        $self->register_in_outputs_model($self->{current_registration}, undef);
    }
    my $index = $self->get_page_index;
    if (defined $index && $index > -1) {
        $self->{notebook}->remove_page( $index );
    }

    return;
}

sub set_tab_reorderable {
    my $self = shift;
    my $page = shift || $self->{page};

    $self->{notebook}->set_tab_reorderable($page, 1);

    return;
}

sub on_close {
    my $self = shift;
    $self->{gui}->remove_tab($self);
    #print "[GUI] Closed tab - ", $self->get_page_index(), "\n";
    return;
}

# Make ourselves known to the Outputs tab to that it
# can switch to this tab if the user presses "Show"
sub register_in_outputs_model {
    my $self = shift;
    my $output_ref = shift;
    my $tabref = shift; # either $self, or undef to deregister
    my $model = $self->{project}->get_base_data_output_model();

    # Find iter
    my $iter;
    my $iter_base = $model->get_iter_first();

    while ($iter_base) {
        
        my $iter_output = $model->iter_children($iter_base);
        while ($iter_output) {
            if ($model->get($iter_output, MODEL_OBJECT) eq $output_ref) {
                $iter = $iter_output;
                last; #FIXME: do we have to look at other iter_bases, or does this iterate over entire level?
            }
            
            $iter_output = $model->iter_next($iter_output);
        }
        
        last if $iter; # break if found it
        $iter_base = $model->iter_next($iter_base);
    }

    if ($iter) {
        $model->set($iter, MODEL_TAB, $tabref);
        $self->{current_registration} = $output_ref;
    }
    
    return;
}

#  prepend some text to the grid hover text
sub get_grid_text_pfx {
    my $self = shift;

    my $bd = $self->get_base_ref;
    my @cellsizes = $bd->get_cell_sizes;
    my $col_count = scalar @cellsizes;
    my $pfx = $col_count > 2
        ? "<i>Note: Basedata has more than two axes so some cells will be overplotted and thus not visible</i>\n"
        : q{};

    return $pfx;
}

##########################################################
# Keyboard shortcuts
##########################################################

my $snooper_id;
my $handler_entered = 0;

# Called when user switches to this tab
#   installs keyboard-shortcut handler
sub set_keyboard_handler {
    my $self = shift;
    # Make CTRL-G activate the "go!" button (on_run)
    if ($snooper_id) {
        ##print "[Tab] Removing keyboard snooper $snooper_id\n";
        Gtk2->key_snooper_remove($snooper_id);
        $snooper_id = undef;
    }


    $snooper_id = Gtk2->key_snooper_install(\&hotkey_handler, $self);
    ##print "[Tab] Installed keyboard snooper $snooper_id\n";
}

sub remove_keyboard_handler {
    my $self = shift;
    if ($snooper_id) {
        ##print "[Tab] Removing keyboard snooper $snooper_id\n";
        Gtk2->key_snooper_remove($snooper_id);
        $snooper_id = undef;
    }
}
    
# Processes keyboard shortcuts like CTRL-G = Go!
sub hotkey_handler {
    my ($widget, $event, $self) = @_;
    my $retval;

    # stop recursion into on_run if shortcut triggered during processing
    #   (this happens because progress-dialogs pump events..)

    return 1 if ($handler_entered == 1);

    $handler_entered = 1;

    if ($event->type eq 'key-press') {
        # if CTL- key is pressed
        if ($event->state >= ['control-mask']) {
            my $keyval = $event->keyval;
            #print $keyval . "\n";
            
            # Go!
            if ((uc chr $keyval) eq 'G') {
                $self->on_run();
                $retval = 1; # stop processing
            }

            # Close tab (CTRL-W)
            elsif ((uc chr $keyval) eq 'W') {
                if ($self->get_removable) {
                    $self->{gui}->remove_tab($self);
                    $retval = 1; # stop processing
                }
            }

            # Change to next tab
            elsif ($keyval eq Gtk2::Gdk->keyval_from_name ('Tab')) {
                #  switch tabs
                #print "keyval is $keyval (tab), state is " . $event->state . "\n";
                my $page_index = $self->get_page_index;
                $self->{gui}->switch_tab (undef, $page_index + 1); #  go right
            }
            elsif ($keyval eq Gtk2::Gdk->keyval_from_name ('ISO_Left_Tab')) {
                #  switch tabs
                #print "keyval is $keyval (left tab), state is " . $event->state . "\n";
                my $page_index = $self->get_page_index;
                $self->{gui}->switch_tab (undef, $page_index - 1); #  go left
            }
        }
    }

    $handler_entered = 0;
    $retval = 0; # continue processing
    return $retval;
}

######################################
#  Other stuff


sub on_run {} # default for tabs that don't implement on_run

sub get_removable { return 1; } # default - tabs removable

#  codes to define percentiles etc
sub get_display_stretch_codes {
    my $self = shift;
    
    my %codes = (
        '2.5'  => 'PCT025',
        '97.5' => 'PCT975',
        '5'    => 'PCT05',
        '95'   => 'PCT95',
    );

    return wantarray ? %codes : \%codes;
}

sub get_plot_min_max_values {
    my $self = shift;

    my @minmax = ($self->{plot_min_value}, $self->{plot_max_value});

    return wantarray ? @minmax : \@minmax;
}

sub format_number_for_display {
    my $self = shift;
    my %args = @_;
    my $val = $args{number};

    my $text = sprintf ('%.4f', $val); # round to 4 d.p.
    if ($text == 0) {
        $text = sprintf ('%.2e', $val);
    }
    if ($text == 0) {
        $text = 0;  #  make sure it is 0 and not 0.00e+000
    };
    return $text;
}

sub set_legend_ltgt_flags {
    my $self = shift;
    my $stats = shift;

    my $flag = 0;
    my $stat_name = ($self->{PLOT_STAT_MIN} || 'MIN');
    eval {
        if (defined $stats->{$stat_name}
            and $stats->{$stat_name} != $stats->{MIN}
            and $stat_name =~ /PCT/) {
            $flag = 1;
        }
        $self->{grid}->set_legend_lt_flag ($flag);
    };
    $flag = 0;
    $stat_name = ($self->{PLOT_STAT_MAX} || 'MAX');
    eval {
        if (defined $stats->{$stat_name}
            and $stats->{$stat_name} != $stats->{MAX}
            and $stat_name =~ /PCT/) {
            $flag = 1;
        }
        $self->{grid}->set_legend_gt_flag ($flag);
    };
    return;
}

1;
