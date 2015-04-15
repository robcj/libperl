#!/usr/bin/perl -w

=head1 package Jira::JiraRest;

 Purpose is to provide a simple oo access to the Jira REST APIs.
 Currently only has methods relating to watchers, but using this framework it should be simple to add more.

=cut

package Jira::JiraRest;
our $VERSION = "0.002";

use strict;
use JSON;
use HTTP::Request;
use LWP::UserAgent;

use lib qw( . .. ../lib ../libperl );
use MIME::Base64;
use Utilities::Logit 1.100;
use Utilities::perlUtils 1.400;
use Utilities::perlUtils 1.400 qw(flattenQ flattenVersion hasContent);

$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;

=head2 new([config hashref])

 Constructor.
 Where config hashref keys are: jiraurl jirapass jirauser
 And optional: loglevel logfile (default to info and STDOUT)
  
=cut

sub new {
	my $class      = shift;
	my $confighref = shift;
	my $self       = {@_};
	bless $self;

	# defaults

	my @configkeys = qw(loglevel logfile jiraurl jirapass jirauser );
	for (@configkeys) {
		$self->{$_} = $confighref->{$_}
		  if defined $confighref->{$_};
	}

	$self->resturl( $self->{jiraurl} . "/rest/api/latest" );
	setLogging( $self->loglevel, $self->logfile );
	for (@configkeys) { logdebug "$_: $self->{$_}" if defined $self->{$_} }
	return $self;
}

=head2 Get/Set Methods

 Available getsetter methods/properties are: 
  loglevel logfile jiraurl jirapass jirauser resturl

=cut

sub jiraurl  { $_[0]->{jiraurl}  = $_[1] if defined $_[1]; $_[0]->{jiraurl}; }
sub jirauser { $_[0]->{jirauser} = $_[1] if defined $_[1]; $_[0]->{jirauser}; }
sub jirapass { $_[0]->{jirapass} = $_[1] if defined $_[1]; $_[0]->{jirapass}; }
sub resturl  { $_[0]->{resturl}  = $_[1] if defined $_[1]; $_[0]->{resturl}; }
sub loglevel { $_[0]->{loglevel} = $_[1] if defined $_[1]; $_[0]->{loglevel}; }
sub logfile  { $_[0]->{logfile}  = $_[1] if defined $_[1]; $_[0]->{logfile}; }

################
# Rest Requests
################

=head2 getServerInfo

 Returns Jira server details hashref

=cut

sub getServerInfo {
	requestGET( shift, "serverInfo" );
}

=head2 getJiraVersion

 Returns Jira server version

=cut

sub jiraversion {
	my $info = $_[0]->getServerInfo;
	unless ( ref($info) eq "HASH" ) {
		logcrit "Unable to determine Jira server version.";
		return 0;
	}
	$_[0]->{jiraversion} = $info->{version}
	  unless defined $_[0]->{jiraversion};

	logdebug "Jira version " . $_[0]->{jiraversion};
	$_[0]->{jiraversion};
}
sub getJiraVersion { jiraversion(@_) }

=head2 versionOk( <version number> )

 Returns true if the supplied version number is less than the target Jira server version,
 true if it is equal or greater.
 ie. returns true if the required version is less than or equal to the Jira server version.
 Only uses the first digits in each of the version fields.

=cut

sub versionOk {
	my ( $self, $rqver ) = @_;
	my $jver = $self->jiraversion;
	return 0 unless $jver;
	logdebug "Comparing v $jver with $rqver";
	$jver  = flattenVersion($jver);
	$rqver = flattenVersion($rqver);
	logdebug "Comparing v $jver with $rqver";
	return 1 if $rqver <= $jver;
	0;
}

# Issue Requests

=head2 getIssue ( <issuekey> )

 Returns issue details hashref for issuekey.

=cut

sub getIssue {
	requestGET( shift, "issue/$_[0]" );
}

=head2 getComments ( <issuekey> )
 
 Returns comments hashref for issuekey.

=cut

sub getComments {
	my ( $self, $issue ) = @_;
	return requestGET( $self, "issue/$issue/comment" )
	  if $self->versionOk('5.0');
	my $ref = getIssue( $self, $issue );
	return 0 unless ref($ref) eq "HASH";
	$ref->{fields}{comment}{value};
}

sub getCommentCount {
	my ( $self, $commenthref ) = @_;
	if ( $self->versionOk('5.0') ) {
		ref($commenthref) eq 'HASH'
		  ? $commenthref->{total}
		  : getComments(@_)->{total};
	}
	else {
		ref($commenthref) eq 'HASH'
		  ? scalar @$commenthref
		  : scalar getComments(@_);
	}
}

sub getCommentBodies {
	my $self = shift;
	my $comments;
	if ( $self->versionOk('5.0') ) {
		$comments =
		  ref( $_[0] ) eq 'HASH'
		  ? $_[0]->{comments}
		  : $self->getComments(@_)->{comments};
	}
	else {
		$comments =
		  ref( $_[0] ) eq 'HASH'
		  ? $_[0]->{comments}
		  : $self->getComments(@_);
	}
	return 0 unless ref($comments) eq "ARRAY";
	map { $_->{body} } @$comments;
}

sub getCommentLastCreated {
	my $self = shift;
	if ( $self->versionOk('5.0') ) {
		ref( $_[0] ) eq 'HASH'
		  ? $_[0]->{comments}[-1]
		  : $self->getComments(@_)->{comments}[-1];
	}
	else {
		ref( $_[0] ) eq 'HASH'
		  ? $_->[0][-1]
		  : $self->getComments(@_)->[-1];
	}
}

sub addComment {
	my ( $self, $key, $body, $type, $value ) = @_;
	return 0 unless $self->{jiraversion} && $self->{jiraversion} > 0 ;
	unless ( $self->versionOk('5.0') ) {
		my $msg =
"Method addComment is not available for Jira versions prior to 5.0.  Use the SOAP API instead.";
		$@ = $msg;
		logcrit $msg;
		return 0;
	}

=head3	 Example JSON data:

	{
    "body": "Lorem ipsum dolor sit amet",
    "visibility": {
        "type": "role",
        "value": "Administrators"
    }
	}

=cut	

	my %params;
	$params{body} = $body;
	$params{visibility}{type}  = $type if $type;
	$params{visibility}{value} = $type if $value;

	$self->requestPOST( "$key/comment", \%params );
}

# Watcher Requests

sub getWatchers {
	requestGET( shift, "issue/$_[0]/watchers" );
}

=head2 getWatcherIds ( <issuekey>|<watchers-hashref> )

 Given an issue key string or 'watchers' hashref as supplied from getWatchers()
 returns list of IDs of issuekey's watchers.

=cut

sub getWatcherIds {
	my $self = shift;
	my $watchers =
	  ref( $_[0] ) eq 'HASH'
	  ? $_[0]->{watchers}
	  : $self->getWatchers(@_)->{watchers};
	map { $_->{name} } @$watchers;
}

=head2 getWatcherCount ( <issuekey>|<watchers-hashref> )

=cut

sub getWatcherCount {
	$_[0]->{watchCount}
	  ? ref( $_[0] ) eq 'HASH'
	  : getWatchers(@_)->{watchCount};
}

=head2 addWatcher ( <issuekey>, <username> )

=cut

sub addWatcher {
	requestPOST( shift, "issue/$_[0]/watchers", $_[1] );
}

=head2 deleteWatcher ( <issuekey>, <username> )

=cut

sub deleteWatcher {
	requestDELETE( shift, "issue/$_[0]/watchers", { username => $_[1] } );
}

#########################
# Request method wrappers
#########################

=head2 Request Methods

=over

=item *

 requestGET ( <URL>, [params hashref] )

=item *

 requestPOST ( <URL>, [params hashref] )

=item *

 requestDELETE ( <URL>, [params hashref] )

=back

 Wrappers for restRequest(), setting the http request-method as per the perl method name.
 Returns hashhref of returned content decoded from JSON for successful calls, for unsuccessful calls it just returns the response content string.

=cut

sub requestGET    { restRequest( shift, "GET",    @_ ) }
sub requestPOST   { restRequest( shift, "POST",   @_ ) }
sub requestDELETE { restRequest( shift, "DELETE", @_ ) }

##############################
# Create and send rest Request
##############################

=head2 restRequest ( <GET|POST|DELETE>, <URL>, [params hashref] )

 Creates and sends rest request, converting any parameters to JSON format for POST requests.
 Returns hashhref of returned content decoded from JSON.
 $@ is set with errors if request is unsuccessful.

=cut

sub restRequest {
	my ( $self, $method, $url, $params ) = @_;
	my @errors;
	$url = $self->resturl . "/$url";
	if ( $params && $method =~ /GET|DELETE/ ) {
		$url .= "?" . join( "&", map { "$_=$params->{$_}" } keys %$params );
	}
	logdebug "HTTP Request Method: $method  URL: $url";
	my $request = eval { HTTP::Request->new( $method => $url ) };
	if ($@) { push @errors, $@; logwarn $@ }
	$request->header( Authorization => "Basic "
		  . encode_base64( $self->jirauser . ":" . $self->jirapass ) );
	$request->header( 'Content-type' => 'application/json' );

	if ( $method eq 'POST' ) {
		my $content;
		if ( ref($params) eq 'HASH' ) { $content = encode_json $params }
		elsif ( $params && $method eq 'POST' ) {
			$content = JSON->new->allow_nonref->encode($params);
		}
		logdebug "POST Request Content: $content";
		$request->content($content);
	}

	my $ua = LWP::UserAgent->new();
	my $response = eval { $ua->request($request) };
	if ($@) { push @errors, $@; logwarn $@ }
	my $rcontent = $response->content;

	logdebug "Response: $rcontent";
	if ( $response->is_success ) {
		$rcontent = decode_json $rcontent if $rcontent;
	}
	else {
		my $error = "Request Unsuccessful. Response: $rcontent";
		$error .= "\nMethod: $method ; URL: $url ; Params: ";
		$error .= flattenQ($params) if hasContent($params);
		push @errors, $error;
		logwarn $error;
	}

	$@ = join( "\n", @errors );
	return $rcontent;
}

1;
__END__

=head1 Usage Example

 my $jirest = Jira::JiraRest->new({ jiraurl => "http://jiraserver:8080/jirainst", jirauser => "fredm", jirapass => "mypass" }):
 print Dumper($jirest->getServerInfo);
 print $jirest->addWatcher("TA-1", "robincj");
 print Dumper($jirest->getWatchers("TA-1"));
 print Dumper($jirest->getWatcherIds($jirest->getWatchers("TA-1")));
 print "DELETE\n" . $jirest->deleteWatcher("TA-1", "robincj");
 print Dumper($jirest->getWatchers("TA-1"));
 print Dumper($jirest->getWatcherIds($jirest->getWatchers("TA-1")));

=head1 Notes:

 Linux Curl equivalent commands for the cli:

 Get watcher details (json response):
  curl -k -X GET "http://robincj:mypass@172.20.22.169:8080/rest/api/latest/issue/CIN-16322/watchers"
 
 Delete a watcher:
  curl -k -X DELETE "http://robincj:mypass@172.20.22.169:8080/rest/api/latest/issue/CIN-16322/watchers?username=robincj"

 Add a watcher (note double quotes around username to add):
  curl -k -X POST -d '"robincj"' -H "Content-Type: application/json" http://robincj:mypass@172.20.22.169:8080/rest/api/latest/issue/CIN-16322/watchers


=cut



