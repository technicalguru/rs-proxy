package RsProxy::RenewalConfig;

use strict;
use warnings;

sub new {
	my $class = shift;
	my $self  = { @_ };
	return bless $self, $class;
}

sub getName {
	my $self = shift;
	return $self->{name};
}

sub isEnabled {
	my $self = shift;
	if (!defined $self->{enabled}) {
		$self->{enabled} = 1;
	}
	return $self->{enabled};
}

sub getConfigFile {
	my $self = shift;
	return defined $self->{configFile} ? $self->{configFile} : '';
}

sub getCertType {
	my $self = shift;
	if (!defined $self->{certType}) {
		$self->{certType} = 'renew';
	}
	return $self->{certType};
}

sub getCertDir {
	my $self = shift;
	return defined $self->{certDir} ? $self->{certDir} : '';
}

sub getLESubDir {
	my $self = shift;
	return defined $self->{leSubDir} ? $self->{leSubDir} : '';
}

sub getPostActions {
	my $self = shift;
	if (!defined $self->{postActions}) {
		$self->{postActions} = [];
	}
	return @{$self->{postActions}};
}

sub getCertFiles {
	my $self = shift;
	if (!defined $self->{certFiles}) {
		$self->{certFiles} = [];
	}
	return @{$self->{certFiles}};
}

sub getCreationTimestamp {
	my $self = shift;
	if (defined($self->{creationTimestamp}) && ($self->{creationTimestamp} =~ /^\d+$/)) {
		my @T = gmtime($self->{creationTimestamp});
		return sprintf('%04d-%02d-%02dT%02d:%02d:%02dZ', $T[5]+1900, $T[4]+1, $T[3], $T[2], $T[1], $T[0]);
	} elsif (!defined($self->{creationTimestamp})) {
		my @T = gmtime(time);
		return sprintf('%04d-%02d-%02dT%02d:%02d:%02dZ', $T[5]+1900, $T[4]+1, $T[3], $T[2], $T[1], $T[0]);
	}
	return $self->{creationTimestamp};
}

sub getLastModificationTime {
	my $self = shift;
	if (defined($self->{lastModificationTime}) && ($self->{lastModificationTime} =~ /^\d+$/)) {
		my @T = gmtime($self->{lastModificationTime});
		return sprintf('%04d-%02d-%02dT%02d:%02d:%02dZ', $T[5]+1900, $T[4]+1, $T[3], $T[2], $T[1], $T[0]);
	} elsif (!defined($self->{lastModificationTime})) {
		my @T = gmtime(time);
		return sprintf('%04d-%02d-%02dT%02d:%02d:%02dZ', $T[5]+1900, $T[4]+1, $T[3], $T[2], $T[1], $T[0]);
	}
	return $self->{lastModificationTime};
}

sub to_json {
	my $self = shift;
	my $rc = '{';
	$rc .= '"apiVersion": "proxy.ralph-schuster.eu/v1",';
	$rc .= '"kind": "CertConfig",';
	$rc .= '"metadata":{';
	$rc .= '"name":"'.$self->getName().'",';
	$rc .= '"creationTimestamp":"'.$self->getCreationTimestamp().'",';
	$rc .= '"annotations":{"lastModificationTime":"'.$self->getLastModificationTime().'"}},';
	$rc .= '"spec":{';
	$rc .= '"enabled":'.($self->isEnabled() ? 'true' : 'false').',';
	$rc .= '"configFile":"'.$self->getConfigFile().'",';
	$rc .= '"certType":"'.$self->getCertType().'",';
	$rc .= '"certDir":"'.$self->getCertDir().'",';
	$rc .= '"leSubDir":"'.$self->getLESubDir().'",';

	my $a;
	my $hasEntry = 0;
	$rc .= '"certFiles":[';
	foreach $a (@{$self->{certFiles}}) {
		$rc .= ',' if $hasEntry;
		$rc .= '"'.$a.'"';
		$hasEntry = 1;
	}
	$rc .= '],';

	$hasEntry = 0;
	$rc .= '"postActions":[';
	foreach $a (@{$self->{postActions}}) {
		$rc .= ',' if $hasEntry;
		$rc .= '"'.$a.'"';
		$hasEntry = 1;
	}
	$rc .= ']';
	$rc .= '}}';
	return $rc;
}

1;


