#!/usr/bin/perl
package Utilities::Logit;

use 5.006;
use strict;
use warnings FATAL => 'all';
use Utilities::perlUtils 1.5;
use Utilities::perlUtils 1.5 qw(stacktrace);
use feature 'say';

=head1 NAME

Utilities::Logit - Module providing simple Logging facilities

=head1 VERSION

Version 2.002

=cut

our $VERSION = 2.002;
$VERSION = eval $VERSION;

=head1 SYNOPSIS

Module provides simple Logging facilities, using non-OO exported functions
to make its usage simple and more concise than OO style would be.

Log levels are any one of (case insensitive): critical warn info debug
 or 1, 2, 3, 4 respectively.

e.g.
	setLogging( "info", "/tmp/logfile.log" );
	logdebug("Starting script"); # will be ignored because max level is currently "info"
	logwarn("Help! Something is wrong!"); # will write that message to the log file
 
 Message will look like:
  2011/07/21 16:44:42 WARN: Help! Something is wrong!

=head1 EXPORT

 Default Exports:
 setLogging logcrit loginfo logwarn logdebug abort logEndSub logcaller logstack
 
 Optional Exports:
 get_datetime

=cut

require Exporter;

our @ISA    = qw(Exporter);
our @EXPORT =
  qw(setLogging logcrit loginfo logwarn logdebug abort logEndSub logcaller logstack);
our @EXPORT_OK = qw(get_datetime);

=head1 GLOBAL VARIABLES

=head2 $logfh

 Filehandle reference which points to the log file
  
=head2 $loglevel

 Holds the current logging level
 
=cut

my $logfh = *STDOUT;
my $loglevel = 0;

=head1 SUBROUTINES

=head2 setLogging

 Parameters  : level, logfile
 Returns     : boolean
 Description : Required for initialising the logging settings.
               Level is one of: critical warn info debug
               or 1, 2, 3, 4 respectively.
               Default is info.
               logfile is a file path, default is STDOUT (/dev/tty) on Linux, 'CON' on Windows
 
=cut

sub setLogging {
	my ( $level, $logfile ) = @_;
	# Set default log level to info and logfile to STDOUT
	$level   = 'info'   unless ($level);
	$logfile = 'STDOUT' unless ($logfile);

	my @levelnames = qw( critical warn info debug );
	if ( !grep( /$level/, @levelnames ) ) {
		sayErr "ERROR: $level is an invalid logging level.";
		sayErr "  Please supply one from: " . join( ", ", @levelnames );
		exit 1;
	}

	if ( $logfile =~ /^STDOUT$/i ) { $logfh = *STDOUT }
	elsif ( !open( $logfh, ">>$logfile" ) ) {
		sayErr "ERROR: Cannot write to log file $logfile";
		return 0;
	}

	$loglevel = 0;
	foreach my $name (@levelnames) {
		$loglevel++;
		last if ( $level =~ /$name/i );
	}
	loginfo("Logging level set to $loglevel, $level.  Writing log to: $logfile.");

}

=head2 logit

 Parameters  : loglevel-prefix, message [, message ...]
 Returns     : boolean
 Description : Used by the log<level> subs to actually write the logging message to the file.

=cut

sub logit {
	my $prefix = shift;
	setLogging unless $logfh;

	# Split message(s) by EOL so we can datestamp and prefix each row
	my $datetime = get_datetime( "now", "logformat" );
	my $eol = eol;
	if (@_) {
		say $logfh "$datetime $prefix $_" foreach map { split $eol, $_, -1 } @_;
	}
	else { say $logfh "" }
}

=head2 logcrit

 Parameters  : message
 Returns     : void
 Description : Writes message preceded by "CRIT:" to the log file.

=cut

sub logcrit {
	unless ( $loglevel < 1 ) {
		logit( "CRIT:", @_ );
		sayErr "CRITICAL ERROR: ", @_;
	}
}

=head2 logwarn

 Parameters  : message
 Returns     : void
 Description : Writes message preceded by "WARN:" to the log file.

=cut

sub logwarn { logit( "WARN:", @_ ) unless $loglevel < 2 }

=head2 loginfo

 Parameters  : message
 Returns     : void
 Description : Writes message preceded by "INFO:" to the log file.

=cut

sub loginfo { logit( "INFO:", @_ ) unless $loglevel < 3; }

=head2 logdebug

 Parameters  : message
 Returns     : void
 Description : Writes message preceded by "DBUG:" to the log file.

=cut

sub logdebug { logit( "DBUG:", @_ ) unless $loglevel < 4; }

=head2 abort

 Parameters  : message
 Returns     : void (exit)
 Description : Writes message preceded by "CRIT:" to the log file then exits the script.

=cut

sub abort {
	my ( $message, $exitcode ) = @_;
	$exitcode = 1 unless $exitcode;
	logcrit($message);
	logcrit("################# exited due to errors ###############\n");
	exit $exitcode;
}

=head2 logstack

 Parameters  : 
 Returns     : void
 Description : Writes a stack trace as debug output.

=cut

sub logstack { logdebug stacktrace(2) }

=head2 logcaller

 Parameters  : 
 Returns     : subroutine-name, line-number
 Description : Handy for debugging.
               Logs (as debug output) the calling subroutine's name and the line number.
               Also returns these a 2 value list.

=cut

sub logcaller {
	my ( $package, $filename, $line, $subname, $hasargs ) = caller(1);
	logdebug
"Caller Package: '$package', File: '$filename', Sub '$subname', Line: $line, Args: $hasargs";
	return ( $subname, $line );
}

=head2 logEndSub

 Parameters  : 
 Returns     : void
 Description : Handy for debugging.
               Put this at the end of any subroutines, before 'return' to log that a sub has reached its end.

=cut

sub logEndSub {
	my ( $package, $filename, $line, $subname, $hasargs ) = caller(1);
	logdebug "End of Sub '$subname' called from line: $line";
	logdebug "";
}

=head2 get_datetime( $timetoget, $format )

 Parameters  : timetoget, format
 Returns     : formatted-datetime-string
 Description : Returns date-time in various formats.
               Default timetoget is now (can be specified as 'now'), alternative is 'expired' which returns
               date of 1 month ago, for use when expiring log files.
               format parameter can be pgformat or logformat, for postgres database friendly format, or nice logging format.

=cut

sub get_datetime {
	my ( $timetoget, $format ) = @_;

	my $datetime;
	my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst );

	if ( !$timetoget || $timetoget eq "now" ) {
		( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
		  localtime;
	}
	elsif ( $timetoget eq "expired" ) {    # 1st day of 1 month ago
		my $monthsecs =
		  28 * 24 * 60 * 60;    # number of seconds in a month (28 days)
		( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
		  localtime( time() - $monthsecs );
		$mday = 1;
		$hour = $min = $sec = 0;
	}
	else {                      # no other options available yet.
		( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
		  localtime;
	}

	$mon = $mon + 1;
	my $yyyy = $year + 1900;
	my $yy   = sprintf( "%02d", $year % 100 );

	if ( $format eq "pgformat" ) {

		# yyyy-mm-dd hh:mm:ss
		my $MM   = substr( "00" . $mon,  -2, 2 );
		my $mday = substr( "00" . $mday, -2, 2 );
		my $hour = substr( "00" . $hour, -2, 2 );
		my $min  = substr( "00" . $min,  -2, 2 );
		my $sec  = substr( "00" . $sec,  -2, 2 );
		$datetime = "$yyyy-$MM-$mday $hour:$min:$sec";
	}
	elsif ( $format eq "logformat" ) {
		my $MM   = substr( "00" . $mon,  -2, 2 );
		my $mday = substr( "00" . $mday, -2, 2 );
		my $hour = substr( "00" . $hour, -2, 2 );
		my $min  = substr( "00" . $min,  -2, 2 );
		my $sec  = substr( "00" . $sec,  -2, 2 );
		$datetime = "$yyyy/$MM/$mday $hour:$min:$sec";
	}

	return $datetime;
}

=head1 AUTHOR

Robin CJ, C<< <robin at cameron-jones.net> >>

=head1 CREATED

 2011-07-07

=head1 BUGS

n/a

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Utilities::Logit

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

1;    # End of Utilities::Logit
