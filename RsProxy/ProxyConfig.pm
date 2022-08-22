package RsProxy::ProxyConfig;

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

sub isCertEnabled {
	my $self = shift;
	if (!defined $self->{certEnabled}) {
		$self->{certEnabled} = 1;
	}
	return $self->{certEnabled};
}

sub getServerName {
	my $self = shift;
	return $self->{serverName};
}

sub getServerAliases {
	my $self = shift;
	if (!defined $self->{serverAliases}) {
		$self->{serverAliases} = [];
	}
	return @{$self->{serverAliases}};
}

sub getHttpsRedirect {
	my $self = shift;
	if (!defined $self->{httpsRedirect}) {
		$self->{httpsRedirect} = 'ServerName';
	}
	return $self->{httpsRedirect};
}

sub getHttpsInclude {
	my $self = shift;
	return $self->{httpsInclude};
}

sub getProxyType {
	my $self = shift;
	if (!defined $self->{proxyType}) {
		$self->{proxyType} = 'ReverseProxy';
	}
	return $self->{proxyType};
}

sub addReverseProxy {
	my $self = shift;
	my $path = shift;
	my $target = shift;

	$self->{reverseProxies} = [] if !defined $self->{reverseProxies};
	my $proxy = {};
	$proxy->{target} = $target;
	$proxy->{path}   = defined $path ? $path : '/';
	push(@{$self->{reverseProxies}}, $proxy);
}

sub getReverseProxies {
	my $self = shift;
	return @{$self->{reverseProxies}};
}

sub getCertType {
	my $self = shift;
	if (!defined $self->{certType}) {
		$self->{certType} = 'renew';
	}
	return $self->{certType};
}

sub getCertFiles {
	my $self = shift;
	if (!defined $self->{certFiles}) {
		$self->{certFiles} = [];
	}
	return @{$self->{certFiles}};
}

sub getPostActions {
	my $self = shift;
	if (!defined $self->{postActions}) {
		$self->{postActions} = [];
	}
	return @{$self->{postActions}};
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
	$rc .= '"kind": "ProxyConfig",';
	$rc .= '"metadata":{';
	$rc .= '"name":"'.$self->getName().'",';
	if ($self->{namespace}) {
		$rc .= '"name":"'.$self->{namespace}.'",';
	}
	$rc .= '"creationTimestamp":"'.$self->getCreationTimestamp().'",';
	$rc .= '"annotations":{"lastModificationTime":"'.$self->getLastModificationTime().'"}},';
	$rc .= '"lastModificationTime":"'.$self->getLastModificationTime().'"},';
	$rc .= '"spec":{';
	$rc .= '"enabled":'.($self->isEnabled() ? 'true' : 'false').',';
	$rc .= '"certEnabled":'.($self->isCertEnabled() ? 'true' : 'false').',';
	$rc .= '"serverName":"'.$self->getServerName().'",';

	my $a;
	my $hasEntry = 0;
	$rc .= '"serverAliases":[';
	foreach $a (@{$self->{serverAliases}}) {
		$rc .= ',' if $hasEntry;
		$rc .= '"'.$a.'"';
		$hasEntry = 1;
	}
	$rc .= '],';

	$rc .= '"httpsRedirect":"'.$self->getHttpsRedirect().'",';
	$rc .= '"proxyType":"'.$self->getProxyType().'",';

	$hasEntry = 0;
	$rc .= '"reverseProxies":[';
	foreach $a (@{$self->{reverseProxies}}) {
		$rc .= ',' if $hasEntry;
		$rc .= '{"path":"'.$a->{path}.',","target":"'.$a->{target}.'"}';
		$hasEntry = 1;
	}
	$rc .= '],';

	$rc .= '"certType":"'.$self->getCertType().'",';

	$hasEntry = 0;
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

sub to_yaml {
	my $self = shift;
	my $rc = "apiVersion: proxy.ralph-schuster.eu/v1\n";
	$rc   .= "kind: ProxyConfig\n";
	$rc   .= "metadata:\n";
	$rc   .= "  name: ".$self->getName()."\n";
	$rc   .= "  creationTimestamp: ".$self->getCreationTimestamp()."\n";
	$rc   .= "  annotations:\n";
    $rc   .= "    lastModificationTime: ".$self->getLastModificationTime()."\n";
	$rc   .= "spec:\n";
	$rc   .= "  enabled: false\n" if !$self->isEnabled();
	$rc   .= '  proxyType: "'.$self->getProxyType()."\"\n";
	$rc   .= "  serverName: \"".$self->getServerName()."\"\n" if $self->getServerName();

	my $a;
	my $hasEntry = 0;
	if (@{$self->{serverAliases}}) {
		$rc .= "  serverAliases: [";
		foreach $a (@{$self->{serverAliases}}) {
			$rc .= ', ' if $hasEntry;
			$rc .= '"'.$a.'"';
			$hasEntry = 1;
		}
		$rc .= "]\n";
	}

	$rc .= '  httpsRedirect: "'.$self->getHttpsRedirect()."\"\n" if $self->getHttpsRedirect() ne 'ServerName';

	if (@{$self->{reverseProxies}}) {
		$rc .= "  reverseProxies: \n";
		foreach $a (@{$self->{reverseProxies}}) {
			$rc .= "  - path: \"".$a->{path}."\"\n";
			$rc .= "    target: \"".$a->{target}."\"\n";
		}
	}

	$rc .= "  certEnabled: false\n" if !$self->isCertEnabled();
	$rc .= "  certType: \"".$self->getCertType()."\"\n";

	if (@{$self->{certFiles}}) {
		$hasEntry = 0;
		$rc .= "  certFiles: [";
		foreach $a (@{$self->{certFiles}}) {
			$rc .= ', ' if $hasEntry;
			$rc .= '"'.$a.'"';
			$hasEntry = 1;
		}
	}

	if (@{$self->{postActions}}) {
		$hasEntry = 0;
		$rc .= "  postActions: [";
		foreach $a (@{$self->{postActions}}) {
			$rc .= ', ' if $hasEntry;
			$rc .= '"'.$a.'"';
			$hasEntry = 1;
		}
	}

	return $rc;
}

# Load from a file configuration object
sub fromFile {
	my $self   = shift;
	my $config = shift;

	$self->{lastModificationTime} = $config->{lastModificationTime};
	$self->{enabled}              = $config->get('apache', 'enabled');
	$self->{enabled}              = 1 if !defined($self->{enabled});
	$self->{certEnabled}          = $config->get('certificate', 'enabled');
	$self->{certEnabled}          = 1 if !defined($self->{certEnabled});
	$self->{serverName}           = $config->get('apache', 'ServerName');
	$self->{serverName}           = '' if !defined($self->{serverName});
	$self->{serverAliases}        = [];
	if (defined $config->get('apache', 'ServerAlias')) {
		push(@{$self->{serverAliases}}, split(/[,\s]+/, $config->get('apache', 'ServerAlias')));
	}
	$self->{httpsRedirect}  = $config->get('apache', 'httpsRedirect');
	$self->{httpsRedirect}  = 'ServerName' if !defined($self->{httpsRedirect});
	$self->{proxyType}      = $config->get('apache', 'type');
	$self->{proxyType}      = 'ReverseProxy' if !defined($self->{proxyType});
	$self->{httpsInclude}   = $config->get('apache', 'httpsInclude');
	$self->{reverseProxies} = [];
	if (defined $config->get('apache', 'ReverseProxy')) {
		$self->addReverseProxy($config->get('apache', 'ReverseProxyPath'), $config->get('apache', 'ReverseProxy'));
	}
	my $no = 1;
	while (defined $config->get('apache', 'ReverseProxy.'.$no)) {
		$self->addReverseProxy($config->get('apache', 'ReverseProxyPath.'.$no), $config->get('apache', 'ReverseProxy.'.$no));
		$no++;
	}
	$self->{certType}      = $config->get('certificate', 'type');
	$self->{certType}      = 'renew' if !defined($self->{certType});
	$self->{certFiles}   = [];
	if (defined $config->get('certificate', 'certFiles')) {
		 push(@{$self->{certFiles}}, split(/[,\s]+/, $config->get('certificate', 'certFiles')));
	}
	$self->{postActions}   = [];
	if (defined $config->get('certificate', 'postActions')) {
		push(@{$self->{postActions}}, split(/[,\s]+/, $config->get('certificate', 'postActions')));
	} 
}

1;


