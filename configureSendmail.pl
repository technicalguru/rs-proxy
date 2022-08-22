#!/usr/bin/perl
#

my $HOSTS = '/etc/hosts';

my @LINES = ();
if (open(FIN, "<$HOSTS")) {
	while (<FIN>) {
		chomp;
		my $line = $_;
		if ($line =~ /^(10\.[0-9]+\.[0-9]+\.[0-9]+)\s+([^\s]+)/) {
			$line = "$1 $2 $2.localdomain";
		}
		push(@LINES, $line);
	}
	close(FIN);
	if (open(FOUT, ">$HOSTS")) {
		print FOUT join("\n", @LINES)."\n";
		close(FOUT);
	} else {
		print "Cannot write $HOSTS\n";
		exit 1;
	}
} else {
	print "Cannot open $HOSTS\n";
	exit 1;
}

# Make sure sendmail is started
my $STARTED=`/etc/init.d/sendmail status`;
if ($STARTED !~ /sendmail: MTA: accepting connections/i) {
	system('/etc/init.d/sendmail start');
}

exit 0;

