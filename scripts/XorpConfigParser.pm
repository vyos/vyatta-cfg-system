# Perl module for parsing config files.

use lib "/opt/vyatta/share/perl5/";

package XorpConfigParser;

use strict;
my %data;

my %fields = ( _data => \%data );

sub new {
    my $that  = shift;
    my $class = ref($that) || $that;
    my $self  = { %fields, };

    bless $self, $class;
    return $self;
}

#
# This method is used to copy nodes whose names begin with a particular string
# from one array to another.
#
# Parameters:
#
# $from		Reference to the source array
# $to		Reference to the destination array
# $name		The string with which the beginning of the node names will be matched
#
sub copy_node {
    my ( $self, $from, $to, $name ) = @_;
    if ( !defined($from) || !defined($to) || !defined($name) ) {
        return;
    }

    foreach my $node (@$from) {
        my $stringNodeNameHere = $node->{'name'};
        if ( $stringNodeNameHere =~ /^$name.*/ ) {
            foreach my $nodeCheck (@$to) {
                my $stringCheck = $nodeCheck->{'name'};
                if ( $name eq $stringCheck ) {
                    $nodeCheck->{'value'}    = $node->{'value'};
                    $nodeCheck->{'children'} = $node->{'children'};
                    $nodeCheck->{'comment'}  = $node->{'comment'};
                    $nodeCheck->{'disable'}  = $node->{'disable'};
                    return;
                }
            }
            push( @$to, $node );
        }
    }
}

#
# This method is used to create duplicate copies of multinodes with the name
# specified, and to return the new copies in a new array.
#
#  $nodes	A reference to an array of multinodes
#  $name	The name of the multinodes to copy into the new array
#
sub copy_multis {
    my ( $self, $nodes, $name ) = @_;

    return if ( !defined($nodes) || !defined($name) );

    my @multis;

    foreach my $node (@$nodes) {
        my $stringNodeNameHere = $node->{'name'};
        if ( $stringNodeNameHere =~ /$name\s(\S+)/ ) {
            my $stringNameHere = $1;
            my %multi          = (
                'name'     => $stringNameHere,
                'comment'  => $node->{'comment'},
                'value'    => $node->{'value'},
                'disable'  => $node->{'disable'},
                'children' => $node->{'children'}
            );
            push( @multis, \%multi );
        }
    }

    return @multis;
}

#
# This method is used to comment out a particular child.
#
#  $children	A reference to an array of children
#  $name	The name of the child to comment out
#  $comment	The comment string that will be included inside the comment
#
sub comment_out_child {
    my ( $self, $children, $name, $comment ) = @_;
    if ( !defined($children) || !defined($name) ) {
        return;
    }

    for ( my $i = 0 ; $i < @$children ; $i++ ) {
        my $stringNodeNameHere = @$children[$i]->{'name'};
        if ( $name eq $stringNodeNameHere ) {
            $self->comment_out_node( @$children[$i] );
            if ( defined($comment) ) {
                @$children[$i]->{'comment_out'} = $comment;
            }
        }
    }
}

#
# This method is used to comment out a particular node.
#
#  $node	A reference to the node to comment out
#
sub comment_out_node {
    my ( $self, $node ) = @_;
    if ( !defined($node) ) {
        return;
    }

    $node->{'comment_out'} = "1";
}

#
# This method is used to create a node with the path specified.  The method
# will create parent nodes as necessary.
#
#  $path	A reference to the array containing the path segments
#
sub create_node {
    my ( $self, $path ) = @_;

    my $hash = \%data;
  SEGMENT:
    foreach my $segment (@$path) {
        my $children = $hash->{'children'};

        unless ($children) {
            my @new_children;
            $hash->{'children'} = \@new_children;
            $children = \@new_children;
        }

        foreach my $child (@$children) {
            my $name = $child->{'name'};
            next unless $name;

            if ( $name eq $segment ) {
                $hash = $child;		# record insertion point
                next SEGMENT;
            }
        }

        my %new_hash = ( 'name' => $segment );

	if ($hash != \%data) {
	    # insertion in subtree
	    push @$children, \%new_hash;
	} else {
	    # special case for insertion at top put new before version comment
	    my @comments;
	    while (my $child = pop @$children) {
		if ($child->{'comment'}) {
		    unshift @comments, $child;
		} else {
		    push @$children, $child;
		    last;
		}
	    }

	    push @$children, \%new_hash;
	    push @$children, @comments;
	}
        $hash = \%new_hash;
    }
    return $hash;
}

#
# This method is used to delete a child node with the name specified from an array of child nodes.
#
#  $children	A reference to the array of child nodes
#  $name	The name of the child node to delete
#
sub delete_child {
    my ( $self, $children, $name ) = @_;
    return if ( !defined($children) || !defined($name) );

    for ( my $i = 0 ; $i < @$children ; $i++ ) {
        my $stringNodeNameHere = @$children[$i]->{'name'};
        if ( $name eq $stringNodeNameHere ) {
            @$children[$i] = undef;
        }
    }
}

#
# This method is used to return a reference to the child node
# with the name specified.
#
#  $children	A reference to an array containing the child nodes.
#  $name	The name of the child node reference to which will be returned.
#
# If the child node with the name specified is not found,
# then 'undef' is returned.
#
sub find_child {
    my ( $self, $children, $name ) = @_;
    return if ( !defined($children) || !defined($name) );

    foreach my $child (@$children) {
        return $child if ( $name eq $child->{'name'} );
    }
    return;
}

# $ref: reference to the node to be used as the starting point.
# the same as node_exists() except that the starting point is the specified
# node (instead of root).
sub node_exists_with_ref {
    my ( $self, $ref, $path ) = @_;
    my @parr = split / /, $path;
    if ( defined( $self->get_node_with_ref( $ref, \@parr ) ) ) {
        return 1;
    }
    return 0;
}

# $path: a space-delimited string representing the path to a node.
#        e.g., 'interfaces ethernet eth0'. note that the path
#        is relative from the root level.
# returns 1 if the specified node exists. otherwise returns 0.
sub node_exists {
    my ( $self, $path ) = @_;
    my @parr = split / /, $path;

    return $self->get_node( \@parr );
}

# $ref: reference to the node to be used as the starting point.
# the same as get_node() except that the starting point is the specified
# node (instead of root).
sub get_node_with_ref {
    my ( $self, $ref, $path ) = @_;
    my $hash = $ref;

  SEGMENT:
    foreach my $segment (@$path) {
        my $children = $hash->{'children'};
        return unless $children;

        foreach my $child (@$children) {
            next unless ( $child->{'name'} eq $segment );

            $hash = $child;
            next SEGMENT;
        }

        # No children matched segment
        return;
    }

    return $hash;
}

#
# This method is used to return a reference to the hash
# of the node with the path specified.
#
#  $path - reference to an array containing the path segments of the node.
#
# If the path is invalid, then undef is returned.
sub get_node {
    my ( $self, $path ) = @_;

    return $self->get_node_with_ref( $self->{_data}, $path );
}

#
# Move a subtree from one place to another in hierarchy
# Assumes both $from and $to exist
# Returns undef if no match
sub move_child {
    my ( $self, $from, $to, $name ) = @_;
    my $source = $from->{'children'};
    return unless $source;

    for ( my $i = 0 ; $i < @$source ; $i++ ) {
        my $match = @$source[$i];
        next unless $match->{'name'} eq $name;
        splice @$source, $i, 1;    # remove old list

        my $children = $to->{'children'};
        unless ($children) {
            my @new_children;
            $to->{'children'} = \@new_children;
            $children = \@new_children;
        }

        push @$children, $match;
        return $match;
    }

    return;
}

#
# This method is used to insert a comment at a particular path.
#
#  $path	A reference to an array containing the path segments to the
#               node for which the comment is to be inserted.  The comment
#               will appear above the node.
#
# If the node with the path specified does not exist, a node with empty name
# will be created for the comment.
#
sub push_comment {
    my ( $self, $path, $comment ) = @_;

    my $hash = \%data;
    foreach my $segment (@$path) {
        my $children = $hash->{'children'};
        if ( !defined($children) ) {
            my @children;
            $hash->{'children'} = \@children;
            $children = \@children;
        }

        my $child_found = 0;
        foreach my $child (@$children) {
            if ( $child->{'name'} eq $segment ) {
                $child_found = 1;
                $hash        = $child;
                last;
            }
        }

        if ( $child_found == 0 ) {
            my %new_hash = ( 'name' => $segment );
            push( @$children, \%new_hash );
            $hash = \%new_hash;
        }
    }

    my %new_comment = ( 'comment' => $comment );
    my $childrenPush = $hash->{'children'};
    if ( !defined($childrenPush) ) {
        my @new_children;
        $hash->{'children'} = \@new_children;
        $childrenPush = \@new_children;
    }
    push( @$childrenPush, \%new_comment );
}

#
# This method is used to set the value of a particular node
#
#  $path	A reference to an array containing the path segments to the node
#  $value	String of the value to set
#
sub set_value {
    my ( $self, $path, $value ) = @_;

    my $hash = $self->create_node($path);
    if ( defined($hash) ) {
        $hash->{'value'} = $value;
    }
}

#
# This method is used to set the value of a particular node
#
#  $path	A reference to an array containing the path segments to the node
#  $value	String of the value to set
#
sub set_disable {
    my ( $self, $path ) = @_;
    my $hash = $self->create_node($path);
    if ( defined($hash) ) {
        $hash->{'disable'} = 'true';
    }
}

#
# This method is used to generate the output of the node tree in the XORP config
# file format.  The output is printed out to currently selected standard out.
#
#  $depth	Number of indents, used when this method calls itself
#               recursively, should be 0 when used.
#  $hash	A reference to the parent node, should be the roor node when
#               used.
#
sub output {
    my ( $self, $depth, $hash ) = @_;

    $hash = $self->{_data} unless $hash;

    my $comment = $hash->{'comment'};
    print '/*' . $comment . "*/\n"
      if $comment;

    my $children = $hash->{'children'};
    foreach my $child (@$children) {
        next unless $child;
        my $name = $child->{'name'};

        my $comment_out = $child->{'comment_out'};
        if ($comment_out) {
            print "\n";
            print "/*   --- $comment_out ---   */\n"
              if ( $comment_out ne "1" );
            print
"/*   --- CONFIGURATION COMMENTED OUT DURING MIGRATION BELOW ---\n";
        }

        print "    " x $depth;
        my $value = $child->{'value'};
        if ($value) {
            print "$name $value";
            print "\n";
        }
        else {
            my $print_brackets = 0;
            my $children       = $child->{'children'};
            if ( defined($children) && @$children > 0 ) {
                $print_brackets = 1;
            }
            elsif ( defined($name) && !( $name =~ /\s/ ) ) {
                $print_brackets = 1;
            }

            if ($name) {
                print "$name";
                if ($print_brackets) {
                    print " {";
                }
                print "\n";
            }

            $self->output( $depth + 1, $child );
            if ($print_brackets) {
                print "    " x $depth;
                print "}\n";
            }
        }

        print
"     --- CONFIGURATION COMMENTED OUT DURING MIGRATION ABOVE ---  */\n\n"
          if ($comment_out);
    }
}

#
# This method is used to parse the XORP config file specified into the internal tree
# structure that the methods above process and manipulate.
#
#  $file	String of the filename to parse
#
sub parse {
    my ( $self, $file ) = @_;

    %data = ();

    open my $in, '<', $file
      or die "Error!  Unable to open file \"$file\".  $!";

    my $contents = "";
    while (<$in>) {
        $contents .= $_;
    }
    close $in;

    my @array_contents = split( '', $contents );

    #	print scalar(@array_contents) . "\n";

    my $length_contents = @array_contents;
    my $colon           = 0;
    my $colon_quote     = 0;
    my $in_quote        = 0;
    my $name            = '';
    my $value           = undef;
    my $disable         = undef;
    my @path;
    my %tree;

    for ( my $i = 0 ; $i < $length_contents ; ) {
        my $c     = $array_contents[$i];
        my $cNext = $array_contents[ $i + 1 ];

        if ( $colon == 1 ) {
            my $value_end = 0;
            if ( $c eq '"' ) {
                $value .= $c;
                if ( $colon_quote == 1 ) {
                    $value_end = 1;
                }
                else {
                    $colon_quote = 1;
                }
            }
            elsif ( $c eq '\\' && $cNext eq '"' ) {
                $value .= '\\"';
                $i++;
            }
            elsif ( defined($value) ) {
                if ( ( length($value) > 0 ) || ( !( $c =~ /\s/ ) ) ) {
                    $value .= $c;
                }
            }

            if ( $colon_quote == 0
                && ( $cNext eq '}' || $cNext eq ';' || $cNext =~ /\s/ ) )
            {
                $value_end = 1;
            }
            $i++;

            if ( $value_end == 1 ) {
                if ( length($value) > 0 ) {

                    #					print "Path is: \"@path\"    Value is: $value\n";
                    $self->set_value( \@path, $value );
                    $value = undef;
                }
                pop(@path);
                $colon_quote = 0;
                $colon       = 0;
            }
            next;
        }

        # ! $colon
        # check for quotes
        if ( $c eq '"' ) {
            if ($in_quote) {
                $in_quote = 0;
            }
            else {
                $in_quote = 1;
            }
            $name .= '"';
            $i++;
            next;
        }
        elsif ( $c eq '\\' && $cNext eq '"' ) {
            $name .= '\\"';
            $i += 2;
            next;
        }

	if ( !$in_quote && $c eq '!' && $cNext eq ' ') {
	    $disable = 'true';
	    $i += 2;
	}
        elsif ( !$in_quote && $c eq '/' && $cNext eq '*' ) {
            my $comment_text = '';
            my $comment_end = index( $contents, '*/', $i + 2 );
            if ( $comment_end == -1 ) {
                $comment_text = substr( $contents, $i + 2 );
            }
            else {
                $comment_text =
                  substr( $contents, $i + 2, $comment_end - $i - 2 );
                $i = $comment_end + 2;
            }

            #			print 'Comment is: "' . $comment_text . "\"\n";
            $self->push_comment( \@path, $comment_text );
        }
        elsif (( !$in_quote && $c eq '{' )
            || ( $c eq ':' && !( $name =~ /\s/ ) )
            || $c eq "\n" )
        {
            $name =~ s/^\s+|\s$//g;

            if ( length($name) > 0 ) {
                push( @path, $name );

		if (defined $disable && $disable eq 'true') {
                $self->set_disable(\@path);
                $disable = undef;
            }

                #				print "Path is: \"@path\"    Name is: \"$name\"\n";
                $self->set_value( \@path, $value );
                $name = '';

                if ( $c eq "\n" ) {
                    pop(@path);
                }
                if ( $c eq ':' ) {
                    $colon = 1;
                }
            }

            $i++;
        }
        elsif ( !$in_quote && $c eq '}' ) {
            pop(@path);
            $name = '';
            $disable = undef;
            $i++;
        }
        elsif ( !$in_quote && $c eq ';' ) {
            $i++;
        }
        else {
            if ( ( length($name) > 0 ) || ( !( $c =~ /\s/ ) ) ) {
                $name .= $c;
            }
            $i++;
        }
    }
}

1;
