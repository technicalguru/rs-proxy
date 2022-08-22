package RsProxy::Config;

use strict;
use warnings;
use JSON;
use RsProxy::FileConfig;
use RsProxy::RenewalConfig;
use RsProxy::ProxyConfig;
#use RsProxy::WatchConfig;

my $ETC = '/etc/rs-proxy';

sub new {
	my $class = shift;
	my $self  = { @_ };
	$self->{timestamp} = 0;
	if (!$self->{log}) {
		$self->{log} = new RsLog();
	}
	if (!$self->{application}) {
		$self->{log}->error("Cannot detect application type");
		exit 1;
	}

	my $rc = bless $self, $class;
	$self->loadConfigFile();
	return $rc;
}

# Load the config
sub loadConfigFile {
	my $self = shift;

	if ($self->{application} eq 'renew') {
		$self->loadRenewConfig();
	} elsif ($self->{application} eq 'proxy') {
		$self->loadProxyConfig();
	} else {
		$self->{log}->error("Unknown application type: ".$self->{application});
		exit 1;
	}
	if (defined $self->{logFile}) {
		$self->{log}->info('Log can be found at: '.$self->{logFile});
		$self->{log}->{logfile} = $self->{logFile};
	}
}

# Has the common config changed?
sub hasChanged {
	my $self = shift;
	return $self->{config}->hasChanged();
}

# Reload the config if it has changed
sub reloadIfChanged {
	my $self = shift;
	if ($self->hasChanged()) {
		$self->{log}->info('Configuration changed');
		$self->reset();
		$self->loadConfigFile();
		return 1;
	}
	return 0;
}

# Reset the config
sub reset {
	my $self = shift;
	undef($self->{config});
	undef($self->{renewals});
	undef($self->{proxies});
}

# Load the Certbot Renewal configs
sub loadRenewConfig {
	my $self = shift;
	my $configFile = $self->getRootConfig('./renewCerts.ini', './renewCerts.conf', '/etc/renewCerts.ini', '/etc/renewCerts.conf', '/etc/rs-proxy/renewCerts.ini', '/etc/rs-proxy/renewCerts.conf');
	$self->{config} = new RsProxy::FileConfig(log => $self->{log}, configFile => $configFile);
	$self->{lastModificationTime} = $self->{config}->{lastModificationTime};
	$self->{renewals} = [];

	# The config itself is used: Translate each config now
	my @SECTIONS = $self->{config}->getSections();
	my $name;
	foreach $name (@SECTIONS) {
		next if $name eq 'common';
		next if $name eq 'apache';
		my $cert = new RsProxy::RenewalConfig('name' => $name);
		$cert->{lastModificationTime} = $self->{lastModificationTime};
		$cert->{enabled}              = $self->{config}->get($name, 'enabled');
		$cert->{enabled}              = 1 if !defined($cert->{enabled});
		$cert->{configFile}           = $self->{config}->get($name, 'configFile');
		$cert->{certType}             = $self->{config}->get($name, 'type');
		$cert->{certType}             = 'renew' if !defined($cert->{certType});
		$cert->{certDir}              = $self->{config}->get($name, 'certDir');
		$cert->{leSubDir}             = $self->{config}->get($name, 'leSubDir');
		$cert->{certFiles}            = [];
		if (defined $self->{config}->get($name, 'certFiles')) {
			 push(@{$cert->{certFiles}}, split(/[,\s]+/, $self->{config}->get($name, 'certFiles')));
		}
		$cert->{postActions} = [];
		if (defined $self->{config}->get($name, 'postActions')) {
			push(@{$cert->{postActions}}, split(/[,\s]+/, $self->{config}->get($name, 'postActions')));
		} 
		#$self->{log}->debug($cert->to_json());
		push(@{$self->{renewals}}, $cert);
	}
}

# Load the Proxy configuration configs
sub loadProxyConfig {
	my $self = shift;
	my $configFile = $self->getRootConfig('./proxy.conf', '/etc/proxy.conf', '/etc/rs-proxy/proxy.conf');
	$self->{config} = new RsProxy::FileConfig(log => $self->{log}, configFile => $configFile);
	$self->{lastModificationTime} = $self->{config}->{lastModificationTime};
	$self->{proxies} = [];

	# Load from conf.d directory
	if (opendir(DIRIN, "$ETC/conf.d")) {
		my @FILES = readdir(DIRIN);
		closedir(DIRIN);

		my $f;
		my $name;
		foreach $f (@FILES) {
			my $fp = "$ETC/conf.d/$f";
			next if $fp !~ /\.conf$/;
			next if !-f $fp;
			($f =~ /^(.*)\.conf$/) && ($name = $1);
			my $config = new RsProxy::FileConfig(log => $self->{log}, configFile => $fp);
			if (!$config->isEmpty()) {
				my $proxy  = new RsProxy::ProxyConfig(name => $name);
				$proxy->fromFile($config);
				push(@{$self->{proxies}}, $proxy);
			}
		}
	} else {
		die "Cannot read $ETC/conf.d\n";
	}
}

# Helper method
sub createReverseProxy {
	my $self   = shift;
	my $path   = shift;
	my $target = shift;

	my $rc = {};
	$rc->{target} = $target;
	$rc->{path}   = defined $path ? $path : '/';
	return $rc;
}

# Find the first file available from the list
sub getRootConfig {
	my $self = shift;

	# Given argument to object comes first
	my $file = defined $self->{configFile} ? $self->{configFile} : 'undef';
	while (scalar(@_) && (($file eq 'undef') || !-f $file)) {
		$file = shift;
	}

	if (($file eq 'undef') || !-f $file) {
		$self->{log}->error('Cannot find config file: '.$file);
		exit 1;
	} else {
		$self->{log}->debug('Config file found at: '.$file);
	}
	return $file;
}

sub writeCertificate {
	my $self   = shift;
	my $name   = shift;
	my $file   = shift;
	my $base64 = shift;

	my $data   = `echo $base64 | base64 -d -i `;
	if (open(FOUT, ">$file")) {
		print FOUT $data;
		close(FOUT);
		$self->{log}->info("[$name] $file created");
	} else {
		$self->{log}->error("[$name] Cannot write to $file");
	}

}

# Get the renewal configs
sub getRenewals {
	my $self = shift;
	return $self->{renewals};
}

# Get the proxy configs
sub getProxies {
	my $self = shift;
	return $self->{proxies};
}

sub get {
	my $self = shift;
	return $self->{config}->get(@_);
}

sub set {
	my $self = shift;
	my $key  = shift;
	my $val  = shift;
	$self->{config}->set($key, $val);
}

sub put {
	my $self = shift;
	my $key  = shift;
	my $val  = shift;
	$self->{config}->put($key, $val);
}

sub getSections {
	my $self = shift;
	return $self->{config}->getSections();
}

sub getActions {
	my $self   = shift;
	return $self->{config}->getActions();
}

sub getAction {
	my $self   = shift;
	my $action = shift;
	return $self->{config}->getAction($action);
}

sub getSectionConfig {
	my $self    = shift;
	my $section = shift;
	return $self->{config}->getSectionConfig($section);
}

1;


