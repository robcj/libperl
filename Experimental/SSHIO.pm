#!/usr/bin/perl -w

package Utilities::SSHIO;

use IO::Handle qw( );
use IPC::Open2;
use File::Basename;

sub new {
	my $class = shift(@_);

	my ( $to_ssh, $fr_ssh );

	# open2 dies on error.
	my $pid = open2( $fr_ssh, $to_ssh, 'ssh', '-T', @_ );

	$to_ssh->autoflush(1);

	return bless(
		{
			pid    => $pid,
			to_ssh => $to_ssh,
			fr_ssh => $fr_ssh,
		},
		$class
	);

}

sub exitcode { $_[0]->{exitcode} = $_[1] if defined $_[1]; $_[0]->{exitcode} }
sub exitCode { exitcode @_ }

sub maxUndef {
	$_[0]->{maxUndef} = $_[1] if defined $_[1];
	$_[0]->{maxUndef} = 100 unless defined $_[0]->{maxUndef};
	$_[0]->{maxUndef};
}

sub terminator {
	$_[0]->{terminator} = $_[1] if defined $_[1];
	$_[0]->{terminator} =
	  basename($0) . "-$$-" . ++$_[0]->{counter} . "-FLUSH\n"
	  unless defined $_[0]->{terminator};
	$_[0]->{terminator};
}

sub initiator {
	$_[0]->{initiator} = $_[1] if defined $_[1];
	$_[0]->{initiator} = basename($0) . "-$$-" . ++$_[0]->{counter} . "-START\n"
	  unless defined $_[0]->{initiator};
	$_[0]->{initiator};
}

sub disconnect { $_[0]->DESTROY }

sub DESTROY {
	my ($self) = @_;

	#my @trash = $self->run("exit 2>/dev/null");
	close $self->{fr_ssh};
	close $self->{to_ssh};
	kill 1, $self->{pid} || kill 9, $self->{pid} || kill 15, $self->{pid};
	waitpid( $self->{pid}, 0 );
}

sub sendCmd {
	my ( $self, $command ) = @_;
	my $fr_ssh = $self->{fr_ssh};
	my $to_ssh = $self->{to_ssh};
	print $to_ssh $command;
	my @response;

	# open2 buffer ends at 99 lines so need to detect if it has ended early
	# and continue reading the pipe if it has.
	while ( my ( $terminated, @ret ) = $self->readPipe ) {
		push @response, @ret;
		last if $terminated;
	}
	return @response;
}

sub readPipe {
	my ($self) = @_;
	my $fr_ssh = $self->{fr_ssh};

	my @response;
	my $udcount  = 0;
	my $lastline = 0;

	# open2 buffer ends at 99 lines so need to detect if it has ended early
	# and continue reading the pipe if it has.
	while ( my $line = <$fr_ssh> ) {

		# make sure the fr_ssh pipe is cleared of accidental old junk
		if ( $line eq $self->initiator ) {
			@response = ();
			$udcount  = 0;
			next;
		}
		if ( $line eq $self->terminator ) { $lastline = $line; last }
		last if ++$udcount >= $self->maxUndef;
		push @response, $line if ($line);
	}
	return $lastline, @response;
}

sub run {
	my ( $self, $cmd ) = @_;

	# reset initiator and terminator
	$self->{initiator}  = undef;
	$self->{terminator} = undef;

# echo the initiator to show the start of this command output, so any previous residual dirt can be ignored
	my $command = 'echo -e "\n"' . $self->initiator;

	# Append an eol to command if there isn't one
	$command .= "\n" unless ( $command =~ /\n$/ );

	$command .= $cmd;

	# Append an eol to command if there isn't one
	$command .= "\n" unless ( $command =~ /\n$/ );

	# Echo the last exit code
	$command .= "echo \$?\n";

# echo the terminator to trigger the output flush with extra preceding \n in case command does not output a \n at the end.
#$command .=  'echo -e "\n"'. $self->terminator;
	$command .= 'echo ' . $self->terminator;

	# Append an eol to terminator if there isn't one
	$command .= "\n" unless ( $command =~ /\n$/ );
	my @response = $self->sendCmd($command);
	chomp $response[$#response]
	  if scalar
	  @response;    # remove the extra \n that we prepended to the terminator.
	                # get the exitcode we echoed at the end of the command
	$self->{exitcode} = pop @response;
	return @response;
}

sub runStr {
	join '', run(@_);
}

=head1 Example

 my $ssh = SSHIO->new("-l robincj", "vr2-ak-test-dcs-01" );
 print $ssh->runStr("ls");
 print $ssh->runStr("ls -l /vretrieve/");

=cut

1;
