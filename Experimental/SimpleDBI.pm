#!/usr/bin/perl -w

package Utilities::SimpleDBI;

###########
# Modules #
###########

use strict;
use DBI;

##################
# Pre-declare Methods
# perl -ne '/^(sub \w+)\s{\W/$1 ;/; print' SimpleDBI.pm
##################

=head2 Methods

sub new ;
sub user ;
sub setUser ;
sub getUser ;
sub dbname ;
sub setDbName ;
sub getDbName ;
sub host ;
sub setHost ;
sub getHost ;
sub port ;
sub setPort ;
sub getPort ;
sub pass ;
sub setPass ;
sub getPass ;
sub dbConnect ;
sub dbDisconnect ;
sub getDbh ;
sub getSqlSth ;
sub sqlFetchAllArray ;
sub getFirstColSortedArray ;
sub getFirstColArrayRef ;
sub get1DimSQLResponseHash ;
sub getSqlSingleValue ;
sub getSqlSingleRowArray ;
sub getPreparedSqlSingleValue ;
sub sthFinish ;
sub getPreparedSqlSingleRowArray ;
sub prepareSql ;
sub executePreparedStatement ;
sub abort ;

=cut

##################
# Methods
##################

sub new {
  my $class = shift;
  my $confighref = shift;
  my $self = {@_};
  bless $self;

  my @configkeys =  qw(dbuser user dblogin db dbname name dbpass pass dbhost host dbserver port dbport);
  for (@configkeys) { $self->$_( $confighref->{$_} ) if defined $confighref->{$_}; }

  # Defaults
	$self->port('5432') unless defined $self->{port};

  return $self;
}

##################

sub user { $_[0]->{user}=$_[1] if defined $_[1]; $_[0]->{user}; }
sub setUser { user(@_); }
sub getUser { user(@_); }
sub dbuser { user(@_); }
sub dblogin { user(@_); }

sub dbname { $_[0]->{dbname}=$_[1] if defined $_[1]; $_[0]->{dbname}; }
sub setDbName { dbname(@_); }
sub getDbName { dbname(@_); }
sub dbName { dbname(@_); }
sub db { dbname(@_); }

sub host { $_[0]->{host}=$_[1] if defined $_[1]; $_[0]->{host}; }
sub setHost { host(@_); }
sub getHost { host(@_); }
sub dbhost { host(@_); }
sub dbserver { host(@_); }

sub port { $_[0]->{port}=$_[1] if defined $_[1]; $_[0]->{port}; }
sub setPort { port(@_); }
sub getPort { port(@_); }
sub dbport { port(@_); }

sub pass { $_[0]->{pass}=$_[1] if defined $_[1]; $_[0]->{pass}; }
sub setPass { pass(@_); }
sub getPass { pass(@_); }
sub dbpass { pass(@_); }

sub dbh { $_[0]->{dbh}=$_[1] if defined $_[1]; $_[0]->{dbh}; }

#############

sub dbConnect {
	my $self = shift;
  # Return if the dbhandle is already set
  return $self->getDbh if (defined $self->{dbh});
	
	my ($dbname, $host, $port, $user, $pass) = ($self->getDbName, $self->getHost, $self->getPort, $self->getUser, $self->getPass);
	grep { die "db parameter $_ not defined" unless defined $self->{$_} } ( qw(dbname host port user pass) ) ;

  # Set up the dbhandle reference
    $self->{dbh} = DBI->connect("dbi:Pg:dbname=$dbname;host=$host;port=$port",
      $user,
      $pass,
      {AutoCommit => 0, RaiseError => 1, PrintError => 0}
    );

  while ( $self->{dbh}->err )  {
    abort("Error code $_ returned when trying to connect to dbi:Pg:dbname=$dbname;host=$host;port=$port as $user ", $_);
  }

  return $self->{dbh};
}

#############

sub dbDisconnect {
	my $self = shift ;
	$self->{dbh}->disconnect;
	delete $self->{dbh};
}

#############

# get current dbh handle 
sub getDbh { $_[0]->{dbh}; }

#############

sub getSqlSth {
	# get statement handle for SQL statement
	my ($self, $sql, @params) = @_ ;
	my $sth = $self->{dbh}->prepare_cached($sql);
	$sth->execute(@params);
	return $sth;
}

#############

sub sqlFetchAllArray {
	my ($self, $sql) = @_ ;
	my $aref = $self->{dbh}->selectall_arrayref($sql);
	return @$aref
}

#############

sub selectcol_array {
	@{$_[0]->selectcol_arrayref($_[1])};
}

#############

sub selectcol_arrayref {
  $_[0]->dbConnect->selectcol_arrayref($_[1])
}

#############

sub getSqlResponseHash {
  # Params: sql query string, Returns: hash ref
  # SQL query must return just 2 columns, first will be the hash key, second will be the values
  # extra columns will be ignored.
	my ($self, $sql) = @_ ;
	my $aref = $self->{dbh}->selectall_arrayref($sql);
	return { map { $$_[0], $$_[1] } @{$aref} } ;
}

#############

sub getSqlSingleValue {
	my $self = shift ;
	my ($result) = $self->{dbh}->selectrow_array(shift);
	return $result;
}

#############

sub getSqlSingleRowArray {
	my $self = shift ;
	return $self->{dbh}->selectrow_array(shift);
}

#############

sub getPreparedSqlSingleValue {
	my $self = shift ;
	my $sth = $self->executePreparedStatement(@_);
	my ($result) = $sth->fetchrow_array;
	return $result;
}

#############

sub getPreparedSqlSingleRowArray {
	my $self = shift ;
	my $sth = $self->executePreparedStatement(@_);
	$self->{sth}->fetchrow_array();
}

#############

sub prepareSql {
	my $self = shift ;
  my ($psname, $sql) = @_;
  # Args: Prepared statement name, SQL
  #eg. $self->prepareSql("prepare_cr_clean", "SELECT * FROM jira_issues WHERE duedate < ?");
  # Probably should have used prepare_cached method here, but I believe I'm acheiving the
  # same thing with the bonus of being able to refer to a prepared query
  # using a short name ($psname).
  # Although that may not be as useful here as I had previously thought.

	return abort("No name provided for prepared statement. $psname", 0 ) unless $psname;
	return abort("No sql provided for prepared statement. $sql", 0 ) unless $sql;

  if ( defined $self->{prepared}{$psname}{psref} ) {
      logdebug("Prepared sql statement named '$psname' already prepared, skipping");
      return;
  }

	# Add newly provided sql to the hash
	$self->{prepared}{$psname}{sql} = $sql;

  $self->dbConnect;
	$self->{prepared}{$psname}{psref} = $self->{dbh}->prepare($sql) ;
	# the psname psref element now holds a statement handle (sth) for this query.

	if ( $self->{dbh}->err ){
		delete $self->{prepared}{$psname};
	 	return abort("Failed to prepare '$psname' sql statement:\n $sql\nReturned error string:". $self->{dbh}->errstr , 1 );
	}

}

###################

sub executePreparedStatement {
  # Execute pre-prepared statement and return results statement handle 
	my $self = shift ;
  my ( $psname, @parameters ) = @_;

	abort("Query '$psname' has not been prepared.",0) unless ( defined $self->{prepared}{$psname}{psref} );

  my $sth =  $self->{prepared}{$psname}{psref};

  if ( ! $sth->execute(@parameters) ){
		$sth->rollback;
		return abort("Failed to execute prepared statement $psname.\n". $sth->errstr, 0 );
  }

  if ( ! $self->{dbh}->commit ){
    $self->{dbh}->rollback;
    return abort("Commit failed. ". $self->{dbh}->errstr, 0 );
  }

  # The results can now be obtained by using methods like fetchrow_array on the $self->{prepared}{$stname}{psref}
	return $self->{prepared}{$psname}{psref};
}


#############
# misc utils
#############

sub abort {
	warn(shift);
	my $errval = shift;
	return $errval ? $errval : 0 ;
}
1;

