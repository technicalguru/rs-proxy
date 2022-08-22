package RsProxy::FileConfig;

use strict;
use warnings;

sub new {
	my $class = shift;
	my $self  = { @_ };
	if (!$self->{log}) {
		$self->{log} = new RsLog();
	}
	my $rc = bless $self, $class;
	$self->loadConfigFile();
	return $rc;
}

sub loadConfigFile {
	my $self = shift;
	$self->{config} = { };
	$self->{sections} = [ ];
	$self->{actions} = [ ];
	if (open(FIN, '<'.$self->{configFile})) {
		my $section = '_';
		my $action  = '';
		while (<FIN>) {
			chomp;
			my $line = $_;
			next if $line =~ /^\s*$/;
			next if $line =~ /^#\s*$/;
			if ($line =~ /^\s*\[([-0-9A-Za-z.:]+)\]\s*$/) {
				$section = $1;
				if ($section =~ /^action:(.*)/) {
					$action  = $1;
					$section = '';
					push(@{$self->{actions}}, $action);
				} else {
					$section =~ tr/A-Z/a-z/;
					push(@{$self->{sections}}, $section);
				}
			} elsif ($section) {
				my ($key, $value) = split('=', $line, 2);
				# Line ends with \ - then we continue reading next line
				while ($line =~ /\\\s*$/) {
					$line = <FIN>;
					$value =~ s/\\\s*$/\n/;
					$value .= $line;
				}
				$self->{config}->{$section.'.'.$key} = $value;
			} else {
				# Action definition
				$self->{config}->{'action.'.$action} .= $line."\n";
			}
		}
		close(FIN);
		my @CONFIG_STAT = stat($self->{configFile});
		$self->{lastModificationTime} = $CONFIG_STAT[9];
		$self->{log}->info('Configuration loaded: '.$self->{configFile});
	} else {
		$self->{log}->error('Cannot open configuration: '.$self->{configFile});
		exit 1;
	}
}

sub hasChanged {
	my $self = shift;
	my @CONFIG_STAT = stat($self->{configFile});
	return 1 if $self->{lastModificationTime} < $CONFIG_STAT[9];
	return 0;
}

sub isEmpty {
	my $self = shift;
	my $cnt  = scalar(keys(%{$self->{config}})) + scalar(@{$self->{sections}}) + scalar(@{$self->{actions}});
	return $cnt == 0;
}

sub get {
	my $self = shift;
	my $key = join('.', @_);

	return $self->{config}->{$key};
}

sub set {
	my $self = shift;
	my $key  = shift;
	my $val  = shift;
	$self->put($key, $val);
}

sub put {
	my $self = shift;
	my $key  = shift;
	my $val  = shift;

	$self->{config}->{$key} = $val;
}

sub getSections {
	my $self = shift;
	return (@{$self->{sections}});
}

sub getActions {
	my $self = shift;
	my $rc   = {};
	my $action;

	foreach $action (@{$self->{actions}}) {
		$rc->{$action} = $self->{config}->{'action.'.$action};
	}
	return $rc;
}

sub getAction {
	my $self = shift;
	my $action = shift;

	my @RC = ();
	@RC = split(/\s*\n\s*/, $self->{config}->{'action.'.$action});
	return (@RC);
}

sub getSectionConfig {
	my $self = shift;
	my $section = shift;
	my $rc = {};
	my $key;

	foreach $key (keys(%{$self->{config}})) {
		if ($key =~ /^$section\./) {
			my $tmp = $key;
			$tmp =~  s/^$section\.//;
			$rc->{$tmp} = $self->{config}->{$key};
		}
	}
	return $rc;
}

1;


