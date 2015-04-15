#!/usr/bin/perl -w

package Utilities::perlUtils;

use strict;
use feature 'say';

=head1 NAME

Utilities::perlUtils - Useful utility subroutines.

=head1 VERSION

Version 1.514

=cut

our $VERSION = '1.514';
$VERSION = eval $VERSION;

=head1 SYNOPSIS

 A wide range of useful subroutines, mostly for string handling
 use Utilities::perlUtils;

=head1 EXPORT

 Exports the following subroutines available for use by default:
 os isWindows isLinux eol isModule getCaller isArray unique say_ sayErr flatten joinPaths

 Optional imports:
  sendEmail help say
  loadConfig loadBasicConfig
  flattenDefined flattenTrue 
  flattenToArrayRef flattenToArray flattenQ flattenQQ valKey  flattenVersion
  listIntersect listIntersectMatch listContains listComplement
  hasContent definedToArray trueToArray
  dateToSec dateFormat timeCalc
 
 EXPORT_TAGS: DateUtils, ListUtils
 
 eg.
 use Utilities::perlUtils;
 use Utilities::perlUtils qw(sendEmail loadConfig loadBasicConfig help);
 use Utilities::perlUtils qw(:DateUtils);
 
=cut

require Exporter;

our @ISA       = qw(Exporter);
our @EXPORT    = qw( eol isModule getCaller isArray unique say_ sayErr flatten joinPaths);
our @EXPORT_OK = qw(sendEmail help say loadConfig loadBasicConfig stacktrace );

our %EXPORT_TAGS = (
	DateUtils => [qw( dateToSec dateFormat timeCalc toJulian)],
	ListUtils => [
		qw( flattenDefined flattenTrue trueToArray isArray unique
		  flattenToArrayRef flattenToArray flattenQ flattenQQ valKey flattenVersion
		  listIntersect listIntersectMatch listContains listComplement
		  hasContent definedToArray lcHashKeys)
	],
	OSUtils => [qw(os isWindows isLinux eol)]
);

Exporter::export_ok_tags( 'DateUtils', 'ListUtils' );
Exporter::export_tags('OSUtils');

=head1 SUBROUTINES

=head2 os

 Parameters  :
 Returns     : string "MSWin" or "linux"
 Description : Returns the OS - MSWin or linux

=cut

sub os {
	return $^O;
}

=head2 isWindows 

 Parameters  :
 Returns     : Boolean
 Description : Returns true if the OS is Windows

=cut

sub isWindows {
	return 1 if ( os =~ /MSWin/i );
	0;
}

=head2 isLinux 

 Parameters  :
 Returns     : Boolean
 Description : Returns true if the OS is Linux

=cut

sub isLinux {
	return 1 if ( os =~ /linux/i );
	0;
}

=head2 eol 

 Parameters  :
 Returns     : eol character for local OS
 Description : Returns the appropriate EOL (end of line/newline) marker for the local OS.
               Currently \n\r for windows, \n for anything else.

=cut

sub eol {
	return "\n";
	if    (isWindows) { return "\n\r" }
	elsif (isLinux)   { return "\n" }
	else { return "\n" }
}

=head2 isModule

 Parameters  : list of module names
 Returns     : Boolean
 Description : Returns true if all modules listed as params are available, false if not.
               Note: The test loads the module using 'use'
               so you may need to import the module content using: ModuleName->import();

=cut

sub isModule {
	foreach (@_) {
		return 0 unless eval "use $_ ; 1;";
	}
	1;
}

##############

=head2 getCaller

 Parameters  :
 Returns     : subroutine name, line number
 Description : Handy for debugging. Returns the calling subroutine's name and the line number.

=cut

sub getCaller {
	my ( $package, $filename, $line, $subname, $hasargs ) = caller(1);
	return ( $subname, $line );
}
##############

=head2 stacktrace

 Parameters  :
 Returns     : Array of stacktrace strings
 Description : Returns array of stacktrace lines from caller()

=cut

sub stacktrace {
	my ($frame) = @_ ? $_[0] + 1 : 1;
	my @frames;
	while ( my ( $package, $filename, $line, $subname, $hasargs, $wantarray, $evaltext, $isrequire ) =
		caller( $frame++ ) )
	{
		my $msg = "Frame: $frame Pkg: $package ; File: $filename ; Line: $line";
		$msg .= " ; Sub: $subname "       if $subname;
		$msg .= " ; Args: $hasargs "      if $hasargs;
		$msg .= " ; Array: $wantarray "   if $wantarray;
		$msg .= " ; Eval: $evaltext "     if $evaltext;
		$msg .= " ; Require: $isrequire " if $isrequire;
		push @frames, $msg;
	}

	return @frames;
}
##############

=head2 isArray

 Parameters  : scalar variable
 Returns     : Boolean
 Description : Returns true if variable is an array ref, else false

=cut

sub isArray {
	return 1 if ( ref( $_[0] ) =~ /ARRAY/i );
	return 0;
}

##############

=head2 unique

 Parameters  : list/array
 Returns     : list/array with duplicates removed
 Description : Return a list derived from the provided list with duplicate values removed.
 
=cut

sub unique {
	logcaller() if ( exists &logdebug );
	my %hash;
	foreach (@_) { $hash{$_}++; }
	return keys %hash;
}

##############

=head2 say

 Parameters  : list of strings
 Returns     : 
 Description : Prints to stdout, the strings each on a newline.
               This is for perl v<5.10 ; use "use feature say;" in perl v>5.10.
 
=cut

sub say {
	print say_(@_);
}

=head2 say_

 Parameters  : list of strings
 Returns     : String
 Description : Returns the provided list of strings as a single string joined together by newlines.

=cut

sub say_ {
	my $eol = eol;
	return join( $eol, @_ ) . $eol;
}

=head2 sayFH

 Parameters  : Filehandle, list of strings
 Returns     : 
 Description : Prints to the Filehandle, the strings joined together by newlines.
               This is for perl v<5.10 ; use "use feature say;" in perl v>5.10.

=cut

sub sayFH {
	my $eol = eol;
	my $fh  = shift;
	print $fh say_(@_);
}

=head2 sayErr

 Parameters  : Filehandle, list of strings
 Returns     : 
 Description : Prints to STDERR the strings, joined together by newlines.

=cut

sub sayErr {

	#sayFH( \*STDERR, @_ );
	say STDERR @_;
}

###########

=head2 loadConfig

 Parameters  : filename , config hashref [, options hashref]
 Returns     : hashref or error message string
 Description : Uses Config::Simple to load the config file into the supplied hashref.
               Removes the 'default.' key prefixes if options hashref->{defaultprefix} is not true.
               Default values can be provided in the options hashref->{default} hash.
               Override values can be provided in the options hashref->{override} hash.
               Config::Simple prefixes .ini style block names onto the element name, e.g. 
               [block]
               element = bla
               
               $config{block.element} == 'bla'
               To change this behaviour to make blocks into sub-elements set options hashref->{blocktree} to true. 
               loadConfig( $filename, \%config, { blocktree => 1 })
               This assumes that no block names contain "." characters, because they will be used to indicate the split.
               
               If Config::Simple is not available then it will do a very basic config file input using the format:
                   key = value
               Multiple values with the same key will be treated as an array.
               Returns the hashref or an error message, so test the output for errors, eg:
                 my $ret = loadConfig($configfile, \%config) ;
                 abort $ret unless ( ref($ret) eq 'HASH')

=cut

sub loadConfig {
	my ( $file, $hashref, $options ) = @_;
	$hashref = {} unless $hashref;

	if ( isModule("Config::Simple") ) {

		#use Config::Simple;
		Config::Simple->import_from( $file, $hashref )
		  or return "Failed to read config $file: " . Config::Simple->error();

		# Config Simple uses .ini style blocks, we aren't using any so it prepends
		# 'default' to each key name.  We will remove that unless defaultprefix option is set:
		if (   !exists( $options->{defaultprefix} )
			|| !$options->{defaultprefix} )
		{
			for ( keys %$hashref ) {
				my ($key) = /^default\.(.*)/;
				next unless $key;
				$hashref->{$key} = delete $hashref->{$_};
			}
		}
	}
	else { loadBasicConfig(@_) unless ( isModule("Config::Simple") ) }

	# Set defaults for undefined config values
	# (do this after using Config::Simple or it will treat them as arrays)
	if ( exists( $options->{defaults} ) ) {
		while ( my ( $key, $value ) = each( %{ $options->{defaults} } ) ) {
			unless ( exists $hashref->{$key} && $hashref->{$key} ) {
				$hashref->{$key} = $options->{defaults}->{$key};
			}
		}
	}

	if ( exists( $options->{override} ) ) {
		while ( my ( $key, $value ) = each( %{ $options->{override} } ) ) {
			$hashref->{$key} = $options->{override}->{$key};
		}
	}

	if ( exists( $options->{blocktree} ) && $options->{blocktree} ) {
		for ( keys %$hashref ) {
			my ( $key1, $key2 ) = /^([^.]+)\.(.*)/;
			next unless $key2;
			$hashref->{$key1}->{$key2} = delete $hashref->{$_};
		}
	}

	return $hashref;
}

=head2 loadBasicConfig

 Parameters  : filename [, config hashref ]
 Returns     : hashref or error message string
 Description : Used by loadConfig() if the Config::Simple module is not available.

=cut

sub loadBasicConfig {
	my ( $file, $hashref ) = @_;
	return "Cannot find config file '$file'." unless ( -f $file );
	return "Could not open config file $file. $!"
	  unless ( open( CONFIG, "<", $file ) );
	$hashref = {} unless $hashref;
	while (<CONFIG>) {
		next if (/^\s*#|^\s*$/);
		chomp;
		my ( $key, $value );
		if (/^\s*(\w+)\s*=\s*(\S.*\S?)\s*$/) {
			( $key, $value ) = ( $1, $2 );
		}
		elsif (/^\s*(\w+)\s*=\s*$/) {
			( $key, $value ) = ( $1, '' );
		}

		if ($value) {
			$value =~ s/^"(.+)"$/$1/;    # strip any surrounding quotes
			$value =~ s/^'(.+)'$/$1/;    # strip any surrounding quotes
		}

		if ( exists $hashref->{$key} && ref( $hashref->{$key} ) ne 'ARRAY' ) {
			$hashref->{$key} = [ $hashref->{$key} ];
			push @{ $hashref->{$key} }, $value;
		}
		else { $hashref->{$key} = $value; }
	}
}

###########

=head2 flatten

 Parameters  : delimiter, list|arrayref|hashref
 Returns     : String
 Description : Takes the list, array ref or hashref passed to it, flattens all the values into a string, delimited by the delimiter.
               Undefined values are replaced with empty strings.
               Like join but also works on array refs and hashrefs and acts recursively until it reaches a scalar value.

=cut

sub flatten {
	return join( shift, map { defined $_ ? $_ : '' } flattenToArray(@_) )
	  if @_;
}

=head2 flattenDefined

 Parameters  : delimiter, list|arrayref|hashref
 Returns     : String
 Description : Takes the list, array ref or hashref passed to it, flattens all defined values into a string, delimited by the delimiter.
               Undefined values are ignored.
               Like join but also works on array refs and hashrefs and acts recursively until it reaches a scalar value.

=cut

sub flattenDefined {
	return join( shift, definedToArray(@_) ) if @_;
}

=head2 flattenTrue

 Parameters  : delimiter, list|arrayref|hashref
 Returns     : String
 Description : Takes the list, array ref or hashref passed to it, flattens all true values (ie. not 0, undef or "") into a string, delimited by the delimiter.
               Undefined values are ignored.
               Like join but also works on array refs and hashrefs and acts recursively until it reaches a scalar value.

=cut

sub flattenTrue {
	return join( shift, trueToArray(@_) ) if @_;
}

=head2 flattenQ

 Parameters  : list|arrayref|hashref
 Returns     : String
 Description : Takes the list, array ref or hashref passed to it, flattens all the values into a string,
               with each element wrapped in single quotes and delimted by a comma and space.
               Useful for SQL string lists.
               Like join but also works on array refs and hashrefs and acts recursively until it reaches a scalar value.

=cut

sub flattenQ {
	return q(') . flatten( q(', '), @_ ) . q(') if $_[0];
}

=head2 flattenQQ

 Parameters  : list|arrayref|hashref
 Returns     : String
 Description : Takes the list, array ref or hashref passed to it, flattens all the values into a string,
               with each element wrapped in double quotes and delimted by a comma and space.
               Like join but also works on array refs and hashrefs and acts recursively until it reaches a scalar value.

=cut

sub flattenQQ {
	return q(") . flatten( q(", "), @_ ) . q(") if $_[0];
}

=head2 flattenVersion

 Parameters  : version as a string
 Returns     : Formatted version as a string
 Description : Returns a 9 digit version of the supplied 1-3 point version number with every number part zero padded to 3 digits.
               Non digit characters suffixing a digit will be ignored.
               eg. 4.1x.12b becomes 004001012
                   4.2 becomes 004002000
                   63 becomes 063000000
 
=cut

sub flattenVersion {
	my @parts = $_[0] =~ /(?:^|\.)(\d+)/g;
	for ( 0 .. 2 ) { $parts[$_] = '0' unless $parts[$_] }
	join "", map { sprintf( "%03d", $_ ) } @parts;
}

=head2 flattenToArray

 Parameters  : list|arrayref|hashref
 Returns     : List
 Description : Recursively turns the deepest scalar values of a an array ref or hash ref into a single level list.
               Returns the list.

=cut

sub flattenToArray {
	my @flat;
	foreach (@_) {
		if ( !defined $_ ) { push @flat, $_ }
		elsif ( ref($_) eq "ARRAY" ) {
			push @flat, map { flattenToArray($_) } @$_;
		}
		elsif ( ref($_) eq "HASH" ) {
			push @flat, flattenToArray( [ values %$_ ] );
		}
		else { push @flat, $_ }
	}
	return @flat;
}

=head2 flattenToArrayRef

 Parameters  : list|arrayref|hashref
 Returns     : List
 Description : Recursively turns the deepest scalar values of a an array ref or hash ref into a single level list.
               Returns the array reference to the list.

=cut

sub flattenToArrayRef {
	[ flattenToArray(@_) ];
}

=head2 definedToArray

 Parameters  : list|arrayref|hashref
 Returns     : List
 Description : Recursively turns the deepest scalar values that are defined (i.e. not undef) of an array ref or hash ref into a single level list.
               Returns the list in list context, or list count in scalar context.

=cut

sub definedToArray {
	grep { defined $_ } flattenToArray @_;
}

=head2 trueToArray

 Parameters  : list|arrayref|hashref
 Returns     : List
 Description : Recursively turns the deepest scalar values that are not false (ie. not 0, undef or "") of an array ref or hash ref into a single level list.
               Returns the list in list context, or list count in scalar context.

=cut

sub trueToArray {
	grep { $_ } flattenToArray @_;
}

=head2 lcHashKeys

 Parameters  : hashref
 Returns     : hashref
 Description : Converts hash keys to lowercase.  Not recursive.

=cut

sub lcHashKeys {
	my $hr = $_[0];
	for my $key ( keys %$hr ) {
		my $lckey = lc($key);
		if ( $lckey ne $key ) {
			$hr->{ lc($key) } = $hr->{$key};
			delete ${$hr}{$key};
		}
	}
	$hr;
}

###########

=head2 joinPaths

 Parameters  : list|arrayref|hashref
 Returns     : path string of concatenated paths
 Description : Takes the list, array ref or hashref passed to it, flattens all the values into a string,
               delimted by the first path delimiter it finds in the string, or by the path delimiter used by the local OS.

=cut

sub joinPaths {
	my @paths = flattenToArray(@_);

	# get the first delimiter found in the paths
	my ($delim) = ( join( "", @paths ) =~ /([\\\/])/ );

	# if there isn't one then use File::Spec to get the local OS delimiter
	if ( !$delim ) { ($delim) = ( File::Spec->catfile( "a", "b" ) =~ /a(.)b/ ) }

	# Get the leading delim if there is one, or two
	my ($lead) = ( $paths[0] =~ /^([\\\/]*)/ );

	# Strip the leading and trailing delims from each path
	map { $_ =~ s/(?:^[\\\/]|[\\\/]$)//g } @paths;

	# split any paths that contain more directories
	my @parts;
	for my $path (@paths) {
		push @parts, split( /[\\\/]/, $path );
	}

	# Assemble the path using the derived delimiter
	my $path = $lead . join( $delim, @paths );
	$path;
}

=head2 hasContent

 Parameters  : list|arrayref|hashref
 Returns     : Integer
 Description : Recursively counts the deepest scalar values that are not false (ie. not 0, undef or "") of a an array ref or hash ref into a single level list.
 Returns list count.

=cut

sub hasContent {
	my $count;
	foreach (@_) {
		if ( ref($_) eq "ARRAY" ) {
			for (@$_) { $count += hasContent($_) if $_ }
		}
		elsif ( ref($_) eq "HASH" ) { $count += hasContent( [ values %$_ ] ) }
		else { $count++ if $_ }
	}
	return $count;
}

=head2 listContains

 Parameters  : string|list|arrayref|hashref, value
 Returns     : Integer
 Description : For the given list or array reference, and a value: returns the count of values that match in scalar context, or list of matches (as per grep).
               Returns 0 (false) if the value is not found.

=cut

sub listContains {
	my $value = pop @_;
	0 unless grep $value eq $_, flattenToArray(@_);
}

=head2 valKey

 Parameters  : arrayref|hashref, value
 Returns     : Array/hash key
 Description : For the given arrayref or hashref returns the names of the keys whose values match the given value.

=cut

sub valKey {
	my ( $ref, $value ) = @_;
	my @array;
	if ( ref($ref) eq "ARRAY" ) {
		foreach ( 0 .. @$_ - 1 ) { push @array, $_ if $ref->[$_] eq $value }
	}
	elsif ( ref($ref) eq "HASH" ) {
		foreach ( keys %{$ref} ) { push @array, $_ if $ref->{$_} eq $value }
	}
	return @array;
}

=head2 listComplement

 Parameters  : arrayref, arrayref
 Returns     : List
 Description : Returns list of elements that exist in list A but not in list B

=cut

sub listComplement {
	my ( $listrefA, $listrefB ) = @_;
	grep !${ { map { $_, 1 } @{$listrefB} } }{$_}, @{$listrefA};
}

=head2 listIntersect

 Parameters  : arrayref, arrayref [, arrayref ...]
 Returns     : List
 Description : Returns list of elements that exist in all parameters (arrays provided as arrayrefs).
 The returned list values are in the same order as list A if only 2 lists are provided,
  otherwise they will be in the order of the earliest list they are found in. 

=cut

sub listIntersect {
	my $listrefA = shift @_;
	while ( my $listrefB = shift @_ ) {
		$listrefA = [ grep ${ { map { $_, 1 } @{$listrefB} } }{$_}, @{$listrefA} ];
	}
	@{$listrefA};
}

=head2 listIntersectMatch

 Parameters  : arrayref, arrayref
 Returns     : hashref
 Description : First parameter is a reference to a list of regexes.  Parameter B is a ref to a list of strings. 
 Returns hashref with keys being the regexes (from param 1), and values being lists of elements from list B which match the regex

=cut

sub listIntersectMatch {
	my ( $listrefA, $listrefB ) = @_;
	my %matches;
	foreach my $regex ( @{$listrefA} ) {
		my @match = grep( /$regex/, @{$listrefB} );
		$matches{$regex} = \@match if @match;
	}
	return \%matches;
}

=head2 sendEmail

 Parameters  : headref, body, mailserver, type
 Returns     : Integer return code
 Description : Uses Mail::Mailer to send an email, where:
               headref is a hashref of headers,
               e.g.
                $headref = {Subject => "Subject text", To => [ 'email1@bla.com', 'email2@bla.com' ], From => 'myemail@address.com', "Content-Type" => "text/html"}
               
               $body is the email body in a single string,
               $mailserver is the dns name or ip of the mailserver (optional if defined in the system)
               $type is the mail protocol type, usually smtp
               
               Return codes:
                   0  Failed to create the mail (open())
                  -1 Failed to send and close the mail (close())
                  -2 Unable to load module "Mail::Mailer" - check it is installed.

=cut

sub sendEmail {
	my ( $headref, $body, $mailserver, $type ) = @_;
	$type = 'smtp' unless $type;

	if ( !isModule("Mail::Mailer") ) {
		$! = "Unable to load module 'Mail::Mailer' - check it is installed";
		return -2;
	}
	my $mailer;

	if ($mailserver) {
		eval { $mailer = Mail::Mailer->new( $type, Server => $mailserver ) };
	}
	else {
		eval { $mailer = Mail::Mailer->new($type) };
	}

	my $fh = $mailer->open($headref);
	unless ($fh) { $@ .= "Failed to create the mail (open())"; return 0 }

	print $fh $body;

	# send and close

	unless ( $fh->close ) {
		$@ .= "Failed to send and close the mail (close())";
		return -1;
	}
	1;
}

###########

=head2 help

 Parameters  : 
 Returns     : 
 Description : Displays perldoc for the current script then exits.

=cut

sub help {
	system("perldoc $0");
	exit;
}
##############

=head2 dateToSec

 Parameters  : date string [, date string (for calculations)]
 Returns     : date string in seconds
 Description : Converts a date of any format to the epoch in seconds.
               Also performs date calculations from the present time (or supplied ep) if presented with a relative time, eg. -3 hours
               Accepts relative time units: years months weeks days hours minutes seconds
               Currently a year is always 365 days and a month is always 30 days
               Requires Date::Parse

=cut

sub dateToSec {
	return "You need to install the Date::Parse module to use the dateToSec function."
	  unless ( isModule("Date::Parse") );
	my $date = shift;

	my $epoch = $_[0] ? dateToSec( $_[0] ) : time;

	if ( $date =~ /^\s*([+-])?\s*(\d+)\s*([[:alpha:]]+)$/ ) {

		# looks like we're using the +/- time displacement format
		# prepend a + if a + or - is not present
		my $sign = $1 ? $1 : '+';
		my $disp = "$sign$2";

		if ( $3 =~ /^y/i ) { $epoch += $disp * 60 * 60 * 24 * 365 }
		elsif ( $3 =~ /^mo/i ) {
			$epoch = monthsDisplacement( $disp, $epoch );
		}
		elsif ( $3 =~ /^w/i )  { $epoch += $disp * 60 * 60 * 24 * 7 }
		elsif ( $3 =~ /^d/i )  { $epoch += $disp * 60 * 60 * 24 }
		elsif ( $3 =~ /^h/i )  { $epoch += $disp * 60 * 60 }
		elsif ( $3 =~ /^mi/i ) { $epoch += $disp * 60 }
		elsif ( $3 =~ /^s/i )  { $epoch += $disp }
	}
	elsif ( $date =~ /^\d+$/ ) {

		# purely numeric date supplied, so we'll assume it's seconds since the epoch.
		$epoch = $date;
	}
	else {

		# hopefully it's a full format date recognisable by Date::Parse
		$epoch = str2time($date);
	}

	return $epoch;
}

############

=head2 dateFormat ( <date>, <format> )

 Parameters  : date string, format number
 Returns     : formatted date string
 Description : Convert misc date formats to selected type:
                0: CCYY-MM-DD HH:MM:SS
                1: DD-MM-CCYY HH:MM
                2: CCYY-MM-DD HH:MM
                3: CCYY-MM-DD
                4: CCYY-MM-DD-HH-MM
                5: CCYY-MM-DD-HHMMSS
                6: CCYYMMDDHHMMSS

               Requires Date::Format
               First param is the date in any format, second param is either a number for the selected format type,
               or a format using the % notation, or "julian".
               If first param is not provided or evaluates to false (e.g. 0), then current time is used. 
               Returns reformatted date string.

=cut

sub dateFormat {
	return "You need to install the Date::Format module to use the dateFormat function."
	  unless ( isModule("Date::Format") );
	my ( $date, $format ) = @_;
	my $epoch = $date ? dateToSec($date) : time;
	my @formats = (
		"%Y-%m-%d %H:%M:%S", "%d-%m-%Y %H:%M",    "%Y-%m-%d %H:%M", "%Y-%m-%d",
		"%Y-%m-%d-%H-%M",    "%Y-%m-%d-%H-%M-%S", "%Y%m%d%H%M%S",   "%H:%M:%S",
		"%H%M%S",
	);

	if ( !$format ) { $format = $formats[0] }

	my $formatted;
	if ( $format =~ /^\d$/ ) { $formatted = time2str( $formats[$format], $epoch ) }
	elsif ( $format =~ /^julian$/i ) { $formatted = toJulian($epoch) }
	else { $formatted = time2str( $format, $epoch ); }

	$formatted;
}

=head4 toJulian($uxtimestamp)

 Parameters  : unix timestamp
 Returns     : Julian date
 Description :  Converts the given unixtimestamp to a JDE compatible Julian date,
 				ie. a 6 digit (or 5 digits before the year 2000) integer consisting of:
 				years since 1900 . day of the year
 
=cut

sub toJulian {
	my ($epoch) = @_;
	$epoch = time
	  unless $epoch;
	my ( $yyy, $yday ) = ( localtime($epoch) )[ 5, 7 ];
	$yday = sprintf "%03d", $yday + 1;
	return $yyy . $yday;
}

=head2 timeCalc
 
 Parameters  : hash ref
 Returns     : time (epoch in seconds) adjusted by the hashref attribute values
 Description : hash ref attributes:
               seconds, minutes, hours, days, months, years, time
               Values are all integers, + or -.
               time attribute is any time (in epoch seconds, or date string) if you don't want to calculate from the present time.
               e.g. to calculate the time 3 years, 5 months and 20 minutes ago:
               $ago = timeCalc({ years => -3, months => -5, minutes => -20});
               print scalar localtime($ago);
               To do the same calculation but from a particular date use the time attribute:
               $ago = timeCalc({ time => "3rd February 2016" years => -3, months => -5, minutes => -20});
               print scalar localtime($ago);
               
=cut

sub timeCalc {
	use Time::Local;
	return unless ( ref( $_[0] ) eq "HASH" );
	my ($href) = @_;

	$href->{time} = exists( $href->{time} ) ? dateToSec( $href->{time} ) : time;

	my $epoch = $href->{time};
	$epoch += $href->{seconds};
	$epoch += $href->{minutes} * 60;
	$epoch += $href->{hours} * 60 * 60;
	$epoch += $href->{days} * 60 * 60 * 24;

	my ( $sec, $min, $hour, $day, $mon, $year ) = localtime($epoch);

	$year += $href->{years} + int( $href->{months} / 12 );
	$mon += $href->{months} - ( 12 * int( $href->{months} / 12 ) );
	if ( $mon < 0 ) {
		$year--;
		$mon += 12;
	}
	timelocal( $sec, $min, $hour, $day, $mon, $year );
}

#########
1;
__END__

