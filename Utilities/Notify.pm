package Utilities::Notify;

use 5.006;
use strict;
use warnings FATAL => 'all';
use Utilities::perlUtils 1.514;
use Utilities::perlUtils 1.514 qw(flattenToArrayRef definedToArray sendEmail flattenDefined listContains);
use Utilities::perlUtils 1.515 qw(:OSUtils);
use File::Basename;

=head1 NAME

Utilities::Notify - For accumulating and sending of notification and alert messages.

=head1 VERSION

Version 0.11

=cut

our $VERSION = '0.11';

=head1 SYNOPSIS

    use Utilities::Notify;

    my $notify = Utilities::Notify->new( mailserver => "191.9.211.10", lastTimeStore => "/home/scriptrunner/time-records.dat", minInterval => 3600 );
    $notify->addAlertEmail('me@example.com,him@example.com','someone.else@example.com');
    $notify->addNotificationEmail('theboss@example.com,him@example.com','someone.else@example.com');
    $notify->notify("$0 Started processing at " . localtime);
    $notify->alert("We have had a nasty problem!  Send help!");
    $notify->alert("We have had another nasty problem!  Send more help!");
    $notify->notify("$0 Finished processing at " . localtime);
    $notify->sendAlerts(); # sends one email containing all the above alerts to all the alert email addresses.
    $notify->alertsWithNotifications(0); # if set to true then notification email will include all alerts as well, if alerts haven't been sent recently so you don't have to sendAlerts.
    $notify->sendNotifications(); # sends one email containing all the above notify to all the alert email addresses.
    
    ...
    Optional constructor (new()) attributes:
    lastTimeStore
    minInterval
    alertsWithNotifications
    emailFrom
    alerting
    notifying
    alertEmailsTo
    notificationEmailsTo
    alertsWithNotifications
    mailserver
    
    These can be set as parameters to the constructor, or using a get/setter of the same name.

=cut

=head1 SUBROUTINES/METHODS

=head2 new
 
 Parameters  : optional attributes 
 Returns     : object
 Description : optional attributes - alerting, notifying, alertEmailsTo, notificationEmailsTo, alertsWithNotifications, emailFrom, mailserver, notifications, alerts 
               e.g.  my $alerter = Utilities::Notify->new( mailserver => "mail.example.com", emailFrom => 'alerts@example.com', alerting => 1, notifying => 0 );

=cut

sub new {
	my $invocant = shift;
	my $class    = ref($invocant) || $invocant;
	my $self     = {

		# Set defaults here:
		lastTimeStore => basename($0) . ".lasttimestore",
		notifying     => 1,
		alerting      => 1,
		@_    # Remaining args become attributes
	};
	bless( $self, $class );    # Bestow objecthood
	$self->{alertEmailsTo}        = [];
	$self->{notificationEmailsTo} = [];
	$self->{logFH}                = devnullFH();
	return $self;
}

=head2 setLoggingFH
 
 Parameters  : open writeable filehandle
 Returns     : 
 Description : Sets the logging filehandle so that logging can be written somewhere (otherwise it defaults to /dev/null or NUL)

=cut

sub setLoggingFH {
	my $self = shift;
	close $self->{logFH} if $self->{logFH};
	$self->{logFH} = shift;
}

=head2 getset
 
 Parameters  : value
 Returns     : value for property/variable with same name as calling class method/sub name
 Description : To increase my OO laziness

=cut

sub getset {
	my @caller   = caller(1);
	my $property = $caller[3];
	$property =~ s/.*:://;
	$_[0]->{$property} = $_[1] if defined $_[1];
	$_[0]->{$property};
}

=head2 alerting
 
 Parameters  : boolean
 Returns     : boolean
 Description : Enable or disable the sending of alert messages

=cut

sub alerting { getset(@_) }

=head2 notifying
 
 Parameters  : boolean
 Returns     : boolean
 Description : Enable or disable the sending of notification messages

=cut

sub notifying { getset(@_) }

=head2 alertEmailsTo
 
 Parameters  : List of alert email addresses
 Returns     : arrayref of alert email addresses
 Description : getter/setter

=cut

sub alertEmailsTo {
	my ( $self, @emails ) = @_;
	$self->{alertEmailsTo} = flattenToArrayRef(@emails) if @emails;
	$self->{alertEmailsTo};
}

=head2 notificationEmailsTo
 
 Parameters  : List of notification email addresses
 Returns     : arrayref of notification email addresses
 Description : getter/setter

=cut

sub notificationEmailsTo {
	my ( $self, @emails ) = @_;
	$self->{notificationEmailsTo} = flattenToArrayRef(@emails) if @emails;
	$self->{notificationEmailsTo};
}

=head2 addAlertEmail
 
 Parameters  : List of email addresses
 Returns     : Arrayref of email addresses
 Description : 

=cut

sub addAlertEmail {
	my ( $self, @emails ) = @_;
	for (@emails) { push @{ $self->{alertEmailsTo} }, split /[;,]/ }
	$self->{alertEmailsTo};
}

=head2 addNotificationEmail
 
 Parameters  : List of email addresses
 Returns     : Arrayref of email addresses
 Description : 

=cut

sub addNotificationEmail {
	my ( $self, @emails ) = @_;
	for (@emails) { push @{ $self->{notificationEmailsTo} }, split /[;,]/ }
	$self->{notificationEmailsTo};
}

=head2 emailFrom
 
 Parameters  : Email address to use in From field of sent emails
 Returns     : From email addresses
 Description : Set the from email address.  Default is notifications@HOSTNAME.

=cut

sub emailFrom {

	if ( $_[1] ) { $_[0]->{emailFrom} = $_[1] }
	elsif ( !$_[0]->{emailFrom} ) {
		my $hostname =
		    $ENV{HOSTNAME}     ? $ENV{HOSTNAME}
		  : $ENV{COMPUTERNAME} ? $ENV{COMPUTERNAME}
		  : "mycomputer";
		$_[0]->{emailFrom} = 'notifications@' . $hostname;
	}
	$_[0]->{emailFrom};
}

=head2 mailserver
 
 Parameters  : mailserver hostname
 Returns     : mailserver hostname
 Description : 

=cut

sub mailserver { getset(@_) }

=head2 minInterval
 
 Parameters  : seconds
 Returns     : seconds
 Description : Minimum time (sec) allowed between repeated messages, identified by alert or notification type ID.

=cut

sub minInterval { getset(@_) }

=head2 alerts
 
 Parameters  : Hashref of arrays of alert messages keyed by id.
 Returns     : Hashref of arrays of alert messages, keyed by id.
 Description : getter/special-setter

=cut

sub alerts { getset(@_) }

=head2 notifications
 
 Parameters  : Hashref of arrays of notification messages keyed by id.
 Returns     : Hashref of arrays of notification messages, keyed by id.
 Description : getter/setter

=cut

sub notifications { getset(@_) }

=head2 idAlerts
 
 Parameters  : ID, Array of messages
 Returns     : Array of alert messages for supplied ID
 Description : Assign the list of alerts to the type ID.  ID will be used for identifying the type of alert, so notification intervals can be set.

=cut

sub idAlerts {
	my $self = shift;
	my $id   = shift;
	$self->{alerts}->{$id}->{messages} = shift if @_;
	$self->{alerts}->{$id}->{messages};
}

=head2 idNotifications
 
 Parameters  : ID, Array of messages
 Returns     : Array of messages for supplied ID
 Description : Assign the list of messages to the type ID.  ID will be used for identifying the type of alert, so notification intervals can be set.

=cut

sub idNotifications {
	my $self = shift;
	my $id   = shift;
	$self->{notifications}->{$id}->{messages} = shift if @_;
	$self->{notifications}->{$id}->{messages};
}

=head2 lastTime
 
 Parameters  : type, ID, seconds
 Returns     : Last time a notification or alert was sent for this type ID (0 = never)
 Description : getter/setter - For storing or getting the last time a message was sent.  

=cut

sub lastTime {
	my ( $self, $type, $id ) = ( shift, shift, shift );
	$self->{$type}->{$id}->{lastTime} = shift if @_;
	$self->{$type}->{$id}->{lastTime};
}

=head2 lastTimeStore
 
 Parameters  : Filepath string
 Returns     : seconds
 Description : Minimum time (sec) allowed between repeated messages, identified by alert or notification type ID.

=cut

sub lastTimeStore { getset(@_) }

=head2 recordLastTimes
 
 Parameters  : message types.
 Returns     : 0 if fails to open file for writing.  file open error message will be in $!
 Description : Writes to a file the information for the last times each message (by ID, which can be the message itself) was sent.
               Format:
               epoch time in seconds|type(alerts or notifications)|ID

=cut

sub recordLastTimes {
	my ( $self, @types ) = @_;
	@types = ( "alerts", "notifications" ) unless @types;
	for my $type (@types) {
		my $file = $self->lastTimeStore . ".$type";
		open my $fh, ">", $file or return 0;
		next unless ref( $self->{$type} ) eq "HASH";
		for my $id ( keys $self->{$type} ) {
			my $lastTime = $self->lastTime( $type, $id );
			$lastTime = time unless $lastTime;
			my $line = join( ',', $lastTime, $type, $id ) . eol();
			print $fh $line;
		}
		close $fh;
	}

}

=head2 loadLastTimes
 
 Parameters  : message types.
 Returns     : 0 if fails to read file.
 Description : Loads from a file the information for the last times each message (by ID, which can be the message itself) was sent,
 				discarding any that have exceeded the minimum interval period.
               Format:
               epoch time in seconds|type(alerts or notifications)|ID

=cut

sub loadLastTimes {
	my ( $self, @types ) = @_;

	for my $type (@types) {
		my $file = $self->lastTimeStore . ".$type";
		next unless -f $file;
		open my $fh, "<", $file or return 0;
		my $intvl = $self->minInterval || 0;
		my $maxtime = time - $intvl;
		while ( my $line = <$fh> ) {
			chomp $line;
			next if $line !~ /^(\d+),(.+),(.*)$/;
			my ( $last, $type, $id ) = ( $1, $2, $3 );
			if ( $last >= $maxtime ) {

				# Only keep the messages that were sent within the min interval period
				$self->lastTime( $type, $id, $last );
			}
		}
		close $fh;
	}
}

=head2 alert
 
 Parameters  : Message string to add to the alerts list [, a type ID, the last time this id's messages were sent] 
 Returns     : Hashref of details of this type ID.
 Description : Adds message to the alerts message list, type ID can be used to determine whether this alert has already occurred recently.

=cut

sub alert {
	my $self = shift;
	$self->addMessage( "alerts", @_ );
}

=head2 alertPrepend
 
 Parameters  : Message string to add to the TOP of the alerts list [, a type ID, the last time this id's messages were sent] 
 Returns     : Hashref of details of this type ID.
 Description : Adds message to the top of the alerts message list, type ID can be used to determine whether this alert has already occurred recently.

=cut

sub alertPrepend {
	my $self = shift;
	$self->addMessageToTop( "alerts", @_ );
}

=head2 notify
 
 Parameters  : Message string to add to the notifications list [, a type ID, the last time this id's messages were sent] 
 Returns     : Hashref of details of this type ID.
 Description : Adds message to the notifications message list, type ID can be used to determine whether this notification has already occurred recently.

=cut

sub notify {
	my $self = shift;
	$self->addMessage( "notifications", @_ );
}

=head2 notifyPrepend
 
 Parameters  : Message string to add to the TOP of the notifications list [, a type ID, the last time this id's messages were sent] 
 Returns     : Hashref of details of this type ID.
 Description : Adds message to the top of the notifications message list, type ID can be used to determine whether this notification has already occurred recently.

=cut

sub notifyPrepend {
	my $self = shift;
	$self->addMessageToTop( "notifications", @_ );
}

=head2 addMessage
 
 Parameters  : Type of message (alert or notification), Message string to add to the notifications list [, a type ID, the last time this id's messages were sent] 
 Returns     : Hashref of details of this type ID.
 Description : Adds message to the notifications message list, type ID can be used to determine whether this notification has already occurred recently.

=cut

sub addMessage {
	my ( $self, $type, $message, $id, $last ) = @_;
	$id = $message unless $id;    #use message as the id if none is provided.
	push( @{ $self->{$type}->{$id}->{messages} }, $message ) if $message;
	$self->{$type}->{$id}->{lastTime} = $last if $last;
	$self->{$type}->{$id};
}

=head2 addMessageToTop
 
 Parameters  : Type of message (alert or notification), Message string to add to the TOP of the notifications list [, a type ID, the last time this id's messages were sent] 
 Returns     : Hashref of details of this type ID.
 Description : Adds message to the top of the notifications message list, type ID can be used to determine whether this notification has already occurred recently.

=cut

sub addMessageToTop {
	my ( $self, $type, $message, $id, $last ) = @_;
	$id = $message unless $id;    #use message as the id if none is provided.
	unshift( @{ $self->{$type}->{$id}->{messages} }, $message ) if $message;
	$self->{$type}->{$id}->{lastTime} = $last if $last;
	$self->{$type}->{$id};
}

=head2 sendAlerts
 
 Parameters  : Subject, Upper body, Lower body  (all optional)
 Returns     : String containing email details.  $@ set to error message if there is a problem, or alerting is disabled.
 Description : Send all accumulated alerts in an email to the configured recipient.  Email is only sent if there are messages to send.
 			   Generic messages of no specific type will use the message as the ID - messages with unique data (timestamps) will therefore not be subject to the minInterval. 
 			   If a time (sec) string is provided instead of a hashref then that will be used for all types (IDs, if type IDs are used at all).
 			   
=cut

sub sendAlerts {
	my ( $self, $subject, $upper, $lower ) = @_;
	$@ = '';
	return 0 unless @{ $self->alertEmailsTo };         # no destinations defined
	return 0 unless definedToArray( $self->alerts );
	return 0 unless $self->alerting;

	$self->loadLastTimes("alerts") if $self->minInterval;

	my @messages = $self->getMessagesToSend("alerts");

	return 0 unless @messages;
	my $body = flattenDefined( eol(), $upper, @messages, $lower );

	my $addr = flatten( ",", $self->alertEmailsTo );
	my $header = {
		Subject => $subject || "Alerts",
		To   => $self->alertEmailsTo,
		From => $self->emailFrom,

		#"Content-Type" => "text/html"
	};

	my $summary = join(
		eol(),
		"Mailserver: " . $self->mailserver,
		"To: " . flatten( ",", $header->{To} ),
		"From: " . $header->{From}, $body
	);

	say {$self->{logFH}} "Sending email: $summary\nSubject: $header->{Subject}\nBody: $body";
	if ( sendEmail( $header, $body, $self->mailserver, 'smtp' ) ) {
		$self->recordLastTimes("alerts");
	}
	else {
		die $!;
	}
	$summary;
}

=head2 sendNotifications
 
 Parameters  : Subject, Upper body, Lower body (all optional)
 Returns     : String containing email details.  $@ set to error message if there is a problem, or notifications are disabled.
 Description : Send all accumulated alerts in an email to the configured recipient.  Email is only sent if there are messages to send.
 			   Generic messages of no specific type will use the message as the ID - messages with unique data (timestamps) will therefore not be subject to the minInterval. 
 			   If a time (sec) string is provided instead of a hashref then that will be used for all types (IDs, if type IDs are used at all).
 			   
=cut

sub sendNotifications {
	my ( $self, $subject, $upper, $lower ) = @_;
	$@ = '';
	return 0 unless @{ $self->notificationEmailsTo };    # no destinations defined
	return 0 unless $self->notifications;
	return 0 unless $self->notifying;
	$self->loadLastTimes("notifications") if $self->minInterval;

	my @messages = $self->getMessagesToSend("notifications");
	push @messages, $self->getMessagesToSend("alerts")
	  if $self->alertsWithNotifications;
	return 0 unless @messages;

	@messages = definedToArray(@messages);
	my $body = flatten( eol(), $upper, @messages, $lower );

	my $header = {
		Subject => $subject || "Notifications",
		To   => $self->notificationEmailsTo,
		From => $self->emailFrom,

		#"Content-Type" => "text/html"
	};
	my $summary = join(
		eol(),
		"Mailserver: " . $self->mailserver,
		"To: " . flatten( ",", $header->{To} ),
		"From: " . $header->{From}, $body
	);

	say {$self->{logFH}} "Sending email: $summary\nSubject: $header->{Subject}\nBody: $body";

	if ( sendEmail( $header, $body, $self->mailserver, 'smtp' ) ) {
		$self->recordLastTimes("notifications");
	}
	else {
		die $!;
	}
	$summary;
}

=head2 getMessagesToSend
 
 Parameters  : Message type (alerts or notifications)
 Returns     : List of messages which are allowed to be sent, according to interval ID checks.
 Description : Send all accumulated alerts in an email to the configured recipient.  Email is only sent if there are messages to send. 			   
 			   Uses the lastTime value for a type->id.
 			   Since we're not running this as a daemon/service these values must be provided by the caller.
 			   Generic messages of no specific type will use the message as the ID - messages with unique data (timestamps) will therefore not be subject to the minInterval. 
 			   If a time (sec) string is provided instead of a hashref then that will be used for all types (IDs, if type IDs are used at all).
 			   
=cut

sub getMessagesToSend {
	my ( $self, $type ) = @_;
	my $tref = $self->{$type};

	# if there is no interval defined then use all messages
	return map { $tref->{$_}->{messages} } keys %$tref
	  unless $self->minInterval;

	my @messages;
	for my $id ( keys %$tref ) {

		# note that by default the $id is the same as the message itself.
		my $iref    = $tref->{$id};
		my @newmsgs = definedToArray( $iref->{messages} );

		# use the last time for this id, if defined, else use zero
		my $last = $iref->{lastTime} || 0;

		# Only add messages to the list if we have some
		# and if their last time was more than the minInterval ago
		my $diff = time - $last;

		if ( @newmsgs && $diff > $self->minInterval ) {
			push( @messages, @newmsgs );
		}
		$iref->{lastTime} = time;
	}
	@messages;
}

=head2 alertsWithNotifications
 
 Parameters  : boolean
 Returns     : boolean
 Description : getter/setter.
 			   Set to true if you want alert messages to be sent in the email with notification messages.
 			   Default is undef/false.

=cut

sub alertsWithNotifications { getset(@_) }

=head1 AUTHOR

Robin CJ, C<< <robin@cameron-jones.net> >>

=head1 BUGS

Please report any bugs or feature requests to Robin CJ, C<< <robin@cameron-jones.net> >>

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Utilities::Logit


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Utilities-Logit>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Utilities-Logit>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Utilities-Logit>

=item * Search CPAN

L<http://search.cpan.org/dist/Utilities-Logit/>

=back


=head1 ACKNOWLEDGEMENTS


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

1;    # End of Utilities::Notify

