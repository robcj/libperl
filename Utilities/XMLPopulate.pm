#!/usr/bin/perl

package Utilities::XMLPopulate;

use 5.012;
use strict;
use warnings FATAL => 'all';
use XML::LibXML;
use Utilities::Characters qw(:ASCII);

=head1 NAME

Utilities::XMLPopulate - populates a simple xml template structure using values provided in a hash. 


=head1 VERSION

Version 1.003

=cut

our $VERSION = '1.003';
$VERSION = eval $VERSION;

=head1 SYNOPSIS

print Utilities::XMLPopulate->new(data=>loadData(), template=>$templatefile)->formatted();

=head1 SUBROUTINES

=head2 new

 Parameters  : 
 Returns     : self-object
 Description : Constructor
               new( data=>$dataHashRef, template=>$templatefile);
               e.g.
                print Utilities::XMLPopulate->new(data=>loadData(), template=>$templatefile)->formatted();

=cut

sub new {
	my $class = shift;
	my $self  = {@_};
	bless $self;
	return $self;
}

=head2 formatResult

 Parameters  : [ XML::LibXML-object ]
 Returns     : formatted XML string
 Description : Returns nicely formatted XML output. 

=cut

sub formatResult {
	my ( $self, $xmlobject ) = @_;
	return $self->resultXML()->toString(2) unless $xmlobject;
	$xmlobject->toString(2);
}

=head2 resultXML

 Parameters  : 
 Returns     : populated XML::LibXML object
 Description : Populates the supplied template XML with data from the data hashref.

=cut

sub resultXML {
	my ($self) = @_;
	my ( $dataHref, $templateDoc ) = ( $self->{data}, $self->{template} );

	# If a filename was supplied then load the xml template data
	unless ( ref $templateDoc ) {
		$templateDoc = XML::LibXML->new()->load_xml( location => $templateDoc );
	}

# Using data in the hash, populate the XML template, starting at the root node (the document's first child)
	return walkChildNodes( $dataHref, $templateDoc->firstChild );
}

=head2 walkChildNodes( $currentHashEl, $parentNode )

 Parameters  : current hashref of XML node, XML::LibXML object of parent node
 Returns     : populated parent node (XML::LibXML object) 
 Description : Given a hashref representing the desired node values and the node that needs to be populated
               Walk the XML node template and look for each element name in the hash.
               Some hash data won't be required for some status types so elements that exist in the hash but not in the XML will be skipped.
               Elements that exist in the XML template but not in the hash will be left as they are.
               If an element exists in the hash and in the XML then the value in the XML will be overridden unless the value is undef. 
   
=cut

sub walkChildNodes {
	my ( $currentHashEl, $parentNode ) = @_;
	my $child = $parentNode->firstChild;

	while ($child) {

		# skip "#text" nodes because they are caused by whitespace in the file.
		if ( $child->nodeType == 1 ) {
			my $name = $child->nodeName;
			if ( exists $currentHashEl->{$name}
				&& defined $currentHashEl->{$name} )
			{
				my $value = $currentHashEl->{$name};
				$child = setNodeValues( $child, $value );
			}
		}
		$child = $child->nextNonBlankSibling() if $child;

	}

	#
	#do {
	#	{    #bare block within do block to allow loop control (next etc)
	#		 # skip "#text" nodes because they are caused by whitespace in the file.
	#		next if $child->nodeType != 1;
	#		my $name = $child->nodeName;
	#		if ( exists $currentHashEl->{$name}
	#			&& defined $currentHashEl->{$name} )
	#		{
	#			my $value = $currentHashEl->{$name};
	#			$child = setNodeValues( $child, $value );
	#		}
	#
	#		}
	#	} while ( $child = $child->nextNonBlankSibling() );

	return $parentNode;
}

=head2 setNodeValues( $node, @values )

 Parameters  : XML::LibXML node object, values list
 Returns     : last added node (XML::LibXML object)
 Description : Replaces a given template node with a node for each of the given values.
               Values can be hashrefs containing nested elements.
  
=cut

sub setNodeValues {
	my ( $node, @values ) = @_;
	foreach my $value (@values) {
		if ( ref($value) eq "ARRAY" ) {
			return setNodeValues( $node, @$value );
		}

		my $clone = $node->cloneNode(1);
		if ( ref($value) eq "HASH" ) {
			$clone = walkChildNodes( $value, $clone );
		}
		else {    # text value node
			$value = nonASCIIFix($value);
			$clone->removeChildNodes();
			$clone->appendText($value);
		}

		#inserts node with new value before the template node.
		$node->parentNode->insertBefore( $clone, $node );
	}

	# Shifts back to the last inserted node
	my $lastNode = $node->previousNonBlankSibling();

	# removes the template node
	$lastNode->parentNode->removeChild($node) if $lastNode;
	return $lastNode;
}

=head1 AUTHOR

Robin CJ, C<< <robin at cameron-jones.net> >>

=head1 CREATED

 2013-11-30

=head1 BUGS

n/a

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Utilities::XMLPopulate

=head1 ACKNOWLEDGEMENTS

n/a

=head1 LICENSE AND COPYRIGHT

Copyright 2014 Robin CJ.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived from a Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, offer to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

1;
