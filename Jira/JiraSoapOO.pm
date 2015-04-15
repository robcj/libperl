#!/usr/bin/perl -w

##############
# Perldoc
##############

=head1 Author

 2011/07/21 Robin CJ
 2013/02/17 Robin CJ - converted to Object Oriented version

=head1 NAME

 Jira::JiraSoapOO	 - Perl module to wrap the jira soapservices

=head1 SYNOPSIS

	use Jira::JiraSoapOO; # Import default methods

=head1 DESCRIPTION

 Methods:
	cascadeSelect
	setCascadeSelect
	getCascadeSelect
	
	getResolutionDateByKey
	getResolution_by_id
	getIssueType_by_id
	getStatus_by_id
	getPriority_by_id
	do_jql_search
	doJiraSoapMethod
	getIssue
	soapcall_getCustomFields
	get_customfield_ids
	get_customfield_names
	get_customfield_value
	soap_connect
	soap_logout
	get_projects
	getUpdated
	getNotUpdatedSince

 And 
	jira_soapcall
	get_all_customfields
 
 Method names are currently rather inconsistently named as they were assembled from different sources for this module.
 Should look at tidying this up.

=head2 Common error
 
 If your connection fails due to "certificate verify failed" try changing the environment variable
 to tell LWP to ignore the cert:
 $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}=0
 This usually happens in Windows perl.

=head1 METHOD DESCRIPTIONS
 
=cut

package Jira::JiraSoapOO;
##########
# Version
##########

our $VERSION = '1.000';
$VERSION = eval $VERSION;

##########
# Modules
##########

use lib qw( . .. ../lib ../libperl );
use strict;
use Utilities::Logit 1.1;
use SOAP::Lite;

##############
# Global Variables
##############

# Hash of fields which contain reference ids for field-values held in special tables,
# hash values are the soap call to use to get the real value
my %fieldsWhichContainRefIds =
  qw( status getStatuses resolution getResolutions priority getPriorities type getIssueTypes );

############# #############
# Setup
############# #############

=head2 new()

 Constructor

=cut

sub new {
	my $class = shift;
	my $self  = {@_};
	bless $self;
	return $self;
}

=head2 defaults()

	Set default properties

=cut

sub defaults {
	$_[0]->dbhost("localhost");
}

##########

# Holds authentication token when logged in
sub auth { $_[0]->{auth} = $_[1] if defined $_[1]; $_[0]->{auth}; }

# Soap connection handle
sub soap { $_[0]->{soap} = $_[1] if defined $_[1]; $_[0]->{soap}; }

# Project used for certain queries
sub project { $_[0]->{project} = $_[1] if defined $_[1]; $_[0]->{project}; }
sub setProject { project(@_) }
sub getProject { project(@_) }

# Hold customfields hash
my %customfields;    # key: cfid, value: cfname

sub customfields {
	my ( $self, $key, $value ) = @_;
	return $self->{customfields}{$key} = $value if defined $value;
	return $self->{customfields}{$key} if defined $key;
	$self->{customfields};
}
sub addCustomfield { customfields(@_) }
sub getCustomfield { customfields(@_) }

=head2 setLogging( <loglevel>, <logfile> )

 MANDATORY
 Calls the imported setLogging function of logit.pm
 loglevel is the maximum level that will be written to the file, one of crit, warn, info or debug.
 Any use of the functions of lower levels will be ignored.
 logfile is a filename and path which you want the log data written to.

=cut

##########

=head2 setCascadeSelectList( <fieldname> [, <fieldname> ... ] )

 MANDATORY if you intend to get values from custom fields which are populated from cascading select lists.
 Supply a list of field names of custom fields which are populated from cascading select lists.
 eg.  $jira->setCascadeSelectList('Client Name', 'SLA Miss');
 Otherwise the customfieldoption id will be returned rather than the actual value, and subvalues.

=cut

sub cascadeSelectList {
	my $self = shift;
	$self->{cascadeSelectList} = @_ if defined $_[0];
	@{ $self->{cascadeSelectList} };
}
sub getCascadeSelectList { cascadeSelectList(@_) }
sub setCascadeSelectList { cascadeSelectList(@_) }

############# #############
# Jira soap method call subs
############# #############

=head2 getIssue( <issue key> )
 
 Supply the issue key and it will return the issue details as an array of hashrefs.

=cut

sub getIssue {
	my $self     = shift;
	my $callname = "getIssue";
	$self->jira_soapcall( $callname, @_ );
}

=head2 getIssues( <list of issue keys> )
 
  Params: list of issue keys
  Returns: arrayref of issue detail hashrefs.

=cut

sub getIssues {
	my $self     = shift;
	my $callname = "getIssue";
	[ map { $self->jira_soapcall( $callname, $_ ) } @_ ];
}

=head2 getComments( <issue key> )

	Returns array of hashrefs containing details of the issue's comments
	Keys are: groupLevel author body created updateAuthor id roleLevel updated

=cut

sub getComments {
	my $self     = shift;
	my $callname = "getComments";
	my ($comments) = $self->jira_soapcall( $callname, @_ );
	return @$comments;
}

=head2 getLastComment( <issue key> )

	Returns hashref containing details of the issue's last comment
	or false (0) if there are no comments.

=cut

sub getLastComment {
	my @comments = getComments(@_);

	#return 0 unless scalar(@comments);
	my $comment = $comments[$#comments];
	return $comment;
}
###############

=head2 getLastCommentMatching( <issue key|comments arrayref>, <body regex|hashref of search regexes>  )

	Returns a hashref containing details of the issue's most recently created
	comment that matches the supplied search regexes.
	Search regex hashref keys are: groupLevel author body created updateAuthor id roleLevel updated

=cut

sub getLastCommentMatching {
	( getCommentsMatching(@_) )[-1];
}

=head2 getCommentsMatching( <issue key|comments arrayref>, <body regex|hashref of search regexes>  )

	Returns array of hashrefs containing details of the issue's comments that match the supplied search regexes.
	Search regex hashref keys are: groupLevel author body created updateAuthor id roleLevel updated

=cut

sub getCommentsMatching {
	my $self     = shift;
	my $comments = shift;
	my $search   = shift;
	if ( ref($comments) ne 'ARRAY' )
	{    # it appears to be an issue key rather than comments arrayref
		$comments = [ $self->getComments($comments) ];
	}
	my @matching;
  COMMENTS: foreach my $ckey ( 0 .. @$comments ) {
		my $comment = $comments->[$ckey];
		foreach my $skey (
			qw(groupLevel author body created updateAuthor id roleLevel updated)
		  )
		{
			next COMMENTS
			  unless ( $search->{$skey}
				&& $comment->{$skey} =~ /$search->{$skey}/ );
			push @matching, $ckey;
		}
	}
	return @{$comments}[@matching] if @matching;
	();
}

=head2 addComment( <issue key>, <comment> )

=cut

sub addComment {
	my $self     = shift;
	my $callname = "addComment";

	#print "\nCOMMENT: " . join( ", ", @_) ."\n";
	my $key        = shift;
	my $body       = shift;
	my $commentObj = SOAP::Data->type( 'RemoteComment' => { 'body' => $body } );
	return $self->jira_soapcall( $callname, $key, $commentObj );
}

=head2 getUpdated( <issue key> )

=cut

sub getUpdated {
	my $self    = shift;
	my @details = $self->getIssue(@_);
	$details[0]->{updated};    # need to confirm this hash key name
}

=head2 getOpenIssuesByTime( <time-field-name>, <date|time-period>, [operator(>|<|>=|= etc)], <extra JQL> )

	Returns hashref of details for unresolved/unclosed issues with the supplied
	date/time-field value more recent than the supplied date/time.
	since the supplied date|time.
	Default operator is ">=" unless a different operator is supplied as the 3rd parameter.
	Additional JQL query can be added as the 4th parameter, string should start with AND or OR, it is positioned in the query immediately after the "updated = <datetime>" clause.
	
=head4 JQL Details for date format

	If a time-component is not specified, midnight will be assumed.
	Please note that the search results will be
	relative to your configured time zone (which is by default the JIRA 
	server's time zone).

	Use one of the following formats:
	"yyyy/MM/dd HH:mm"
	"yyyy-MM-dd HH:mm"
	"yyyy/MM/dd"
	"yyyy-MM-dd"

	Or use "w" (weeks), "d" (days), "h" (hours) or "m" (minutes) to specify
	a date relative to the current time. The default is "m" (minutes).
	Be sure to use quote-marks ("); if you omit the quote-marks, the number
	you supply will be interpreted as milliseconds after epoch (1970-1-1).
	
	Source:
	https://confluence.atlassian.com/display/JIRA/Advanced+Searching#AdvancedSearching-Updated
	
=cut

sub getOpenIssuesByTime {
	my $self = shift;
	my ( $timeField, $since, $afterBefore, $extraJQL ) = @_;
	$afterBefore = ">=" unless defined $afterBefore;

	# where timeField is a date/time field, eg. updated, created etc.
	# afterBefore is > or <
	# JQL query to retrieve list of issues with timefield > time-value
	my $jql =
"status NOT IN (closed, resolved) AND $timeField $afterBefore \"$since\" ";
	$jql .= $extraJQL;
	$jql .= " AND project = '" . $self->project . "'" if ( $self->project );
	$self->do_jql_search( $jql, 1 );
}

sub getOpenIssuesAfter { shift->getOpenIssuesByTime( shift, shift, ">", @_ ) }

sub getOpenIssuesBefore { shift->getOpenIssuesByTime( shift, shift, "<", @_ ) }

sub getOpenIssuesOn { shift->getOpenIssuesByTime( shift, shift, "=", @_ ) }

=head2 getLastUpdatedBefore( <date|time-period> )

	Returns hashref of details for unresolved/unclosed issues last updated 
	before the supplied date|time.
	Uses date|time as per getOpenIssuesSince

=cut

sub getLastUpdatedBefore { shift->getOpenIssuesBefore( "updated", shift, @_ ) }

=head2 getLastUpdatedAfter( <date|time-period> )

	Returns hashref of details for unresolved/unclosed issues last updated 
	since the supplied date|time.
	Uses date|time as per getOpenIssuesSince

=cut

sub getLastUpdatedAfter { shift->getOpenIssuesAfter( "updated", shift, @_ ) }

=head2 getLastUpdatedOn( <date|time-period> )

	Returns hashref of details for unresolved/unclosed issues last updated 
	on the supplied date|time.
	Uses date|time as per getOpenIssuesSince

=cut

sub getLastUpdatedOn { shift->getOpenIssuesOn( "updated", shift, "=", @_ ) }

=head2 convertIdsToValues( <results hashref> )
 
 Certain fields are returned from the JQL search as ids which must be looked up to find its actual value.
 This function handles the ones I am currently aware of, converting them by using the appropriate SOAP call.
 This currently applies to Resolution, IssueType, Status and Priority, listed in the fieldsWhichContainRefIds hash

=cut

sub convertResultsArrayIdsToValues {
	logdebug( "sub " . ( caller(0) )[3] );
	my ( $self, $results ) = @_;    # Results hashref
	foreach my $result (@$results) {

	# In most cases @$results will only contain 1 element (0) referencing a hash
		foreach my $row (@$result) { convertRowIdsToValues($row) }
	}
}

sub convertRowIdsToValues {
	logdebug( "sub " . ( caller(0) )[3] );
	my ( $self, $row ) = @_;        # Take a single results row object ref
	foreach my $fieldname ( keys(%fieldsWhichContainRefIds) ) {

# If the field name exists in the hash and contains a value then change its value (id) to the real value
		if ( exists( $row->{$fieldname} ) && $row->{$fieldname} ) {
			loginfo("Converting "
				  . $row->{key}
				  . " $fieldname id value to real value" );
			$row->{$fieldname} =
			  $self->get_name_for_id( $fieldsWhichContainRefIds{$fieldname},
				$row->{$fieldname} );
		}
	}
}

=head2 getResolution_by_id( <id> )
 
 id is the figure returned by the JQL search and must be looked up to find its actual value.
 Returns the actual value represented by the supplied id.
 The same applies for Resolution, IssueType, Status and Priority.

=cut

sub getResolution_by_id {
	logdebug( "sub " . ( caller(0) )[3] );
	my ( $self, $id ) = @_;
	my $callname = "getResolutions";
	return $self->get_name_for_id( $callname, $id );
}

#############

sub getIssueType_by_id {
	logdebug( "sub " . ( caller(0) )[3] );
	my ( $self, $id ) = @_;
	my $callname = "getIssueTypes";
	return $self->get_name_for_id( $callname, $id );
}

#############

sub getStatus_by_id {
	logdebug( "sub " . ( caller(0) )[3] );
	my ( $self, $id ) = @_;
	my $callname = "getStatuses";
	return $self->get_name_for_id( $callname, $id );
}

#############

sub getPriority_by_id {
	logdebug( "sub " . ( caller(0) )[3] );
	my ( $self, $id ) = @_;
	my $callname = "getPriorities";
	return $self->get_name_for_id( $callname, $id );
}

#############

sub get_name_for_id {
	logdebug( "sub " . ( caller(0) )[3] );
	my $self = shift;
	my ( $callname, $id ) = @_;
	logdebug("$callname looking up name for id $id");
	my $results = $self->jira_soapcall($callname);
	foreach my $row (@$results) {
		my $gotid       = $row->{id};
		my $name        = $row->{name};
		my $description = $row->{description};

		if ( $gotid == $id ) {
			loginfo("Found $callname for id $id : $name");
			return $name;
		}
	}
	logwarn(
"Unrecognised id being looked up using $callname.  Returning empty value."
	);
	return "";

}

=head2 getResolutionDateByKey ( <issue key> )
 
 Given an issue key, this method returns the resolution date for this issue.
 If the issue hasn't been resolved yet, this method will return null.
 If the no issue with the given key exists a RemoteException will be thrown. 

=cut

sub getResolutionDateByKey {
	logdebug( "sub " . ( caller(0) )[3] );
	my $self = shift;
	my ($pkey) = @_;
	logdebug("Looking up Resolution Date for $pkey");
	my $results = $self->jira_soapcall( "getResolutionDateByKey", $pkey );
	loginfo("Got $pkey Resolution Date: $results");

	return $results;
}

#############
# JQL Search
#############

=head2 do_jql_search ( <JQL Query> [, [Convert ids Y/N] )

 Takes JQL query and returns array object containing result data
 If convertids flag is set then convert the standard fields which contain ids
 ie. Resolution, IssueType, Status and Priority,
 to their true values.  I don't recommend using this feature because it is very slow.
 If you are going to iterate through the array later then use convertIdsToValues
 then instead.

=cut

sub do_jql_search {
	my ( $self, $query, $convertids ) = @_;
	logdebug "JQL: $query\n";
	my @results =
	  $self->jira_soapcall( "getIssuesFromJqlSearch", $query, 10000 );
	if ($convertids) {
		$self->convertResultsArrayIdsToValues( \@results );
	}

	return \@results;
}

sub doJQL { do_jql_search(@_) }    #alias

############# #############
# Jira Customfield Subs
############# #############

sub soapcall_getCustomFields {
	my ($self) = @_;

	# javadoc:
	#getCustomFields
	#RemoteField[] getCustomFields(java.lang.String token)
	#Throws: RemoteException

	return $self->jira_soapcall("getCustomFields");

}

############

sub get_all_customfields {
	my ($self) = @_;

	# Just here for one-off extract to use for mapping names.
	my $results = $self->soapcall_getCustomFields();
	my @cfs;
	foreach my $row (@$results) {
		my $cfname = $row->{name};
		my $cfid   = $row->{id};

		#print "$cfid: $cfname\n";
		push @cfs, $cfname;
	}

	return @cfs;
}

############

=head2 get_customfield_ids( <customfield names> )

 Returns list of custom field ids for supplied names

=cut

sub get_customfield_ids {

	# Param: list of custom field names
	# Returns:  list of custom field ids
	my $self    = shift;
	my @cfnames = @_;
	my %cfs;

	logdebug( "Getting customfield ids for customfield names: "
		  . join( ', ', @cfnames ) );

	my $results = $self->soapcall_getCustomFields();

	foreach my $row (@$results) {
		my $cfname = $row->{name};
		my $cfid   = $row->{id};

		# Returned id looks like "customfield_10034"
		# for most purposes, eg. db selects, we just want the numeric part so:
		$cfid =~ s/^\D+(\d+)$/$1/;

		#logdebug("Customfield id $cfid has name $cfname.");
		foreach (@cfnames) {
			if ( $cfname eq $_ ) {
				loginfo("Requested customfield name $cfname has id $cfid.");
				$cfs{$cfname} = $cfid;
			}
		}
	}

	# Need to return the list in the correct order
	my @cfids;
	foreach (@cfnames) {
		if ( !exists( $cfs{$_} ) ) {
			logcrit(
"Cannot find custom field named '$_' using getCustomFields soap request."
			);
			exit 1;
		}
		push( @cfids, $cfs{$_} );
	}

	return @cfids;
}

############

=head2 get_customfield_names( <customfield ids> )

 Returns list of custom field names for supplied ids

=cut

sub get_customfield_names {

	# Param: list of custom field ids
	# Returns:  list of custom field names
	my ( $self, @cfids ) = @_;
	my %cfs;

	loginfo( "Getting customfield names for customfield ids: "
		  . join( ', ', @cfids ) );

	my $results = $self->soapcall_getCustomFields();

	foreach my $row (@$results) {
		my $cfname = $row->{name};
		my $cfid   = $row->{id};
		logdebug("Customfield id $cfid has name $cfname.");
		foreach (@cfids) {
			if ( $cfid eq $_ ) {
				loginfo("Requested customfield id $cfid has name $cfname.");
				$cfs{$cfid} = $cfname;
			}
		}
	}

	# Need to return the list in the correct order
	my @cfnames;
	foreach (@cfids) {
		if ( !exists( $cfs{$_} ) ) {
			logcrit(
"Cannot find custom field id '$_' using getCustomFields soap request."
			);
			exit 1;
		}
		push( @cfnames, $cfs{$_} );
	}

	return @cfnames;
}

############

=head2 get_customfield_value( <issue key>, <custom field name>, <values> )

 Values returned from a jql search are ids which reference the real custom field value.
 This function takes those ids and returns the real values.

=cut

sub get_customfield_value {

	# Returns an array of values for the supplied custom field name
	my ( $self, $pkey, $fieldname, $customfieldvalues ) = @_;

	# Filter info
	my $customfield_id;

# $customfieldvalues is a reference to an array of objects of class RemoteCustomFieldValue,
# ie. an array of hashes, each hash having the keys: customfieldId, values, key

	foreach my $customfielddata (@$customfieldvalues) {
		my $id = $customfielddata->{customfieldId};
		my $cf = $self->customfields($id);
		$self->customfields( $id, $self->get_customfield_names($id) )
		  unless ($cf);

		my $name = $customfields{$id};

		next if ( $name ne $fieldname );

		my @values;
		@values = @{ $customfielddata->{values} };

		logdebug( "Found value(s) for customfield '$fieldname': "
			  . join( ", ", @values ) );

# Note that if value is from a cascading select list then it will have to
# be looked up in the db, because there is currently no way of doing this via the SOAP interface.

		if ( grep ( /^$fieldname$/, $self->getCascadeSelectList ) ) {
			logdebug(
"Getting values for cascading select custom field $fieldname from db."
			);
			@values = $self->get_cascadeselect_values( $pkey, $values[0] );
		}

		return @values;
	}

	logdebug(
"No values for customfield name '$fieldname'.  Returning string \%NOVALUE%."
	);
	if ( grep ( /^$fieldname$/, $self->getCascadeSelectList ) ) {
		return ( '%NOVALUE%', '%NOVALUE%' );
	}

	return '%NOVALUE%';
}

############

sub get_cascadeselect_values {
	my ( $self, $pkey, $cfoptionid ) = @_;
	my @values = ( "", "" );

	if ( $cfoptionid && $cfoptionid ne '%NOVALUE%' ) {
		logdebug( "and cf option id " . $cfoptionid );
		@values = $self->get_cf_value_from_db( $pkey, $cfoptionid );

		# Currently we always want 2 values for the Cascading Select fields,
		# if the sub value doesn't exist then we need to make it blank
		$values[1] = "" if ( !$values[1] || $values[1] eq '%NOVALUE%' );
	}

	return @values;

}

##################

sub dbname   { $_[0]->{dbname}   = $_[1] if defined $_[1]; $_[0]->{dbname}; }
sub dblogin  { $_[0]->{dblogin}  = $_[1] if defined $_[1]; $_[0]->{dblogin}; }
sub dbpass   { $_[0]->{dbpass}   = $_[1] if defined $_[1]; $_[0]->{dbpass}; }
sub dbhost   { $_[0]->{dbhost}   = $_[1] if defined $_[1]; $_[0]->{dbhost}; }
sub dbdriver { $_[0]->{dbdriver} = $_[1] if defined $_[1]; $_[0]->{dbdriver}; }

sub get_cf_value_from_db {
	my ( $self, $pkey, $cfoptionid ) = @_;
	use DBI;

# Quick rough hack, hoping Atlassian will provide a SOAP service to do this soon.
	my $dbname   = $self->dbname;
	my $dblogin  = $self->dblogin;
	my $dbpass   = $self->dbpass;
	my $dbhost   = $self->dbhost;
	my $dbdriver =
	  $self->dbdriver;    # ODBC should work for MSSQL, Pg for Postgres

	foreach (qw( dbname dblogin dbpass )) {
		die("$_ not defined. use \$object->$_(<value>) to define the value.\n")
		  unless ( $self->$_ );
	}

	# Re-use dbh if it is already set
	$self->{dbh} = DBI->connect( "dbi:$dbdriver:dbname=$dbname;host=$dbhost",
		$dblogin, $dbpass, { AutoCommit => 0 } )
	  unless ( $self->{dbh} );

	die( "Failed to connect to db: " . $DBI::errstr . "\n" )
	  unless ( $self->{dbh} );

	my $dbh = $self->{dbh};
	my @values;
	my $query;

#my $query = "
# SELECT customvalue FROM customfieldoption
# WHERE id =
#   (SELECT parentkey FROM customfieldvalue WHERE issue = (select id from jiraissue where pkey = '$pkey' ) and customfield = $cfid )
# ";

	$query =
	  "SELECT customvalue FROM customfieldoption WHERE id = $cfoptionid ";
	logdebug("$query");
	my $sth = $dbh->prepare($query);
	$sth->execute();

	my ($value) = $sth->fetchrow_array;
	$sth->finish;
	logdebug( "Found parent id '$cfoptionid' with value '" . $value . "'." );
	if ( !$value ) { $value = '%NOVALUE%'; }
	push( @values, $value );

	$query =
" select customvalue from customfieldoption where id = ( select stringvalue from customfieldvalue where issue = ( SELECT id FROM jiraissue WHERE pkey = '$pkey' ) and parentkey = $cfoptionid )";

	logdebug("$query");
	$sth = $dbh->prepare($query);
	$sth->execute();

	($value) = $sth->fetchrow_array;    # should really only be 1 result
	$sth->finish;
	logdebug( "Found child with value '" . $value . "'." );
	if ( !$value ) { $value = '%NOVALUE%'; }
	push( @values, $value );

	#$dbh->disconnect;

	loginfo("Customfield Values: @values");
	return (@values);

}

############# #############
# Jira SOAP Connection subs
############# #############

=head2 soap_connect( <Jira login>, <password>, <URL> )

 MANDATORY - Sets up soap connection

=cut

sub soap_connect {
	my ( $self, $soapuser, $soappass, $jiraurl ) = @_;
	$jiraurl = "http://localhost" if not defined $jiraurl;

	my $wsdlurl = "$jiraurl/rpc/soap/jirasoapservice-v2?wsdl";

	$self->soap( SOAP::Lite->new( proxy => $wsdlurl ) );

	# login method returns authentication token which we hold in $auth
	$self->auth( $self->soap->login( $soapuser, $soappass ) );

	if ( $self->{auth}->faultcode || $self->{auth}->faultstring ) {
		my $soap_error = join ', ', $self->{auth}->faultcode,
		  $self->{auth}->faultstring;
		logcrit("Cannot login to JIRA - error $soap_error");
		exit 0;
	}
	else {
		loginfo(
"Logged in to JIRA SOAP interface on $wsdlurl successful as user $soapuser"
		);
	}

}

###########

=head2 soap_logout

 Logs out current Jira SOAP connection.
 Good idea to run this from an END block.

=cut

sub soap_logout {
	my ($self) = @_;
	my $response = $self->{soap}->logout( $self->auth->result );

	if ( $response->faultcode || $response->faultstring ) {
		my $soap_error = join ', ', $response->faultcode,
		  $response->faultstring;
		logwarn("Cannot log out of JIRA - error $soap_error");
		exit 1;
	}
	else {
		loginfo("Jira SOAP connection logged out.");
	}

}

#############

=head2 doJiraSoapMethod ( <soap method name>, <arg>[, <arg>...] )

 Allows any jira soap method to be run
 Export is optional, so must be specified to import
 eg.
	use JiraSoap qw( doJiraSoapMethod );

=cut

sub doJiraSoapMethod {

	# Exportable wrapper for the jira_soapcall sub
	my ( $self, $callname, @args ) = @_;
	return $self->jira_soapcall( $callname, @args );
}

#############

sub jira_soapcall {
	my ( $self, $callname, @args ) = @_;
	my $authref = $self->auth;

	logdebug("Performing jira soap call to method $callname");
	logdebug( "with arguments: " . join( ", ", @args ) );

	my $response = $self->{soap}->$callname( $authref->result, @args );

	if ( $response->faultcode || $response->faultstring ) {
		my $soap_error = join ', ', $response->faultcode,
		  $response->faultstring;
		my $message =
		  "Cannot get results from $callname soap call.\n error: $soap_error";
		logwarn($message);
		return 0;
	}

	my $results = $response->result;

	return $results;

}

#############

sub get_projects {

	# Testing SOAP using this method.
	my ($self) = @_;
	my $response = $self->{soap}->getProjects( $self->auth->result );

	my @results = $response->result;

	foreach my $result (@results) {
		foreach my $project (@$result) {
			my $name = $project->{name};
			my $key  = $project->{key};
			my $url  = $project->{url};

			loginfo("Project: $name ; Key: $key ; URL: $url");
		}
	}
}

#######
# FIN #
#######
1;
