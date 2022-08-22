#!/usr/bin/perl
# Find modules regardless how the script was called
use File::Basename;
use Net::SMTP;
#use Net::SMTPS;
#use Net::SMTP::SSL;
use Cwd qw(abs_path);
use lib dirname (abs_path(__FILE__));
use RsLog;
use RsProxy::Config;

# CONSTANTS
my $CHECKEXPIRY_BIN    = dirname(abs_path(__FILE__)).'/checkCertExpiry.sh';
my $CONFIGSENDMAIL_BIN = dirname(abs_path(__FILE__)).'/configureSendmail.pl';

my $smtpserver = 'smtp.ralph-schuster.eu';
my $smtpport = 465;
my $smtpuser   = 'business@ralph-schuster.eu';
my $smtppassword = 'AmE5ad5.e5l';

# Create the log
my $LOG = new RsLog(TYPES => ['ERROR', 'INFO', 'WARN', 'DEBUG']);

# Process options
my $STAGING = '';
my $FORCE   = 0;
my $DRYRUN  = 0;
my $CONFIG_FILE;

while (@ARGV[0] =~ /^-/) {
	my $option = shift;
	if ($option eq '-s') {
		$STAGING = '--staging ';
	} elsif (($option eq '-d') || ($option eq '--dry-run')) {
		# Dry run
		$DRYRUN = 1;
		$LOG->info('Dry run only');
	} elsif ($option eq '-f') {
		# Force renewal
		$FORCE = 1;
		$LOG->info('Force mode activated');
	} elsif ($option eq '-c') {
		# Find the config file
		$CONFIG_FILE = shift;
	}
}

# Load the config
my $CONFIG = new RsProxy::Config(log => $LOG, application => 'renew', configFile => $CONFIG_FILE);

##############
# All other options are section names
my @DOMAIN_KEYS = @ARGV;

my $renewal;
foreach $renewal (@{$CONFIG->getRenewals()}) {
	$name = $renewal->getName();

	# Proceed when we have no domain keys or current name in this list
	next if (scalar(@DOMAIN_KEYS) > 0) && !grep(/^$name$/, @DOMAIN_KEYS);
	next if $name eq 'certificates';
	
	if ($renewal->isEnabled()) {

		# Check if certificate requires renewal
		my $rc = 0;
		if (!$FORCE) {
			if (!scalar($renewal->getCertFiles())) {
				$rc = willCertExpire($renewal->getCertDir().'/cert.pem', 30);
			} else {
				$cmd = 0;
				my $file;
				foreach $file ($renewal->getCertFiles()) {
					$rc |= willCertExpire($file, 30);
				}
			}
		} else {
			# Force renewal / pretend it expires
			$rc = 1;
		}
		if ($rc) {
			# sendmail needs a fix
			system($CONFIGSENDMAIL_BIN.' >/dev/null');

			if ($renewal->getCertType() eq 'check-only') {
				# Warn about expiry
				if (!scalar($renewal->getCertFiles())) {
					my $enddate = getEndDate($renewal->getCertDir().'/cert.pem');
					$LOG->info("[$name] - Certificate will expire on $enddate");
					$cmd = '(echo "Subject: ['.$name.'] Certificate will expire '.$enddate.'"; echo ""; echo "Certificate will expire soon") | '.$CONFIG->get('certificates.sendmail').' -f '.$CONFIG->get('certificates.sender').' '.$CONFIG->get('certificates.recipient');
				} else {
					$cmd = '(echo "Subject: ['.$name.'] Certificates will expire"; echo "";';
					my $file;
					foreach $file ($renewal->getCertFiles()) {
						if (-f $file) {
							my $enddate = getEndDate($file);
							$LOG->info("[$name] - $file will expire on $enddate");
							$cmd .= ' echo "'.$file.' will expire on '.$enddate.'"; ';
						} else {
							$LOG->info("[$name] - $file not found");
							$cmd .= ' echo "'.$file.' not found"; ';
						}
					}
					$cmd .= ') | '.$CONFIG->get('certificates.sendmail').' -f '.$CONFIG->get('certificates.sender').' '.$CONFIG->('certificates.recipient');
				}
				$rc = system($cmd);
				if ($rc) {
					$LOG->error("[$name] - Cannot send email");
				} else {
					$LOG->info("[$name] - Email sent");
				}
			} else {
				if ($DRYRUN) {
					$LOG->info("[$name] - Renewing and deploying certificate...");
				} else {
					$cmd = $CONFIG->get('certificates.letsencrypt').' certonly '.$STAGING.' --config '.$renewal->getConfigFile().' --non-interactive';
					$rc = system($cmd);
					if (!$rc) {
						$rc = deployCurrentCertificate($renewal);
						if ($rc) {
							$LOG->error("[$name] - Cannot deploy certificates");
							$cmd = '(echo "Subject: ['.$name.'] Cannot deploy certificate"; echo ""; echo "Cannot deploy certificate") | '.$CONFIG->get('certificates.sendmail').' -f '.$CONFIG->get('certificates.sender').' '.$CONFIG->get('certificates.recipient');
							system($cmd);
						} else {
							$LOG->info("[$name] - Deployed");
							executeActions($renewal->getPostActions(), $name);
						}
					} else {
						$LOG->error("[$name] - Cannot renew certificates");
						$LOG->error("[$name] - $cmd");
						$cmd = '(echo "Subject: ['.$name.'] Cannot renew certificate"; echo ""; echo "Cannot renew certificate") | '.$CONFIG->get('certificates.sendmail').' -f '.$CONFIG->get('certificates.sender').' '.$CONFIG->get('certificates.recipient');
						system($cmd);
					}
				}
			} 
		} else {
			# No expiry detected / No force
			if (!scalar($renewal->getCertFiles())) {
				my $enddate = getEndDate($renewal->getCertDir().'/cert.pem');
				$LOG->info("[$name] - Certificate does not expire within 30 days / $enddate");
			} else {
				my $file;
				foreach $file ($renewal->getCertFiles()) {
					my $enddate = getEndDate($file);
					$LOG->info("[$name] - $file does not expire within 30 days / $enddate");
				}
			}
		}
	} else {
		$LOG->info("[$name] Disabled... ");
	}
}


exit 0;

sub getEndDate {
	my $certFile = shift;
	my $cmd = $CONFIG->get('certificates.openssl').' x509 -enddate -noout -in '.$certFile;
	my $enddate = 'unknown';
	if (open(FIN, "$cmd|")) {
		while (<FIN>) {
			chomp;
			($_ =~ /notAfter=(.*)/) && ($enddate = $1);
		}
		close(FIN);
	}
	return $enddate;
}

sub executeActions {
	my @ACTIONS = @{shift};
	my $name    = shift;
	 
	my $action;
	foreach $action (@ACTIONS) {
		next if !$action;

		my @cmds = $CONFIG->getAction($action);
		my $cmd;
		foreach $cmd (@cmds) {
			next if !$cmd;
			my $rc = system($cmd);
			if ($rc) {
				$LOG->error("[$name] - Cannot execute $action: $cmd");
			}
		}
		$LOG->info("[$name] - $action Done");
	}
}

sub sendmail {
	#my $smtp = Net::SMTPS->new($smtpserver, Port => $smtpport,  doSSL => 'starttls', SSL_version=>'TLSv1', Debug => 1);
	my $smtp = Net::SMTP->new('smtp.ralph-schuster.eu', Port=>25, Timeout => 10, Debug => 1, SSL => 0);
	die "Could not connect to server! $!\n" unless $smtp;

	
	$smtp->starttls();
	$smtp->auth($smtpuser, $smtppassword);
	$smtp->mail('letsencrypt@ralph-schuster.eu');
	$smtp->to('privat@ralph-schuster.eu');
	$smtp->data();
	$smtp->datasend("To: privat\@ralph-schuster.eu\n");
	$smtp->datasend("Subject: Testmail from container\n\n");
	$smtp->datasend("Some content\n");
    $smtp->dataend();
	$smtp->quit;
}

sub willCertExpire {
	my $file = shift;
	my $days = shift || 30;

	return 1 if (!-f $file);
	my $cmd = $CHECKEXPIRY_BIN.' '.$days.' "'.$file.'" >/dev/null';
	return system($cmd);
}

sub deployCurrentCertificate {
	my $renewal = shift;

	my $leDir   = '/etc/letsencrypt/live/'.$renewal->getLESubDir();

	# We need to check whether the cert.pem is a current one (shall not expire)
	my $expires = willCertExpire($leDir.'/cert.pem', 30);
	if ($expires) {
		# Check the alternative directories that LE creates
		my $no = 1;
		while ($expires) {
			my $sno = $no;
			$sno = '0'.$sno while (length($sno) < 4);
			last if !-d "$leDir-$sno";
			$expires = willCertExpire($leDir.'-'.$sno.'/cert.pem', 30);
			if (!$expires) {
				$leDir = $leDir.'-'.$sno;
				last;
			}
			$no++;
		}
	}
	if (!$expires) {
		my $cmd = 'cp '.$leDir.'/* '.$renewal->getCertDir().'/';
		return system($cmd);
	}
	return 1;
}
