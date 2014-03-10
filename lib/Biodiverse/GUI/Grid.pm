=head1 GRID

A component that displays a BaseStruct using GnomeCanvas

=cut

package Biodiverse::GUI::Grid;

use 5.010;
use strict;
use warnings;
use Data::Dumper;
use Carp;

use Gtk2;
use Gnome2::Canvas;
use Tree::R;
#use Algorithm::QuadTree;

use Geo::ShapeFile;

our $VERSION = '0.19';

use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::CellPopup;
use Biodiverse::BaseStruct;
use Biodiverse::Progress;

require Biodiverse::Config;
my $progress_update_interval = $Biodiverse::Config::progress_update_interval;

##########################################################
# Rendering constants
##########################################################
use constant CELL_SIZE_X        => 10;    # Cell size (canvas units)
use constant CIRCLE_DIAMETER    => 5;
use constant MARK_X_OFFSET      => 2;

use constant MARK_OFFSET_X      => 3;    # How far inside the cells, marks (cross,cricle) are drawn
use constant MARK_END_OFFSET_X  => CELL_SIZE_X - MARK_OFFSET_X;

use constant BORDER_SIZE        => 20;
use constant LEGEND_WIDTH       => 20;

# Lists for each cell container
use constant INDEX_COLOUR       => 0;  # current Gtk2::Gdk::Color
use constant INDEX_ELEMENT      => 1;  # BaseStruct element for this cell
use constant INDEX_RECT         => 2;  # Canvas (square) rectangle for the cell
use constant INDEX_CROSS        => 3;
use constant INDEX_CIRCLE       => 4;
use constant INDEX_MINUS        => 5;

use constant INDEX_VALUES       => undef; # DELETE DELETE FIXME

use constant HOVER_CURSOR       => 'hand2';

use constant HIGHLIGHT_COLOUR   => Gtk2::Gdk::Color->new(255*257,0,0); # red
use constant CELL_BLACK         => Gtk2::Gdk::Color->new(0, 0, 0);
use constant CELL_WHITE         => Gtk2::Gdk::Color->new(255*257, 255*257, 255*257);
use constant CELL_OUTLINE       => Gtk2::Gdk::Color->new(0, 0, 0);
use constant OVERLAY_COLOUR     => Gtk2::Gdk::Color->parse('#001169');
use constant DARKEST_GREY_FRAC  => 0.2;
use constant LIGHTEST_GREY_FRAC => 0.8;

##########################################################
# Construction
##########################################################

=head2 Constructor

=over 5

=item frame

The GtkFrame to hold the canvas

=item hscroll

=item vscroll

The scrollbars for the canvas

=item show_legend

Whether to show the legend colour-bar on the right.
Used when spatial indices are plotted

=item show_value

Whether to show a label in the top-left corner.
It can be changed by calling set_value_label

=item hover_func

=item click_func

Closures that will be invoked with the grid cell's element name
whenever cell is hovered over or clicked

=back

=cut


#  badly needs to use keyword args
sub new {
    my $class   = shift;
    my $frame   = shift;
    my $hscroll = shift;
    my $vscroll = shift;
    
    my $show_legend = shift || 0;  #  this is irrelevant now, gets hidden as appropriate (but should allow user to show/hide)
    my $show_value  = shift || 0;

    my $self = {
        legend_mode => 'Hue',
        hue         => 0,     # default constant-hue red
    }; 
    bless $self, $class;

    $self->{hover_func}  = shift || undef; # Callback function for when users move mouse over a cell
    #$self->{use_hover_func} = 1;          #  we should use the hover func by default
    $self->{click_func}  = shift || undef; # Callback function for when users click on a cell
    $self->{select_func} = shift || undef; # Callback function for when users select a set of elements
    my $g = 0;
    $self->{colour_none} = Gtk2::Gdk::Color->new($g, $g, $g);

    # Make the canvas and hook it up
    $self->{canvas} = Gnome2::Canvas->new();
    $frame->add($self->{canvas});
    $self->{canvas}->signal_connect_swapped (size_allocate => \&on_size_allocate, $self);

    # Set up custom scrollbars due to flicker problems whilst panning..
    $self->{hadjust} = Gtk2::Adjustment->new(0, 0, 1, 1, 1, 1);
    $self->{vadjust} = Gtk2::Adjustment->new(0, 0, 1, 1, 1, 1);

    $hscroll->set_adjustment( $self->{hadjust} );
    $vscroll->set_adjustment( $self->{vadjust} );
    
    $self->{hadjust}->signal_connect_swapped('value-changed', \&on_scrollbars_scroll, $self);
    $self->{vadjust}->signal_connect_swapped('value-changed', \&on_scrollbars_scroll, $self);

    $self->{canvas}->get_vadjustment->signal_connect_swapped('value-changed', \&on_scroll, $self);
    $self->{canvas}->get_hadjustment->signal_connect_swapped('value-changed', \&on_scroll, $self);

    # Set up canvas
    $self->{canvas}->set_center_scroll_region(0);
    $self->{canvas}->show;
    $self->{zoom_fit} = 1;
    $self->{dragging} = 0;
    
    if ($show_value) {
        $self->setup_value_label();
    }

    # Create background rectangle to receive mouse events for panning
    my $rect = Gnome2::Canvas::Item->new (
        $self->{canvas}->root,
        'Gnome2::Canvas::Rect',
        x1 => 0,
        y1 => 0,
        x2 => CELL_SIZE_X,
        fill_color_gdk => CELL_WHITE,
        #outline_color => "black",
        #width_pixels => 2,
        y2 => CELL_SIZE_X,
    );
    $rect->lower_to_bottom();

    $self->{canvas}->root->signal_connect_swapped (
        event => \&on_background_event,
        $self,
    );

    $self->{back_rect} = $rect;

    #if ($show_legend) {
        $self->show_legend;
    #}

    return $self;
}

sub show_legend {
    my $self = shift;
    #print "already have legend!\n" if $self->{legend};
    return if $self->{legend};

    # Create legend
    my $pixbuf = $self->make_legend_pixbuf;
    
    $self->{legend} = Gnome2::Canvas::Item->new (
        $self->{canvas}->root,
        'Gnome2::Canvas::Pixbuf',
        pixbuf           => $pixbuf,
        width_in_pixels  => 1,
        height_in_pixels => 1,
        'height-set'     => 1,
        width            => LEGEND_WIDTH,
    );
    
    $self->{legend}->raise_to_top();
    $self->{back_rect}->lower_to_bottom();

    $self->{marks}[0] = $self->make_mark( 'nw' );
    $self->{marks}[1] = $self->make_mark( 'w'  );
    $self->{marks}[2] = $self->make_mark( 'w'  );
    $self->{marks}[3] = $self->make_mark( 'sw' );
    
    eval {
        $self->reposition;  #  trigger a redisplay of the legend
    };
    
    return;
}

sub hide_legend {
    my $self = shift;

    if ($self->{legend}) {
        $self->{legend}->destroy();
        delete $self->{legend};

        foreach my $i (0..3) {
            $self->{marks}[$i]->destroy();
        }
    }
    delete $self->{marks};
    
    return;
}

sub destroy {
    my $self = shift;

    # Destroy cell groups
    if ($self->{shapefile_group}) {
        $self->{shapefile_group}->destroy();
    }
    if ($self->{cells_group}) {
        $self->{cells_group}->destroy();
    }

    if ($self->{legend}) {
        $self->{legend}->destroy();
        delete $self->{legend};

        foreach my $i (0..3) {
            $self->{marks}[$i]->destroy();
        }
    }

    $self->{value_group}->destroy if $self->{value_group};
    delete $self->{value_group};
    delete $self->{value_text};
    delete $self->{value_rect};

    delete $self->{marks};

    delete $self->{hover_func};  #??? not sure if helps
    delete $self->{click_func};  #??? not sure if helps
    delete $self->{select_func}; #??? not sure if helps
    
    delete $self->{cells_group}; #!!!! Without this, GnomeCanvas __crashes__
                                # Apparently, a reference cycle prevents it
                                #   from being destroyed properly,
                                # and a bug makes it repaint in a half-dead state
    delete $self->{shapefile_group};
    delete $self->{back_rect};
    delete $self->{cells};

    delete $self->{canvas};
    
    return;
}


##########################################################
# Setting up the canvas
##########################################################

sub make_mark {
    my $self   = shift;
    my $anchor = shift;

    my $mark = Gnome2::Canvas::Item->new (
        $self->{canvas}->root,
        'Gnome2::Canvas::Text',
        text            => q{},
        anchor          => $anchor,
        fill_color_gdk  => CELL_BLACK,
    );

    $mark->raise_to_top();

    return $mark;
}

sub make_legend_pixbuf {
    my $self = shift;
    my ($width, $height);
    my @pixels;

    # Make array of rgb values

    if ($self->{legend_mode} eq 'Hue') {
        
        ($width, $height) = (LEGEND_WIDTH, 180);

        foreach my $row (0..($height - 1)) {
            my @rgb = hsv_to_rgb($row, 1, 1);
            push @pixels, (@rgb) x $width;
        }

    }
    elsif ($self->{legend_mode} eq 'Sat') {
        
        ($width, $height) = (LEGEND_WIDTH, 100);

        foreach my $row (0..($height - 1)) {
            my @rgb = hsv_to_rgb(
                $self->{hue},
                1 - $row / 100.0,
                1,
            );
            push @pixels, (@rgb) x $width;
        }

    }
    elsif ($self->{legend_mode} eq 'Grey') {
        
        ($width, $height) = (LEGEND_WIDTH, 255);

        foreach my $row (0..($height - 1)) {
            my $intensity = $self->rescale_grey(255 - $row);
            my @rgb = ($intensity) x 3;
            push @pixels, (@rgb) x $width;
        }
    }
    else {
        croak "Legend: Invalid colour system\n";
    }


    # Convert to low-level integers
    my $data = pack "C*", @pixels;

    my $pixbuf = Gtk2::Gdk::Pixbuf->new_from_data(
        $data,       # the data.  this will be copied.
        'rgb',       # only currently supported colorspace
        0,           # true, because we do have alpha channel data
        8,           # gdk-pixbuf currently allows only 8-bit samples
        $width,      # width in pixels
        $height,     # height in pixels
        $width * 3,  # rowstride -- we have RGBA data, so it's four
    );               # bytes per pixel.

    return $pixbuf;
}

sub setup_value_label {
    my $self = shift;
    my $group = shift;

    my $value_group = Gnome2::Canvas::Item->new (
        $self->{canvas}->root,
        'Gnome2::Canvas::Group',
        x => 0,
        y => 100,
    );

    my $text = Gnome2::Canvas::Item->new (
        $value_group,
        'Gnome2::Canvas::Text',
        x => 0, y => 0,
        markup => "<b>Value: </b>",
        anchor => 'nw',
        fill_color_gdk => CELL_BLACK,
    );

    my ($text_width, $text_height)
        = $text->get('text-width', 'text-height');

    my $rect = Gnome2::Canvas::Item->new (
        $value_group,
        'Gnome2::Canvas::Rect',
        x1 => 0,
        y1 => 0,
        x2 => $text_width,
        y2 => $text_height,
        fill_color_gdk => CELL_WHITE,
    );

    $rect->lower(1);
    $self->{value_group} = $value_group;
    $self->{value_text} = $text;
    $self->{value_rect} = $rect;
    
    return;
}

sub set_value_label {
    my $self = shift;
    my $val = shift;

    $self->{value_text}->set(markup => "<b>Value: </b>$val");

    # Resize value background rectangle
    my ($text_width, $text_height)
        = $self->{value_text}->get('text-width', 'text-height');
    $self->{value_rect}->set(x2 => $text_width, y2 => $text_height);
    
    return;
}

##########################################################
# Drawing stuff on the grid (mostly public)
##########################################################

#  convert canvas world units to basestruct units
sub units_canvas2basestruct {
    my $self = shift;
    my ($x, $y) = @_;
    
    my $cellsizes = $self->{base_struct_cellsizes};
    my $bounds    = $self->{base_struct_bounds};
    
    my $cellsize_canvas_x = CELL_SIZE_X;
    my $cellsize_canvas_y = $self->{cell_size_y};
    
    my $x_cell_units = $x / $cellsize_canvas_x;
    my $x_base_units = ($x_cell_units * $cellsizes->[0]) + $bounds->[0];
    
    my $y_cell_units = $y / $cellsize_canvas_y;
    my $y_base_units = ($y_cell_units * $cellsizes->[1]) + ($bounds->[1] || 0);
    
    return wantarray
        ? ($x_base_units, $y_base_units)
        : [$x_base_units, $y_base_units];
}

sub get_rtree {
    my $self = shift;
    
    #  return if we have one
    return $self->{rtree} if ($self->{rtree});
    
    #  check basestruct
    $self->{rtree} = $self->{base_struct}->get_param('RTREE');
    return $self->{rtree} if ($self->{rtree});
    
    #  otherwise build it ourselves and cache it
    my $rtree = Tree::R->new();
    $self->{rtree} = $rtree;
    $self->{base_struct}->set_param (RTREE => $rtree);
    $self->{build_rtree} = 1;

    return $self->{rtree};
}

# Draw cells coming from elements in a BaseStruct
# This can come either from a BaseData or a Spatial Output
sub set_base_struct {
    my $self = shift;
    my $data = shift;

    $self->{base_struct} = $data;
    $self->{cells} = {};
    
    my ($min_x, $max_x, $min_y, $max_y) = $self->find_max_min($data);
    print join (q{ }, ($min_x, $max_x, $min_y, $max_y)) . "\n";

    my @res = $self->get_cell_sizes($data);  #  handles zero and text
    
    my $cell_x = shift @res;  #  just grab first two for now
    my $cell_y = shift @res || $cell_x;  #  default to a square if not defined or zero
    
    #  save some coords stuff for later transforms
    $self->{base_struct_cellsizes} = [$cell_x, $cell_y];
    $self->{base_struct_bounds}    = [$min_x, $min_y, $max_x, $max_y];

    my $sizes = $data->get_param ('CELL_SIZES');
    my @sizes = @$sizes;
    my $width_pixels = 0;
    if ($sizes[0] == 0
        || ! defined $sizes[1]
        || $sizes[1] == 0 ) {
        $width_pixels = 1
    }

#    my ($cell_x, $cell_y, $width_pixels) = $self->get_cell_sizes($data);
    #$cell_y = 1 if ! defined $cell_y; #  catcher for single axis data sets
    
    #print "[GRID] Cellsizes:  $cell_x, $cell_y, (width: $width_pixels)\n";
    #print "[GRID] Basedata cell size is: ", join (" ", @{$data->get_param ('CELL_SIZES')}), "\n";

    # Configure cell heights and y-offsets for the marks (circles, lines,...)
    my $ratio = eval {$cell_y / $cell_x} || 1;  #  trap divide by zero
    my $cell_size_y = CELL_SIZE_X * $ratio;
    $self->{cell_size_y} = $cell_size_y;
    
    #  setup the index if needed
    if (defined $self->{select_func}) {
        my $rtree = $self->get_rtree();
    }
    
    my $elts = $data->get_element_hash();
    #print Data::Dumper::Dumper($elts);

    my $count = scalar keys %$elts;
    
    croak "No groups to display - BaseData is empty\n"
      if $count == 0;
    
    #my $progress_bar = Biodiverse::GUI::ProgressDialog->new;
    my $progress_bar = Biodiverse::Progress->new(gui_only => 1);

    print "[Grid] Grid loading $count elements (cells)\n";
    $progress_bar->update ("Grid loading $count elements (cells)", 0);


    # Delete any old cells
    if ($self->{cells_group}) {
        $self->{cells_group}->destroy();
    }

    # Make group so we can transform everything together
    my $cells_group = Gnome2::Canvas::Item->new (
        $self->{canvas}->root,
        'Gnome2::Canvas::Group',
        x => 0,
        y => 0,
    );

##  DEBUG add a background rect - should buffer the extents by 2 cells or more
## Make container group ("cell") for the rectangle and any marks
#my $xx = eval {($max_x - $min_x) / $cell_x};
#my $yy = eval {($max_y - $min_y) / $cell_y};
#my $container_xx = Gnome2::Canvas::Item->new (
#    $cells_group,
#    'Gnome2::Canvas::Group',
#    x => 0,
#    y => 0,
#);
#my $rect = Gnome2::Canvas::Item->new (
#    $container_xx,
#    'Gnome2::Canvas::Rect',
#    x1                  => 0,
#    y1                  => 0,
#    x2                  => $xx * CELL_SIZE_X,
#    y2                  => $yy * $cell_size_y,
#    fill_color_gdk      => CELL_WHITE,
#    outline_color_gdk   => CELL_BLACK,
#    width_pixels        => $width_pixels
#);

    $self->{cells_group} = $cells_group;
    $cells_group->lower_to_bottom();

    my $i = 0;
    foreach my $element (keys %$elts) {
        no warnings 'uninitialized';  #  suppress these warnings
        
        $progress_bar->update (
            "Grid loading $i of $count elements (cells)",
            $i / $count
        );
        $i++;

        #FIXME: ????:
        # NOTE: this will stuff things, since we store $element in INDEX_ELEMENT
        my ($x_bd, $y_bd) = $data->get_element_name_coord (element => $element);

        # Transform into number of cells in X and Y directions
        my $x = eval {($x_bd - $min_x) / $cell_x};
        my $y = eval {($y_bd - $min_y) / $cell_y};

        # We shift by half the cell size to make the coordinate hits cells center
        my $xcoord = $x * CELL_SIZE_X  - CELL_SIZE_X  / 2;
        my $ycoord = $y * $cell_size_y - $cell_size_y / 2;

#my $testx = $x * CELL_SIZE_X;
#my $testy = $y * $cell_size_y;
#my @test = $self->units_canvas2basestruct ($testx, $testy);

        # Make container group ("cell") for the rectangle and any marks
        my $container = Gnome2::Canvas::Item->new (
            $cells_group,
            'Gnome2::Canvas::Group',
            x => $xcoord,
            y => $ycoord
        );

        # (all coords now relative to the group)
        my $rect = Gnome2::Canvas::Item->new (
            $container,
            'Gnome2::Canvas::Rect',
            x1                  => 0,
            y1                  => 0,
            x2                  => CELL_SIZE_X,
            y2                  => $cell_size_y,
            fill_color_gdk      => CELL_WHITE,
            outline_color_gdk   => CELL_BLACK,
            width_pixels        => $width_pixels
        );

        $container->signal_connect_swapped (event => \&on_event, $self);

        $self->{cells}{$container}[INDEX_COLOUR]  = CELL_WHITE;
        $self->{cells}{$container}[INDEX_ELEMENT] = $element;
        $self->{cells}{$container}[INDEX_RECT]    = $rect;

        #  add to the r-tree
        #  (profiling indicates this takes most of the time in this sub)
        if (defined $self->{select_func} && $self->{build_rtree}) {
            $self->{rtree}->insert( #  Tree::R method
                $element,
                $x_bd - $cell_x / 2,  #  basestruct units
                $y_bd - $cell_y / 2,
                $x_bd + $cell_x / 2,
                $y_bd + $cell_y / 2,
            );
        }
    }

    $progress_bar = undef;

    #  THIS SHOULD BE ABOVE THE init_grid CALL to display properly from first?
    # Flip the y-axis (default has origin top-left with y going down)
    # Add border
    my $total_cells_X   = eval {($max_x - $min_x) / $cell_x} || 1;  #  default to one cell if undef
    my $total_cells_Y   = defined $max_y
        ? eval {($max_y - $min_y) / $cell_y} || 1
        : 1;
    my $width           = $total_cells_X * CELL_SIZE_X;
    my $height          = $total_cells_Y * $cell_size_y;
    
    $self->{width_units}  = $width  + 2*BORDER_SIZE;
    $self->{height_units} = $height + 4*BORDER_SIZE;

    $cells_group->affine_absolute([
        1,
        0,
        0,
        -1,
        BORDER_SIZE,
        $height + 2*BORDER_SIZE,
    ]);
    
    # Set visible region
    $self->{canvas}->set_scroll_region(
        0,
        0,
        $self->{width_units},
        $self->{height_units},
    );

    # Update
    $self->setup_scrollbars();
    $self->resize_background_rect();
    
    #  show legend by default - gets hidden by caller if needed
    $self->show_legend;

    # Store info needed by load_shapefile
    $self->{dataset_info} = [$min_x, $min_y, $max_x, $max_y, $cell_x, $cell_y];

    return 1;
}

sub get_base_struct {
    my $self = shift;
    return $self->{base_struct};
}

# Draws a polygonal shapefile
sub set_overlay {
    my $self      = shift;
    my $shapefile = shift;
    my $colour    = shift || OVERLAY_COLOUR;

    # Delete any existing
    if ($self->{shapefile_group}) {
        $self->{shapefile_group}->destroy;
        delete $self->{shapefile_group};
    }
    
    if ($shapefile) {
        my @args = @{ $self->{dataset_info} };
        $self->load_shapefile(@args, $shapefile, $colour);
    }

    return;
}

sub load_shapefile {
    my ($self, $min_x, $min_y, $max_x, $max_y, $cell_x, $cell_y, $shapefile, $colour) = @_;

    my @rect = (
        $min_x - $cell_x,
        $min_y - $cell_y,
        $max_x + $cell_x,
        $max_y + $cell_y,
    );

    # Get shapes within visible region - allow for cell extents
    my @shapes;
    @shapes = $shapefile->shapes_in_area (@rect);
    #  try to get all, but canvas ignores those outside the area...
    #@shapes = $shapefile->shapes_in_area ($shapefile->bounds);
    
    my $num = @shapes;
    print "[Grid] Shapes within plot area: $num\n";

    # Work out how far away a point has to be from the previous point
    # to not get clipped - REDUNDANT NOW
    # This will massively reduce detail when we're zoomed out
    #my $ppu = $self->{canvas}->get_pixels_per_unit();
    #my $min_distance = 1 / $ppu * 3; # don't draw points within 3px of each other
    #my $min_distance2 = $min_distance * $min_distance;
    ##print "[Grid] minimum point distance - $min_distance\n";
    #
    my $unit_multiplier_x = CELL_SIZE_X / $cell_x;
    my $unit_multiplier_y = $self->{cell_size_y} / $cell_y;
    my $unit_multiplier2  = $unit_multiplier_x * $unit_multiplier_x; #FIXME: maybe take max of _x,_y

    # Put it into a group so that it can be deleted more easily
    my $shapefile_group = Gnome2::Canvas::Item->new (
        $self->{cells_group},
        'Gnome2::Canvas::Group',
        x => 0,
        y => 0,
    );

    $shapefile_group->raise_to_top();
    $self->{shapefile_group} = $shapefile_group;

    # Add all shapes
    foreach my $shapeid (@shapes) {
        #my $shape = $shapefile->get_shape($shapeid);
        my $shape = $shapefile->get_shp_record($shapeid);

        # Make polygon from each "part"
        BY_PART:
        foreach my $part (1 .. $shape->num_parts) {

            my @plot_points;    # x,y coordinates that will be given to canvas
            my @segments = $shape->get_segments($part);

            #  add the points from all of the vertices
            #  Geo::ShapeFile gives them to us as vertex pairs
            #  so extract the first point from each
            POINT_TO_ADD:
            foreach my $vertex (@segments) {
                push @plot_points, (
                    ($vertex->[0]->{X} - $min_x) * $unit_multiplier_x,
                    ($vertex->[0]->{Y} - $min_y) * $unit_multiplier_y,
                );
            }

            #  get the end of the line
            my $current_vertex = $segments[-1];
            push @plot_points, (
                ($current_vertex->[1]->{X} - $min_x) * $unit_multiplier_x,
                ($current_vertex->[1]->{Y} - $min_y) * $unit_multiplier_y,
            );

            #print "@plot_points\n";
            if (@plot_points > 2) { # must have more than one point (two coords)
                my $poly = Gnome2::Canvas::Item->new (
                    $shapefile_group,
                    'Gnome2::Canvas::Line',
                    points          => \@plot_points,
                    fill_color_gdk  => $colour,
                );
            }
        }
    }

    return;
}

# Colours elements using a callback function
# The callback should return a Gtk2::Gdk::Color object, or undef
# to set the colour to CELL_WHITE
sub colour {
    my $self     = shift;
    my $callback = shift;

#print "Colouring " . (scalar keys %{$self->{cells}}) . " cells\n";

  CELL:
    foreach my $cell (values %{$self->{cells}}) {

        next CELL if !defined $cell->[INDEX_RECT];

        my $colour_ref = $callback->($cell->[INDEX_ELEMENT]) // CELL_WHITE;
        $cell->[INDEX_COLOUR] = $colour_ref;

        eval {
            $cell->[INDEX_RECT]->set('fill-color-gdk' => $colour_ref);
        };
        warn $@ if $@;
    }

    return;
}

sub set_cell_outline_colour {
    my $self = shift;
    my $colour = shift;
    
    if (! $colour) {  #  should fire up a colour selector
        #$colour = Gtk2::Gdk::Color->parse('red');
        $colour = $self->get_colour_from_chooser;
    }

    #  if still no colour chosen
    return if !$colour;

    foreach my $cell (values %{$self->{cells}}) {
        my $rect = $cell->[INDEX_RECT];
        $rect->set('outline_color_gdk', $colour);
    }

    return;
}

sub get_colour_from_chooser {
    my $self = shift;
    
    my $dialog = Gtk2::ColorSelectionDialog->new ('Select a color');
    my $c;
    if ('ok' eq $dialog->run) {
        $c = $dialog->colorsel->get_current_color;
    }
    $dialog->destroy;
    
    #if ($c) {
    #    my %colours = (
    #        red => $c->red,
    #        green => $c->green,
    #        blue => $c->blue,
    #    );
    #    print %colours; 
    #}
    return $c;
}

# Sets the values of the textboxes next to the legend */
sub set_legend_min_max {
    my ($self, $min, $max) = @_;
    
    return if ! ($self->{marks}
                 && defined $min
                 && defined $max
                );

    # Set legend textbox markers
    my $marker_step = ($max - $min) / 3;
    foreach my $i (0..3) {
        my $val = $min + $i * $marker_step;
        my $text = $self->format_number_for_display (number => $val);
        my $text_num = $text;  #  need to not have '<=' and '>=' in comparison lower down
        if ($i == 0 and $self->{legend_lt_flag}) {
            $text = '<=' . $text;
        }
        elsif ($i == 3 and $self->{legend_gt_flag}) {
            $text = '>=' . $text;
        }
        elsif ($self->{legend_lt_flag} or $self->{legend_gt_flag}) {
            $text = '  ' . $text;
        }
        
        my $mark = $self->{marks}[3 - $i];
        $mark->set( text => $text );
        #  move the mark to right align with the legend
        my @bounds = $mark->get_bounds;
        my @lbounds = $self->{legend}->get_bounds;
        my $offset = $lbounds[0] - $bounds[2];
        if (($text_num + 0) != 0) {
            $mark->move ($offset - length ($text), 0);
        }
        else {
            $mark->move ($offset - length ($text) - 0.5, 0);
        }
    }
    
    return;
}


#  dup from Tab.pm - need to inherit from single source
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

sub set_legend_gt_flag {
    my $self = shift;
    my $flag = shift;
    $self->{legend_gt_flag} = $flag;
    return;
}

sub set_legend_lt_flag {
    my $self = shift;
    my $flag = shift;
    $self->{legend_lt_flag} = $flag;
    return;
}

# Sets list to use for colouring (eg: SPATIAL_RESULTS, RAND_COMPARE, ...)
# Is this ever called?
sub set_calculation_list {
    my $self = shift;
    my $list_name = shift;
    print "[Grid] Setting calculation list to $list_name\n";

    my $elts = $self->{base_struct}->get_element_hash();

    foreach my $element (sort keys %{$elts}) {
        my $cell = $self->{element_group}{$element};
        $cell->[INDEX_VALUES] = $elts->{$element}{$list_name};
    }

    return;
}


##########################################################
# Marking out certain elements by colour, circles, etc...
##########################################################

sub grayout_elements {
    my $self = shift;

    # ed: actually just white works better - leaving this in just in case is handy elsewhere
    # This is from the GnomeCanvas demo
    #my $gray50_width = 4;
    #my $gray50_height = 4;
    #my $gray50_bits = pack "CC", 0x80, 0x01, 0x80, 0x01;
    #my $stipple = Gtk2::Gdk::Bitmap->create_from_data (undef, $gray50_bits, $gray50_width, $gray50_height);

    foreach my $cell (values %{$self->{cells}}) {
        my $rect = $cell->[INDEX_RECT];
        $rect->set('fill-color', '#FFFFFF'); # , 'fill-stipple', $stipple);

    }
    
    return;
}

# Places a circle/cross inside a cell if it exists in a hash
sub mark_if_exists {
    my $self  = shift;
    my $hash  = shift;
    my $shape = shift; # "circle" or "cross"

  CELL:
    foreach my $cell (values %{$self->{cells}}) {
        #  hackish, but sometimes we are called before the data are populated
        next CELL if !$cell || !$cell->[INDEX_RECT];

        my $group = $cell->[INDEX_RECT]->parent;

        if (exists $hash->{$cell->[INDEX_ELEMENT]}) {
            # Circle
            if ($shape eq 'circle' && not $cell->[INDEX_CIRCLE]) {
                $cell->[INDEX_CIRCLE] = $self->draw_circle($group);
                #$group->signal_handlers_disconnect_by_func(\&on_event);
            }

            # Cross
            #if ($shape eq 'cross' && not $cell->[INDEX_CROSS]) {
            #    $cell->[INDEX_CROSS] = $self->draw_cross($group);
            #} 

            # Minus
            if ($shape eq 'minus' && not $cell->[INDEX_MINUS]) {
                $cell->[INDEX_MINUS] = $self->draw_minus($group);
            } 

        }
        else {
            if ($shape eq 'circle' && $cell->[INDEX_CIRCLE]) {
                $cell->[INDEX_CIRCLE]->destroy;
                $cell->[INDEX_CIRCLE] = undef;
                #$group->signal_connect_swapped(event => \&on_event, $self);
            }
            #if ($shape eq 'cross' && $cell->[INDEX_CROSS]) {
            #    $cell->[INDEX_CROSS]->destroy;
            #    $cell->[INDEX_CROSS] = undef;
            #}    
            if ($shape eq 'minus' && $cell->[INDEX_MINUS]) {
                $cell->[INDEX_MINUS]->destroy;
                $cell->[INDEX_MINUS] = undef;
            }
        }
    }
    
    return;
}

sub draw_circle {
    my ($self, $group) = @_;
    my $offset_x = (CELL_SIZE_X - CIRCLE_DIAMETER) / 2;
    my $offset_y = ($self->{cell_size_y} - CIRCLE_DIAMETER) / 2;

    my $item = Gnome2::Canvas::Item->new (
        $group,
        'Gnome2::Canvas::Ellipse',
        x1                => $offset_x,
        y1                => $offset_y,
        x2                => $offset_x + CIRCLE_DIAMETER,
        y2                => $offset_y + CIRCLE_DIAMETER,
        fill_color_gdk    => CELL_BLACK,
        outline_color_gdk => CELL_BLACK,
    );
    #$item->signal_connect_swapped(event => \&on_marker_event, $self);
    return $item;
}

sub on_marker_event {
    # FIXME FIXME FIXME All this stuff has serious problems between Windows/Linux
    my ($self, $event, $cell) = @_;
    print "Marker event: " . $event->type .  "\n";
    $self->on_event($event, $cell->parent);
    return 1;
}

# sub draw_cross {
#         my ($self, $group) = @_;
#         # Use a group to hold the two lines
#         my $cross_group = Gnome2::Canvas::Item->new ($group,
#                                                                 "Gnome2::Canvas::Group",
#                                                                 x => 0, y => 0);
#
#         Gnome2::Canvas::Item->new ($cross_group,
#                                                                 "Gnome2::Canvas::Line",
#                                                                 points => [MARK_OFFSET_X, MARK_OFFSET_X, MARK_END_OFFSET_X, MARK_END_OFFSET_X],
#                                                                 fill_color_gdk => CELL_BLACK,
#                                                                 width_units => 1);
#         Gnome2::Canvas::Item->new ($cross_group,
#                                                                 "Gnome2::Canvas::Line",
#                                                                 points => [MARK_END_OFFSET_X, MARK_OFFSET_X, MARK_OFFSET_X, MARK_END_OFFSET_X],
#                                                                 fill_color_gdk => CELL_BLACK,
#                                                                 width_units => 1);
#         return $cross_group;
# }

sub draw_minus {
    my ($self, $group) = @_;
    my $offset_y = ($self->{cell_size_y} - 1) / 2;

    return Gnome2::Canvas::Item->new (
        $group,
        'Gnome2::Canvas::Line',
        points => [
            MARK_X_OFFSET,
            $offset_y,
            CELL_SIZE_X - MARK_X_OFFSET,
            $offset_y,
        ],
        fill_color_gdk => CELL_BLACK,
        width_units => 1,
    );

}




##########################################################
# Colouring based on an analysis value
##########################################################

sub colour_cells {
    my $self = shift;
    
    #  default to black if an analysis is specified, white otherwise
    #my $colour_none = shift || (defined $self->{analysis} ? CELL_BLACK : CELL_WHITE);
    my $colour_none = $self->get_colour_none;

    foreach my $cell (values %{$self->{cells}}) {
        my $val = defined $self->{analysis} ? $cell->[INDEX_VALUES]{$self->{analysis}} : undef;
        my $rect = $cell->[INDEX_RECT];
        my $colour = defined $val ? $self->get_colour($val, $self->{min}, $self->{max}) : $colour_none;
        $rect->set('fill-color-gdk',  $colour);
    }

    return;
}

sub get_colour_none {
    my $self = shift;
    my $colour_none = shift;

    #  default to black if an analysis is specified, white otherwise
    my $null    = $self->{colour_none} || CELL_BLACK;
    my $default = defined $self->{analysis} ? $null : CELL_WHITE;

    $colour_none ||= $default;

    return $colour_none;    
}

sub get_colour {
    my ($self, $val, $min, $max) = @_;

    if (defined $min and $val < $min) {
        $val = $min;
    }
    if (defined $max and $val > $max) {
        $val = $max;
    }
    my @args = ($val, $min, $max);
    
    if    ($self->{legend_mode} eq 'Hue') {
        return $self->get_colour_hue(@args);
    }
    elsif ($self->{legend_mode} eq 'Sat') {
        return $self->get_colour_saturation(@args);
    }
    elsif ($self->{legend_mode} eq 'Grey') {
        return $self->get_colour_grey(@args);
    }
    else {
        croak "Unknown colour system: " . $self->{legend_mode} . "\n";
    }

    return;
}

sub get_colour_hue {
    my ($self, $val, $min, $max) = @_;
    # We use the following system:
    #   Linear interpolation between min...max
    #   HUE goes from 180 to 0 as val goes from min to max
    #   Saturation, Brightness are 1
    #
    my $hue;
    if (! defined $max || ! defined $min) {
        return Gtk2::Gdk::Color->new(0, 0, 0);
        #return CELL_BLACK;
    }
    elsif ($max != $min) {
        return Gtk2::Gdk::Color->new(0, 0, 0) if ! defined $val;
        $hue = ($val - $min) / ($max - $min) * 180;
    }
    else {
        $hue = 0;
    }
    
    $hue = int(180 - $hue); # reverse 0..180 to 180..0 (this makes high values red)
    
    my ($r, $g, $b) = hsv_to_rgb($hue, 1, 1);
    
    return Gtk2::Gdk::Color->new($r*257, $g*257, $b*257);
}

sub get_colour_saturation {
    my ($self, $val, $min, $max) = @_;
    #   Linear interpolation between min...max
    #   SATURATION goes from 0 to 1 as val goes from min to max
    #   Hue is variable, Brightness 1
    my $sat;
    if (! defined $max || ! defined $min) {
        return Gtk2::Gdk::Color->new(0, 0, 0);
        #return CELL_BLACK;
    }
    elsif ($max != $min) {
        return Gtk2::Gdk::Color->new(0, 0, 0) if ! defined $val;
        $sat = ($val - $min) / ($max - $min);
    }
    else {
        $sat = 1;
    }
    
    my ($r, $g, $b) = hsv_to_rgb($self->{hue}, $sat, 1);
    
    return Gtk2::Gdk::Color->new($r*257, $g*257, $b*257);
}

sub get_colour_grey {
    my ($self, $val, $min, $max) = @_;
    
    my $sat;
    if (! defined $max || ! defined $min) {
        return Gtk2::Gdk::Color->new(0, 0, 0);
        #return CELL_BLACK;
    }
    elsif ($max != $min) {
        return Gtk2::Gdk::Color->new(0, 0, 0)
          if ! defined $val;
        
        $sat = ($val - $min) / ($max - $min);
    }
    else {
        $sat = 1;
    }
    $sat *= 255;
    $sat = $self->rescale_grey($sat);  #  don't use all the shades
    $sat *= 257;
    
    return Gtk2::Gdk::Color->new($sat, $sat, $sat);
}

# FROM http://blog.webkist.com/archives/000052.html
# by Jacob Ehnmark
sub hsv_to_rgb {
    my($h, $s, $v) = @_;
    $v = $v >= 1.0 ? 255 : $v * 256;

    # Grey image.
    return((int($v)) x 3) if ($s == 0);

    $h /= 60;
    my $i = int($h);
    my $f = $h - int($i);
    my $p = int($v * (1 - $s));
    my $q = int($v * (1 - $s * $f));
    my $t = int($v * (1 - $s * (1 - $f)));
    $v = int($v);

    if   ($i == 0) { return($v, $t, $p); }
    elsif($i == 1) { return($q, $v, $p); }
    elsif($i == 2) { return($p, $v, $t); }
    elsif($i == 3) { return($p, $q, $v); }
    elsif($i == 4) { return($t, $p, $v); }
    else           { return($v, $p, $q); }
}

sub rgb_to_hsv {
    my $var_r = $_[0] / 255;
    my $var_g = $_[1] / 255;
    my $var_b = $_[2] / 255;
    my($var_max, $var_min) = maxmin($var_r, $var_g, $var_b);
    my $del_max = $var_max - $var_min;

    if($del_max) {
        my $del_r = ((($var_max - $var_r) / 6) + ($del_max / 2)) / $del_max;
        my $del_g = ((($var_max - $var_g) / 6) + ($del_max / 2)) / $del_max;
        my $del_b = ((($var_max - $var_b) / 6) + ($del_max / 2)) / $del_max;
    
        my $h;
        if($var_r == $var_max) { $h = $del_b - $del_g; }
        elsif($var_g == $var_max) { $h = 1/3 + $del_r - $del_b; }
        elsif($var_b == $var_max) { $h = 2/3 + $del_g - $del_r; }
    
        if($h < 0) { $h += 1 }
        if($h > 1) { $h -= 1 }
    
        return($h * 360, $del_max / $var_max, $var_max);
    }
    else {
        return(0, 0, $var_max);
    }
}

#  rescale the grey values into lighter shades
sub rescale_grey {
    my $self  = shift;
    my $value = shift;
    my $max   = shift;
    defined $max or $max = 255;
    
    $value /= $max;
    $value *= (LIGHTEST_GREY_FRAC - DARKEST_GREY_FRAC);
    $value += DARKEST_GREY_FRAC;
    $value *= $max;
    
    return $value;
}

sub maxmin {
    my($min, $max) = @_;
    
    for(my $i=0; $i<@_; $i++) {
        $max = $_[$i] if($max < $_[$i]);
        $min = $_[$i] if($min > $_[$i]);
    }
    
    return($max,$min);
}

##########################################################
# Data extraction utilities
##########################################################

sub find_max_min {
    my $self = shift;
    my $data = shift;
    my ($min_x, $max_x, $min_y, $max_y);

    foreach ($data->get_element_list) {

        my ($x, $y) = $data->get_element_name_coord (element => $_);

        $min_x = $x if ( (not defined $min_x) || $x < $min_x);
        $min_y = $y if ( (not defined $min_y) || $y < $min_y);

        $max_x = $x if ( (not defined $max_x) || $x > $max_x);
        $max_y = $y if ( (not defined $max_y) || $y > $max_y);
    }

    return ($min_x, $max_x, $min_y, $max_y);
}

sub get_cell_sizes {
    my $data = $_[1];
    #my ($cell_x, $cell_y) = @{$data->get_param("CELL_SIZES")};
    my @cell_sizes = @{$data->get_param("CELL_SIZES")};  #  work on a copy
    #my $cellWidth = 0;

    my $i = 0;
    foreach my $axis (@cell_sizes) {
        if ($axis == 0) {  
            # If zero size, we want to display every point
            # Fast dodgy method for computing cell size
            #
            # 1. Sort coordinates
            # 2. Find successive differences
            # 3. Sort differences
            # 4. Make cells square with median distances
    
            print "[Grid] Calculating minimal cell size for axis $i\n";
    
            my $elts = $data->get_element_hash();
            my %axis_coords;  #  want a list of all the unique coords on this axis
            foreach my $element (keys %$elts) {
                my @axes = $data->get_element_name_as_array(element => $element);
                $axis_coords{$axes[$i]} = 1; 
            }
            
            my $j = 0;
            my @array = sort {$a <=> $b} keys %axis_coords;
            #print "@array\n";
            my @diffs;
            foreach my $i (1 .. $#array) {
                my $diff = abs( $array[$i] - $array[$i-1]);
                push @diffs, $diff;
            }
            
            @diffs = sort {$a <=> $b} @diffs;
            $cell_sizes[$i] = ($diffs[int ($#diffs / 2)] || 0);
            $j++;
    
            #$cellWidth = 2; # If have zero cell size, make squares more visible  NOW HANDLED ELSEWHERE
            
        }
        elsif ($axis < 0) {  #  really should loop over each axis
            $cell_sizes[$i] = 1;
            #$cellWidth = 2;
        }
        $i++;
    }
    print "[Grid]   using cellsizes ", join (", ", @cell_sizes) , "\n";
    #my ($cell_x, $cell_y) = @cell_sizes;
    #return ($cell_x, $cell_y, $cellWidth);
    return wantarray ? @cell_sizes : \@cell_sizes;
}


##########################################################
# Event handling
##########################################################

# Implements pop-ups and hover-markers
# FIXME FIXME FIXME Horrible problems between windows / linux due to the markers being on top...
sub on_event {
    my ($self, $event, $cell) = @_;

#my $type = $event->type;
#my $state = $event->state;
#if ($state) {
#    print "Event is $type, state is $state \n";
#}

    if ($event->type eq '2button_press') {
        print "Double click does nothing";
    }
    elsif ($event->type eq 'enter-notify') {

        # Call client-defined callback function
        if (defined $self->{hover_func} and not $self->{clicked_cell}) {
            my $f = $self->{hover_func};
            $f->($self->{cells}{$cell}[INDEX_ELEMENT]);
        }

        # Change the cursor
        my $cursor = Gtk2::Gdk::Cursor->new(HOVER_CURSOR);
        $self->{canvas}->window->set_cursor($cursor);

    }
    elsif ($event->type eq 'leave-notify') {

        # Call client-defined callback function
        #if (defined $self->{hover_func} and not $self->{clicked_cell}) {
        #    my $f = $self->{hover_func};
        #    # FIXME: Disabling hiding of markers since this stuffs up
        #    # the popups on win32 - we receive leave-notify on button click!
        #    #$f->(undef);
        #}

        # Change cursor back to default
        $self->{canvas}->window->set_cursor(undef);

    }
    elsif ($event->type eq 'button-press') {
        $self->{clicked_cell} = undef unless $event->button == 2;  #  clear any clicked cell
        
        # If middle-click or control-click
        if (        $event->button == 2
            || (    $event->button == 1
                and not $self->{selecting}
                and $event->state >= [ 'control-mask' ])
            ) {
            #print "===========Cell popup\n";
            # Show/Hide the labels popup dialog
            my $element = $self->{cells}{$cell}[INDEX_ELEMENT];
            my $f = $self->{click_func};
            $f->($element);
            
            return 1;  #  Don't propagate the events
        }
        
        elsif ($event->button == 1) { # left click and drag
            
            if (defined $self->{select_func}
                and not $self->{selecting}
                and not ($event->state >= [ 'control-mask' ])
                ) {
                
                ($self->{sel_start_x}, $self->{sel_start_y}) = ($event->x, $event->y);
                
                # Grab mouse
                $cell->grab (
                    [qw/pointer-motion-mask button-release-mask/],
                    Gtk2::Gdk::Cursor->new ('fleur'),
                    $event->time,
                );
                $self->{selecting} = 1;
                $self->{grabbed_cell} = $cell;
                
                $self->{sel_rect} = Gnome2::Canvas::Item->new (
                    $self->{canvas}->root,
                    'Gnome2::Canvas::Rect',
                    x1 => $event->x,
                    y1 => $event->y,
                    x2 => $event->x,
                    y2 => $event->y,
                    fill_color_gdk => undef,
                    outline_color_gdk => CELL_BLACK,
                    #outline_color_gdk => HIGHLIGHT_COLOUR,
                    width_pixels => 0,
                );
            }
        }
        elsif ($event->button == 3) { # right click - use hover function but fix it in place
            # Call client-defined callback function
            if (defined $self->{hover_func}) {
                my $f = $self->{hover_func};
                $f->($self->{cells}{$cell}[INDEX_ELEMENT]);
            }
            $self->{clicked_cell} = $cell;
            
        }

    }
    elsif ($event->type eq 'button-release') {
        $cell->ungrab ($event->time);

        if ($self->{selecting} and defined $self->{select_func}) {

            $cell->ungrab ($event->time);
            
            $self->{selecting} = 0;
            
            # Establish the selection
            my ($x_start, $y_start) = ($self->{sel_start_x}, $self->{sel_start_y});
            my ($x_end, $y_end)     = ($event->x, $event->y);

            $self->end_selection($x_start, $y_start, $x_end, $y_end);

            #  Try to get rid of the dot that appears when selecting.
            #  Lowering at least stops it getting in the way.
            my $sel_rect = $self->{sel_rect};
            delete $self->{sel_rect};
            $sel_rect->lower_to_bottom();
            $sel_rect->hide();
            $sel_rect->destroy;
            
        }

    }
    if ($event->type eq 'motion-notify') {

        if ($self->{selecting}) {
            # Resize selection rectangle
            $self->{sel_rect}->set(x2 => $event->x, y2 => $event->y);
        }
    }

    return 0;    
}

# Implements resizing
sub on_size_allocate {
    my ($self, $size, $canvas) = @_;
    $self->{width_px}  = $size->width;
    $self->{height_px} = $size->height;

    if (exists $self->{width_units}) {
        $self->fit_grid() if ($self->{zoom_fit});

        $self->reposition();
        $self->setup_scrollbars();
        $self->resize_background_rect();

    }
    
    return;
}

# Implements panning
sub on_background_event {
    my ($self, $event, $cell) = @_;

my $type = $event->type;
my $state = $event->state;
#print "BK Event is $type, state is $state \n";


    if ( $event->type eq 'button-press') {
        
        if ($event->button == 1 and defined $self->{select_func} and not $self->{selecting}) {
#print "COMMENCING SELECTION  $self->{select_func}\n";
            ($self->{sel_start_x}, $self->{sel_start_y}) = ($event->x, $event->y);

            # Grab mouse
            $cell->grab (
                [qw /pointer-motion-mask button-release-mask/ ],
                Gtk2::Gdk::Cursor->new ('fleur'),
                $event->time,
            );
            $self->{selecting} = 1;
            $self->{grabbed_cell} = $cell;

            $self->{sel_rect} = Gnome2::Canvas::Item->new (
                $self->{canvas}->root,
                'Gnome2::Canvas::Rect',
                x1 => $event->x,
                y1 => $event->y,
                x2 => $event->x,
                y2 => $event->y,
                fill_color_gdk => undef,
                outline_color_gdk => CELL_BLACK,
                width_pixels => 0,
            );
        }
        else {
            ($self->{pan_start_x}, $self->{pan_start_y}) = $event->coords;

            # Grab mouse
            $cell->grab (
                [qw/pointer-motion-mask button-release-mask/],
                Gtk2::Gdk::Cursor->new ('fleur'),
                $event->time,
            );
            $self->{dragging} = 1;
        }

    }
    elsif ( $event->type eq 'button-release') {

        if ($self->{selecting} and $event->button == 1) {
            # Establish the selection
            my ($x_start, $y_start) = ($self->{sel_start_x}, $self->{sel_start_y});
            my ($x_end, $y_end)     = ($event->x, $event->y);

            if (defined $self->{select_func}) {
                
                $cell->ungrab ($event->time);
                $self->{selecting} = 0;
                
                #  Try to get rid of the dot that appears when selecting.
                #  Lowering at least stops it getting in the way.
                my $sel_rect = $self->{sel_rect};
                delete $self->{sel_rect};
                #$sel_rect->lower_to_bottom();
                #$sel_rect->hide();
                $sel_rect->destroy;
                
                #if (! $event->state >= ["control-mask" ]) {  #  not if control key is pressed
                    $self->end_selection($x_start, $y_start, $x_end, $y_end);
                #}
            }

        }
        elsif ($self->{dragging}) {
            $cell->ungrab ($event->time);
            $self->{dragging} = 0;
            $self->update_scrollbars(); #FIXME: If we do this for motion-notify - get great flicker!?!?
        }

    }
    elsif ( $event->type eq 'motion-notify') {
#        print "Background Event\tMotion\n";
        
        if ($self->{selecting}) {

            # Resize selection rectangle
            $self->{sel_rect}->set(x2 => $event->x, y2 => $event->y);

        }
        elsif ($self->{dragging}) {
            # Work out how much we've moved away from pan_start (world coords)
            my ($x, $y) = $event->coords;
            my ($dx, $dy) = ($x - $self->{pan_start_x}, $y - $self->{pan_start_y});

            # Scroll to get back to pan_start
            my ($scrollx, $scrolly) = $self->{canvas}->get_scroll_offsets();
            my ($cx, $cy) =  $self->{canvas}->w2c($dx, $dy);
            $self->{canvas}->scroll_to(-1 * $cx + $scrollx, -1 * $cy + $scrolly);
        }
    }

    return 0;    
}

# Called to complete selection. Finds selected elements and calls callback
sub end_selection {
    my $self = shift;
    my ($x_start, $y_start, $x_end, $y_end) = @_;

    # Find selected elements
    my $yoffset = $self->{height_units} - 2 * BORDER_SIZE;

    my @rect = (
        $x_start - BORDER_SIZE,
        $yoffset - $y_start,
        $x_end - BORDER_SIZE,
        $yoffset - $y_end,
    );

    # Make sure end distances are greater than start distances
    my $tmp;
    if ($rect[0] > $rect[2]) {
        $tmp = $rect[0];
        $rect[0] = $rect[2];
        $rect[2] = $tmp;
    }
    if ($rect[1] > $rect[3]) {
        $tmp = $rect[1];
        $rect[1] = $rect[3];
        $rect[3] = $tmp;
    }

    my @rect_baseunits = (
        $self->units_canvas2basestruct ($rect[0], $rect[1]),
        $self->units_canvas2basestruct ($rect[2], $rect[3]),
    );

    my $elements = [];
    #$self->{rtree}->query_partly_within_rect(@rect, $elements);
    $self->{rtree}->query_partly_within_rect(@rect_baseunits, $elements);
    #my $elements = $self->{rtree}->get_enclosed_objects (@rect);
    if (0) {
        print "[Grid] selection rect: @rect\n";
        for my $element (@$elements) {
            print "[Grid]\tselected: $element\n";
        }
    }

    # call callback
    my $f = $self->{select_func};
    $f->($elements);
    
    return;
}

##########################################################
# Scrolling
##########################################################

sub setup_scrollbars {
    my $self = shift;
    my ($total_width, $total_height) = $self->{canvas}->w2c($self->{width_units}, $self->{height_units});

    $self->{hadjust}->upper( $total_width );
    $self->{vadjust}->upper( $total_height );

    if ($self->{width_px}) {
        $self->{hadjust}->page_size( $self->{width_px} );
        $self->{vadjust}->page_size( $self->{height_px} );

        $self->{hadjust}->page_increment( $self->{width_px} / 2 );
        $self->{vadjust}->page_increment( $self->{height_px} / 2 );
    }

    $self->{hadjust}->changed;
    $self->{vadjust}->changed;
    
    return;
}

sub update_scrollbars {
    my $self = shift;

    my ($scrollx, $scrolly) = $self->{canvas}->get_scroll_offsets();
    $self->{hadjust}->set_value($scrollx);
    $self->{vadjust}->set_value($scrolly);
    
    return;
}

sub on_scrollbars_scroll {
    my $self = shift;

    if (not $self->{dragging}) {
        my ($x, $y) = ($self->{hadjust}->get_value, $self->{vadjust}->get_value);
        $self->{canvas}->scroll_to($x, $y);
        $self->reposition();
    }
    
    return;
}


##########################################################
# Zoom and Resizing
##########################################################

# Calculate pixels-per-unit to make image fit
sub fit_grid {
    my $self = shift;

    my $ppu_width = $self->{width_px} / $self->{width_units};
    my $ppu_height = $self->{height_px} / $self->{height_units};
    my $min_ppu = $ppu_width < $ppu_height ? $ppu_width : $ppu_height;
    $self->{canvas}->set_pixels_per_unit( $min_ppu );
    #print "[Grid] Setting grid zoom (pixels per unit) to $min_ppu\n";
    
    return;
}

# Resize background rectangle which is dragged for panning
sub resize_background_rect {
    my $self = shift;

    if ($self->{width_px}) {

        # Make it the full visible area
        my ($width, $height) = $self->{canvas}->c2w($self->{width_px}, $self->{height_px});
        if (not $self->{dragging}) {
            $self->{back_rect}->set(
                x2 => max($width,  $self->{width_units}),
                y2 => max($height, $self->{height_units}),
            );
            $self->{back_rect}->lower_to_bottom();
        }

    }
    
    return;
}

# Updates position of legend and value box when canvas is resized or scrolled
sub reposition {
    my $self = shift;
    return if not defined $self->{legend};

    # Convert coordinates into world units
    # (this has been tricky to get working right...)
    my ($width, $height) = $self->{canvas}->c2w($self->{width_px} || 0, $self->{height_px} || 0);

    my ($scroll_x, $scroll_y) = $self->{canvas}->get_scroll_offsets();
    ($scroll_x, $scroll_y) = $self->{canvas}->c2w($scroll_x, $scroll_y);

    my ($border_width, $legend_width) = $self->{canvas}->c2w(BORDER_SIZE, LEGEND_WIDTH);

    $self->{legend}->set(
        x       => $width + $scroll_x - $legend_width,  # world units
        y       => $scroll_y,                           # world units
        width   => LEGEND_WIDTH,                        # pixels
        height  => $self->{height_px},                  # pixels
    );            
    
    # Reposition the "mark" textboxes
    my $mark_x = $scroll_x              # world units
                 + $width
                 - $legend_width
                 - 2 * $border_width; 
    foreach my $i (0..3) {
        $self->{marks}[$i]->set(
            x => $mark_x ,
            y => $scroll_y + $i * $height / 3,
        );
    }
    
    # Reposition value box
    if ($self->{value_group}) {
        my ($value_x, $value_y) = $self->{value_group}->get('x', 'y');
        $self->{value_group}->move(
            $scroll_x - $value_x,
            $scroll_y - $value_y,
        );

        my ($text_width, $text_height)
            = $self->{value_text}->get('text-width', 'text-height');

        # Resize value background rectangle
        $self->{value_rect}->set(
            x2 => $text_width,
            y2 => $text_height,
        );
    }
    
    return;
}

sub max {
    return ($_[0] > $_[1]) ? $_[0] : $_[1];
}

sub on_scroll {
    my $self = shift;
    #FIXME: check if this helps reduce flicker
    $self->reposition();
    
    return;
}

##########################################################
# More public functions (zoom/colours)
##########################################################

sub zoom_in {
    my $self = shift;
    my $ppu = $self->{canvas}->get_pixels_per_unit();
    $self->{canvas}->set_pixels_per_unit( $ppu * 1.5 );
    $self->{zoom_fit} = 0;
    $self->post_zoom();
    
    return;
}

sub zoom_out {
    my $self = shift;
    my $ppu = $self->{canvas}->get_pixels_per_unit();
    $self->{canvas}->set_pixels_per_unit( $ppu / 1.5 );
    $self->{zoom_fit} = 0;
    $self->post_zoom();
    
    return;
}

sub zoom_fit {
    my $self = shift;
    $self->{zoom_fit} = 1;
    $self->fit_grid();
    $self->post_zoom();
    
    return;
}

sub post_zoom {
    my $self = shift;
    $self->setup_scrollbars();
    $self->reposition();
    $self->resize_background_rect();
    
    return;
}




# Set colouring mode - 'Hue' or 'Sat'
sub set_legend_mode {
    my $self = shift;
    my $mode = shift;
    
    croak "Invalid display mode '$mode'\n"
        if not $mode =~ /^Hue|Sat|Grey$/;
    
    $self->{legend_mode} = $mode;

    $self->colour_cells();

    # Update legend
    if ($self->{legend}) { 
        $self->{legend}->set(pixbuf => $self->make_legend_pixbuf() );
    }
    
    return;
}

=head2 setHue

Sets the hue for the saturation (constant-hue) colouring mode

=cut

sub set_legend_hue {
    my $self = shift;
    my $rgb = shift;

    my @x = (rgb_to_hsv($rgb->red / 257, $rgb->green /257, $rgb->blue / 257));

    my $hue = (rgb_to_hsv($rgb->red / 257, $rgb->green /257, $rgb->blue / 257))[0];
    my $last_hue_used = $self->get_legend_hue;
    return if defined $last_hue_used && $hue == $last_hue_used;

    $self->{hue} = $hue;

    $self->colour_cells();

    # Update legend
    if ($self->{legend}) { 
        $self->{legend}->set(pixbuf => $self->make_legend_pixbuf() );
    }
    
    return;
}

sub get_legend_hue {
    my $self = shift;
    return $self->{hue};
}

1;
