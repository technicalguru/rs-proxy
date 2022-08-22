#!/usr/bin/perl
use File::Basename;
use Cwd qw(abs_path);
use lib dirname (abs_path(__FILE__));
use RsLog;
use RsProxy::Config;
use RsProxy::RenewalConfig;
use JSON;

############ CONSTANTS ################
my $ETC = '/etc/rs-proxy';
my $SVN = '/usr/bin/svn';
#######################################

# This script does the following:
#   - Write new certificates.conf 
#
# The /etc/rs-proxy/conf.d/*.conf files will be used to create:
#   - Apache include files in /etc/rs-proxy/apache.d
#     This will consider the [Apache] section and optionally:
#       * <basename>.include to be included in Port 80 and 443 sections, 
#       * <basename>.http.include to be included in Port 80 section only
#       * <basename>.https.include files to be included in Port 443 section only
#   - Certbot config files in /etc/rs-proxy/certs.d 
#   - a certificates.conf file in /etc/rs-proxy/certs.d
#
# If a new config file appears in /etc/rs-proxy/conf.d then the script will:
#   1. Create a very basic Port 80 config file in /etc/rs-proxy/apache.d
#   2. Wait for the Apache to reload
#   3. Create the certbot and certificates.conf file in /etc/rs-proxy/certs.d
#   4. Request the SSL certificate with renew.pl for the new file
#   5. Create the final Apache config file
#

# Create the log
my $LOG = new RsLog(TYPES => ['ERROR', 'INFO']);

# Ensure $ETC is available
# prepare_etc();

# SVN update to latest revision
# update_etc();

# Location of config file
my $CONFIG_FILE;

# Force the update
my $FORCE = 0;

# The list of ServerNames that match a config
my @SERVER_NAMES = ();

# The list of Config names to process
my @CONFIG_NAMES = ();

# Dry run only?
my $DRY_RUN = 0;

# process command line args
while (@ARGV) {
	my $arg = shift;
	if (($arg eq '-c') || ($arg eq '--config-file')) {
		$CONFIG_FILE = shift;
	} elsif (($arg eq '-f') || ($arg eq '--force')) {
		$FORCE = 1;
		$LOG->info('Forcing updates');
	} elsif (($arg eq '-d') || ($arg eq '--dry-run')) {
		$DRY_RUN = 1;
		$LOG->info('Dry run only');
	} elsif ($arg =~ /^-/) {
		$LOG->error('No such argument: '.$arg);
		$LOG->error('Usage: configure.pl [-c|--config-file <configfile>] [-f|--force] [-d|--dry-run] [ <configName>* ]');
		exit 1;
	} else {
		push (@CONFIG_NAMES, $arg);
	}
}

# the configuration file
my $CONFIG      = new RsProxy::Config(log => $LOG, application => 'proxy', configFile => $CONFIG_FILE);

# Process all updates
process_config(detect_updates());

# Check the Apache config and Certificate dirs for obsolete directories
warnObsoleteConfigs($CONFIG->get('apache.configDir'), 'Apache configuration');
warnObsoleteConfigs($CONFIG->get('certificates.certDir'), 'Certbot configuration');

# Save the run timestamp
save_run();

exit 0;

sub prepare_etc {
	if (!-f $ETC.'/proxy.conf') {
		if (-d $ETC.'/.svn') {
			$LOG->error("$ETC is under version control but misses proxy.conf file");
			exit 1;
		}

		my $url = $ENV{'RSPROXY_CONFIG_URL'};
		if (!$url) {
			$LOG->error("RSPROXY_CONFIG_URL is not set");
			exit 1;
		}

		my $cmd = "$SVN co $url $ETC";
		my $rc  = system($cmd);
		if ($rc) {
			$LOG->error("Cannot checkout from $url");
			exit 1;
		}
	}
}

# SVN update /etc/rs-proxy
sub update_etc {
	my $rc = system("cd $ETC; $SVN update ");
	if ($rc) {
		$LOG->error("Cannot update $ETC with svn");
		exit 1;
	}
}

# Detect updates and create config objects
sub detect_updates {
	my $rc = [];

	my $lastRun = 0;
	if (-f "/var/rs-proxy-configure.lastrun") {
		$lastRun = `cat /var/rs-proxy-configure.lastrun`;
	}

	my $proxy;
	foreach $proxy (@{$CONFIG->getProxies()}) {
		if ($proxy->isEnabled()) {

			my $update = 0;
			$update = 1 if $FORCE == 1;
			$update = 1 if $proxy->{lastModificationTime} > $lastRun;

			# Finally decide about inclusion of config file in scope
			my $name = $proxy->getName();
			if ((scalar(@CONFIG_NAMES) > 0) && !grep(/^$name$/i, @CONFIG_NAMES)) {
				$update = 0;
			} elsif (!$update) {
				$LOG->info('['.$proxy->getName().'] No changes');
			}
			if ($update) {
				push(@{$rc}, $proxy);
			}
			if ($proxy->getServerName()) {
				push(@SERVER_NAMES, $proxy->getServerName());
			}
		}
	}

	return $rc;
}

sub process_config {
	my $PROXIES = shift;
	my $proxy;

	my $cnt = 0;
	foreach $proxy (@{$PROXIES}) {
		$LOG->info('['.$proxy->getName().'] Updating...');
		if ($proxy->getServerName()) {
			generateApacheConfig($proxy);
		}
		if ($proxy->isCertEnabled()) {
			generateCertRenewalConfig($proxy);
		}
		$cnt++;
	}
	if ($cnt > 1) {
		$LOG->info($cnt.' proxy configurations updated');
	} elsif ($cnt == 1) {
		$LOG->info('1 proxy configuration updated');
	} else {
		$LOG->info('No changes detected');
	}
}

#################### APACHE ###########################
sub generateApacheConfig {
	my $proxy    = shift;
	my $mainName = $proxy->getServerName();
	my $apConfDir = $CONFIG->get('apache.configDir').'/'.$mainName;
	my $apCertDir = $CONFIG->get('certificates.certDir').'/'.$mainName;
	my $isNew    = !-e $apConfDir;

	if (!$DRY_RUN) {
		mkdirs($apConfDir);
		if (open(FOUT, '>'.$apConfDir.'/site.conf')) {
			write_http_config(FOUT, $proxy);
			write_https_config(FOUT, $proxy) if !$isNew && $proxy->isCertEnabled() && -e $apCertDir.'/cert.pem';
			close(FOUT);
		} else {
			$Log->error('['.$proxy->getName().'] Cannot write to '.$apConfDir.'/site.conf');
			exit 1;
		}
	}

	$LOG->info('['.$proxy->getName().'] Apache config created');
}

sub write_http_config {
	my $fh    = shift;
	my $proxy = shift;

	my $mainName = $proxy->getServerName();
	print $fh "<VirtualHost *:80>\n".
	          "   ServerName \"$mainName\"\n";

	my $alias;
	foreach $alias ($proxy->getServerAliases()) {
		print $fh "   ServerAlias \"$alias\"\n";
	}

	print $fh "\n   UseCanonicalName Off\n\n".
	          "   DocumentRoot /var/www/html\n\n".
	          "   Include /etc/apache2/proxy-conf/badbot.include\n\n".
	          "   RewriteEngine on\n".
	          "   RewriteCond \%{REQUEST_URI} !^/\\.well\\-known\n";
	my $redirectTarget = $mainName;
	if ($proxy->getHttpsRedirect() eq 'http_host') {
		$redirectTarget = '%{HTTP_HOST}';
	} elsif ($proxy->getHttpsRedirect() eq 'ServerName') {
		$redirectTarget = $mainName;
	} else {
		$redirectTarget = $proxy->getHttpsRedirect();
	}
	print $fh "   RewriteRule ^/(.*) https://$redirectTarget/\$1 [NC,R=301,L]\n\n".
	          "   ExpiresActive Off\n".
	          "</VirtualHost>\n\n";
}

sub write_https_config {
	my $fh        = shift;
	my $proxy     = shift;

	my $mainName  = $proxy->getServerName();
	my $certDir   = $CONFIG->get('certificates.certDir').'/'.$mainName;

	# Create Certificate Pinning
	my $hpkp      = `openssl rsa -pubout -in $certDir/privkey.pem -outform der 2>/dev/null | openssl dgst -sha256 -binary 2>/dev/null | base64`;
	chomp($hpkp);
	$SSLConfig =  "   SSLEngine on\n";
	if (-f "$certDir/fullchain.pem") {
		$SSLConfig .= "   SSLCertificateFile      $certDir/fullchain.pem\n";
	} else {
		$SSLConfig .= "   SSLCertificateFile      $certDir/cert.pem\n";
	}
	$SSLConfig .= "   SSLCertificateKeyFile   $certDir/privkey.pem\n".
	              "#   SSLCertificateChainFile $certDir/fullchain.pem\n".
	              "   Header always set Strict-Transport-Security \"max-age=7776000;\"\n".
	              "#   Header set Public-Key-Pins \"pin-sha256=\\'$hpkp\\'; max-age=7776000;\"\n";

	# Redirects to main section will receive extra virtual host sections
	my @ALIASES  = $proxy->getServerAliases();
	if (($proxy->getHttpsRedirect() eq 'ServerName') && scalar(@ALIASES)) {
		my $alias = shift(@ALIASES);
		print $fh "<VirtualHost *:443>\n".
				  "   ServerName \"$alias\"\n";
		foreach $alias (@ALIASES) {
			print $fh "   ServerAlias \"$alias\"\n";
		}
		print $fh "\n   UseCanonicalName Off\n\n".
                  "   DocumentRoot /var/www/html\n\n".
	              "   Include /etc/apache2/proxy-conf/badbot.include\n\n".
		          "   <LocationMatch \"^/(?!\.well-known)\">\n".
		          "      Redirect 301 / https://$mainName/\n".
		          "   </LocationMatch>\n\n".
		              $SSLConfig."\n".
		          "   ExpiresActive Off\n".
		          "</VirtualHost>\n\n";
	}

	# The main ServerName section
	print $fh "<VirtualHost *:443>\n".
	          "   ServerName \"$mainName\"\n";
	# Aliases if required
	my @ALIASES  = $proxy->getServerAliases();
	if (($proxy->getHttpsRedirect() ne 'ServerName') && scalar(@ALIASES)) {
		my $alias;
		foreach $alias (@ALIASES) {
			print $fh "   ServerAlias \"$alias\"\n";
		}
	}
	print $fh "\n   UseCanonicalName Off\n\n".
              "   DocumentRoot /var/www/html\n\n".
	          "   Include /etc/apache2/proxy-conf/badbot.include\n\n";

	if (defined $proxy->getHttpsInclude()) {
		print $fh "   ".$proxy->getHttpsInclude()."\n";
	}
 
	if ($proxy->getProxyType() eq 'ReverseProxy') {
		print $fh "   RequestHeader set X-Forwarded-Protocol https\n".
		          "   RequestHeader set X-Forwarded-Proto https\n".
		          "   RequestHeader set X-Forwarded-Port 443\n".
				  "   ProxyRequests           Off\n".
				  "   ProxyPreserveHost       On\n".
				  "   ProxyPass /.well-known  !\n";
		my @RPROXIES = $proxy->getReverseProxies();
		my $rproxy;
		foreach $rproxy (@RPROXIES) {
			my $target  = $rproxy->{target};
			my $path    = $rproxy->{path};
			print $fh "   ProxyPass               $path $target\n".
					  "   ProxyPassReverse        $path $target\n\n";
		}
	} elsif ($proxy->getProxyType() eq 'Redirect') {
		my $redirectTarget = $proxy->getHttpsRedirect();
	    print $fh "   RewriteEngine on\n".
	              "   RewriteCond \%{REQUEST_URI} !^/\\.well\\-known\n".
		          "   RewriteRule ^/(.*) https://$redirectTarget/\$1 [NC,R=301,L]\n\n";
	}


	print $fh "   ExpiresActive Off\n\n".
	          $SSLConfig.
	          "</VirtualHost>\n\n";
}

#################### CERTBOT ###########################
sub generateCertRenewalConfig {
	my $proxy    = shift;
	my $mainName = $proxy->getServerName();

	mkdirs($CONFIG->get('certificates.certDir').'/'.$mainName);

	generateCertbotConfig($proxy);
	generateRenewalConfig($proxy);
}

sub generateCertbotConfig {
	my $proxy = shift;

	if ($proxy->getCertType() eq 'renew') {
		if (!$DRY_RUN) {
			my $mainName = $proxy->getServerName();
			if (open(FOUT, ">".$CONFIG->get('certificates.certDir').'/'.$mainName.'/certbot.ini')) {
				print FOUT "rsa-key-size = 4096\n".
						   "authenticator = webroot\n".
						   "webroot-path = /var/www/html\n".
						   "server = https://acme-v02.api.letsencrypt.org/directory\n".
						   "renew-by-default = True\n".
						   "agree-tos\n".
						   "reuse-key\n".
						   "email = ".$CONFIG->get('certificates.sender')."\n".
						   "domains = $mainName";
				my $alias;
				foreach $alias ($proxy->getServerAliases()) {
					print FOUT ", $alias" if $alias !~ /^\*/;
				}
				print FOUT "\n";
				close(FOUT);
			} else {
				$LOG->error('['.$proxy->getName().'] Cannot write '.$CONFIG->get('certificates.certDir').'/'.$mainName.'/certbot.ini');
				exit 1;
			}
		}
		$LOG->info('['.$proxy->getName().'] CertBot configuration created');
	}
}

sub generateRenewalConfig {
	my $proxy    = shift;

	updateCertificatesFile($proxy);
}

sub updateCertificatesFile {
	my $proxy    = shift;
	my $name     = $proxy->getName();
	my $mainName = $name;
	   $mainName = $proxy->getServerName() if defined $proxy->getServerName();
	my $certDir    = $CONFIG->get('certificates.certDir').'/'.$mainName;

	my $certConfig = read_config($CONFIG->get('certificates.certDir').'/certificates.conf');
	undef($certConfig->{$name});

	# Create the renewal
	my $renewal = createRenewalConfig($proxy);
	if (defined($renewal)) {
		$certConfig->{$name} = $renewal;
	}

	# Overwrite common config
	$certConfig->{Common}->{letsencrypt} = $CONFIG->get('certificates.letsencrypt');
	$certConfig->{Common}->{openssl}     = $CONFIG->get('certificates.openssl');
	$certConfig->{Common}->{sendmail}    = $CONFIG->get('certificates.sendmail');
	$certConfig->{Common}->{sender}      = $CONFIG->get('certificates.sender');
	$certConfig->{Common}->{recipient}   = $CONFIG->get('certificates.recipient');
	$certConfig->{Common}->{enabled}     = 0;
	
	# Overwrite action configs
	my $actions = $CONFIG->getActions();
	my $action;
	foreach $action (keys(%{$actions})) {
		my @ARR = $CONFIG->getAction($action);
		$certConfig->{'action:'.$action}->{__OTHERS__} = \@ARR;
	}
	if (!$DRY_RUN) {
		write_config($certConfig, $CONFIG->get('certificates.certDir').'/certificates.conf', ['^Common$'], ['^action:']);
	}
	$LOG->info('['.$name.'] Renewal configuration created');
}

sub createRenewalConfig {
	my $proxy    = shift;
	my $name     = $proxy->getName();
	my $mainName = $name;
	   $mainName = $proxy->getServerName() if defined $proxy->getServerName();
	my $certDir    = $CONFIG->get('certificates.certDir').'/'.$mainName;

	my $rc = new RsProxy::RenewalConfig(name => $name, enabled => 1);
	if ($proxy->getCertType() eq 'renew') {
		$rc->{configFile} = $certDir."/certbot.ini";
		$rc->{leSubDir}   = $mainName;
		$rc->{certDir}    = $certDir;
		$rc->{certType}   = 'renew';
		if (scalar($proxy->getPostActions())) {
			$rc->{postActions} = join(',', $proxy->getPostActions());
		}
	} elsif ($proxy->getCertType() eq 'check-only') {
		if (scalar($proxy->getCertFiles())) {
			$rc->{certFiles}  = join(',', $proxy->getCertFiles());
		} else {
			$rc->{certDir}    = $certDir;
		}
		$rc->{certType}       = 'check-only';
	} else {
		return undef;
	}
	return $rc;
}

sub warnObsoleteConfigs {
	my $dir  = shift;
	my $type = shift;

	if (opendir(DIRIN, $dir)) {
		my $count = 0;
		my @ITEMS = readdir(DIRIN);
		closedir(DIRIN);
		my $item;
		foreach $item (@ITEMS) {
			next if $item eq '.';
			next if $item eq '..';
			if (-d "$dir/$item") {
				if (!grep(/^$item$/i, @SERVER_NAMES)) {
					$LOG->warn($type.' '.$item.' is unknown. Remove it with "-r '.$item.'" option.');
					$count++;
				}
			}
		}
		if ($count == 0) {
			$LOG->info('No unknown '.$type.' found');
		}
	}
}

################### HELPER routines ##########################
sub read_config {
	my $file = shift;
	my $rc   = {};

	if (open(FIN, "<$file")) {
		my $section = 'NONE';
		while (<FIN>) {
			chomp;
			my $line = $_;
			next if $line =~ /^\s*#/;
			next if $line =~ /^\s*$/;

			if ($line =~ /^\s*\[([^\]]+)\]\s*$/) {
				$section = $1;
			} elsif ($line =~ /^\s*([^=]+)\s*=\s*(.*?)\s*$/) {
				$rc->{$section}->{$1} = $2;
			} else {
				push(@{$rc->{$section}->{__OTHERS__}}, $line);
			}
		}
		close(FIN);
	}

	return $rc;
}

sub write_config {
	my $config   = shift;
	my $file     = shift;
	my $first    = shift;
	my $last     = shift;

	if (open(FOUT, ">$file")) {
		my $section;

		my @SEQUENCE = sort_sections($first, $last, keys(%{$config}));

		# Now write them
		foreach $section (@SEQUENCE) {
			print FOUT "[$section]\n";
			my $key;
			foreach $key (keys(%{$config->{$section}})) {
				if ($key eq '__OTHERS__') {
					print FOUT join("\n", @{$config->{$section}->{$key}})."\n";
				} else {
					print FOUT "$key=".$config->{$section}->{$key}."\n";
				}
			}
			print FOUT "\n";
		}
		close(FOUT);
	} else {
		$LOG->error("Cannot write $file");
		exit 1;
	}
}

sub sort_sections {
	my $first    = shift;
	my $last     = shift;
	my @sections = @_;

	my @F = ();
	my @L = ();
	my @O = ();

	my $section;
	foreach $section (@sections) {
		if (section_matches($section, $first)) {
			push(@F, $section);
		} elsif (section_matches($section, $last)) {
			push(@L, $section);
		} else {
			push(@O, $section);
		}
	}

	my @RC = @F;
	push(@RC, sort(@O), @L);
	return (@RC);
}

sub section_matches {
	my $name = shift;
	my @rules = @{(shift)};
	my $rule;

	foreach $rule (@rules) {
		if ($name =~ /$rule/) {
			return 1;
		}
	}
	return 0;
}

sub save_run {
	if (open(FOUT, ">/var/rs-proxy-configure.lastrun")) {
		print FOUT time;
		close(FOUT);
	} else {
		$LOG->error("Cannot write to /var/rs-proxy-configure.lastrun");
	}
}

sub mkdirs {
	my $dir   = shift;
	my @PARTS = split(/\//, $dir);
	my $path  = '';
	my $p;
	foreach $p (@PARTS) {
		next if $p eq '';
		$path .= '/'.$p;

		if (!-e $path) {
			mkdir($path);
		} elsif (!-d $path) {
			$LOG->error("$path is not a directory");
			exit 1;
		}
	}
}

