#!/usr/bin/perl -w

package Utilities::Characters;

use strict;
use feature 'say';

=head1 NAME

Utilities::Characters - Useful utility subroutines for dealing with special characters.

=head1 VERSION

Version 1.000

=cut

our $VERSION = '1.001';
$VERSION = eval $VERSION;

=head1 SYNOPSIS

 A wide range of useful subroutines, mostly for dealing with special characters such as non-ascii characters which can cause problems.
 use Utilities::Characters;

=head1 EXPORT

 Exports the following subroutines available for use by default:

 Optional imports:
  nonASCII wideChars nonASCIIFix xmlSpecialCharsFix
 
 EXPORT_TAGS: DateUtils, ListUtils
 
 eg.
 use Utilities::Characters;
 use Utilities::Characters qw(nonASCII wideChars nonASCIIFix);
 use Utilities::Characters qw(:ASCII :XML);
 
=cut

require Exporter;

our @ISA       = qw(Exporter);
our @EXPORT    = qw(  );
our @EXPORT_OK = qw( nonASCII wideChars nonASCIIFix xmlSpecialCharsFix );

our %EXPORT_TAGS =
  ( ASCII => [qw( nonASCII nonASCIIFix )], XML => [qw(xmlSpecialCharsFix)], )
  ;

Exporter::export_ok_tags( 'ASCII', 'XML');
Exporter::export_tags();

=head1 SUBROUTINES

=head2 nonASCII

 Parameters  : string
 Returns     : array of positions of non-ASCII characters (0 is first char in string), so equates to true if line contains bad characters
 Description : In Perl, characters from 128 to 255 (inclusive) are by default internally not encoded as UTF-8 for backward compatibility reasons.
 (ref: http://perldoc.perl.org/functions/chr.html ).  Sometimes attempting to write or process strings containing these characters can
 cause programs to crash when you try to print them (or write to a file).
 Also "wide" characters will cause errors if the correct character encoding is not set up or expected. these are UTF-8 characters which are represented by 2 bytes, so are outside the standard 0-255 ASCII range.
 This function detects non-ascii characters in a string and returns their positions so you can fix them before trying to print them.

=cut

sub nonASCII {
	my $count = -1;
	map { $count++; /[^[:ascii:]]/ && $count } split( "", $_[0] );
}

=head2 wideChars

 Parameters  : string
 Returns     : array of positions of "wide" characters, these are UTF-8 characters which are represented by 2 bytes, so are outside the standard 0-255 ASCII range.
 This function detects non-ascii characters in a string and returns their positions so you can fix them before trying to print them. (see nonASCII).

=cut

sub wideChars {
	my $count = -1;
	map { $count++; $count if ord($_) > 255 } split( "", $_[0] );
}

=head2 nonASCIIFix( $string )

 Parameters  : string
 Returns     : Same string, with known 'bad' characters (wide chars or non-UTF8) replaced or removed.
 Description : Currently just replaces problematic apostrophes and hyphens.
 		e.g. Some MS apostrophes are not ASCII.
        They look like "<92>" when the file is catted in bash, have hex value 92, or decimal 146.
        This function returns true if the string contains a chr(146) apostrophe, false if it doesn't
  
=cut

sub nonASCIIFix {
	my ($str) = @_;

# Map of common problematic characters and the character they should be replaced with
	my %badmap = (
		chr(146) => "'"    # maps unicode/MS apostrophe
		, "\x{2013}" => "-"    # unicode "EN DASH" hyphen
		, "\x{c2}"   => "A"    # unicode "A" with circumplex on top
	);

	# Replace the mapped characters
	while ( my ( $badchar, $goodchar ) = each(%badmap) ) {
		$str =~ s/$badchar/$goodchar/g;
	}

	# Remove any other non-ascii characters and replace with a space.
	$str =~ s/[^[:ascii:]]/ /g;
	$str;
}

=head2 xmlSpecialCharsFix( $string, $specials )

 Parameters  : string, optional hashref of special characters and replacement strings
 Returns     : Array containing:
 Same string, with special characters replaced with xml encoded characters;
 Hashref with special chars as keys, and number of replacements as values.
 
 Description : Second argument can be a hashref, which will be appended to the default one which just converts <, > and & to  &lt;, &gt; and &amp;.
 Or second argument can be an integer denoting the 'set' of specials to use.  '2' tells the function to use the default set plus encode apostrophes and double-quotes.
  
=cut

sub xmlSpecialCharsFix {
	my ( $line, $more ) = @_;
	my %specials = (
		'<' => '&lt;',
		'>' => '&gt;',
		'&' => '&amp;'
	);
	if ( $more == 2 ) {
		$more = {
			"'" => '&apos;',
			'"' => '&quot;'
		};
	}
	%specials = ( %specials, %$more ) if ref($more) eq "HASH";
	my $entstring = join "", keys(%specials);
	my %replaced;
	if ( $line =~ /(?!&\w{2,8};)[$entstring]/g ) {
		for my $ent ( keys(%specials) ) {
			my $replacement = $specials{$ent};
			my $changes = ( $line =~ s/(?!&\w{2,8};)$ent)/$replacement/g );
			$replaced{$ent} = $changes if ($changes);
		}
	}
	( $line, \%replaced );
}

#########
1;
__END__

