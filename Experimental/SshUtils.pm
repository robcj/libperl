#!/usr/bin/perl -w

=head1 NAME

SshUtils.pm - Perform SSH tasks by making calls to shell ssh command, because our perl ssh module has dependencies missing

=head1 SYNOPSIS

=head2 Public methods

=head3 Constructor

 new

=head3 Accessors/get-setter methods

 user
 setUser
 getUser
 host
 setHost
 getHost
 dir
 chdir / cd / setDir
 pwd / getDir

=head3 Utility methods

 shCmd
 plCmd
 rstat($file)  -  return array of remote stat call
 rstatHash($file)  -  return hash of remote stat call with keys as per p801 of Perl Prog book
 fileType
 fileExists
 ls
 printLs
 lsDirs
 isFile
 isLink
 isDir
 atime
 mtime
 ctime
 age
 isOlderThan($time) - where time is seconds, "\d+ days" or "\d+ hours" etc.

 TBA:
 fileExists
 lsIgnore
 mv / move / rename
 rm / unlink
 rmdir
 getMTimeDiff($file, $sec)
 cp / copy
 mkDir

=head1 EXAMPLE

 use Datamail::SshUtils;
 my $objRef = SshUtils->new();
 $objRef->setHost("hostname1");
 $objRef->setUser("user1");
 $objRef->printLs("/tmp");

=cut

package Utilities::SshUtils;

use lib "..";
use strict;
use File::Basename;
use Utilities::SSHIO;
use Data::Dumper;

#############
# Methods
#############

sub new {
    my $class      = shift;
    my $confighref = shift;
    my $self       = {@_};
    bless $self;

    my @configkeys = qw(user login sshuser sshlogin sshhost host );
    for (@configkeys) {
        $self->$_( $confighref->{$_} ) if defined $confighref->{$_};
    }

    return $self;
}

sub user { $_[0]->{user} = $_[1] if defined $_[1]; $_[0]->{user}; }
sub setUser  { user(@_); }
sub getUser  { user(@_); }
sub sshlogin { user(@_); }
sub sshuser  { user(@_); }
sub login    { user(@_); }

sub host { $_[0]->{host} = $_[1] if defined $_[1]; $_[0]->{host}; }
sub setHost { host(@_); }
sub getHost { host(@_); }
sub sshhost { host(@_); }

=head3 exitcode

 Returns the exitcode of the last executed remote command.

=cut

sub exitcode { $_[0]->{ssh}->exitcode }
sub exitCode { exitcode @_ }

sub dir { $_[0]->{dir} = $_[1] if defined $_[1]; $_[0]->{dir}; }
sub cd { dir(@_); }
sub chdir  { dir(@_); }
sub setDir { dir(@_); }
sub getDir { dir(@_); }
sub pwd    { dir(@_); }

sub file { $_[0]->{file} = $_[1] if defined $_[1]; $_[0]->{file}; }
sub currentFile    { file(@_) }
sub setFile        { file(@_) }
sub getFile        { file(@_) }
sub setCurrentFile { file(@_) }
sub getCurrentFile { file(@_) }

sub end { $_[0]->{end} = $_[1] if defined $_[1]; $_[0]->{end}; }

=head3 printLs

 First arg should be dir.
 Print contents of a remote dir.

=cut

sub printLs {
    print join( "\n", ls(@_) ) . "\n";
}

=head3 ls

 List contents of a remote dir.
 Returns array of dir contents
 First arg should be dir.
 Second arg can be predicate options.
 Follows links to destination using -L predicate by default.
 Third arg can be options (find options that come after the path).

=cut

sub ls {
    my $self      = shift;
    my $dir       = shift;
    my $predicate = $_[0] ? shift : " -L ";
    my $opts      = $_[0] ? shift : " -maxdepth 1 ";
    my $cmd       = qq(find $predicate '$dir' $opts | grep -v "^$dir\$" );
    my @ls        = $self->shCmd($cmd);
    chomp @ls;
    return sort @ls;
}

=head3 lsNoFollow

 Same as ls but without the -L link following.

=cut

sub lsNoFollow { ls( @_, " " ) }

=head3 lsFollow

 Same as ls but using the find "-follow" option rather than -L predicate which is unavailable in older versions of find.

=cut

sub lsFollow { ls( @_, " ", "-follow -maxdepth 1" ) }

sub lsPl {
    my $self = shift;
    my $dir  = shift;
    my $cmd =
        'map { /\/\.\.?\$/ || print "\$_\n" } <'
      . $dir
      . '/*>, <'
      . $dir . '/\.*>';

    #my $cmd = 'print join "$_\n" , <' . $dir . '/.*>, <' . $dir . '/*>';
    #my @ls = $self->shCmd("perl -e '$cmd'");
    my @ls = $self->plCmd($cmd);
    chomp @ls;
    return @ls;
}

=head3 lsDirs

 First arg should be dir.
 List directories that exist in a remote dir.
 Returns array of directory names

=cut

sub lsDirs {
    my $self = shift;
    my $dir = shift if $_[0];
    $self->dir($dir) if $dir;
    $dir = $self->dir;

    my $cmd  = "find -L '$dir' -maxdepth 1 -type d ";
    my @dirs = $self->shCmd($cmd);
    chomp @dirs;
    return sort @dirs;
}

=head3 fileExists

 Uses current filename or first arg.
 Returns true if the string is a file (any type, including dir) that exists on the remote host.

=cut

sub fileExists {
    my $self = shift;
    $self->file(shift) if $_[0];
    my $file = $self->file;
    my $cmd  = "[ -e '$file' ] && echo 1 || echo 0 ";
    return ( $self->shCmd($cmd) )[0];
}

=head3 isDir($string)

 Uses current filename or First arg.
 Returns true if the string is a directory path on the remote host.

=cut

sub isDir {
    return isType( @_, 'directory' );
}

=head3 isFile($string)

 Uses current filename or First arg.
 Returns true if the string is a file, with path, on the remote host.

=cut

sub isFile {
    return isType( @_, 'file' );
}

=head3 isLink($string)

 Uses current filename or First arg.
 Returns true if the string is a symbolic link, with path, on the remote host.

=cut

sub isLink {
    return isType( @_, 'symbolic link' );
}

=head3 isType($type,$filepath)

 Uses current filename or First arg.
 Returns true if the string is a symbolic link, with path, on the remote host.

=cut

sub isType {
    my ( $self, $file, $type ) = @_;
    return 1 if ( $self->fileType($file) eq $type );
    0;
}

=head3 fileType <file>

 Uses current file as filepath, else full path and filename must be supplied as first arg.

 Returns the file type - 
		"file"
		"directory"
		"symbolic link"
		"named pipe (FIFO)"
		"socket"
		"block special file"
		"character special file"

 Returns 0 if unable to get a proper result.

=cut

sub fileType {
    my $stat = rstatHash(@_);
    return $stat->{type} if $stat;
    0;
}

=head3 mtime / atime / ctime <file>

 Uses current file as filepath, else full path and filename must be supplied as first arg.
 Returns the mtime, atime or ctime of the file.
 Returns 0 if unable to get a proper result.

=cut

sub mtime {
    my $stat = rstatHash(@_);
    return $stat->{mtime} if $stat;
    0;
}

sub atime {
    my $stat = rstatHash(@_);
    return $stat->{atime} if $stat;
    0;
}

sub ctime {
    my $stat = rstatHash(@_);
    return $stat->{ctime} if $stat;
    0;
}

=head3 age <file>

 Uses current file as filepath, else full path and filename must be supplied as first arg.
 Returns the age, in seconds, of the file.  ie. time since last modified (mtime).
 
=cut

sub age {
    my $mtime = mtime(@_);
    return time - $mtime if defined $mtime;
    0;
}

=head3 isOlderThan <time> <file>

 Returns true if file is older than time, time can be relative, eg. -2 days
 
=cut

sub isOlderThan {
    my $self = shift;
    my $time = shift;
    my $file = shift;
    my $age  = $self->age($file);

    if ( $time =~ /^\s*(\d+)\s*(\w+)\s*$/ ) {
        my $num   = $1;
        my $units = $2;
        if    ( $units =~ /minute/i ) { $time = $num * 60 }
        elsif ( $units =~ /hour/i )   { $time = $num * 60 * 60 }
        elsif ( $units =~ /day/i )    { $time = $num * 60 * 60 * 24 }
        elsif ( $units =~ /month/i )  { $time = $num * 60 * 60 * 24 * 30 }
        elsif ( $units =~ /year/i )   { $time = $num * 60 * 60 * 24 * 365 }
        else {
            print
              "ERROR: Invalid time arg '$time' used with sub isOlderThan()\n";
            exit 1;
        }
    }

    return 1 if ( $time < $age );
    0;
}

=head3 lsOlderThan <time> <arrayref of dirs> <arrayref of paths to ignore>

 Returns list of files in dir which are older than time, time must be relative, eg. 2 days
 dir can contain wildcards, eg. /vretrieve/input/*/input/normal
 
=cut

sub lsOlderThan {
    my $self       = shift;
    my $time       = shift;
    my $dirsaref   = shift;
    my $ignorearef = shift;
    my $maxdepth   = 1;
    my @ignore     = $ignorearef ? @$ignorearef : ();

    # need to get time in minutes to use with find command
    if ( $time =~ /^\s*([+-]?\d+)\s*(\w+)\s*$/ ) {
        my $num   = $1;
        my $units = $2;
        if    ( $units =~ /minute/i ) { $time = $num }
        elsif ( $units =~ /hour/i )   { $time = $num * 60 }
        elsif ( $units =~ /day/i )    { $time = $num * 60 * 24 }
        elsif ( $units =~ /month/i )  { $time = $num * 60 * 24 * 30 }
        elsif ( $units =~ /year/i )   { $time = $num * 60 * 24 * 365 }
        else {
            print
              "ERROR: Invalid time arg '$time' used with sub lsOlderThan()\n";
            exit 1;
        }
    }

    $time =~ s/^(\d)/\+$1/;

    # to prevent the parent dir itself being listed
    #my $dirstr = '"' . join('" "', @$dirsaref) . '"';
    # escape any spaces in dir path - can't quote or wildcards won't be expanded
    map { $_ =~ s/(\s)/\\$1/g } @$dirsaref;
    my $dirstr = join( ' ', @$dirsaref );
    my $ignorestr =
      ' ! -wholename "' . join( '" ! -wholename "', @$dirsaref, @ignore ) . '"';
    my $cmd =
      qq(find -L $dirstr -maxdepth $maxdepth -mmin $time $ignorestr 2>&1 );

    #print "CMD: $cmd\n";
    my @results = $self->shCmd($cmd);
    chomp @results;
    return @results;
}

=head3 rstat

 Uses current file as filename, else full path and filename must be supplied as first arg.
 Retrieve the perl stat array values for a remote file.
 Returns array.

=cut

sub rstat {
    my $self = shift;
    my $file = shift if $_[0];

    unless ($file) {
        print
"No file/dir defined. File/dir path must be provided as first parameter to this method.\n";
        return 0;
    }
    unless ( $self->fileExists($file) ) {
        print
"File '$file' does not appear to exist so cannot perform remote stat.\n";
        return 0;
    }

    $self->setCurrentFile($file) if $file;
    $file = $self->getCurrentFile;

    #my $cmd = qq( print join(',',stat('$file')); );
    my $delim = '~X' . ++$self->{counter} . 'X~';

    #my $delim = '~XX~';
    my $cmd = qq( print join('$delim',lstat('$file'),
    -f _ ? "file" :
    -d _ ? "directory" :
    -l _ ? "symbolic link" :
    -p _ ? "named pipe (FIFO)" :
    -S _ ? "socket" :
    -b _ ? "block special file" :
    -c _ ? "character special file" :
		"unknown"
    ). "\n";
  );

    my @data = $self->plCmd($cmd);
    my @results = split( $delim, join( '', @data ) );
    if ( $#results < 0 ) {
        print "Problem with rstat, nothing returned for file '$file'.\n";
        return 0;
    }

#elsif ( $#results == 0 ) { print "Problem with rstat, for file '$file'.\n Command: $cmd\n Results returned just: $results[0]\n"; return 0 }
    elsif ( $#results == 0 ) {
        print "Problem with rstat, for file '$file'.\n";

   # Command: $cmd\n Results returned ". split(/\n/, "$results[0]") ." lines\n";
        return 0;
    }
    return @results;
}

=head3 rstatHash

 Uses current file as filename, else full path and filename must be supplied as first arg.
 Retrieve the perl stat array values for a remote file, and determine file type
 Returns the results as a hash with keys:
	dev inode mode nlink uid gid rdev size atime mtime ctime blksize blocks type perm typeoct

=cut

sub rstatHash {
    my @stat   = rstat(@_);
    my $file   = pop;
    my $caller = ( caller(1) )[3];
    unless ( scalar @stat > 1 ) {
        if ( $#stat == 0 && "$stat[0]" eq "0" ) {
            print
"rstat function failed when reading '$file' for caller $caller.\n";
        }
        elsif ( defined $file ) {
            print
"Nothing returned from rstat subroutine. There must have been a problem reading $file\n";
        }
        else {
            print
"No file supplied to subtroutine rstatHash.  Here is the subroutine call stack for the last 5 calls:\n";
            foreach my $call ( 1 .. 5 ) {
                print join( ",", ( caller($call) )[ ( 0, 3, 2 ) ] ) . "\n";
            }
        }
        return 0;
    }

    my %hash;
    foreach (
        qw(dev inode mode nlink uid gid rdev size atime mtime ctime blksize blocks type)
      )
    {
        $hash{$_} = shift @stat;
    }

 #my $caller = (caller(1))[3]; print "CALLER: $caller : @_ mode: $hash{mode}\n";
    $hash{perm} = sprintf( "%04o", $hash{mode} & 07777 ) if defined $hash{mode};
    $hash{typeoct} = sprintf( "%04o", $hash{mode} & 70000 )
      if defined $hash{mode};
    return \%hash;

}

=head3 rmkdir(<dir>)

 creates a new dir on the remote host
 
=cut

sub rmkdir {
    my $self = shift;
    my $dir  = shift;
    $self->plCmd("print mkdir '$dir'; ");
}

=head3 shCmd([shell command] [,hostname [,login]])
 
  hostname, login parameters are optional if already set using setUser or setHost
  runs a shell command via SSHIO module and returns an array ref of the results.
  The end of the output is indicated by a line defined in $self->end

=cut

sub shCmd {
    my $self = shift;
    my $cmd = shift if $_[0];
    $self->setHost(shift) if $_[0];
    $self->setUser(shift) if $_[0];
    $self->{ssh} =
      Utilities::SSHIO->new( "-l " . $self->getUser, $self->getHost )
      unless defined $self->{ssh};

    unless ($cmd) {
        print
"No shell command defined. Command must be provided as first parameter to this method.\n";
        return 0;
    }

    unless ( defined $self->getHost ) {
        print "No remote host defined.\n";
        return 0;
    }

    #print "CMD: $cmd\n";
    return $self->{ssh}->run($cmd);
}

sub plCmd {
    my $self = shift;
    my $cmd = shift if $_[0];

    $cmd = qq(perl <<PERLEOT_SshUtils\n$cmd\nPERLEOT_SshUtils\n);
    return $self->shCmd( $cmd, @_ );
}

sub disconnect { finished(@_) }
sub finished   { $_[0]->{ssh}->DESTROY }

1;
