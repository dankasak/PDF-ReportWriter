# vim: ts=8 sw=8 tw=0 ai nu noet
#
# (C) Daniel Kasak: dan@entropy.homelinux.org ...
#  ... with contributions from ( in chronological order )
#       - Bill Hess
#       - Cosimo Streppone
#       - Scott Mazur
#      ( see the changelog for details )
#
# See COPYRIGHT file for full license
#
# See 'man PDF::ReportWriter' for full documentation

use strict;

use warnings;

package PDF::ReportWriter;

use PDF::API2;
use Image::Size;

use Carp;

use Data::Dumper;

BEGIN {
    use Exporter ();
    use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
    $VERSION     = '1.58';
    @ISA         = qw(Exporter);
    @EXPORT      = qw();
    @EXPORT_OK   = qw(
        A4_x A4_y letter_x letter_y bsize_x bsize_y legal_x legal_y
        mm in TRUE FALSE
     );
     %EXPORT_TAGS = (
         Standard => \@EXPORT_OK
     );
}

use constant mm         => 72/25.4;             # 25.4 mm in an inch, 72 points in an inch
use constant in         => 72;                  # 72 points in an inch

use constant A4_x       => 210 * mm;            # x points in an A4 page ( 595.2755 )
use constant A4_y       => 297 * mm;            # y points in an A4 page ( 841.8897 )

use constant letter_x   => 8.5 * in;            # x points in a letter page
use constant letter_y   => 11 * in;             # y points in a letter page

use constant bsize_x    => 11 * in;             # x points in a B size page
use constant bsize_y    => 17 * in;             # y points in a B size page

use constant legal_x    => 11 * in;             # x points in a legal page
use constant legal_y    => 14 * in;             # y points in a legal page

use constant TRUE       => 1;
use constant FALSE      => 0;

sub new {
    
    my ( $class, $options ) = @_;
    
    # Create new object
    my $self = {};
    bless $self, $class;
    
    # Initialize object state
    $self->parse_options($options);
    
    return $self;
}

#
# render_report( $xml, $data_arrayref )
#
# $xml can be either an xml file or any kind of object that
# supports `load()' and `get_data()'
#
# Take report definition, add report data and
# shake well. Your report is ready.
#
sub render_report
{
    
    # Use P::R::Report to handle xml report loading
    require PDF::ReportWriter::Report;
    
    my ( $self, $xml, $data_records ) = @_;
    my $report;
    my $config;
    my $data;
    
    # First parameter can be a report xml filename
    # or PDF::ReportWriter::Report object. Check and load the report profile
    if( ! $xml ) {
        die "Specify an xml report file or PDF::ReportWriter::Report object!";
    }
    
    # $xml is a filename?
    if ( ! ref $xml ) {
        
        # Try loading the report definition file
        unless( $report = PDF::ReportWriter::Report->new({ report => $xml }) ) {
            # Can't load xml report file
            die qq(Can't load xml report file $xml);
         }
    
    # $xml is a PDF::ReportWriter::Report or something that can `load()'?
    } elsif( $xml->can('load') ) {
        
         $report = $xml;
    }
    
    # Try loading the XML report profile and see if something breaks
    eval {
        $config = $report->load();
        #use Data::Dumper;
        #print Dumper($config);
    };
    
    # Report error to user
    if( $@ )
    {
        die qq(Can't load xml report profile from $xml object: $@);
    }

    # Ok, profile "definition" data structure is our hash
    # of main report options
    $self->parse_options( $config->{definition} );
    
    # Profile "data" structure is our hash to be passed
    # render_data() function.
    $data = $config->{data};
    
    # Store report object for later use (resave to xml)
    $self->{__report} = $report;
    
    # If we already have report data, we are done
    if( ! defined $data_records ) {
        
        # Report object's `get_data()' method can be used to populate report data
        # with name of data source to use
        if( $report->can('get_data') ) {
            # XXX Change `detail' in `report', or `main' ??
            $data_records = $report->get_data('detail');
        }
    }
    
    # "data" hash structure must be filled with real records
    $data->{data_array} = $data_records;
    
    # Store "data" section for later use (save to xml)
    $self->{data} =                            # XXX Remove?
    $self->{__report}->{data} = $data;
    
    # Fire!
    $self->render_data( $data) ;
    
}

#
# Returns the current page object (PDF::API2::Page) we are working on
#
sub current_page
{
    my $self = $_[0];
    my $page_list = $self->{pages};

    if( ref $page_list eq 'ARRAY' && scalar @$page_list )
    {
        return $page_list->[ $#$page_list ];
    }
    else
    {
        return undef;
    }
}

sub report
{
    my $self = $_[0];
    return $self->{__report};
}

sub parse_options
{
    
    my ( $self, $opt ) = @_;
    
    # Create a new PDF document if needed
    $self->{pdf} ||= PDF::API2->new;
    
    if ( ! defined $opt )
    {
        return( $self );
    }
    
    # Check for old margin settings and translate to new ones
    if ( exists $opt->{y_margin} ) {
        $opt->{upper_margin} = $opt->{y_margin};
        $opt->{lower_margin} = $opt->{y_margin};
        delete $opt->{y_margin};
    }
    
    if ( exists $opt->{x_margin} ) {
        $opt->{left_margin} = $opt->{x_margin};
        $opt->{right_margin} = $opt->{x_margin};
        delete $opt->{x_margin};
    }
    
    # Store options in the __report member that we will use
    # to export to XML format
    $self->{__report}->{definition} = $opt;
    
    if ( $opt->{paper} eq "A4" ) {
        
        $self->{page_width} = A4_x;
        $self->{page_height} = A4_y;
        
    } elsif ( $opt->{paper} eq "Letter" || $opt->{paper} eq "letter" ) {
        
        $self->{page_width} = letter_x;
        $self->{page_height} = letter_y;
        
    } elsif ( $opt->{paper} eq "bsize" || $opt->{paper} eq "Bsize" ) {
        
        $self->{page_width} = bsize_x;
        $self->{page_height} = bsize_y;
        
    } elsif ( $opt->{paper} eq "Legal" || $opt->{paper} eq "legal" ) {
        
        $self->{page_width} = legal_x;
        $self->{page_height} = legal_y;
        
    # Parse user defined format `150 x 120 mm', or `29.7 x 21.0 cm', or `500X300'
    # Default unit is `mm' unless specified. Accepted units: `mm', `in'
    } elsif ( $opt->{paper} =~ /^\s*([\d\.]+)\s*[xX]\s*([\d\.]+)\s*(\S*)\s*$/ ) {
        
        $self->{page_width}  = $self->format_unit("$1 $3");
        $self->{page_height} = $self->format_unit("$2 $3");
        
    } else {
        die "Unsupported paper format: " . $opt->{paper} . "\n";
    }
    
    # Swap width/height in case of landscape orientation
    if( exists $opt->{orientation} && $opt->{orientation} ) {
        
        if( $opt->{orientation} eq 'landscape' ) {
            ($self->{page_width},  $self->{page_height}) =
            ($self->{page_height}, $self->{page_width});
        } elsif( $opt->{orientation} ne 'portrait' ) {
            die 'Unsupported orientation: ' . $opt->{orientation} . "\n"; 
        }
    }
    
    # translate measurement units
    $opt->{upper_margin} = $self->format_unit($opt->{upper_margin} || 0, $self->{page_height} || 0);
    $opt->{lower_margin} = $self->format_unit($opt->{lower_margin} || 0, $self->{page_height} || 0);
    $opt->{left_margin} = $self->format_unit($opt->{left_margin} || 0, $self->{page_width} || 0);
    $opt->{right_margin} = $self->format_unit($opt->{right_margin} || 0, $self->{page_width} || 0);
    
    # XXX
    # Store some option keys into main object
    # Now this is necessary for all code to work correctly
    #
    for ( qw( destination upper_margin lower_margin left_margin right_margin debug template ) ) {
        $self->{$_} = $opt->{$_}
    }                         
                              
    $self->{print_right_margin} = $self->{page_width} - $self->{right_margin};
    $self->{print_width} = $self->{print_right_margin} - $self->{left_margin};
    $self->{print_height} = $self->{page_height} - $self->{upper_margin} - $self->{lower_margin};
        
    #
    # Now initialize object
    #
    
    # Set some info stuff
    my $localtime = localtime time;
    
    $self->{pdf}->info(
                        Author          => $opt->{info}->{Author},
                        CreationDate    => $localtime,
                        # Should we allow a different creator?
                        Creator         => $opt->{info}->{Creator} || "PDF::ReportWriter $PDF::ReportWriter::VERSION",
                        Keywords        => $opt->{info}->{Keywords},
                        ModDate         => $localtime,
                        Subject         => $opt->{info}->{Subject},
                        Title           => $opt->{info}->{Title}
                      );
    
    # Add requested fonts
    $opt->{font_list} ||= $opt->{font} || [ 'Helvetica' ];
    
    # Requested encoding or default latin1
    $opt->{font_encoding} ||= 'latin1';
    
    for my $font ( @{$opt->{font_list}} ) {
        
        # Roman fonts are easy
        $self->{fonts}->{$font}->{Roman} = $self->{pdf}->corefont(          $font,                  -encoding => $opt->{font_encoding});
        # The rest are f'n ridiculous. Adobe either didn't think about this, or are just stoopid
        if ($font eq 'Courier') {
            $self->{fonts}->{$font}->{Bold} = $self->{pdf}->corefont(       "Courier-Bold",         -encoding => $opt->{font_encoding});
            $self->{fonts}->{$font}->{Italic} = $self->{pdf}->corefont(     "Courier-Oblique",      -encoding => $opt->{font_encoding});
            $self->{fonts}->{$font}->{BoldItalic} = $self->{pdf}->corefont( "Courier-BoldOblique",  -encoding => $opt->{font_encoding});
        }
        if ($font eq 'Helvetica') {
            $self->{fonts}->{$font}->{Bold} = $self->{pdf}->corefont(       "Helvetica-Bold",       -encoding => $opt->{font_encoding});
            $self->{fonts}->{$font}->{Italic} = $self->{pdf}->corefont(     "Helvetica-Oblique",    -encoding => $opt->{font_encoding});
            $self->{fonts}->{$font}->{BoldItalic} = $self->{pdf}->corefont( "Helvetica-BoldOblique",-encoding => $opt->{font_encoding});
        }
        if ($font eq 'Times') {
            $self->{fonts}->{$font}->{Bold} = $self->{pdf}->corefont(       "Times-Bold",           -encoding => $opt->{font_encoding});
            $self->{fonts}->{$font}->{Italic} = $self->{pdf}->corefont(     "Times-Italic",         -encoding => $opt->{font_encoding});
            $self->{fonts}->{$font}->{BoldItalic} = $self->{pdf}->corefont( "Times-BoldItalic",     -encoding => $opt->{font_encoding});
        }
    }
    
    # Default report font size to 12 in case a default hasn't been supplied
    $self->{default_font_size} = $self->format_unit($opt->{default_font_size}) || 12;
    $self->{default_font}      = $opt->{default_font}      || 'Helvetica';
    
    # Mark date/time of document generation
    $self->{__generationtime} = $localtime;
    
    # initialize page structures (text for example)
    $self->{page} = $self->init_page(1);

    return( $self );
    
}

sub setup_cell_definitions {
    
    my ( $self, $cell_array, $type, $group, $split_height ) = @_;
    
    my $x = $self->{left_margin};
    my $row = 0;
    my $cell_counter = 0;
    my $max_cell_height = 0;
    my $row_height = 0;
    my @row_heights;
    
    my $split_flag = 0;
    for my $cell ( @{$cell_array} ) {
        
        # print "Processing cell $cell->{name} " . Dumper( $cell ) . "\n\n";
        
        # The cell's full width ( border to border )
        if ( exists $cell->{width} ) {
            $cell->{full_width} = $self->format_unit($cell->{width}, $self->{print_width});
        }
        elsif ( exists $cell->{percent} ) {  # legacy support
            $cell->{full_width} = $self->format_unit($cell->{percent} . '%', $self->{print_width});
        }

        # TODO is a zero width valid?
        die "No cell width $type: $cell_counter" . ( $cell->{name} ? "($cell->{name})" : "" ) . "\n"
            unless $cell->{full_width};

        # Support multi-line row definitions - watch out for rounding errors
        if ( int($x + $cell->{full_width}) > $self->{print_right_margin} ) {
            push @row_heights, $row_height;
            $row_height = 0;
            $row ++;
            $x = $self->{left_margin};
        }
        
        # format and default x/y
        $cell->{x} = $self->format_unit($cell->{x}, $self->{print_width}) if exists $cell->{x};
        $cell->{y} = $self->format_unit($cell->{y}, $self->{print_height}) if exists $cell->{y};

        # convert measurement units
        # TODO should percent be relative to page or cell or page height?
        $cell->{shift_row_up} = exists $cell->{shift_row_up}
            ? $self->format_unit($cell->{shift_row_up}, $self->{print_height})
            : 0;

        # copy text_margins into text_margin_left and text_margin_right
        if (exists  $cell->{text_margins}) {
            $cell->{text_margin_left} = $cell->{text_margins} unless exists $cell->{text_margin_left};
            $cell->{text_margin_right} = $cell->{text_margins} unless exists $cell->{text_margin_right};
        }

        # format and default text left/right margins
        $cell->{text_margin_left} = exists $cell->{text_margin_left}
            ? $self->format_unit($cell->{text_margin_left}, $self->{print_width})
            : 0;
        $cell->{text_margin_right} = exists $cell->{text_margin_right}
            ? $self->format_unit($cell->{text_margin_right}, $self->{print_width})
            : 0;

        # validate and format align (default align left)

        # default for least surprise
        $cell->{align} = $cell->{text_align} if exists $cell->{text_align} and !exists $cell->{align};

        # align is a cell level format
        $cell->{align} = (exists $cell->{align} and $cell->{align} =~ m/^([lrcj])/i)
            ? uc($1)
            : $type eq 'field_headers' ? 'C' :'L';

        # validate and format align (default inherit cell align)
        $cell->{text_align} = (exists $cell->{text_align} and $cell->{text_align} =~ m/^([lrcj])/i)
            ? uc($1)
            : $cell->{align};

        # validate and format valign (default valign bottom)
        if ( exists $cell->{valign} and $cell->{valign} =~ m/^([c])/i ) {
            carp( "Converting valign attribute 'centre' to 'middle'" );
            $cell->{valign} = 'middle';
        }
        $cell->{valign} = (exists $cell->{valign} and $cell->{valign} =~ m/^([tmb])/i)
            ? uc($1)
            : $type eq 'field_headers' ? 'M' :'B';
          
        # validate and format text_position
        if (exists $cell->{text_position} and $cell->{text_position} =~ m/^([lr])/i) {
           $cell->{text_position} = uc($1);
        }
        else { $cell->{text_position} = '' } # default no text position (overlaps)

        # setup auto margins
        $cell->{auto_margin_left} = $cell->{text_margin_left};
        $cell->{auto_margin_right} = $cell->{text_margin_right};

        $cell->{row} = $row;
        
        # (a split cell uses it's parent border)
        $x = $cell->{x_border} if defined $split_height;

        # The cell's left-hand border position
        $cell->{x_border} = $x;
        
        # The cell's font size - user defined by cell, or from the report default
        if ( exists $cell->{font_size} ) {
            $cell->{font_size} = $self->format_unit($cell->{font_size}, $self->{print_width});
        }
        else {
            $cell->{font_size} = $self->{default_font_size};
        }
        
        # The cell's text whitespace ( the minimum distance between the cell border and cell text )
        # Default to half the font size if not given
        if ( exists $cell->{text_whitespace} ) {
            $cell->{text_whitespace} = $self->format_unit($cell->{text_whitespace}, $self->{print_width});
        }
        else {
            $cell->{text_whitespace} = $cell->{font_size} >> 1;
        }
        
        # The cell's left-hand text position
        $cell->{x_text} = $x + $cell->{text_whitespace};
        
        # The cell's maximum width of text (for now)
        $cell->{text_width} = $cell->{full_width} - ( $cell->{text_whitespace} * 2 ) - $cell->{text_margin_left} - $cell->{text_margin_right};
        
        # TODO maybe these 'type' adjustments should be taken out of here and moved to the caller?
        if ( $type eq "data" ) {
            # Default to the data-level background if there is none defined for this cell
            # We don't do this for page headers / footers, because I don't think this
            # is appropriate default behaviour for these ( ie usually doesn't look good )
            if ( ! $cell->{background} ) {
                $cell->{background} = $self->{data}->{background};
            }

            if ( ! $cell->{filler} ) {
                if (defined $cell->{name}) {
            # Populate the cell_mapping hash so we can easily get hold of fields via their name
                    $self->{data}->{cell_mapping}->{ $cell->{name} } = $cell_counter++;
            }
                else {
                    die "missing data cell name: $cell_counter\n";
            }
            }
            
        } elsif ( $type eq "field_headers" ) {
            if (my $headings = $self->{data}->{headings}) {
                foreach (keys %$headings) {
                    $cell->{$_} = $headings->{$_} unless exists $cell->{$_};
            }
            }
            $cell->{wrap_text} = TRUE;
            $cell->{text} = $cell->{name} unless exists $cell->{text};
        } elsif ( $type eq "group" ) {
            # For aggregate functions, we need the name of the group, which is used later
            # to retrieve the aggregate values ( which are stored against the group,
            # hence the need for the group name ). However when rendering a row,
            # we don't have access to the group *name*, so storing it in the 'text'
            # key is a nice way around this
            if ( exists $cell->{aggregate_source} ) {
                $cell->{text} = $group->{name};
            }
            
            # Initialise group aggregate results
            $cell->{group_results}->{$group->{name}} = 0;
            $cell->{grand_aggregate_result}->{$group->{name}} = 0;
            
        }
        
        # Set 'bold' key for legacy behaviour anything other than data cells and images
#         if ( $type ne "data" && ! $cell->{image} && ! exists $cell->{bold} ) {
#             $cell->{bold} = TRUE;
#         }

        if ( my $image = $cell->{image} ) {
        
            # format/default the image height
            $image->{height} = exists $image->{height}
                ? $self->format_unit($image->{height}, $self->{print_height})
                : 0;
            
            # Default to a buffer of 0.5 to surround images,
            # otherwise they overlap cell borders
            if ( ! exists $image->{buffer} ) {
                $image->{buffer} = 0.5;
            }
            
            # Initialise the tmp hash that we store temporary image dimensions in later
            $image->{tmp} = {};
            
        }
        
        # Convert old 'type' key to the new 'format' key
        # But *don't* do anything with types not listed here. Cosimo is using
        # this key for barcode stuff, and this is handled completely separately of number formatting
        
        if ( exists $cell->{type} ) {
            
            if ( $cell->{type} eq "currency" ) {
                
                carp( "\nEncountered a legacy type key with 'currency'.\n"
                    . " Converting to the new 'format' key.\n"
                    . " Please update your code accordingly\n" );
                
                $cell->{format} = {
                    currency            => TRUE,
                    decimal_places      => 2,
                    decimal_fill        => TRUE,
                    separate_thousands  => TRUE
                };
                
                delete $cell->{type};
                
            } elsif ( $cell->{type} eq "currency:no_fill" ) {
                
                carp( "\nEncountered a legacy type key with 'currency:nofill'.\n"
                    .  " Converting to the new 'format' key.\n"
                    .  " Please update your code accordingly\n\n" );
                
                $cell->{format} = {
                    currency            => TRUE,
                    decimal_places      => 2,
                    decimal_fill        => FALSE,
                    separate_thousands  => TRUE
                };
                
                delete $cell->{type};
                
            } elsif ( $cell->{type} eq "thousands_separated" ) {
                
                carp( "\nEncountered a legacy type key with 'thousands_separated'.\n"
                    .  " Converting to the new 'format' key.\n"
                    .  " Please update your code accordingly\n\n" );
                
                $cell->{format} = {
                  separate_thousands  => TRUE
                };
                
                delete $cell->{type};
                
            }
            
        }
        
        # Calculate cell height depending on type, etc...
        my $height = $self->calculate_cell_height( $cell );
        
        my $reverse_height = $split_height || 0;
        # keep track of reverse offset
        $cell->{split_y_offset_up} = $reverse_height;
        if (my $split_cell = $cell->{split_down}) {
            # force width/percent to match parent
            foreach ( qw(width percent valign) ) { delete $split_cell->{$_} }
            # preload split cell defaults with parent values
            foreach (sort keys %$cell) {
                # don't copy these
                next if m/^(image|text|barcode|split_down|text_height|text_line_height)$/;
                $split_cell->{$_} = $cell->{$_} unless exists $split_cell->{$_};
            }
            if (! $reverse_height) {
                # first cell of the split (top cell)
                # set split_valign for the rest of the split cells
                $cell->{split_valign} = $cell->{valign};
                # The top cell of a vertically centered split is forced to bottom align
                # (hugs the cell below it)
                $cell->{valign} = 'B' if $cell->{valign} eq 'M';
            } elsif ($cell->{split_down}) {
                # Middle cells of a split are are always reduced to content height
                # and vertically defaulted to centered
                $cell->{valign} = 'M';
            }
            # pass the parent valign down through the splits
            $split_cell->{split_valign} = $cell->{split_valign};
            # setup the split cell.  Keep building the offsets down
            my $split_height = $self->setup_cell_definitions([$split_cell], $type, $group, $reverse_height + $height);
            # remember the split cell height
            $cell->{split_y_offset_down} = $split_height;
            # total up the cell heights
            $height += $split_height;
        } else {
            $cell->{split_y_offset_down} = 0;
            if ($reverse_height) {
                # last cell of the split (bottom cell)
                # The bottom cell of a top or centered split is forced to top align
                # (hugs the cell above it)
                $cell->{valign} = 'T' if $cell->{split_valign} =~ m/[TM]/;
            } else {
                $cell->{split_valign} = ''
            }
        }
        
        $row_height = $height if $height > $row_height;
        $max_cell_height = $height if $height > $max_cell_height;

        # Move along to the next position
        $x += $cell->{full_width};

    }
    
    push @row_heights, $row_height;

    # now map the row_height into each cell
    map { $_->{row_height} = $row_heights[$_->{row}] } @{$cell_array};

    return $max_cell_height;
}

sub render_data {
    
    my ( $self, $data ) = @_;
    
    $self->{data} = $data;
    
    $data->{cell_height} = 0;
    
    # Complete field definitions ...
    # ... calculate the position of each cell's borders and text positioning
    
    # Create a default background object if $self->{cell_borders} is set ( ie legacy support )
    if ( $data->{cell_borders} ) {
        $data->{background} = { border => "grey" };
    }
    
    # Normal cells
    # We also need to set the data-level max_cell_height
    # This refers to the height of the actual cell ...
    #  ... ie ie it doesn't include upper_buffer and lower_buffer whitespace

    $data->{max_cell_height} = $self->setup_cell_definitions( $data->{fields}, "data" );

    # Set up data-level upper_buffer and lower_buffer values
    foreach (qw(upper_buffer lower_buffer)) {
        $data->{$_} = exists $data->{$_}
            ? $self->format_unit($data->{$_}, $self->{print_height})
            : 0; # Default to 0, which was the previous behaviour
    }
    
    # Field headers
    if ( ! $data->{no_field_headers} ) {
        # Construct the field_headers definition if required ...
        #  ... ie provide legacy behaviour if no field_headers array provided
        if ( ! $data->{field_headers} ) {
            foreach my $field ( @{$data->{fields}} ) {
                push @{$data->{field_headers}},
                {
                    name                => $field->{name},
                    text                => $field->{name}, # this helps in the calculation of heights of headers
                    percent             => $field->{percent},
                    bold                => TRUE,
                    font_size           => $field->{font_size},
                    text_whitespace     => $field->{text_whitespace},
                    align               => $field->{header_align} || $field->{align} || 'centre',
                    text_align          => $field->{header_text_align} || $field->{text_align},
                    valign              => $field->{header_valign} || $field->{valign},
                    colour              => $field->{header_colour} || $field->{colour}
                };
            }
        }

        # And now continue with the normal setup ...

        $data->{max_field_header_height} = $self->setup_cell_definitions( $data->{field_headers}, "field_headers" );

        # Set up field_header upper_buffer and lower_buffer values

        foreach (qw(field_headers_upper_buffer field_headers_lower_buffer)) {
            $data->{$_} = exists $data->{$_}
                ? $self->format_unit($data->{$_}, $self->{print_height})
                : 0; # Default to 0
    }
    
    }
    
    # Page headers
    if ( $data->{page}->{header} ) {
        $data->{page_header_max_cell_height} = $self->setup_cell_definitions( $data->{page}->{header}, "page_header" );
    }
        
    $self->{page_footer_and_margin} = $self->{lower_margin};
        
    # Page footers
    if ( ! $data->{page}->{footerless} ) {
        if ( ! $data->{page}->{footer} ) {
        
        # Set a default page footer if we haven't been explicitely told not to
            $data->{cell_height} = 12; # Default text_whitespace of font size * .5
        
            $data->{page}->{footer} = [
            {
                percent         => 50,
                font_size       => 8,
                text            => "Rendered on \%TIME\%",
                align           => 'left',
                bold            => FALSE
            },
            {
                percent         => 50,
                font_size       => 8,
                text            => "Page \%PAGE\% of \%PAGES\%",
                align           => 'right',
                bold            => FALSE
            }
        ];
                                          
        }

        my $max_cell_height = $self->setup_cell_definitions( $data->{page}->{footer}, 'page_footer' );

        $self->{page_footer_and_margin} += $max_cell_height;
        $data->{page_footer_max_cell_height} = $max_cell_height;

    }
    
    # Groups
    for my $group ( @{$data->{groups}} ) {
        
        for my $group_type ( qw ( header footer ) ) {
            if ( $group->{$group_type} ) {
                $group->{$group_type . "_max_cell_height"} =
                    $self->setup_cell_definitions( $group->{$group_type}, 'group', $group );

                # Set up upper_buffer and lower_buffer values on groups

                foreach ($group_type . '_upper_buffer', $group_type . '_lower_buffer') {
                    $data->{$_} = exists $data->{$_}
                        ? $self->format_unit($data->{$_}, $self->{print_height})
                        : 0; # Default to 0 - legacy behaviour
                }

            }
        }
        # Set all group values to a special character so we recognise that we are entering
        # a new value for each of them ... particularly the GrandTotal group
        $group->{value} = '!';
        
        # Set the data_column of the GrandTotals group so the user doesn't have to specify it
        
        next unless $group->{name} eq 'GrandTotals';
        
        # Check that there is at least one record in the data array, or this assignment triggers
        # an error about undefined ARRAY reference...
        
        my $data_ref = $data->{data_array};
        if (
            ref ( $data_ref )      eq 'ARRAY'
             && ref ( $data_ref->[0] ) eq 'ARRAY'
        ) {
            $group->{data_column} = scalar ( @{( $data_ref->[0] )} );
        }
    }
    
    # Create an array for the group header queue ( otherwise new_page() won't work so well )
    $self->{group_header_queue} = [];
    
    # Create a new page if we have none ( ie at the start of the report )
    if ( ! $self->{pages} ) {
        $self->new_page;
    }
    
    my $row_counter = 0;
    
    # Reset the 'need_data_header' flag - if there aren't any groups, this won't we reset
    $self->{need_data_header} = TRUE;
    
    # Main loop
    for my $row ( @{$data->{data_array}} ) {
        
        # Assemble the Group Header queue ... firstly assuming we *don't* require
        # a page break due to a lack of remaining paper. assemble_group_header_queue()
        # returns whether any of the new groups encounted have requested a page break
        
        my $want_new_page = $self->assemble_group_header_queue(
            $row,
            $row_counter,
            FALSE
        );
        
        if ( ! $want_new_page ) {
            
            # If none of the groups specifically requested a page break, check
            # whether everything will fit on the page
            
            # TODO: we're double dipping here.
            #  calculate_y_needed() now, then repeat again render_row
            my $size_calculation = $self->calculate_y_needed(
                {
                    cells               => $data->{fields},
                    max_cell_height     => $data->{max_cell_height},
                    row                 => $row
                }
            );
            
            if ( $self->{y} - ( $size_calculation->{y_needed} + $self->{page_footer_and_margin} ) < 0 ) {
                
                # Our 1st set of queued headers & 1 row of data spills over the page.
                # We need to re-create the group header queue, and force $want_new_page
                # so that assemble_group_header_queue() knows this and adds all headers
                # that we need ( ie so we pick up reprinting headers that may not have been
                # added in the first pass because it wasn't known at the time that we were
                # taking a new page
                
                # First though, we have to reset the group values in all currently queued headers,
                # so they get re-detected on the 2nd pass
                foreach my $queued_group ( @{$self->{group_header_queue}} ) {
                    
                    # Loop through our groups to find the one with the corresponding name
                    # TODO We need to create a group_mapping hash so this is not required
                    foreach my $group ( @{$data->{groups}} ) {
                        if ( $group->{name} eq $queued_group->{group}->{name} ) {
                            $group->{value} = "!";
                        }
                    }
                    
                }
                
                $self->{group_header_queue} = undef;
                
                $want_new_page = $self->assemble_group_header_queue(
                    $row,
                    $row_counter,
                    TRUE
                );
                
            }
            
        }
        
        # We're using $row_counter here to detect whether we've actually printed
        # any data yet or not - we don't want to page break on the 1st page ...
        if ( $want_new_page && $row_counter ) {
            $self->new_page;
        }

        $self->render_row(
            $data->{fields},
            $row,
            'data',
            $data->{max_cell_height},
            $data->{upper_buffer},
            $data->{lower_buffer}
        );
        
        # Reset the need_data_header flag after rendering a data row ...
        #  ... this gets reset when entering a new group
        $self->{need_data_header} = FALSE;
        
        $row_counter ++;
        
    }
    
    # The final group footers will not have been triggered ( only happens when we get a *new* group ), so we do them now
    foreach my $group ( reverse @{$data->{groups}} ) {
        if ( $group->{footer} ) {
            $self->group_footer($group);
        }
    }
    
    # Move down some more at the end of this pass
    # why??
    #$self->{y} -= $data->{max_cell_height};
    
}

sub assemble_group_header_queue {
    
    my ( $self, $row, $row_counter, $want_new_page ) = @_;
     
    foreach my $group ( reverse @{$self->{data}->{groups}} ) {
        
        # If we've entered a new group value, * OR *
        #   - We're rendering gruop heavers because a new page has been triggered
        #       ( $want_new_page is already set - by a lower-level group ) * AND *
        #   - This group has the 'reprinting_header' key set
        
        #if ( $want_new_page && $group->{reprinting_header} ) {
            
        if ( ( $group->{value} ne $$row[$group->{data_column}] ) || ( $want_new_page && $group->{reprinting_header} ) ) {
            
            # Remember to page break if we've been told to
            if ( $group->{page_break} ) {
                $want_new_page = TRUE;
            }
            
            # Only do a group footer if we have a ( non-zero ) value in $row_counter
            #  ( ie if we've rendered at least 1 row of data so far )
            # * AND * $want_new_page is NOT set
            # If $want_new_page IS set, then this is our 2nd run through here, and we've already
            # printed group footers
            
            if ( $row_counter && $group->{footer} && ! $want_new_page ) {
                $self->group_footer($group);
            }
            
            # Queue headers for rendering in the data cycle
            # ... prevents rendering a header before the last group footer is done
            if ( $group->{header} ) {
                push
                    @{$self->{group_header_queue}},
                    {
                        group => $group,
                        value => $$row[$group->{data_column}]
                    };
            }
            
            $self->{need_data_header} = TRUE; # Remember that we need to render a data header afterwoods
            
            # If we're entering a new group, reset group totals
            if ( $group->{value} ne $$row[$group->{data_column}] ) {
                for my $field ( @{ $self->{data}->{fields} } ) {
                    $field->{group_results}->{$group->{name}} = 0;
                }
            }
            
            # Store new group value
            $group->{value} = $$row[$group->{data_column}];
            
        }
        
    }
    
    return $want_new_page;
    
}

sub fetch_group_results {
    
    my ( $self, $options ) = @_;
    
    # This is a convenience function that returns the group aggregate value
    # for a given cell / group combination
    
    # First do a little error checking
    if ( ! exists $self->{data}->{cell_mapping}->{ $options->{cell} } ) {
        carp( "\nPDF::ReportWriter::fetch_group_results called with an invalid cell: $options->{cell}\n\n" );
        return;
    }
    
    if ( ! exists $self->{data}->{fields}[ $self->{data}->{cell_mapping}->{ $options->{cell} } ]->{group_results}->{ $options->{group} } ) {
        caro( "\nPDF::ReportWriter::fetch_group_results called with an invalid group: $options->{group} ...\n"
            . " ... check that the cell $options->{cell} has an aggregate function defined, and that the group $options->{group} exists\n" );
        return;
    }
    
    return $self->{data}->{fields}[ $self->{data}->{cell_mapping}->{ $options->{cell} } ]->{group_results}->{ $options->{group} };
    
}

# Define a new page like the PDF template (if template is specified)
# or create a new page from scratch...
sub page_template
{
    
    my $self     = shift;
    my $pdf_tmpl = shift || $self->{template}; # TODO document page_template and optional override
    my $new_page;
    my $user_warned = 0;
    
    if(defined $pdf_tmpl && $pdf_tmpl)
    {
        
        # Try to open template page

        # TODO Cache this object to include a new page without
        #      repeated opening of template file
        if( my $pdf_doc = PDF::API2->open($pdf_tmpl) )
        {
            # Template opened, import first page
            $new_page = $self->{pdf}->importpage($pdf_doc, 1);
        }

        # Warn user in case of invalid template file
        unless($new_page || $user_warned)
        {
            warn "Defined page template $pdf_tmpl not valid. Creating empty page.";
            $user_warned = 1;
        }
        
    }
    
    # Generate an empty page if no valid page was extracted
    # from the template or there was no template...
    $self->{pdf} ||= PDF::API2->new();                     # XXX
    $new_page    ||= $self->{pdf}->page;
    
    return ($new_page);
    
}

sub init_page {
    my ($self, $init_only_flg) = @_;
    
    my $page = 0;
    
    if ($self->{page}) {
        # when the ReportWriter object is created it initializes the page
        # to get layout methods (fonts in particular)
        # re-use this page now
        $page = $self->{page};
        delete $self->{page};
    }
    else {
    # Create a new page	and eventually apply pdf template
        $page = $self->page_template;
    
    # Set page dimensions
    $page->mediabox( $self->{page_width}, $self->{page_height} );
    
    # Create a new txt object for the page
        # TODO this is done in new() do we really need it here too?
    $self->{txt} = $page->text;
    
    # Create a new gfx object for our lines
    $self->{line} = $page->gfx;
    
    # And a shape object for cell backgrounds and stuff
    # We *need* to call ->gfx with a *positive* value to make it render first ...
    #  ... otherwise it won't be the background - it will be the foreground!
    $self->{shape} = $page->gfx(1);
    
        # re-use the initialization page later
        $self->{page} = $page if $init_only_flg;
    }

    # Remember that we need to print a data header
    $self->{need_data_header} = TRUE;

    # Set y to the top of the page
    $self->{y} = $self->{page_height} - $self->{upper_margin};

    return $page;
}

sub new_page {
    my $self = shift;

    # remember the current y value in case footers are attached
    my $current_y = $self->{y};

    my $page = $self->init_page;
    my $data = $self->{data};
    my $data_page = $data->{page};

    # Append our page footer definition to an array - we store one per page, and render
    # them immediately prior to saving the PDF, so we can say "Page n of m" etc
    # (but only if we've got footers to begin with!)

    # remember the current y value (which happens to belong to the previous page)
    push @{$self->{page_footers}}, {cells => $data_page->{footer}, y => $current_y}
        unless $data_page->{footerless};
    
    # Push new page onto array of pages
    push @{$self->{pages}}, $page;
    
    # Render page header if defined
    if ( $data_page->{header} ) {
        $self->render_row(
            $data_page->{header},
            undef,
            'page_header',
            $data->{page_header_max_cell_height},
            0, # Page headers don't need
            0  # upper / lower buffers
            # TODO Should we should add upper / buffers to page headers?
         );
    }

    # Renderer any group headers that have been set as 'reprinting_header'
    # ( but not if the group has the special value ! which means that we haven't started yet,
    # and also not if we've got group headers already queued )
    for my $group ( @{$self->{data}->{groups}} ) {
            if ( ( ! $self->{group_header_queue} )
                    && ( $group->{reprinting_header} )
                    && ( $group->{value} ne "!" )
               ) {
                    $self->group_header( $group );
            }
    }
    
    return( $page );
    
}

sub group_header {
    
    # Renders a new group header
    
    my ( $self, $group ) = @_;
    
    if ( $group->{name} ne 'GrandTotals' ) {
        $self->{y} -= $group->{header_upper_buffer};
    }
    
    $self->render_row(
        $group->{header},
        $group->{value},
        'group_header',
        $group->{header_max_cell_height},
        $group->{header_upper_buffer},
        $group->{header_lower_buffer}
    );
    
    $self->{y} -= $group->{header_lower_buffer};
    
}

sub group_footer {
    
    # Renders a new group footer
    
    my ( $self, $group ) = @_;
    
    my $y_needed = $self->{page_footer_and_margin}
        + $group->{footer_max_cell_height}
        + $group->{footer_upper_buffer}
        + $group->{footer_lower_buffer};
    
    if ( $y_needed <= $self->{page_height} && $self->{y} - $y_needed < 0 ) {
        $self->new_page;
    }
    
    $self->render_row(
        $group->{footer},
        $group->{value},
        'group_footer',
        $group->{footer_max_cell_height},
        $group->{footer_upper_buffer},
        $group->{footer_lower_buffer}
     );
    
}

sub set_cell_text_height {
    
    # Tries to calculate cell text height for a given string depending on different cell properties.
    my ( $self, $cell, $string ) = @_;
    
    $string = '' unless defined $string;
    
    $string =~ s/\015\012?|\012/\n/g; # funky line return variations
    
    if ( $cell->{wrap_text} ) {
        # We need to set the font here so that wrap_text() can accurately calculate where to wrap
        $self->{txt}->font( $self->get_cell_font($cell), $cell->{font_size} );
        
        $string = $self->wrap_text(
            {
                string          => $string,
                text_width      => $cell->{text_width},
                strip_breaks    => $cell->{strip_breaks}
            }
        );
    }
    
    my $text_height = $cell->{text_line_height} = $cell->{font_size} + $cell->{text_whitespace};
    my @text_rows = split /\n/, $string;
    
    $text_height *= @text_rows if @text_rows;
    
    # remember the text_height for later
    return $cell->{text_height} = $text_height, \@text_rows;
}

sub calculate_cell_height {
    
    # Tries to calculate maximum cell height depending on different cell types and properties.
    my ( $self, $cell ) = @_;
    
    # minimum height
    my $height = 0;

    # If cell is a barcode, height is given by its "zone" (height of the bars)
    if ( exists $cell->{barcode} ) {
        # TODO This calculation should be done adding upper mending zone,
        #       lower mending zone, font size and bars height, but probably
        #       we don't have them here...
        my $bar_height = $cell->{zone} + 25;
        $height = $bar_height if $bar_height > $height;
    }
    
    # default height to one text line regardless of whether there's text or not
    #  question: why? Maybe an empty cell should be squashed?
    #  answer: because I print empty lines, damnit!
    #   ... basically, I render text such as:
    # "This is some text\n\n\nI'm more text, but not directly underneath"
    
    # If you *really* want to squash empty cells, then this *must* be made
    # an option ( defaulted to OFF ) so it doesn't break a considerable number
    # of production reports
    
    my ( $text_height ) = $self->set_cell_text_height( $cell, $cell->{text} );
        
    # find the maximum height for the cell
    $height = $text_height if $text_height > $height;
        
    return $cell->{content_height} = $height;
    
}

sub calculate_y_needed {
    
    my ( $self, $options ) = @_;
    
    # TODO OPTIMISATION: cache calculate_y_needed() values
    # We need to revisit this calculate_y_needed(), or more specifically
    # our callers. We are called *way* too many times. We should be caching the
    # values somewhere and using them instead of continually recalculating.
    
    # This function calculates the y-space needed to render a particular row,
    # and returns it to the caller in the form of:
    # {
    #    current_height  => $current_height,        # LEGACY!
    #    y_needed        => $y_needed,
    #    row_heights     => \@row_heights
    # };
    
    # Unpack options hash
    my $cells               = $options->{cells};
    my $max_cell_height     = $options->{max_cell_height};
    my $row                 = $options->{row};
    
    # We've just been passed the max_cell_height
    # This will be all we need if we are
    # only rendering single-line text
    
    # In the case of data render cycles,
    # the max_cell_height is taken from $self->{data}->{max_cell_height},
    # which is in turn set by setup_cell_definitions(),
    # which goes over each cell with calculate_cell_height()
    
    my $current_height = 0;
    
    # Search for an image in the current row
    # If one is encountered, adjust our $y_needed according to scaling definition
    
    my $counter = 0;
    my @row_heights;
    my @row_shifts;
    my $current_row = -1;

    my $true_value = 0; # keep track of value status for print_if_true
    my $row_render = 1;
    
    for my $cell ( @{$options->{cells}} ) {
        
        if ( $current_row != $cell->{row} ) {
            if ( !$row_render ) {
                # the last row wasn't rendered (print_if_true), zero the line height
                $row_heights[$current_row] = $row_shifts[$current_row] = 0;
            }
            $current_row = $cell->{row};
            $current_height = $cell->{auto_row_height} ? $cell->{row_height} : $max_cell_height;
            $row_heights[$current_row] = $row_shifts[$current_row] = 0;
            $row_render = 0;
        }
        
        if ( my $image = $cell->{image} ) {
            
            # Use this to accumulate image temporary data
            my %imgdata;

            my $buffer_fill = $image->{buffer} * 2;
            # Support dynamic images ( image path comes from data array )
            # Note: $options->{row} won't necessarily be a data array ...
            #  ... it will ONLY be an array if we're rendering a row of data
            
            if ( $image->{dynamic} && ref $options->{row} eq "ARRAY" ) {
                $image->{path} = $options->{row}->[$counter];
                $true_value = 1;
# Commented out, as it's double-incrementing counter ( gets incremented below )
#                $counter++;
            }
            $row_render++;
            
            # TODO support use of images in memory instead of from files?
            # Is there actually a use for this? It's possible that images could come
            # from a database, or be created on-the-fly. Wait for someone to request
            # it, and then get them to implement it :)
            
            # Only do imgsize() calculation if this is a different path from last time ...
            if ( ( ! $imgdata{img_x} ) || ( $image->{path} && $image->{path} ne $image->{previous_path} ) ) {
                (
                    $imgdata{img_x},
                    $imgdata{img_y},
                    $imgdata{img_type}
                ) = imgsize( $image->{path} );
                # Remember that we've calculated 
                $image->{previous_path} = $image->{path};
            }
            
            # Deal with problems with image
            if ( ! $imgdata{img_x} ) {
                warn "Image $image->{path} had zero width ... setting to 1\n";
                $imgdata{img_x} = 1;
            }
            
            if ( ! $imgdata{img_y} ) {
                warn "Image $image->{path} had zero height ... setting to 1\n";
                $imgdata{img_y} = 1;
            }
            
            if ( $self->{debug} ) {
                print "Image $image->{path} is $imgdata{img_x} x $imgdata{img_y}\n";
            }
            
            if ( $image->{height} ) {
                
                # The user has defined an image height
                $imgdata{y_scale_ratio} = ( $image->{height} - $buffer_fill ) / $imgdata{img_y};
                
            } elsif ( $image->{scale_to_fit} ) {
                
                # We're scaling to fit the current cell
                $imgdata{y_scale_ratio} = ( $current_height - $buffer_fill ) / $imgdata{img_y};
                
            } else {
                
                # no scaling or hard-coded height defined
                
                # TODO Check with Cosimo: what's the << operator for here?
                #if ( ( $imgdata{img_y} + $image->{buffer} << 1 ) > ( $self->{y} - $self->{page_footer_and_margin} ) ) {
                my $max_height_available = $self->{y} - $self->{page_footer_and_margin} - $buffer_fill;
                if ( $imgdata{img_y} > $max_height_available ) {
                    #$imgdata{y_scale_ratio} = ( $imgdata{img_y} + $image->{buffer} << 1 ) / ( $self->{y} - $self->{page_footer_and_margin} );
                    #$imgdata{y_scale_ratio} = ( $self->{y} - $self->{page_footer_and_margin} ) / ( $imgdata{img_y} + ( $image->{buffer} *2 ) );
                    $imgdata{y_scale_ratio} = $max_height_available / $imgdata{img_y};

                    # adjust height of this cell
                    $current_height = $max_height_available if $max_height_available > $current_height;

                } else {
                    $imgdata{y_scale_ratio} = 1;
                }
                
            };
            
            if ( $self->{debug} ) {
                print "Current height ( before adjusting for this image ) is $current_height\n";
                print "Y scale ratio = $imgdata{y_scale_ratio}\n";
            }
            
            # A this point, no matter what scaling, fixed size, or lack of
            # other instructions, we still have to test whether the image will fit
            # length-wise in the cell
            
            $imgdata{x_scale_ratio} = ( $cell->{full_width} - $buffer_fill ) / $imgdata{img_x};
            
            if ( $self->{debug} ) {
                print "X scale ratio = $imgdata{x_scale_ratio}\n";
            }
            
            # Choose the smallest of x & y scale ratios to ensure we'll fit both ways
            $imgdata{scale_ratio} = $imgdata{y_scale_ratio} < $imgdata{x_scale_ratio}
                ? $imgdata{y_scale_ratio}
                : $imgdata{x_scale_ratio};

            if ( $self->{debug} ) {
                print "Smallest scaling ratio is $imgdata{scale_ratio}\n";
            }
            
            # Set our new image dimensions based on this scale_ratio,
            # but *DON'T* overwrite the original dimensions ...
            #  ... we're caching these for later re-use
            $imgdata{this_img_x} = $imgdata{img_x} * $imgdata{scale_ratio};
            $imgdata{this_img_y} = $imgdata{img_y} * $imgdata{scale_ratio};

            # full size of final image
            my $image_width = $imgdata{this_img_x} + $buffer_fill;
            my $image_height = $imgdata{this_img_y} + $buffer_fill;

            if ( $self->{debug} ) {
                print "New dimensions:\n Image X: $imgdata{this_img_x}\n Image Y: $imgdata{this_img_y}\n";
                print " New height: $current_height\n";
            }
            
            # Store image data for future reference
            $image->{tmp} = \%imgdata;
            
            # adjust auto_margin to float text around image
            # TODO what about justified?
            $row_heights[$current_row] = $current_height if $current_height > $row_heights[$current_row];
            
            if ( $cell->{align} eq 'L' and $cell->{text_position} eq 'R' ) {
                
                $cell->{auto_margin_left} = $cell->{text_margin_left} + $image_width;
                $cell->{text_width} = $cell->{full_width} - ( $cell->{text_whitespace} * 2 )
                        - $cell->{auto_margin_left} - $cell->{auto_margin_right};
                
            } elsif ( $cell->{align} eq 'R' and $cell->{text_position} eq 'L' ) {
                
                $cell->{auto_margin_right} = $cell->{text_margin_right} + $image_width;
                $cell->{text_width} = $cell->{full_width} - ( $cell->{text_whitespace} * 2 )
                        - $cell->{auto_margin_left} - $cell->{auto_margin_right};
                
            } elsif ($cell->{align} eq 'C') {
                
                if ( $cell->{text_position} eq 'L' ) {
                    
                    $cell->{auto_margin_right} = $cell->{text_margin_right} + $image_width;
                    $cell->{text_width} = $cell->{full_width} - ( $cell->{text_whitespace} * 2 )
                            - $cell->{auto_margin_left} - $cell->{auto_margin_right};
                    
                } elsif ( $cell->{text_position} eq 'R' ) {
                    
                    $cell->{auto_margin_left} = $cell->{text_margin_left} + $image_width;
                    $cell->{text_width} = $cell->{full_width} - ( $cell->{text_whitespace} * 2 )
                            - $cell->{auto_margin_left} - $cell->{auto_margin_right};
                    
                }
                
            }

            # adjust the cell height for the image size
            $current_height = $image_height if $image_height > $current_height;

        }
            
        # combine image and text in same cell to get height
        
        # If $options->{row} has been passed ( and is an array ), we're in a data-rendering cycle
        
        my $text_string;
        
        if ( ref $row eq "ARRAY" ) {
            if ($cell->{filler}) {
                # A filler cell may also contain text?
                $text_string = $cell->{text};
            } else {
                # get text height from data
                $text_string = $$row[$counter];
                $true_value = $text_string ? 1 : 0 unless $true_value;
                $counter++;
            }
            $row_render++ if $true_value or ! $cell->{print_if_true};
        } else {
            $row_render++;
        }
            
        my ($text_height) = $self->set_cell_text_height($cell, $text_string);
            
        # adjust the cell height for the text size
        $current_height = $text_height if $text_height > $current_height;
            
        $row_heights[$current_row] = $current_height if $current_height > $row_heights[$current_row];
        
        # TODO check if shift_row_up is a positive number first!
        if ( $cell->{shift_row_up} and $cell->{shift_row_up} > $row_shifts[$current_row] ) {
            $row_shifts[$current_row] = $cell->{shift_row_up};
        }
    }
        
    if ( ! $row_render ) {
        # the last row wasn't rendered (print_if_true), zero the line height
        $row_heights[$current_row] = 0;
    }
        
    # add up the rows to get the total height
    $current_height = 0;
    foreach ( @row_heights ) {
        $current_height += $_;
    }
    
    # account for any row shifting
    # FIXME this is not right!
#     foreach (@row_shifts) {
#         $current_height -= $_;
#     }

    # If we have queued group headers, calculate how much Y space they need
    
    # Note that at this point, $current_height is the height of the current row
    # We now introduce $y_needed, which is $current_height, PLUS the height of headers, buffers, etc
    
    my $y_needed = $current_height + $self->{data}->{upper_buffer} + $self->{data}->{lower_buffer};
    
    # TODO this will not work if there are *unscaled* images in the headers
    # Is it worth supporting this as well? Maybe.
    # Maybe later ...
    
    if ( $self->{group_header_queue} ) {
        for my $header ( @{$self->{group_header_queue}} ) {
            # For the headers, we take the header's max_cell_height,
            # then add the upper & lower buffers for the group header
            $y_needed += $header->{group}->{header_max_cell_height}
                + $header->{group}->{header_upper_buffer}
                + $header->{group}->{header_lower_buffer};
        }
        # And also the data header if it's turned on
        if ( ! $self->{data}->{no_field_headers} ) {
            $y_needed += $max_cell_height;
        }
    }
    
    return {
        current_height  => $current_height,
        y_needed        => $y_needed,
        row_heights     => \@row_heights,
        row_shifts      => \@row_shifts
    };
    
}

sub render_row {
    
    my ( $self, $cells, $row, $type, $max_cell_height, $upper_buffer, $lower_buffer ) = @_;
    
    # $cells            - a hash of cell definitions
    # $row              - the current row to render
    # $type             - possible values are:
    #                       - header                - prints a row of field names
    #                       - data                  - prints a row of data
    #                       - group_header          - prints a row of group header
    #                       - group_footer          - prints a row of group footer
    #                       - page_header           - prints a page header
    #                       - page_footer           - prints a page footer
    # $max_cell_height  - the height of the *cell* ( not including buffers )
    # upper_buffer      - amount of whitespace to leave above this row
    # lower_buffer      - amount of whitespace to leave after this row
    
    # In the case of page footers, $row will be a hash with useful stuff like
    # page number, total pages, time, etc
    
    # Calculate the y space required, including queued group footers

    # TODO OPTIMISE: we're double dipping here.
    #  calculate_y_needed() performed in render_data, and now again
    my $size_calculation = $self->calculate_y_needed(
        {
            cells           => $cells,
            max_cell_height => $max_cell_height,
            row             => $row
        }
    );
    
    # Page Footer / New Page / Page Header if necessary, otherwise move down by $current_height
    # ( But don't force a new page if we're rendering a page footer )
    
    # Check that total y space needed does not exceed page size.
    # In that case we cannot keep adding more pages, which causes
    # horrible out of memory errors
    
    # TODO Should this be taken into account in calculate_y_needed?
    $size_calculation->{y_needed} += $self->{page_footer_and_margin};

    if ( $type ne 'page_footer'
            && $size_calculation->{y_needed} <= $self->{page_height}
            && $self->{y} - $size_calculation->{y_needed} < 0
       )
    {
        $self->new_page;
    }

    # Trigger any group headers that we have queued, but ONLY if we're in a data cycle
    if ( $type eq "data" ) {
        while ( my $queued_headers = pop @{$self->{group_header_queue}} ) {
            $self->group_header( $queued_headers->{group}, $queued_headers->{value} );
        }
    }
    
    if ( $type eq "data" && $self->{need_data_header} && ! $self->{data}->{no_field_headers} ) {
        
        # If we are in field headers section, leave room as specified by options
        $self->{y} -= $self->{data}->{field_headers_upper_buffer};
        
        # Now render field headers row
        $self->render_row(
            $self->{data}->{field_headers},
            0,
            'field_headers',
            $self->{data}->{max_field_header_height},
            $self->{data}->{field_header_upper_buffer},
            $self->{data}->{field_header_lower_buffer}
        );
        
    }
    
    # Move down for upper_buffer, and then for the current row height
#    $self->{y} -= $upper_buffer + $current_height;
    
    # Move down for upper_buffer, and then for the FIRST row height
    $self->{y} -= $upper_buffer if $upper_buffer;
    
    #
    # Render row
    #
    
    # Prepare options to be passed to *all* cell rendering methods
    my $options = {
        current_row         => $row,
        row_type            => $type,       # Row type (data, header, group, footer)
        cell_y_border       => $self->{y},
        page                => $self->{pages}->[ scalar( @{$self->{pages}} ) - 1 ],
        page_no             => scalar( @{$self->{pages}} ) - 1
    };
    
    my $this_row = -1; # Forces us to move down immediately
    
    my $data_index = 0;
    my $true_value = 0; # keep track of value status for print_if_true
    my $row_render = 1;
    for my $cell ( @{$cells} ) {
        
        # If we're entering a new line ( ie multi-line rows ),
        # then shift our Y position and set the new cell_full_height
        
        if ( $this_row != $cell->{row} ) {
            if (!$row_render) {
                # the last row wasn't rendered (print_if_true), reverse the line movement
                $self->{y} += $size_calculation->{row_heights}[ $this_row ];
                $self->{y} -= $size_calculation->{row_shifts}[ $this_row ];
            }
            $this_row = $cell->{row};
            $self->{y} -= $size_calculation->{row_heights}[ $this_row ];
            $self->{y} += $size_calculation->{row_shifts}[ $this_row ];
            $options->{cell_full_height} = $size_calculation->{row_heights}[ $this_row ];
            $row_render = 0;
        }
        
        $options->{cell} = $cell;
        
        # TODO Apparent we're not looking in 'text' key for hard-coded text any more. Add back ...
        if (!$cell->{filler} and ref( $row ) eq 'ARRAY') {
            $options->{current_value} = '';
            $true_value = $options->{current_value} = $row->[ $data_index++ ];
        }
        else {
            delete $options->{current_value};
        }
        
        #} else {
        #} else {
        #   warn 'Found notref value '.$options->{current_row};
        #   $options->{current_value} = $options->{current_row}->[ $options->{cell_counter} ];
        #   $options->{current_value} = $options->{current_row};
        #}
        
        # check print_if_true setting
        if ($type ne 'data' or !$cell->{print_if_true} or $true_value) {
        $self->render_cell( $cell, $options );
            $row_render++;
        }
        
    }
    
    # Move down for the lower_buffer
    $self->{y} -= $lower_buffer if $lower_buffer;
    
}

sub render_cell {
    
    my ( $self, $cell, $options ) = @_;
    
    # set the cell position and dimensions
    $self->cell_set_box($cell, $options);

    # Render cell background ( an ellipse, box, or cell borders )
    if ( exists $cell->{background} ) {
        $self->render_cell_background( $cell, $options );
    }
    
    # Run custom render functions and see if they return anything
    if ( exists $cell->{custom_render_func} ) {
        
        # XXX Here to unify all the universal forces, the first parameter
        # should be the cell "object", then all the options, even if options
        # already contains a "cell" object
        my $func_return = $cell->{custom_render_func}( $options );
        
        if ( ref $func_return eq "HASH" ) {
            
            # We've received a return hash with instructions on what to do
            if ( exists $func_return->{render_text} ) {
                
                # We've been passed some text to render. Shove it into the current value and continue
                $options->{current_value} = $func_return->{render_text};
                
            } elsif ( exists $func_return->{render_image} ) {
                
                # We've been passed an image hash. Copy each key in the hash back into the cell and continue
                foreach my $key ( keys %{$func_return->{render_image}} ) {
                    $cell->{image}->{$key} = $$func_return->{render_image}->{$key};
                }
                
            } elsif ( exists $func_return->{rendering_done} && $func_return->{rendering_done} ) {
                
                return;
                
            } else {
                
                warn "A custom render function returned an unrecognised hash!\n";
                return;
                
            }
            
        } else {
            
            warn "A custom render function was executed, but it didn't provide a return hash!\n";
            return;
            
        }
    }
    
    # We don't want to render $options->{current_value} if
    # we're actually a dynamic image ( as we'd render the path to the image )
    my $is_dynamic_image = ( exists $cell->{image} && exists $cell->{image}->{dynamic} && $cell->{image}->{dynamic} );
    
    # text firsts
    if ( exists $cell->{text} or exists $options->{current_value} && ! $is_dynamic_image ) {
        
        # Generic text cell rendering
        
        $self->render_cell_text( $cell, $options );
        
        # Now perform aggregate functions if defined
        
        if ( $options->{row_type} eq 'data' and $cell->{aggregate_function} ) {
            
            my $cell_value = $options->{current_value} || 0;
            my $group_res  = $cell->{group_results} ||= {};
            my $aggr_func  = $cell->{aggregate_function};
            
            if ( $aggr_func ) {
                
                if ( $aggr_func eq 'sum' ) {
                    
                    for my $group ( @{$self->{data}->{groups}} ) {
                        $group_res->{$group->{name}} += $cell_value;
                    }
                    
                    $cell->{grand_aggregate_result} += $cell_value;
                    
                } elsif ( $aggr_func eq 'count' ) {
                    
                    for my $group ( @{$self->{data}->{groups}} ) {
                            $group_res->{$group->{name}} ++;
                    }
                    
                    $cell->{grand_aggregate_result} ++;
                    
                } elsif ( $aggr_func eq 'max' ) {
                    
                    for my $group ( @{$self->{data}->{groups}} ) {
                        if( $cell_value > $group_res->{$group->{name}} ) {
                            $cell->{grand_aggregate_result} =
                            $group_res->{$group->{name}}    = $cell_value;
                        }
                    }
                    
                } elsif ( $aggr_func eq 'min' ) {
                    
                    for my $group ( @{$self->{data}->{groups}} ) {
                        if( $cell_value < $group_res->{$group->{name}} ) {
                            $cell->{grand_aggregate_result} =
                            $group_res->{$group->{name}}    = $cell_value;
                        }
                    }
                    
                }
                
                # TODO add an "avg" aggregate function? Should be simple.
                
            }
            
        }
        
    }
    
    # image
    $self->render_cell_image( $cell, $options ) if $cell->{image};

    # Barcode
    $self->render_cell_barcode( $cell, $options ) if $cell->{barcode};

    if (my $split_cell = $cell->{split_down}) {
        $self->render_cell($split_cell, $options);
    }
    
}

sub render_cell_background {
    
    my ( $self, $cell, $opt ) = @_;
    
    my $background;
    
    if ( $cell->{background_func} ) {
        if ( $self->{debug} ) {
            print "\nRunning background_func() \n";
        }
        
        $background = $cell->{background_func}($opt->{current_value}, $opt->{current_row}, $opt)
            or return;
    }
    else {
        $background = $cell->{background} or return;
    }

    # get cell position and dimensions
    my $cell_box = $cell->{box};
    my $x = $cell_box->{x};
    my $y = $cell_box->{y};
    my $width = $cell_box->{width};
    my $height = $cell_box->{height};

    # nothing to render without a dimension
    return unless $height > 0 and $width > 0;
    

# if ($cell->{split_y_offset_down}) {
# print "y $self->{y} cell_full_height $opt->{cell_full_height} split_y_offset_down $cell->{split_y_offset_down} current_height $current_height\n";
# exit;
# }

    # ensure borders overlap so fills are seamless
    
    if ( $background->{shape} ) {
        
        # set fill colour
            
            $self->{shape}->fillcolor( $background->{colour} );
            
        if ( $background->{shape} eq "ellipse" ) {

            $self->{shape}->ellipse(
                $x + ( $width >> 1 ),            # x centre
                $y + ( $height >> 1 ),           # y centre
                $width >> 1,                     # length ( / 2 ... for some reason )
                $height >> 1                     # height ( / 2 ... for some reason )
            );
            
        } elsif ( $background->{shape} eq "box" ) {

            # ensure borders overlap so fills are seamless +1 to width and height.
            # TODO: maybe this adjustment should be configurable?

            # for some reason x dimension is less sensitive (maybe that's just my pdf viewers)
            my $overlap_x = $x - 0.4;
            my $overlap_y = $y - 0.5;
            my $overlap_width = $width + 0.8;
            my $overlap_height = $height + 1;

            # adjust for x or y initially zero
            
            if ($overlap_x < 0) {
                $overlap_width += $overlap_x; # subtract the negative amount
                $overlap_x = 0;
            }
            
            if ($overlap_y < 0) {
                $overlap_height += $overlap_y; # subtract the negative amount
                $overlap_y = 0;
            }
            
            $self->{shape}->rect(
                    $overlap_x,                 # left border
                    $overlap_y,                 # bottom border
                    $overlap_width,             # length
                    $overlap_height             # height
            );
            
        }
        
        # now fill

        $self->{shape}->fill;

    }
    
    #
    # Now render cell background borders
    #
    if ( $background->{border} ) {
        
        my $line = $self->{line};

        # Cell Borders
        $line->strokecolor( $background->{border} );
        
        # TODO OPTIMISE: Move the regex setuff into setup_cell_definitions()
        # so we don't have to regex per cell, which is
        # apparently quite expensive
        
        # If the 'borders' key does not exist then draw all borders
        # to support code written before this was added.
        # A value of 'all' can also be used.
        if ( ( ! exists $background->{borders} ) || ( uc $background->{borders} eq 'ALL' ) )
        {
            $background->{borders} = "tblr";
        }
        
        # The 'borders' key looks for the following chars in the string
        #  t or T - Top Border Line
        #  b or B - Bottom Border Line
        #  l or L - Left Border Line
        #  r or R - Right Border Line
        
        my $cell_bb = $background->{borders};
        
        # Bottom Horz Line
        if ( $cell_bb =~ /[bB]/ ) {
            $line->move( $x, $y );
            $line->line( $x + $width, $y);
            $line->stroke;
        }
        
        # Right Vert Line
        # top y doesn't seem to need extra adjusting
        if ( $cell_bb =~ /[rR]/ ) {
            $line->move( $x + $width, $y);
            $line->line( $x + $width, $y + $height);
            $line->stroke;
        }

        # Top Horz Line
        if ( $cell_bb =~ /[tT]/ ) {
            $line->move( $x + $width, $y + $height);
            $line->line( $x, $y + $height );
            $line->stroke;
        }

        # Left Vert Line
        # top y doesn't seem to need extra adjusting
        if ( $cell_bb =~ /[lL]/ ) {
            $line->move( $x, $y + $height);
            $line->line( $x, $y);
            $line->stroke;
        }
        
    }
    
}

sub cell_set_box {

    my ( $self, $cell, $opt ) = @_;

    my $height = $opt->{cell_full_height};
    my $y = $self->{y};

    # align split_down cells
    if ( $cell->{split_valign} eq 'T' ) {
        if ( $cell->{split_y_offset_down} ) {
            
            # top cells in split_down
            $y += $height - $cell->{content_height} - $cell->{split_y_offset_up};
            $height = $cell->{content_height};
            
        }
        elsif( $cell->{split_y_offset_up} ) {
            
            # bottom cell in split_down
            $height -= $cell->{split_y_offset_up};
            
        }
    } elsif ( $cell->{split_valign} eq 'M' ) {
        my $fill_height = ($height - $cell->{content_height} - $cell->{split_y_offset_down} - $cell->{split_y_offset_up}) >> 1;
        if ( $cell->{split_y_offset_down} and !$cell->{split_y_offset_up} ) {
            
            # top cell in split_down
            $y += $height - $cell->{content_height} - $fill_height;
            $height -= $cell->{split_y_offset_down} + $fill_height;
            
        } elsif ( $cell->{split_y_offset_down} and $cell->{split_y_offset_up} ) {
            
            # middle cells split_down
            $y += $height - $cell->{content_height} - $cell->{split_y_offset_up} - $fill_height;
            $height = $cell->{content_height};
            
        } elsif( $cell->{split_y_offset_up} ) {
            
            # bottom cell in split_down
            $height = $cell->{content_height} + $fill_height;
            
        }
    } else {
        if ( $cell->{split_y_offset_down} and !$cell->{split_y_offset_up} ) {
            
            # top cell in split_down
            $y += $cell->{split_y_offset_down};
            $height -= $cell->{split_y_offset_down};
            
        } elsif( $cell->{split_y_offset_up} ) {
            
            # bottom cells in split_down
            $y += $cell->{split_y_offset_down};
            $height = $cell->{content_height};
            
        }
    }
    
    return $cell->{box} = {
        x => $cell->{x_border},
        y => $y,
        width => $cell->{full_width},
        height => $height
    };
    
}

sub render_cell_barcode {

    my ( $self, $cell, $opt ) = @_;
    
    # PDF::API2 barcode options
    #
    # x, y => center of barcode position
    # type => 'code128', '2of5int', '3of9', 'ean13', 'code39'
    # code => what is written into barcode
    # extn => barcode extension, where applicable
    # umzn => upper mending zone (?)
    # lmzn => lower mending zone (?)
    # quzn => quiet zone (space between frame and barcode)
    # spcr => what to put between each char in the text
    # ofwt => overflow width
    # fnsz => font size for the text
    # text => optional text under the barcode
    # zone => height of the bars
    # scale=> 0 .. 1
    
    my $pdf = $self->{pdf};
    my $bcode = $self->get_cell_text($opt->{current_row}, $cell, $cell->{barcode});
    my $btype = 'xo_code128';
    
    # For EAN-13 barcodes, calculate check digit
    if ( $cell->{type} eq 'ean13' )
    {
            return unless eval { require GD::Barcode::EAN13 };
            $bcode .= '000000000000';
            $bcode  = substr( $bcode, 0, 12 );
            $bcode .= GD::Barcode::EAN13::calcEAN13CD($bcode);
        $btype = 'xo_ean13';
    }
    
    # Define font type
    my %bcode_opt = (
        -font=>$self->get_cell_font($cell),
        -fnsz=>$cell->{font_size} || $self->{default_font_size},
        -code=>$bcode,
        -text=>$bcode,
        -quzn=>exists $cell->{quiet_zone}         ? $cell->{quiet_zone}         :  2,
        -umzn=>exists $cell->{upper_mending_zone} ? $cell->{upper_mending_zone} :  4,
        -zone=>exists $cell->{zone}               ? $cell->{zone}               : 25,
        -lmzn=>exists $cell->{lower_mending_zone} ? $cell->{lower_mending_zone} : 12,
        -spcr=>' ',
        -ofwt=>0.1,
    );
    
    if( $cell->{type} eq 'code128' )
    {
        $bcode_opt{-ean}  = 0;
        # TODO Don't know what type to use here.
        #   `a' does not seem to handle lowercase chars.
        #   `c' is a mess.
        #   `b' seems the better...
        $bcode_opt{-type} = 'b';
    }
    
    if( $cell->{type} eq 'code39' )
    {
        print STDERR "code 39 code\n";
        $bcode_opt{-ean}  = 0;
        # TODO Don't know what type to use here.
        #   `a' does not seem to handle lowercase chars.
        #   `c' is a mess.
        #   `b' seems the better...
        $btype = 'xo_3of9';
    }
    
    my $bar   = $pdf->$btype(%bcode_opt);
    my $scale = exists $cell->{scale} ? $cell->{scale} : 1;

    # get cell position
    my $cell_box = $cell->{box};
    my $x = $cell_box->{x};
    my $y = $cell_box->{y};

    my $x_pos = exists $cell->{x} ? $cell->{x} : $x;
    my $y_pos = exists $cell->{y} ? $cell->{y} : $y;
    
    # Manage alignment (left, right or center)
    my $bar_width = $bar->width * $scale;
    if( $cell->{align} eq 'R' ) {
        $x_pos -= $bar_width;
    } elsif( $cell->{align} eq 'C' ) {
        $x_pos -= $bar_width >> 1;
    }
    
    # Position barcode with correct x,y and scale
    my $gfx = $opt->{page}->gfx;
    $gfx->formimage($bar, $x_pos, $y_pos, $scale);

}

sub render_cell_image {
    
    my( $self, $cell, $opt ) = @_;
    
    # save some reference calculating
    my $image_ref = $cell->{image};

    my $gfx = $opt->{page}->gfx;
    my $image;

    my $imgdata = $image_ref->{tmp};
    
    # TODO Add support for GD::Image images?
    # PDF::API2 supports using them directly.
    # We need another key - shouldn't re-use $cell->{image}->{path}
    # We also shouldn't run imgsize() on it, so we have to figure out
    # another way of getting the image size.
    # I haven't use GD before, but I've noted stuff here for people
    # who want GD::Image support ...
    
    # Try to know if installed version of PDF::API2 support the
    # image we are throwing in the PDF document, to avoid bombs
    # when calling image_* pdf methods.
    my %img_meth = (
        PNG=>'image_png',
        JPG=>'image_jpeg',
        TIF=>'image_tiff',
        GIF=>'image_gif',
        PNM=>'image_pnm',
    );
    
    eval {
    
        my $img_call = exists $img_meth{ $imgdata->{img_type} }
            ? $img_meth{ $imgdata->{img_type} }
            : undef;
    
        if( ! defined $img_call )
        {
            warn "\n * * * * * * * * * * * * * WARNING * * * * * * * * * * * * *\n"
                . " Unknown image type: $imgdata->{img_type}\n"
                . " NOT rendering this image.\n"
                . " Please add support for PDF::ReportWriter and send patches :)\n"
                . "\n * * * * * * * * * * * * * WARNING * * * * * * * * * * * * *\n";
        
            # Return now or errors are going to happen when putting an invalid image
            # object on PDF page gfx context
                die "Unrecognized image type";
        }
    
        # Check for PDF::API2 capabilities
        if( ! $self->{pdf}->can($img_call) )
        {
            my $ver = PDF::API2->VERSION();
            die "Your version of PDF::API2 module ($ver) doesn't support $$imgdata{img_type} images or image file is broken.";
        }
        else
        {
            # Finally try to include image in PDF file
            no strict 'refs';
            $image = $self->{pdf}->$img_call($image_ref->{path});
        }
    };
    
    # Check if some image processing error happened
    if( $@ )
    {
        warn 'Error in image ' . $image_ref->{path} . ' processing: '.$@;
        return();
    }
    
    # get cell position and dimensions
    my $cell_box = $cell->{box};
    my $x = $cell_box->{x};
    my $y = $cell_box->{y};
    my $width = $cell_box->{width};
    my $height = $cell_box->{height};

    # Relative or absolute positioning is handled here...
    my $img_x_pos = exists $cell->{x} ? $cell->{x} : $x;
    my $img_y_pos = exists $cell->{y} ? $cell->{y} : $y;

    # TODO valign
    # TODO respect absolute x/y positioning
    $img_y_pos += ( $height - $imgdata->{this_img_y} ) / 2;
    
    # Alignment
    if ( $cell->{align} eq 'L' ) {
        if ($cell->{text_position} eq 'L') {
            $img_x_pos = $cell->{text_string_right} + $image_ref->{buffer} + $cell->{text_whitespace};
        }
        else {
            $img_x_pos += $image_ref->{buffer};
        }
    }
    elsif ( $cell->{align} eq 'C' ) {
        if ($cell->{text_position} eq 'L') {
            $img_x_pos = $cell->{text_string_right} + $image_ref->{buffer} + $cell->{text_whitespace};
        }
        elsif ($cell->{text_position} eq 'R') {
            $img_x_pos = $cell->{text_string_left} - $imgdata->{this_img_x}
                - $image_ref->{buffer} - $cell->{text_whitespace};
        }
        else {
            $img_x_pos += ( $width - $imgdata->{this_img_x} ) / 2 - $image_ref->{buffer};
        }
    }
    elsif ( $cell->{align} eq 'R' ) {
        if ($cell->{text_position} eq 'L') {
            $img_x_pos = $cell->{text_string_right} + $image_ref->{buffer} + $cell->{text_whitespace};
        }
        elsif ($cell->{text_position} eq 'R') {
            $img_x_pos = $cell->{text_string_left} - $imgdata->{this_img_x}
                - $image_ref->{buffer} - $cell->{text_whitespace};
        }
        else {
            $img_x_pos += $width - $imgdata->{this_img_x} - $image_ref->{buffer};
        }
    }
    
    #warn 'image: '.$image_ref->{path}.' scale_ratio:'. $imgdata->{scale_ratio};
    
    # Place image onto PDF document's graphics context
    $gfx->image(
        $image,                     # The image
        $img_x_pos,                 # X
        $img_y_pos,                 # Y
        $imgdata->{scale_ratio}     # scale
    );

}

sub get_cell_font
{
    my ( $self, $cell ) = @_;
    my $font_type =
        ( exists $cell->{bold} && $cell->{bold} )
            ? ( exists $cell->{italic} && $cell->{italic} ) ? 'BoldItalic' : 'Bold'
            : ( exists $cell->{italic} && $cell->{italic} ) ? 'Italic' : 'Roman';
    my $font_name = $cell->{font} || $self->{default_font};
    return $self->{fonts}->{$font_name}->{$font_type};
}

sub render_cell_text {
    
    my ( $self, $cell, $opt ) = @_;
    
    my $row  = $opt->{current_row};
    my $type = $opt->{row_type};
    
    # Figure out what we're putting into the current cell and set the font and size
    # We currently default to Bold if we're doing a header
    # We also check for an specific font for this field, or fall back on the report default
    
    my $string;
    
    $self->{txt}->font( $self->get_cell_font($cell), $cell->{font_size} );
    
    if ( $type eq 'field_headers' ) {
        
        $string = $cell->{text};
        
    } elsif ( $type eq 'data' and !$cell->{filler}) {
        
        # ??? Did I do this? Remove this line then?
        #$string = $row->[$opt->{cell_counter}];
        $string = $opt->{current_value};
    
    } elsif ( $type eq 'group_header' ) {
    
        # Replaces the `?' char and manages text delimited cells
        $string = $self->get_cell_text( $row, $cell, $cell->{text} );
        
    } elsif ( $type eq 'group_footer' ) {
        
        if ( exists $cell->{aggregate_source} ) {
            my $aggr_field = $self->{data}->{fields}->[ $cell->{aggregate_source} ];
            if ($cell->{text} eq 'GrandTotals') {
                $string = $aggr_field->{grand_aggregate_result};
            } else {
                $string = $aggr_field->{group_results}->{$cell->{text}};
            }
        } else {
            $string = $cell->{text};
        }
        
        $string =~ s/\?/$row/g; # In the case of a group footer, the $row variable is the group value
        #$string = $self->get_cell_text($row, $cell, $string);
        
    } elsif ( $type =~ m/^page/ ) {
        
        # page_header or page_footer
        $string = $self->get_cell_text( $row, $cell, $cell->{text} );
    }
        
    if ( $cell->{colour_func} ) {
        if ( $self->{debug} ) {
            print "\nRunning colour_func() on data: " . $string . "\n";
        }
        $self->{txt}->fillcolor( $cell->{colour_func}( $string, $row, $opt ) || "black" );
    } else {
        $self->{txt}->fillcolor( $cell->{colour} || "black" );
    }
    
    # Formatting
    if ( $type ne 'field_headers' && $cell->{format} ) {
        
        # The new ( v1.4 ) formatter hash
        $string = $self->format_number(
            $cell->{format},
            $string
        );
        
    } elsif ( $cell->{type} && $cell->{type} =~ /^custom:(.+)$/ ) {
        
        # Custom formatter, in the legacy 'type' key
        # Should this be renamed to 'format' too?
        
        # TODO Better develop custom cell type?
        # TODO How do we specify the custom formatter object?
        
        eval "require $1";
        if( $@ )
        {
            warn "Cell custom formatter class $1 was not found or had errors: $@";
        }
        
        my $formatter_obj = $1->new();
        $string = $formatter_obj->format({ cell => $cell, options => $opt, string => $string });
        
        
    }
    
    # Line height, split lines
    my ($text_height, $split_string) = $self->set_cell_text_height($cell, $string);
    
    # copy some well used hash values for faster access
    my $text_line_height = $cell->{text_line_height};
    my $text_width = $cell->{text_width};

    # get cell position and dimensions
    my $cell_box = $cell->{box};
    my $x = $cell_box->{x};
    my $y = $cell_box->{y};
    my $width = $cell_box->{width};
    my $height = $cell_box->{height};
    
    # If cell is absolutely positioned (y), we should avoid automatic page break.
    # This is intuitive to do, I think...
    my $cell_abs_y_pos = exists $cell->{y};
    my $cell_abs_x_pos = exists $cell->{x};

    # $y_pos marks the bottom of the first line of text
    my $y_pos = $cell_abs_y_pos
        ? $cell->{y}
        : $y + $text_height - $text_line_height + $cell->{text_whitespace};

    my $x_pos = $cell_abs_x_pos
        ? $cell->{x}
        : $cell->{x_text} + $cell->{auto_margin_left};

    # skip align if cell is absolutely positioned (x).
    my $text_align = $cell_abs_x_pos ? 'L' : $cell->{text_align};
    my $cell_align = $cell_abs_x_pos ? 'L' : $cell->{align};

    # skip valign if cell is absolutely positioned (y).
    my $valign = $cell_abs_y_pos ? 'B' : $cell->{valign};

    if ( $valign eq 'T' ) {
        $y_pos += $height - $text_height;
    } elsif ( $valign eq 'M' ) {
        $y_pos += ($height - $text_height) >> 1;
    }
    
    # Handle multiline text
    
    # Whatever the format (Dos/Unix/Mac/Amiga), this should correctly split rows
    # NOTE: This breaks rendering of blank lines
    # TODO Check with Cosimo why we're stripping blank rows
    #my @text_rows = split /[\r\n]+\s*/ => $string;
    
    my $max_string_width = 0;
    my $min_string_left = $x_pos + $text_width;
    my $max_string_right = 0;

    # first pass calculate the text block dimensions (max width of all text)
    my @string_position;
    for $string ( @$split_string ) {
        my $string_width = 0;
        my $string_left = $x_pos;
        my $string_right = $string_left;
        
        # Make sure the current string fits inside the current cell
        # Beware: if text_width < 0, there is something wrong with `percent' attribute.
        # Maybe it hasn't been set...
        
        if ( $text_width > 0 ) {
            $string_width = $self->{txt}->advancewidth( $string );
            # make string fit in width
            while ( $string && $string_width > $text_width) {
                chop($string);
                $string_width = $self->{txt}->advancewidth( $string );
            }
        }
        else {
            $string_width = $self->{txt}->advancewidth( $string );
        }
        
        if ( $text_align eq 'L' ) {
            # Default alignment if left-aligned
            
            # calculate string lef/right offsets
            $string_right += $string_width;
        }
        elsif ( $text_align eq 'C' ) {
            # Calculate the width of the string, and move to the right so there's an
            # even gap at both sides, and render left-aligned from there
            
            # calculate string lef/right offsets
            $string_left += ( $text_width - $string_width ) >> 1;
            $string_right = $string_left + $string_width;
        }
        elsif ( $text_align eq 'R' ) {
            # calculate string lef/right offsets
            $string_right += $text_width;
            $string_left = $string_right - $string_width;
        }
        elsif ( $text_align eq 'J' ) {
            # Justify text
            $string_right += $text_width;
            $string_width = $text_width;
        }
            
        # save these dimensions for the next step
        push @string_position, [$string_left, $string_right, $string_width];
             
        # adjust text area limits
        $max_string_width = $string_width if $string_width > $max_string_width;
        $min_string_left = $string_left if $string_left < $min_string_left;
        $max_string_right = $string_right if $string_right > $max_string_right;
    }
            
    # The cell align may be different than the text_align
    # adjust the left offset accordingly
    my $cell_align_x_offset = 0;
            
    if ($cell_align eq 'L') {
        if ($text_align eq 'R') {
            # reverse the text align offset
            $cell_align_x_offset = $x_pos - $min_string_left;
        }
        elsif ($text_align eq 'C') {
            # remove half the cell free space
            $cell_align_x_offset -= ($text_width - $max_string_width) >> 1;
        }
    }
    elsif ($cell_align eq 'C') {
        if ($text_align eq 'L') {
            # add in half the cell free space
            $cell_align_x_offset = ($text_width - $max_string_width) >> 1;
        }
        elsif ($text_align eq 'R') {
            # remove half the cell free space
            $cell_align_x_offset -= ($text_width - $max_string_width) >> 1;
            }
    }
    elsif ($cell_align eq 'R') {
        if ($text_align eq 'L') {
            # reverse the text align offset
            $cell_align_x_offset = $text_width - $max_string_width;
        }
        elsif ($text_align eq 'C') {
            # add in half the cell free space
            $cell_align_x_offset = ($text_width - $max_string_width) >> 1;
        }
    }

    # absolute text block position
    $cell->{text_string_width} = $max_string_width;
    $cell->{text_string_left} = $min_string_left + $cell_align_x_offset;
    $cell->{text_string_right} = $max_string_right + $cell_align_x_offset;

    for $string ( @$split_string ) {

        my $dimensions = shift @string_position;
        my ($string_left, $string_right, $string_width) = @$dimensions;

        if ( $text_align =~ m/[LC]/ ) {
            $self->{txt}->translate( $cell_align_x_offset + $string_left, $y_pos );
            $self->{txt}->text( $string );
            
        }
        elsif ( $text_align eq 'R' ) {
            $self->{txt}->translate( $cell_align_x_offset + $string_right, $y_pos );
            $self->{txt}->text_right($string);
            
        }
        elsif ( $text_align eq 'J' ) {
           
            # Justify text
            # This is largely taken from a brilliant example at: http://incompetech.com/gallimaufry/perl_api2_justify.html
            
            # Set up the control
            $self->{txt}->charspace( 0 );
            
            # Now the experiment
            $self->{txt}->charspace( 1 );
             
            my $experiment_width = $self->{txt}->advancewidth( $string );
            
            # SINCE 0 -> $nominal   AND   1 -> $experiment ... WTF was he on about here?
            if ( $string_width ) {
                
                my $diff = $experiment_width - $string_width;
                my $min  = $text_width - $string_width;
                my $target = $min / $diff;
                
                # TODO MINOR: Provide a 'maxcharspace' option? How about a normal charspace option?
                
                $target = 0 if ( $target > 1 ); # charspacing > 1 looks kinda dodgy, so don't bother with justifying in this case
                
                # Set the target charspace
                $self->{txt}->charspace( $target );
                
                # Render
                $self->{txt}->translate( $string_left, $y_pos );
                $self->{txt}->text( $string );
                
                # Default back to 0 charspace
                $self->{txt}->charspace( 0 );
                
            }
           
        }
        
        # XXX Empirical result? Is there a text line_height information?
        $y_pos -= $text_line_height;
        
        # Run empty on page space? Make a page break
        # Dan's note: THIS SHOULD *NEVER* HAPPEN.
        # If it does, something is wrong with our y-space calculation
        if( $cell_abs_y_pos && $y_pos < $text_line_height ) {
            warn "* * * render_cell_text() is requesting a new page * * *\n"
                . "* * * please check y-space calculate_y_needed()   * * *\n"
                . "* * *             this MUST be a bug ...          * * *\n";
            $self->new_page();
        }
        
    }
    
}

sub wrap_text {
    
    # TODO OPTIMISE wrap_text() is incredibly slow
    # Someone, please fix me ....
    # better? Scott
    # IDEA:
    #  Maybe binary split line until it fits then backtrack first space
    #  It's no doubt faster to search for spaces in the string than it is
    #  to calculate advancewidth for each char position
    my ( $self, $options ) = @_;
    
    my $string          = $options->{string};
    my $text_width      = $options->{text_width};
    
    if ( $text_width == 0 ) {
        return $string;
    }
    
    $string =~ s/\015\012?|\012/\n/g; # funky line return variations
    
    # Remove line breaks?
    # TODO shouldn't the break be replaced with something like a space?
    if ( $options->{strip_breaks} ) {
        $string =~ s/\n//g;
    }
    
    my @wrapped_text;
    my @lines = split /\n/, $string;
    my $txt = $self->{txt}; # avoid unneccessary reference lookups
    
    # We want to maintain any existing line breaks,
    # and also add new line breaks if the text won't fit on 1 line
    
    foreach my $line ( @lines ) {
        
        # take the duck (normal case?)
        if ($txt->advancewidth($line) < $text_width ) {
            push @wrapped_text, $line;
            next;
        }
        
        # find first whitespace break that fits
        while ( length($line) ) {
            
            my $position    = 0;
            my $last_space  = 0;
            my $next_non_space  = 0;
            my $last_space_char = '';
            
            # test the cheaper length() first
            while ( ++$position < length($line)
                    and $txt->advancewidth(substr($line, 0, $position)) < $text_width ) {

                # a tab will do as well as a space?  What about a hyphen?
                if ( substr( $line, $position, 1 ) =~ m/([\s-])/ ) {
                    $last_space_char = $1;
                    $last_space = $position;
                    $position++;
                    # we don't need to keep testing trailing spaces do we?
                    while ($position < length($line)
                            and substr( $line, $position, 1 ) =~ m/\s/) {
                $position ++;
            }
                    $next_non_space = $position;
                }
            }
            
                
            if ( $position == length( $line ) ) {
                # This bit doesn't need wrapping. Take it all
                push @wrapped_text, $line;

                # exit while ( length($line) )
                last;
            }
                
                
                # We didn't get to the end of the string, so this bit *does* need wrapping
                # Go back to the last space
                            
            if (!$last_space) {
                # there was no last space, so hard split on the last char that fit
                $last_space = $next_non_space = $position - 1;
            }
            
            my $length = $last_space_char eq '-'
                ? $last_space + 1
                : $last_space;

            if ( $self->{debug} ) {
                print "PDF::ReportWriter::wrap_text returning line: >>" . substr( $line, 0, $length ) . "<<\n\n";
            }
            
            push @wrapped_text, substr( $line, 0, $length );
            
            $line = substr( $line, $next_non_space, length( $line ) - $next_non_space );
            
        }
        
    }
    
    return join "\n", @wrapped_text;
    
}

sub format_unit {
    my ( $self, $string, $full_percent) = @_;
    
    my $ok = 1;
    $string =~ /^\s*([\d\.]+)\s*(pt|in|mm|\%)?\s*$/i
        or $ok = 0;
    
    if ( ! $ok ) {
        carp( "Unsupported measure unit: $string\n" );   
    }
    
#    $string =~ /^\s*([\d\.]+)\s*(pt|in|mm|\%)?\s*$/i
#        or die "Unsupported measure unit: $string\n";

    my $unit = defined $2 ? lc($2) : return $1;  # default to points
    return ($full_percent || 0) * $1 / 100 if $unit eq '%';
    return $1 if $unit eq 'pt';
    return $1 * mm if $unit eq 'mm';
    return $1 * in if $unit eq 'in';
}

sub format_number {
    
    my ( $self, $options, $value ) = @_;
    
    # $options can contain the following:
    #  - currency               BOOLEAN
    #  - decimal_places         INT     ... or
    #  - decimals               INT
    #  - decimal_fill           BOOLEAN
    #  - separate_thousands     BOOLEAN
    #  - null_if_zero           BOOLEAN
    
    my $calc = $value;
    
    my $final;
    
    # Support for null_if_zero
    if ( exists $options->{null_if_zero} && $options->{null_if_zero} && $value == 0 ) {
        return undef;
    }
    
    my $decimals = exists $options->{decimal_places} ? $options->{decimal_places} : $options->{decimals};
    
    # Allow for our number of decimal places
    if ( $decimals ) {
        $calc *= 10 ** $decimals;
    }
    
    # Round
    $calc = int( $calc + .5 * ( $calc <=> 0 ) );
    
    # Get decimals back
    if ( $decimals ) {
        $calc /= 10 ** $decimals;
    }
    
    # Split whole and decimal parts
    my ( $whole, $decimal ) = split /\./, $calc;
    
    # Pad decimals
    if ( $options->{decimal_fill} ) {
        if ( defined $decimal ) {
            $decimal = $decimal . "0" x ( $decimals - length( $decimal ) );
        } else {
            $decimal = "0" x $decimals;
        }
    }
    
    # Separate thousands
    if ( $options->{separate_thousands} ) {
        # This BS comes from 'perldoc -q numbers'
        $whole =~ s/(^[-+]?\d+?(?=(?>(?:\d{3})+)(?!\d))|\G\d{3}(?=\d))/$1,/g;
    }
    
    # Don't put a decimal point if there are no decimals
    if ( defined $decimal ) {
        $final = $whole . "." . $decimal;
    } else {
        $final = $whole;
    }
    
    # Currency?
    if ( $options->{currency} ) {
        $final = '$' . $final;
        # If this is a negative value, we want to force the
        # negative sign to the left of the dollar sign ...
        $final =~ s/\$-/-\$/;
    }
    
    return $final;
    
}

sub render_footers
{
    my $self = $_[0];
    
    # If no pages defined, there are no footers to render
    if( ! exists $self->{pages} or ! ref $self->{pages} or ! $self->{page_footers} )
    {
        return;
    }
    
    my $total_pages = scalar@{$self->{pages}};
    my $footers = $self->{page_footers};

    # save the current y value (last page)
    my $save_y = $self->{y};

    # Get the current_height of the footer - we have to move this much *above* the lower_margin,
    # as our render_row() will move this much down before rendering
    my $max_cell_height = $self->{data}->{page_footer_max_cell_height};

    # get the attach_footer flag
    my $attach_footer = $self->{data}->{page}->{attach_footer};
    
    # We first loop through all the pages and add footers to them
    for my $this_page_no ( 0 .. $total_pages - 1 ) {
        
        my $footer = shift @$footers;

        # the true ending y value for this page is stored with the next page
        my $this_y = @$footers
            ? $footers->[0]->{y}
            : $save_y; # no next page, use current page y

        $self->{txt} = $self->{pages}[$this_page_no]->text;
        $self->{line} = $self->{pages}[$this_page_no]->gfx;
        $self->{shape} = $self->{pages}[$this_page_no]->gfx(1);
        
        my $localtime = localtime time;
        
        $self->{y} = $attach_footer
            ? $this_y       # attach footer to last rendered row
            : $self->{lower_margin} + $max_cell_height;
        
        $self->render_row(
            $footer->{cells},
            {
                current_page    => $this_page_no + 1,
                total_pages     => $total_pages,
                current_time    => $localtime
            },
            'page_footer',
            $max_cell_height,
            0,
            0
        );
        
    }
    
}

sub stringify
{
    my $self = shift;
    my $pdf_stream;
    
    $self->render_footers();
    
    $pdf_stream = $self->{pdf}->stringify;
    $self->{pdf}->end;
    
    return($pdf_stream);
}

sub save {
    
    my $self = shift;
    my $ok   = 0;
    
    $self->render_footers();
    
    $ok = $self->{pdf}->saveas($self->{destination});
    $self->{pdf}->end();
    
    # TODO Check result of PDF::API2 saveas() and end() methods?
    return(1);
    
}

sub saveas {
    
    my $self = shift;
    my $file = shift;
    $self->{destination} = $file;
    $self->save();
    
}

#
# Spool a report to CUPS print queue for direct printing
#
# $self->print({
#     tempdir => '/tmp',
#     command => '/usr/bin/lpr.cups',
#     printer => 'myprinter',
# });
#
sub print {
    
    use File::Temp ();
    
    my $self = shift;
    my $opt  = shift;
    my @cups_locations = qw(/usr/bin/lpr.cups /usr/bin/lpr-cups /usr/bin/lpr);
    
    # Apply option defaults
    my $unlink_spool = exists $opt->{unlink} ? $opt->{unlink} : 1;
    $opt->{tempdir} ||= '/tmp';
    
    # Try to find a suitable cups command
    if( ! $opt->{command} )
    {
        my $cmd;
        do {
            last unless @cups_locations;
            $cmd = shift @cups_locations;
        } until ( -e $cmd && -x $cmd );
    
        if( ! $cmd )
        {
            warn 'Can\'t find a lpr/cups shell command to run!';
            return undef;
        }
    
        # Ok, found a cups/lpr command
        $opt->{command} = $cmd;
    }
    
    my $cups_cmd = $opt->{command};
    my $ok = my $err = 0;
    my $printer;
    
    # Add printer queue name if supplied
    if( $printer = $opt->{printer} )
    {
        $cups_cmd .= " -P $printer";
    }
    
    # Generate a temporary file to store pdf content
    my($temp_file, $temp_name) = File::Temp::tempfile('reportXXXXXXX', DIR=>$opt->{tempdir}, SUFFIX=>'.pdf');
    
    # Print all pdf stream to file
    if( $temp_file )
    {
            binmode $temp_file;
        $ok   = print $temp_file $self->stringify();
        $ok &&= close $temp_file;
    
        # Now spool this temp file
        if( $ok )
        {
            $cups_cmd .= ' ' . $temp_name;
    
            # Run spool command and get exit status
            my $exit = system($cups_cmd) && 0xFF;
            $ok = ($exit == 0);
    
            if( ! $ok )
            {
                # ERROR 1: FAILED spooling of report with CUPS
                $err = 1;
            }
    
            # OK: Report spooled correctly to CUPS printer
    
        }
        else
        {
            # ERROR 2: FAILED creation of report spool file
            $err = 2;
        }
    
        unlink $temp_name if $unlink_spool;
    }
    else
    {
        # ERROR 3: FAILED opening of a temporary spool file
        $err = 3;
    }
    
    return($err);
}

#
# Replaces `?' with current value and handles cells with delimiter and index
# Returns the final string value
#

{
    # Datasource strings regular expression
    # Example: `%customers[2,5]%'
    my $ds_regex = qr/%(\w+)\[(\d+),(\d+)\]%/o;
    
    sub get_cell_text {
        
        my ( $self, $row, $cell, $text ) = @_;
        
        my $string = $text || $cell->{text};
        
        # If string begins and ends with `%', this is a reference to an external datasource.
        # Example: `%mydata[m,n]%' means lookup the <datasource> tag with name `mydata',
        # try to load the records and return the n-th column of the m-th record.
        # Also multiple data strings are allowed in a text cell, as in
        # `Dear %customers[0,1]% %customers[0,2]%'
        
        while ( $string =~ $ds_regex ) {
            
            # Lookup from external datasource
            my $ds_name = $1;
            my $n_rec   = $2;
            my $n_col   = $3;
            my $ds_value= '';
            
            # TODO Here we must cache the results of `get_data' by
            #      data source name or we could reload many times
            #      the same data...
            if( my $data = $self->report->get_data( $ds_name ) ) {
                $ds_value = $data->[$n_rec]->[$n_col];
            }
            
            $string =~ s/$ds_regex/$ds_value/;
            
        }
        
        # In case row is a scalar, we are into group cell,
        # not data cell rendering.
        if ( ref $row eq 'HASH' ) {
            $string =~ s/\%PAGE\%/$row->{current_page}/;
            $string =~ s/\%PAGES\%/$row->{total_pages}/;
        } else {
            # In case of group headers/footers, $row is a single scalar
            if ( $cell->{delimiter} ) {
                # This assumes the delim is a non-alpha char like |,~,!, etc...
                my $delim = "\\" . $cell->{delimiter}; 
                my $row2 = ( split /$delim/, $row )[ $cell->{index} ];
                $string =~ s/\?/$row2/g;
            } else {
                $string =~ s/\?/$row/g;
            }
        }
        
        # __generationtime member is set at object initialization (parse_options)
        $string =~ s/\%TIME\%/$$self{__generationtime}/;
        
        return ( $string );
        
    }
    
}

1;

=head1 NAME

PDF::ReportWriter

=head1 DESCRIPTION

PDF::ReportWriter is designed to create high-quality business reports, for archiving or printing.

=head1 USAGE

The example below is purely as a reference inside this documentation to give you an idea of what goes
where. It is not intended as a working example - for a working example, see the demo application package,
distributed separately at http://entropy.homelinux.org/axis_not_evil

First we set up the top-level report definition and create a new PDF::ReportWriter object ...

use PDF::ReportWriter qw(:Standard);

$report = {

  destination        => "/home/dan/my_fantastic_report.pdf",
  paper              => "A4",
  orientation        => "portrait",
  template           => '/home/dan/my_page_template.pdf',
  font_list          => [ "Times" ],
  default_font       => "Times",
  default_font_size  => "10",
  x_margin           => 10 * mm,
  y_margin           => 10 * mm,
  info               => {
                            Author      => "Daniel Kasak",
                            Keywords    => "Fantastic, Amazing, Superb",
                            Subject     => "Stuff",
                            Title       => "My Fantastic Report"
                        }

};

my $pdf = PDF::ReportWriter->new( $report );

Next we define our page setup, with a page header ( we can also put a 'footer' object in here as well )

my $page = {

  header             => [
                                {
                      width     => "60%",
                                        font_size      => 15,
                                        align          => "left",
                                        text           => "My Fantastic Report"
                                },
                                {
                      width     => "40%",
                                        align          => "right",
                                        image          => {
                                                                  path          => "/home/dan/fantastic_stuff.png",
                                                                  scale_to_fit  => TRUE
                                                          }
                                }
                         ]

};

Define our fields - which will make up most of the report

my $fields = [

  {
     name               => "Date",                               # 'Date' will appear in field headers
       width              => "35%",                                # The percentage of X-space the cell will occupy
     align              => "centre",                             # Content will be centred
     colour             => "blue",                               # Text will be blue
     font_size          => 12,                                   # Override the default_font_size with '12' for this cell
     header_colour      => "white"                               # Field headers will be rendered in white
  },
  {
     name               => "Item",
       width              => "35%",
     align              => "centre",
     header_colour      => "white",
  },
  {
     name               => "Appraisal",
       width              => "30%",
     align              => "centre",
     colour_func        => sub { red_if_fantastic(@_); },        # red_if_fantastic() will be called to calculate colour for this cell
     aggregate_function => "count"                               # Items will be counted, and the results stored against this cell
   }
   
];

I've defined a custom colour_func for the 'Appraisal' field, so here's the sub:

sub red_if_fantastic {

     my $data = shift;
     if ( $data eq "Fantastic" ) {
          return "red";
     } else {
          return "black";
     }

}

Define some groups ( or in this case, a single group )

my $groups = [
   
   {
      name           => "DateGroup",                             # Not particularly important - apart from the special group "GrandTotals"
      data_column    => 0,                                       # Which column to group on ( 'Date' in this case )
      header => [
      {
           width             => "100%",
         align             => "right",
         colour            => "white",
         background        => {                                  # Draw a background for this cell ...
                                   {
                                         shape     => "ellipse", # ... a filled ellipse ...
                                         colour    => "blue"     # ... and make it blue
                                   }
                              }
         text              => "Entries for ?"                    # ? will be replaced by the current group value ( ie the date )
      }
      footer => [
      {
           width             => "70%",
         align             => "right",
         text              => "Total entries for ?"
      },
      {
           width             => "30%",
         align             => "centre",
         aggregate_source  => 2                                  # Take figure from field 2 ( which has the aggregate_function on it )
      }
   }
   
];

We need a data array ...

my $data_array = $dbh->selectall_arrayref(
 "select Date, Item, Appraisal from Entries order by Date"
);

Note that you MUST order the data array, as above, if you want to use grouping.
PDF::ReportWriter doesn't do any ordering of data for you.

Now we put everything together ...

my $data = {
   
   background              => {                                  # Set up a default background for all cells ...
                                  border      => "grey"          # ... a grey border
                              },
   fields                  => $fields,
   groups                  => $groups,
   page                    => $page,
   data_array              => $data_array,
   headings                => {                                  # This is where we set up field header properties ( not a perfect idea, I know )
                                  background  => {
                                                     shape     => "box",
                                                     colour    => "darkgrey"
                                                 }
                              }
   
};

... and finally pass this into PDF::ReportWriter

$pdf->render_data( $data );

At this point, we can do something like assemble a *completely* new $data object,
and then run $pdf->render_data( $data ) again, or else we can just finish things off here:

$pdf->save;


=head1 CELL DEFINITIONS

PDF::ReportWriter renders all content the same way - in cells. Each cell is defined by a hash.
A report definition is basically a collection of cells, arranged at various levels in the report.

Each 'level' to be rendered is defined by an array of cells.
ie an array of cells for the data, an array of cells for the group header, and an array of cells for page footers.

Cell spacing is relative. You define a width for each cell, and the actual length of the cell is
calculated based on the page dimensions ( in the top-level report definition ).

A cell can have the following attributes

=head2 name

=over 4

The 'name' is used when rendering data headers, which happens whenever a new group or page is started.
It's not used for anything else - data must be arranged in the same order as the cells to 'line up' in
the right place.

You can disable rendering of field headers by setting no_field_headers in your data definition ( ie the
hash that you pass to the render() method ).

=back

=head2 percent ( LEGACY )

=over 4

Please see the 'width' key, below, for improved cell width definition.

The width of the cell, as a percentage of the total available width.
The actual width will depend on the paper definition ( size and orientation )
and the x_margin (left_margin, right_margin) in your report_definition.

In most cases, a collection of cells should add up to 100%. For multi-line 'rows',
you can continue defining cells beyond 100% width, and these will spill over onto the next line.
See the section on MULTI-LINE ROWS, below.

=back

=head2 width

=over 4

The width of the cell, in 'pt' (points where 1 mm = 72/25.4 points - default), 'mm', 'in' (inches) or
as a percentage of the total available width (%).  The actual width of percentage values will depend
on the paper definition (size and orientation) and the x_margin (left_margin, right_margin) in your
report_definition.

In most cases, a collection of cells should add up to 100%. For multi-line 'rows',
you can continue defining cells beyond 100% width, and these will spill over onto the next line.
See the section on MULTI-LINE ROWS, below.

=back

=head2 x

=over 4

The x position of the cell, expressed in 'pt' (points where 1 mm = 72/25.4 points - default), 'mm',
'in' (inches) or as a percentage of the total available width (%).  The actual width of percentage
values will depend on the paper definition (size and orientation) and the x_margin (left_margin,
right_margin) in your report_definition.

=back

=head2 y

=over 4

The y position of the cell, expressed in 'pt' (points where 1 mm = 72/25.4 points - default), 'mm',
'in' (inches) or as a percentage of the total available width (%).  The actual width of percentage
values will depend on the paper definition (size and orientation) and the y_margin (upper_margin,
lower_margin) in your report_definition.

=back

=head2 font

=over 4

The font to use. In most cases, you would set up a report-wide default_font.
Only use this setting to override the default.

=back

=head2 font_size

=over 4

The font size. Nothing special here...

=back

=head2 text_whitespace

=over 4

The padding value added to the text lines, expressed in 'pt' (points where 1 mm = 72/25.4 points - default), 'mm',
'in' (inches) or as a percentage of the total available width (%).  The actual width of percentage
values will depend on the paper definition (size and orientation) and the x_margin (left_margin,
right_margin) in your report_definition.

The text_whitespace is a *minimum* white-space buffer to wrap text lines in. This defaults to on half the font size.

=back

=head2 text_align

=over 4

Possible values are "left", "right", "centre" (or now "center", also), and "justified".

Text_align applies to text blocks (multiple lines of text) independentaly of the cell alignment (see 'align' below).  For
example text can be left justified with text_align = "left" (the default), yet still have the entire text block aligned to
the right edge of the cell with align = 'right'.

=back

=head2 text_margin_left

=over 4

The cell left offset added to the text blocks, images and barcodes, expressed in 'pt' (points where 1 mm = 72/25.4
points - default), 'mm', 'in' (inches) or as a percentage of the total available width (%).  The actual width of percentage
values will depend on the paper definition (size and orientation) and the x_margin (left_margin,
right_margin) in your report_definition.

=back

=head2 text_margin_right

=over 4

The cell right offset added to the text blocks, images and barcodes, expressed in 'pt' (points where 1 mm = 72/25.4
points - default), 'mm', 'in' (inches) or as a percentage of the total available width (%).  The actual width of
percentage values will depend on the paper definition (size and orientation) and the x_margin (left_margin,
right_margin) in your report_definition.

=back

=head2 text_position

=over 4

Possible values are "left" and "right".

When a cell contains both text and an image, text_position determines if the text is printed to the left or the right
of the image.  There's no default value for this key.  If a cell contains both text and an image with no text_position,
the image is simply overlayed on top of the text.

=back

=head2 bold

=over 4

A boolean flag to indicate whether you want the text rendered in bold or not.

=back

=head2 italic

=over 4

A boolean flag to indicate whether you want the text rendered in italic or not.

=back

=head2 colour

=over 4

No surprises here either.

=back

=head2 align

=over 4

Possible values are "left", "right", "centre" (or now "center", also), and "justified".

=back

=head2 valign

=over 4

Possible values are "top", "middle" and "bottom".

=back

=head2 header_colour

=over 4

The colour to use for rendering data headers ( ie field names ).

=back

=head2 header_align

=over 4

The alignment of the data headers ( ie field names ). 
Possible values are "left", "right", "centre" (or now "center", also), and "justified".

=back

=head2 header_text_align

=over 4

The alignment of the data headers text block ( ie field names ).
Possible values are "left", "right", "centre" (or now "center", also), and "justified".

=back

=head2 header_valign

=over 4

The vertical alignment of the data headers ( ie field names ).
Possible values are "top", "middle" and "bottom".

=back

=head2 text

=over 4

The text to display in the cell ( ie if the cell is not rendering data, but static text ).

=back

=head2 wrap_text

=over 4

Turns on wrapping of text that exceeds the width of the cell.

=back

=head2 strip_breaks

=over 4

Strips line breaks out of text.

=back

=head2 auto_row_height

=over 4

A boolean flag to indicate whether this cell height is calculated from all the cells in it's row (see the section on
MULTI-LINE ROWS, below) or all the cells in the group type.  When rendering a group row(s), all the cells are initially
set to the height of the tallest cell in the group.  For multi-line rows, this makes each row an identical height.  When
auto_row_height is set, each row of a multi-line row adjusts to the minimum height needed for that row.

=back

=head2 shift_row_up

=over 4

The y adjustment of a row, expressed in 'pt' (points where 1 mm = 72/25.4 points - default), 'mm',
'in' (inches) or as a percentage of the total available width (%).  The actual width of percentage
values will depend on the paper definition (size and orientation) and the y_margin (upper_margin,
lower_margin) in your report_definition.

If a shift_row_up value is found in any cell of a row, the entire row (and any rows that follow) will be shifted
up by the shift amount.  If a row of cells contains more than one shift value, the maximum shift value is used.

=back

=head2 split_down

=over 4

A hash with details of a new cell to render below the current cell.  The split cell can have any attribute a
regular cell can (including more split_down cells), with the following exceptions:

=over 2
Split cells are fixed to the position and width to match the parent cell.

Split cell heights are added together and counted as one cell in the row.

Split cells are defaulted to the same values (colour, background, etc) as the parent cell.  This can be changed
individually within the split cell definition.

Split cells are vertically aligned (valign) as single block.  That is all the cells in the split are squashed together
and vertical padding is added to the top or bottom of the split cell group to format alignment.
=back

=back

=head2 print_if_true

=over 4

A boolean flag to conditionally render a data row based on data values.  If all the cells of a row have set the
'print_if_true' flag, then that row will not be printed unless at least one value in the row is true (according to
Perl's defininition of true).

=back

=head2 filler

=over 4

A boolean flag to indicate whether this cell counts as data.  When rendering a data row, any cell set with
the 'filler' flag is skipped over (doesn't consume data from the data array).  Use this flag to insert additional
formatting cells in the data row.

=back

=head2 image

=over 4

A hash with details of the image to render. See below for details.
If you try to use an image type that is not supported by your installed
version of PDF::API2, your image is skipped, and a warning is printed out.

=back

=head2 colour_func

=over 4

A user-defined sub that returns a colour. Your colour_func will be passed:

=over 4

=head3 value

=over 4

The current cell value

=back

=head3 row

=over 4

an array reference containing the current row

=back

=head3 options

=over 4

a hash containing the current rendering options:

 {
   current_row          - the current row of data
   row_type             - the current row type (data, group_header, ...)
   current_value        - the current value of this cell
   cell                 - the cell definition ( get x position and width from this )
   cell_counter         - position of the current cell in the row ( 0 .. n - 1 )
   cell_y_border        - the bottom of the cell
   cell_full_height     - the height of the cell
   page                 - the current page ( a PDF::API2 page )
   page_no              - the current page number
 }

=back

Note that prior to version 1.4, we only passed the value.

=back

=head2 background_func

=over 4

A user-defined sub that returns a colour for the cell background. Your background_func will be passed:

=over 4

=head3 value

=over 4

The current cell value

=back

=head3 row

=over 4

an array reference containing the current row

=back

=head3 options

=over 4

a hash containing the current rendering options:

 {
   current_row          - the current row of data
   row_type             - the current row type (data, group_header, ...)
   current_value        - the current value of this cell
   cell                 - the cell definition ( get x position and width from this )
   cell_counter         - position of the current cell in the row ( 0 .. n - 1 )
   cell_y_border        - the bottom of the cell
   cell_full_height     - the height of the cell
   page                 - the current page ( a PDF::API2 page )
   page_no              - the current page number
 }

=back

=back

=head2 custom_render_func

=over 4

A user-define sub to replace the built-in text / image rendering functions
The sub will receive a hash of options:

 {
   current_row          - the current row of data
   row_type             - the current row type (data, group_header, ...)
   current_value        - the current value of this cell
   cell                 - the cell definition ( get x position and width from this )
   cell_counter         - position of the current cell in the row ( 0 .. n - 1 )
   cell_y_border        - the bottom of the cell
   cell_full_height     - the height of the cell
   page                 - the current page ( a PDF::API2 page )
 }

=back

=head2 aggregate_function

=over 4

Possible values are "sum" and "count". Setting this attribute will make PDF::ReportWriter carry
out the selected function and store the results ( attached to the cell ) for later use in group footers.

=back

=head2 type ( LEGACY )

=over 4

Please see the 'format' key, below, for improved numeric / currency formatting.

This key turns on formatting of data.
The possible values currently are 'currency', 'currency:no_fill' and 'thousands_separated'.

There is also another special value that allows custom formatting of text cells: C<custom:{classname}>.
If you define the cell type as, for example, C<custom:my::formatter::class>, the cell text that
will be output is the return value of the following (pseudo) code:

	my $formatter_object = my::formatter::class->new();
	$formatter_object->format({
		cell    => { ... },                 # Cell object "properties"
		options => { ... },                 # Cell options
		string  => 'Original cell text',    # Cell actual content to be formatted
	});

An example of formatter class is the following:

	package formatter::greeter;
	use strict;

	sub new {
		bless \my $self
	}
	sub format {
		my $self = $_[0];
		my $args = $_[1];

		return 'Hello, ' . $args->{string};
	}

This class will greet anything it is specified in its cell.
Useful, eh?!  :-)

=back

=head2 format

=over 4

This key is a hash that controls numeric and currency formatting. Possible keys are:

 {
   currency             - a BOOLEAN that causes all value to have a dollar sign prepeneded to them
   decimal_places       - an INT that indicates how many decimal places to round values to
   decimal_fill         - a BOOLEAN that causes all decimal values to be filled to decimal_places places
   separate_thousands   - a BOOLEAN that turns on thousands separating ( ie with commas )
   null_if_zero         - a BOOLEAN that causes zero amounts to render nothing ( NULL )
 }

=back

=head2 background

=over 4

A hash containing details on how to render the background of the cell. See below.

=back

=head1 IMAGES

You can define images in any cell ( data, or group header / footer ).
The default behaviour is to render the image at its original size.
If the image won't fit horizontally, it is scaled down until it will.
Images can be aligned in the same way as other fields, with the 'align' key.

The images hash has the following keys:

=head2 path

=over 4

The full path to the image to render ( currently only supports png and jpg ).
You should either set the path, or set the 'dynamic' flag, below.

=back

=head2 dynamic

=over 4

A boolean flag to indicate that the full path to the image to use will be in the data array.
You should either set a hard-coded image path ( above ), or set this flag on.

=back

=head2 scale_to_fit

=over 4

A boolean value, indicating whether the image should be scaled to fit the current cell or not.
Whether this is set or not, scaling will still occur if the image is too wide for the cell.

=back

=head2 height

=over 4

You can hard-code a height value if you like. The image will be scaled to the given height value,
to the extent that it still fits length-wise in the cell.

=back

=head2 buffer

=over 4

A *minimum* white-space buffer ( in points ) to wrap the image in. This defaults to 1, which
ensures that the image doesn't render over part of the cell borders ( which looks bad ).

=back

=head1 BACKGROUNDS

You can define a background for any cell, including normal fields, group header & footers, etc.
For data headers ONLY, you must ( currently ) set them up per data set, instead of per field. In this case,
you add the background key to the 'headings' hash in the main data hash.

The background hash has the following keys:

=head2 shape

=over 4

Current options are 'box' or 'ellipse'. 'ellipse' is good for group headers.
'box' is good for data headers or 'normal' cell backgrounds. If you use an 'ellipse',
it tends to look better if the text is centred. More shapes are needed.
A 'round_box', with nice rounded edges, would be great. Send patches. 

=back

=head2 colour

=over 4

The colour to use to fill the background's shape. Keep in mind with data headers ( the automatic
headers that appear at the top of each data set ), that you set the *foreground* colour via the
field's 'header_colour' key, as there are ( currently ) no explicit definitions for data headers.

=back

=head2 border

=over 4

The colour ( if any ) to use to render the cell's border. If this is set, the border will be a rectangle,
around the very outside of the cell. You can have a shaped background and a border rendererd in the
same cell.

=over 4

=head2 borders

If you have set the border key ( above ), you can also define which borders to render by setting
the borders key with the 1st letter(s) of the border to render, from the possible list of:

 l   ( left border )
 r   ( right border )
 t   ( top border )
 b   ( bottom border )
 all ( all borders ) - this is also the default if no 'borders' key is encountered

eg you would set borders = "tlr" to have all borders except the bottom ( b ) border

Upper-case letters will also work.

=back

=back

=head1 BARCODES

You can define barcodes in any cell ( data, or group header / footer ).
The default barcode type is B<code128>. The available types are B<code128> and
B<code39>.

The barcode hash has the following keys:

=over 4

=item type

Type of the barcode, either B<code128> or B<code39>. Support for other barcode types
should be fairly simple, but currently is not there. No default. 

=item x, y

As in text cells.

=item scale

Defines a zoom scale for barcode, where 1.0 means scale 1:1.

=item align

Defines the alignment of the barcode object. Should be C<left> (or C<l>),
C<center> (or C<c>), or C<right> (or C<r>). This should work as expected either
if you specify absolute x,y coordinates or not.

=item font_size

Defines the font size of the clear text that appears below the bars.
If not present, takes report C<default_font_size> property.

=item font

Defines the font face of the clear text that appears below the bars.
If not present, takes report C<default_font> property.

=item zone

Regulates the height of the barcode lines.

=item upper_mending_zone, lower_mending_zone

Space below and above barcode bars? I tried experimenting a bit, but
didn't properly understand what C<upper_mending_zone> does.
C<lower_mending_zone> is the height of the barcode extensions toward the
lower end, where clear text is printed.
I don't know how to explain these better...

=item quiet_zone

Empty space around the barcode bars? Try to experiment yourself.

=back

=head1 GROUP DEFINITIONS

Grouping is achieved by defining a column in the data array to use as a group value. When a new group
value is encountered, a group footer ( if defined ) is rendered, and a new group header ( if defined )
is rendered. At present, the simple group aggregate functions 'count' and 'sum' are supported - see the
cell definition section for details on how to chose a column to perform aggregate functions on, and below
for how to retrieve the aggregate value in a footer. You can perform one aggregate function on each column
in your data array.

As of version 0.9, support has been added for splitting data from a single field ( ie the group value
from the data_column above ) into multiple cells. To do this, simply pack your data into the column
identified by data_column, and separate the fields with a delimiter. Then in your group definition,
set up the cells with the special keys 'delimiter' and 'index' ( see below ) to identify how to
delimit the data, and which column to use for the cell once the data is split. Many thanks to
Bill Hess for this patch :)

Groups have the following attributes:

=head2 name

=over 4

The name is used to identify which value to use in rendering aggregate functions ( see aggregate_source, below ).
Also, a special name, "GrandTotals" will cause PDF::ReportWriter to fetch *Grand* totals instead of group totals.

=back

=head2 page_break

=over 4

Set this to TRUE if you want to cause a page break when entering a new group value.

=back

=head2 data_column

=over 4

The data_column refers to the column ( starting at 0 ) of the data_array that you want to group on.

=back

=head2 reprinting_header

=over 4

If this is set, the group header will be reprinted on each new page

=back

=head2 header_upper_buffer / header_lower_buffer / footer_upper_buffer / footer_lower_buffer

=over 4

These 4 keys set the respective buffers ( ie whitespace ) that separates the group
headers / footers from things above ( upper ) and below ( lower ) them. If you don't specify any
buffers, default values will be set to emulate legacy behaviour.

=back

=head2 header / footer

=over 4

Group headers and footers are defined in a similar way to field definitions ( and rendered by the same code ).
The difference is that the cell definition is contained in the 'header' and 'footer' hashes, ie the header and
footer hashes resemble a field hash. Consequently, most attributes that work for field cells also work for
group cells. Additional attributes in the header and footer hashes are:

=back

=head2 aggregate_source ( footers only )

=over 4

This is used to indicate which column to retrieve the results of an aggregate_function from
( see cell definition section ).

=back

=head2 delimiter ( headers only )

=over 4

This optional key is used in conjunction with the 'index' key ( below ) and defines the
delimiter character used to separate 'fields' in a single column of data.

=back

=head2 index ( headers only )

=over 4

This option key is used inconjunction with the 'delimiter' key ( above ), and defines the
'column' inside the delimited data column to use for the current cell.

=back

=head1 REPORT DEFINITION

Possible attributes for the report defintion are:

=head2 destination

=over 4

The path to the destination ( the pdf that you want to create ).

=back

=head2 paper

=over 4

Supported types are:

=over 4

 - A4
 - Letter
 - bsize
 - legal

=back

=back

=head2 orientation

=over 4

portrait or landscape

=back

=head2 template

=over 4

Path to a single page PDF file to be used as template for new pages of the report.
If PDF is multipage, only first page will be extracted and used.
All content in PDF template will be included in every page of the final report.
Be sure to avoid overlapping PDF template content and report content.

=back

=head2 font_list

=over 4

An array of font names ( from the corefonts supported by PDF::API2 ) to set up.
When you include a font 'family', a range of fonts ( roman, italic, bold, etc ) are created.

=back

=head2 default_font

=over 4

The name of the font type ( from the above list ) to use as a default ( ie if one isn't set up for a cell ).

=back

=head2 default_font_size

=over 4

The default font size to use if one isn't set up for a cell.
This is no longer required and defaults to 12 if one is not given.

=back

=head2 x_margin

=over 4

The amount of space ( left and right ) to leave as a margin for the report.

=back

=head2 y_margin

=over 4

The amount of space ( top and bottom ) to leave as a margin for the report.

=back

=head1 DATA DEFINITION

The data definition wraps up most of the previous definitions, apart from the report definition.
You can now safely replace the entire data definition after a render() operation, allowing you
to define different 'sections' of a report. After replacing the data definition, you simply
render() with a new data array.

Attributes for the data definition:

=head2 cell_borders

=over 4

Whether to render cell borders or not. This is a legacy option - not that there's any
pressing need to remove it - but this is a precursor to background->{border} support,
which can be defined per-cell. Setting cell_borders in the data definition will cause
all data cells to be filled out with: background->{border} set to grey.

=back

=head2 upper_buffer / lower_buffer

=over 4

These 2 keys set the respective buffers ( ie whitespace ) that separates each row of data
from things above ( upper ) and below ( lower ) them. If you don't specify any
buffers, default values of zero will be set to emulate legacy behaviour.

=back

=head2 no_field_headers

=over 4

Set to disable rendering field headers when beginning a new page or group.

=back

=head2 fields

=over 4

This is your field definition hash, from above.

=back

=head2 groups

=over 4

This is your group definition hash, from above.

=back

=head2 data_array

=over 4

This is the data to render.
You *MUST* sort the data yourself. If you are grouping by A, then B and you want all data
sorted by C, then make sure you sort by A, B, C. We currently don't do *any* sorting of data,
as I only intended this module to be used in conjunction with a database server, and database
servers are perfect for sorting data :)

=back

=head2 page

=over 4

This is a hash describing page headers and footers - see below.

=back

=head1 PAGE DEFINITION

The page definition is a hash describing page headers and footers. Possible keys are:

=head2 header

=head2 footer

=over 4

Each of these keys is an array of cell definitions. Unique to the page *footer* is the ability
to define the following special tags:

=over 4

%TIME%

%PAGE%

%PAGES%

=back

These will be replaced with the relevant data when rendered.

If you don't specify a page footer, one will be supplied for you. This is to provide maximum
compatibility with previous versions, which had page footers hard-coded. If you want to supress
this behaviour, then set a value for 'footerless' (see below)

=back

=head2 footerless

=over 4

A boolean flag to indicate whether the footer should be printed.  When set to true, no footer will
be rendered on the page (regardless of any 'footer' definition).

=back

=head2 attach_footer

=over 4

A boolean flag to indicate whether the footer should be rendered attached to the last printed row.  When
set to true, the footer will be positioned directly under the last printed row.  When not set (default)
the page footer is rendered at the bottom of the page.

=back

=head1 MULTI-LINE ROWS

=over 4

You can define 'multi-line' rows of cell definitions by simply appending all subsequent lines
to the array of cell definitions. When PDF::ReportWriter sees a cell with a percentage that would
push the combined percentage beyond 100%, a new-line is assumed.

=back

=back

=head1 METHODS

=head2 new ( report_definition )

=over 4

Object constructor. Pass the report definition in.

=back

=head2 render_data ( data_definition )

=over 4

Renders the data passed in.

You can call 'render_data' as many times as you want, with different data and definitions.
If you want do call render_data multiple times, though, be aware that you will have to destroy
$report->{data}->{field_headers} if you expect new field headers to be automatically generated
from your cells ( ie if you don't provide your own field_headers, which is probably normally
the case ). Otherwise if you don't destroy $report->{data}->{field_headers} and you don't provide
your own, you will get the field headers from the last render_data() operation.

=back

=head2 render_report ( xml [, data ] )

=over 4

Should be used when dealing with xml format reports. One call to rule them all.
The first argument can be either an xml filename or a C<PDF::ReportWriter::Report>
object. The 2nd argument is the real data to be used in your report.
Example of usage for first case (xml file):

	my $rw = PDF::ReportWriter->new();
	my @data = (
		[2004, 'Income',               1000.000 ],
		[2004, 'Expenses',              500.000 ],
		[2005, 'Income',               5000.000 ],
		[2005, 'Expenses',              600.000 ],
		[2006, 'Income (projection)',  9999.000 ],
		[2006, 'Expenses (projection),  900.000 ],
	);
	$rw->render_report('./account.xml', \@data);
	
	# Save to disk
	$rw->save();

	# or get a scalar with all pdf document
	my $pdf_doc = $rw->stringify();

For an example of xml report file, take a look at C<examples>
folder in the PDF::ReportWriter distribution or to
C<PDF::ReportWriter::Examples> documentation.

The alternative form allows for more flexibility. You can pass a
C<PDF::ReportWriter::Report> basic object with a report profile
already loaded. Example:

	my $rw = PDF::ReportWriter->new();
	my $rp = PDF::ReportWriter::Report->new('./account.xml');
	# ... Assume @data as before ...
	$rw->render_report($rp, \@data);
	$rw->save();

If you desire the maximum flexibility, you can also pass B<any> object
in the world that supports C<load()> and C<get_data()> methods, where
C<load()> should return a B<complete report profile> (TO BE CONTINUED),
and C<get_data()> should return an arrayref with all actual records that
you want your report to include, as returned by DBI's C<selectall_arrayref()>
method.

As with C<render_data>, you can call C<render_report> as many times as you want.
The PDF file will grow as necessary. There is only one problem in rendering
of header sections when re-calling C<render_report>.

=back

=head2 fetch_group_results( { cell => "cell_name", group => "group_name" } )

=over 4

This is a convenience function that allows you to retrieve current aggregate values.
Pass a hash with the items 'cell' ( the name of the cell with the aggregate function ) and
'group' ( the group level you want results from ). A good place to use this function is in
conjunction with a cell's custom_render_func(). For example, you might create a
custom_render_func to do some calculations on running totals, and use fetch_group_results() to
get access to those running totals.

=back

=head2 new_page

=over 4

Creates a new page, which in turn calls ->page_template ( see below ).

=back

=head2 page_template ( [ path_to_template ] )

=over 4

This function creates a new page ( and is in fact called by ->new_page ).<
If called with no arguements, it will either use default template, or if there is none,
it will simply create a blank page. Alternatively, you can pass it the path to a PDF
to use as a template for the new page ( the 1st page of the PDF that you pass will
be used ).

=back
 
=head2 save

=over 4

Saves the pdf file ( in the location specified in the report definition ).

=back

=head2 saveas ( newfile )

=over 4

Saves the pdf file in the location specified by C<newfile> string and
overrides default report C<destination> property.

=back

=head2 stringify

=over 4

Returns the pdf document as a scalar.

=back

=head2 print ( options )

=over 4

Tries to print the report pdf file to a CUPS print queue. For now, it only works
with CUPS, though you can supply several options to drive the print job as you like.
Allowed options, to be specified as an hash reference, with their default values,
are the following:

=over 4

=item command

The command to be launched to spool the pdf report (C</usr/bin/lpr.cups>).

=item printer

Name of CUPS printer to print to (no default). If not specified,
takes your system default printer.

=item tempdir

Temporary directory where to put the spool file (C</tmp>).

=item unlink

If true, deletes the temporary spool file (C<true>).

=back

=back

=head1 EXAMPLES

=over 4

Check out the C<examples> folder in the main PDF::ReportWriter distribution that
contains a simple demonstration of results that can be achieved.

=back

=head1 AUTHORS

=over 4

 Dan <dan@entropy.homelinux.org>
 Cosimo Streppone <cosimo@cpan.org>
 Scott Mazur <scott@littlefish.ca>
 

=back

=head1 BUGS

=over 4

I think you must be mistaken.

=back

=head1 ISSUES

=over 4

In the last release of PDF::ReportWriter, I complained bitterly about printing PDFs from Linux.
I am very happy to be able to say that this situation has improved significantly. Using the
latest versions of evince and poppler ( v0.5.1 ), I am now getting *perfect* results when
printing. If you are having issues printing, I suggest updating to the above.

=back

=head1 Other cool things you should know about:

=over 4

This module is part of an umbrella project, 'Axis', which aims to make
Rapid Application Development of database apps using open-source tools a reality.
The project includes:

 Gtk2::Ex::DBI                 - forms
 Gtk2::Ex::Datasheet::DBI      - datasheets
 PDF::ReportWriter             - reports

All the above modules are available via cpan, or for more information, screenshots, etc, see:
http://entropy.homelinux.org/axis

=back

=head1 Crank ON!

=cut
