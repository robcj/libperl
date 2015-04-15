#!/usr/bin/perl -w

use strict;

=head1 NAME

FileLineMatch - OO module to simplify the parsing of text files, locally or over SSH

=head1 SYNOPSIS

=head2 Public methods

=head3 Constructor

 new

=head3 Accessors/get-setter methods

 setRemoteUser
 getRemoteUser
 setRemoteHost
 getRemoteHost
 setFile
 getFile
 addPattern
 getPattern
 setPattern

=head3 Utility methods

 getCurrentPattern
 getCurrentPatternIndex
 getPatternLineCount
 getMatchingLineCount
 getLineCount
 printNextLine
 printNextMatchingLine
 getNextMatchingLine
 getNextLine
 closeFile

=head1 EXAMPLE

 use Datamail::FileLineMatch;
 my $objRef = FileLineMatch->new();
 $objRef->setPattern("^Hi (\w+)$");
 $objRef->setFile("/tmp/example.txt");
 $objRef->setRemoteHost("hostname1");
 $objRef->setRemoteUser("user1");
 $objRef->printNextLine;
 $objRef->printNextMatchingLine;
 while (my $line = $objRef->getNextMatchingLine()) {
 	my $pIx = $objRef->getCurrentPatternIndex();
 	my $pattern = $objRef->getCurrentPattern();
	my ( $capture ) = ( $line =~ m/$pattern/ );
	print "Name: $capture\n";
  print "Current count of matching lines: ". $objRef->getMatchingLineCount ."\n";
 }

 print "Total matching lines: ". $objRef->getMatchingLineCount ."\n";
 print "Total lines read: ". $objRef->getLineCount ."\n";
 $objRef->closeFile;

=cut

package Utilities::FileLineMatch;

##########################
# Predeclare Methods
##########################

# Constructor
sub new ; # public
# Accessors/get-setters
sub remoteUser ;
sub setRemoteUser ; # public
sub getRemoteUser ; # public
sub remoteHost ;
sub setRemoteHost ; # public
sub getRemoteHost ; # public
sub file ;
sub setFile ; # public
sub getFile ; # public
sub patterns ;
sub addPattern ; # public
sub getPattern ; # public
sub setPattern ; # public
# Utility methods
sub currentPattern ;
sub setCurrentPattern ;
sub getCurrentPattern ; # public
sub currentPatternIndex ;
sub setCurrentPatternIndex ;
sub getCurrentPatternIndex ; # public
sub patternLineCount ;
sub setPatternLineCount ;
sub getPatternLineCount ; # public
sub getMatchingLineCount ; # public
sub getLineCount ; # public
sub printNextLine ; # public
sub printNextMatchingLine ; # public
sub getNextMatchingLine ; # public
sub getNextLine ; # public
sub closeFile ; # public
sub openFile ;
sub openRemoteFile ;

#############
# Methods
#############

sub new { 
	my $class = shift;
	my $self = {@_};
	bless $self; 
	return $self;
}

sub remoteUser { $_[0]->{remoteUser}=$_[1] if defined $_[1]; $_[0]->{remoteUser}; }
sub setRemoteUser { remoteUser(@_); }
sub getRemoteUser { remoteUser(@_); }

sub remoteHost { $_[0]->{remoteHost}=$_[1] if defined $_[1]; $_[0]->{remoteHost}; }
sub setRemoteHost { remoteHost(@_); }
sub getRemoteHost { remoteHost(@_); }

sub file { $_[0]->{file}=$_[1] if defined $_[1]; $_[0]->{file}; }
sub setFile { file(@_); }
sub getFile { file(@_); }

sub patterns { my $self = shift ;  @{$self->{patterns}} = @_ if defined $_[0]; $self->{patterns} }
sub addPattern { my $self = shift ;  push( @{$self->{patterns}}, @_ ) if defined $_[0]; $self->{patterns} }
sub getPattern { patterns(@_); }
sub setPattern { patterns(@_); }

sub currentPattern { $_[0]->{currentPattern}=$_[1] if defined $_[1]; $_[0]->{currentPattern}; }
sub setCurrentPattern { currentPattern(@_); }
sub getCurrentPattern { currentPattern(@_); }

sub currentPatternIndex { $_[0]->{currentPatternIndex}=$_[1] if defined $_[1]; $_[0]->{currentPatternIndex}; }
sub setCurrentPatternIndex { currentPatternIndex(@_); }
sub getCurrentPatternIndex { currentPatternIndex(@_); }

sub patternLineCount {
	# method takes 1 or 2 args - the pattern index and optional value, returns current value
	my $self = shift ;
	if (defined $_[0]) {
		my $index = shift;
		$self->{patternLineCount}->[$index] = shift if defined $_[0] ;
		return $self->{patternLineCount}->[$index];
	}
	0;
}
sub setPatternLineCount { patternLineCount(@_) } # method takes 2 args - the pattern index and value, returns value
sub getPatternLineCount { patternLineCount(@_) } # method takes 1 arg - the pattern index and returns the value

sub getMatchingLineCount { $_[0]->{matchingLineCount} }

sub getLineCount { currentPatternIndex(@_); }

sub printNextLine { while (getNextLine(@_)){ print; return $_; } 0; }

sub printNextMatchingLine { while (getNextMatchingLine(@_)) { print; return $_; } 0; }

sub getNextMatchingLine {
	#my $pattern = "(" . join("|", @{patterns(@_)}) . ")";
	#while (getNextLine(@_)) { return $_ if m/$pattern/ ; }
	
	my $self = shift;

	my @patterns = @{$self->patterns(@_)};
	while ( my $line = $self->getNextLine(@_) ) {
		$self->{currentPatternIndex} = -1;
		foreach my $pattern (@patterns) {
			$self->{currentPatternIndex}++;
			if ( $line =~ m/$pattern/ ){
				$self->{currentPattern} = $pattern;
				$self->{patternLineCount}->[$self->{currentPatternIndex}]++;
				$self->{matchingLineCount}++;
				return $line;
			}
		}
	}

	0;
}

sub getNextLine {
	my $self = shift;

	return 0 if (! defined $self->{fh} && ! $self->openFile() ) ;

	my $fh = $self->{fh};
	# only return line if there is one to return
	while (<$fh>) {
		$self->{lineCount}++;
		return $_;
	}
	$self->closeFile();
	0;
}

sub closeFile {
	my $self = shift;
	return 0 if (! defined $self->{fh} );
	close  $self->{fh};
	delete $self->{fh};
}

sub openFile {
	my $self = shift;

	$self->setFile(shift) if $_[0];
	$self->setRemoteHost(shift) if $_[0];

	if ( defined $self->{remoteHost} && lc($self->{remoteHost}) ne 'localhost' ) {
		return $self->openRemoteFile();
	}

	if (! defined $self->{file}) {
		print "No file defined for reading.  Use method: openFile(<filename>).\n";
		return 0;
	}
	if (! open $self->{fh}, "<", $self->{file} ) {
		print ("Cannot open file ". $self->{file} ."\n$!\n");
		return 0;
	}

	return $self->{fh};
}

sub openRemoteFile {
	my $self = shift;
	$self->setFile(shift) if $_[0];
	$self->setRemoteHost(shift) if $_[0];
	
	if (! defined $self->{remoteHost}) {
		print "No remote host defined.  Use method: openFile(<filename>) for local files, or openRemoteFile(<filename>,<hostname>) for remote files.\n";
		return 0;
	}
	if (! defined $self->{file}) {
		print "No file defined for reading.  Use method: openFile(<filename>).\n";
		return 0;
	}
	
	my $file = $self->{file};
	my $remoteHost = $self->{remoteHost};
	my $username = $self->{remoteUser};

	my $cmd = qq(ssh -l $username $remoteHost "cat $file" );
	if (! open( $self->{fh}, "$cmd |" ) ) {
		print ("Cannot open remote file ". $self->{file} ." using command '$cmd'\n$!\n");
		return 0;
	}
	return $self->{fh};
	
}

1;

