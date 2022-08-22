package RsLog;
use strict;
use warnings;

# Defines severities of messages to log
my $TYPES;

my $logfile;

sub new {
	my $class = shift;
	my $self  = { @_ };
	if (!$self->{TYPES}) {
		$self->{TYPES} = ['ERROR', 'WARN', 'INFO', 'DEBUG'];
	}
	return bless $self, $class;
}

# Creates the time string for log messages
# Usage: getTimestring($unixTimeValue)
sub getTimestring {
	my $self = shift;
	my $t = shift;
	$t = time if !$t;
	my @T = localtime($t);
	my $time = sprintf("%02d/%02d/%04d %02d:%02d:%02d",
			   $T[3], $T[4]+1, $T[5]+1900, $T[2], $T[1], $T[0]);
	return $time;
}

# logs an error message
# Usage: error($message);
sub error {
	my $self = shift;
	my $s = shift;
	$self->log($s, 'ERROR');
}

# logs a warn message
# Usage: warn($message);
sub warn {
	my $self = shift;
	my $s = shift;
	$self->log($s, 'WARN');
}

# logs an information message
# Usage: info($message);
sub info {
	my $self = shift;
	my $s = shift;
	$self->log($s, 'INFO');
}

# logs a debug message
# Usage: debug($message);
sub debug {
	my $self = shift;
	my $s = shift;
	$self->log($s, 'DEBUG');
}
# logs a single entry with given message severity
# Usage: logEntry($message, $severity);
sub log {
	my $self = shift;
	my $s = shift;
	my $type = shift;
	return if !grep(/^$type$/, @{$self->{TYPES}});

	# build timestamp and string
	$type = $self->rpad($type, 5);
	my $time = $self->getTimestring();
	$s =~ s/\n/\n$time $type - /g;

	# print to STDOUT if required
	if ($self->{logfile}) {
		if (open(LOGOUT, ">>".$self->{logfile})) {
			print LOGOUT "$time $type - $s\n";
			close(LOGOUT);
		} else {
			print "$time $type - $s\n";
		}
	} else {
		print "$time $type - $s\n";
	}
}

# Right pads a string
# Usage: rpad($string, $maxlen[, $padchar]);
sub rpad {
	my $self = shift;
	my $s = shift;
	my $len = shift;
	my $char = shift;

	$char = ' ' if !$char;
	$s .= $char while (length($s) < $len);
	return $s;
}

1;

