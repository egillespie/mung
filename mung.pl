#!/usr/bin/perl

# USAGE : mung.pl [-r] -e environment [ -f config_file ] file1 directory1 file2 . . .
#
# For the command line parsing.  Here's the parameter info:
#  -e environment          Name of environment to configure.  Must exist in configuration file.
#                          Required.  No default value.
#  -f config_filename      Path to an alternate XML file to use for configuration information.
#                          Optional.  Default value = "mung.xml".
#  -r                      Enable recursive search through any directories passed.

use strict;
use strict 'vars';
use vars qw($VERSION);
use Getopt::Std;
use XML::Checker::Parser;
use XML::Simple;
use Data::Dumper;

# Global variables
$VERSION = "1.0";

our($opt_e, $opt_f, $opt_r);

my $xmlFile = "mung.xml";
my $targetEnv = "";
my $recurse = 0;

my $ldelim = "\{";
my $rdelim = "\}";
my $config;

#
# Here's where the good stuff begins
#

&parse_cmdline();
&dtd_validate($xmlFile);

$config = parse_xmlfile($xmlFile);

# Extract the delimiters
if (exists $config->{"ldelim"}) {
	$ldelim = escape_chars($config->{"ldelim"});
}
if (exists $config->{"rdelim"}) {
	$rdelim = escape_chars($config->{"rdelim"});
}

$config = flatten_config($config, $targetEnv, $ldelim, $rdelim);
&config_config($config, $ldelim, $rdelim);

# Now configure all of the remaining command line arguments
my $filedir;
foreach $filedir (@ARGV) {
	&config_filedir($filedir, $recurse, $config, $ldelim, $rdelim);
}

exit 0;

#
# All of the wonderful subroutines are implented below
#

sub escape_chars {
# Puts a \ in front of all special characters

	my $str = shift;
	$str =~ s/([\{\}\[\]\(\)\^\$\.\|\*\+\?\\])/\\$1/g;
	return $str;
}

sub get_usage {
# Prints how to use this program.  That's it, were you expecting more?

	my $str = "usage: mung.pl [-r] -e env [ -f config_file ] file1 directory2 ...\n";
	return $str;
}

sub HELP_MESSAGE {
# Getopt::Std calls this subroutine to display the help message.
	die get_usage();
}

sub VERSION_MESSAGE {
# Getopt::Std calls this subroutine to display the version info
	die "mung.pl version $VERSION by Erik Gillespie <erik.gillespie\@gmail.com>\n";
}

sub parse_cmdline {
# Sets up variables based on command line options

	&getopts('e:f:r');

	if ($opt_e) {
		$targetEnv = $opt_e;
	}
	else {
		print "Missing or incomplete option : -e\n";
		die get_usage();
	}

	if ($opt_f) {
		$xmlFile = $opt_f;
	}

	if ($opt_r) {
		$recurse = 1;
	}
}

sub dtd_validate {
# Validates the XML file against the DTD specified
# Exits if the XML doesn't match the DTD

	my $file = shift;
	die "Error : $file does not exist!\n" if (! -e $file);

	my $xp = new XML::Checker::Parser( Handlers => { } );

	eval {
		local $XML::Checker::FAIL = \&invalid_xml;
		$xp->parsefile($file);
	};

	die "Error : $file failed during DTD validation.\n" if $@;
}

sub invalid_xml {
# Called when the XML file isn't valid (doesn't fit the DTD)
# Only print messages when error code is less than 300.  Anything
# 300 or higher is informational only and not an error.

	my $code = shift;

	if ($code < 300) {
		XML::Checker::print_error($code, @_);
		die XML::Checker::error_string($code, @_);
	}
}

sub parse_xmlfile {
# Parses the XML file and returns the array structure that
# contains the parsed configuration data

	my $file = shift;
	my $xs = new XML::Simple();
	my $cfg;

	# Ahh, so easy to parse XML
	$cfg = $xs->XMLin($file, ForceArray => 1);

	# Verify that the target environment exists
	my $validEnv = 0;
	my $curEnv = $targetEnv;

	while (exists $cfg->{"env"}->{"$curEnv"}) {
		if (exists $cfg->{"env"}->{"$curEnv"}->{"inherit"}) {
			$curEnv = $cfg->{"env"}->{"$curEnv"}->{"inherit"};
		}
		else {
			$validEnv = 1;
			last;
		}
	}

	die "Error : Environment '$curEnv' is not defined in $file!\n" unless ($validEnv);

	return $cfg;
}

sub flatten_config {
# Takes the multidimensional hashref "tree" and flattens
# it into a single-dimension associative array

	my ($cfg, $orEnv, $ld, $rd) = @_;
	my %flatcfg = ();
	my $key;

	# Get all global configuration values
	foreach $key (keys %{$cfg->{"global"}}) {
		$flatcfg{"$key"} = $cfg->{"global"}->{"$key"}->{"value"};
	}

	#  Get all of the overrides
	&override_config(\%flatcfg, $cfg, $orEnv, $ld, $rd);

	return \%flatcfg;
}

sub override_config {
# Recursive function that replaces global tags in the
# passed configuration hashref with the environment's
# own version of the tag.  If the environment is
# derived from another environment then this function
# is called recursively on the environment's parent
# until no parent environment is available.

	my ($orCfg, $cfg, $orEnv, $ld, $rd) = @_;

	# Check for a parent environment and recurse if one exists
	if (exists $cfg->{"env"}->{"$orEnv"}->{"inherit"}) {
		&override_config($orCfg, $cfg, $cfg->{"env"}->{"$orEnv"}->{"inherit"}, $ld, $rd);
	}

	# Override the current environment's configuration
	for my $key (keys %{$cfg->{"env"}->{"$orEnv"}->{"var"}}) {
		$orCfg->{"$key"} = $cfg->{"env"}->{"$orEnv"}->{"var"}->{"$key"}->{"value"};
	}
}

sub config_config {
# Configure the config structure.  Goes through the 
# array and replaces all found keys with their respective
# values.  The array is looped through repeatedly, until
# no replacements are made.

	my ($cfg, $ld, $rd) = @_;
	my ($key, $repKey);
	my $changes = -1;

	# Keep making passes at the array until we don't make any changes
	while ($changes != 0) {
		$changes = 0;

		# Loop through each element in the array
		for $key (keys %{$cfg}) {
			# Search for a replaceable tag
			while ($cfg->{"$key"} =~ /$ld([^$rd]*)$rd/go) {
				$repKey = $1;
				# See if the tag exists
				if (exists $cfg->{"$repKey"}) {
					# It does, so replace the tag with it's appropriate value
					$cfg->{"$key"} =~ s/$ld$repKey$rd/$cfg->{"$repKey"}/g;
					$changes++;
				}
			}
		}
	}
}

sub config_filedir {
# Takes five arguments:
# 1) the path to a file or directory, 
# 2) whether or not to recurse if the first parameter is a directory,
# 3) Reference to configuration information,
# 4) left delimiter, and
# 5) right delimiter.
# If arg1 is a file, the filename is passed on
# to be configured.  If arg2 is a directory then all files in the
# directory are configured.  If the recurse parameter is set to true
# then all subdirectories of the directory are also configured

	my ($filedir, $r, $cfg, $ld, $rd) = @_;

	if (-f $filedir) {
		unless ((-r $filedir) && (-w $filedir)) {
			print "File $filedir does not have read/write access. Skipping...\n";
			return;
		}

		unless (-T $filedir) {
			print "File $filedir looks like a binary file. Skipping...\n";
			return;
		}

		&config_file($filedir, $cfg, $ld, $rd);
	}
	elsif (-d $filedir) {
		# Configure all files (and directories if recursing) in directory if perms are set
		unless ((-r $filedir) && (-w $filedir) && (-x $filedir)) {
			print "Directory $filedir does not have read/write/execute access. Skipping...\n";
			return;
		}

		unless (opendir(FD, $filedir)) {
			print "Unable to enter directory $filedir. Skipping...\n";
			return;
		}

		my @filelist = grep { /^[^.]/ } readdir(FD);
		closedir(FD);

		my $fd;
		foreach $fd (@filelist) {
			&config_filedir("$filedir/$fd", $r, $cfg, $ld, $rd);
		}
	}
	else {
		print "File $filedir does not appear to be a file or directory. Skipping...\n";
	}
}

sub config_file {
# Replaces all config tags in a file with their corresponding
# values as specified in the config file.  The file is modified
# in place using a temporary file with the same path and filename
# but with the added extension ".mung"

	my ($file, $cfg, $ld, $rd) = @_;
	my $newFile = "$file.mung";
	print "Configuring file $file\n";

	# Open the existing file for read access
	if (!open(FIN, "< $file")) {
		print "Unable to open file $file. Skipping...\n";
		return;
	}

	# Create/open the work file for write access
	if (!open(FOUT, "+> $newFile")) {
		print "Unable to create work file $newFile. Skipping...\n";
		close(FIN);
		return;
	}

	# Lock it so no one can access our work file while we're writing to it
	if (!flock(FOUT, 2)) {
		print "Unable to lock work file $newFile. Skipping...\n";
		close(FIN);
		close(FOUT);
		return;
	}

	# Read file and replace tags one line at a time
	my ($curline, $repKey);

	while ($curline = <FIN>) {
		# Search for a replaceable tag
		while ($curline =~ /$ld([^$rd]*)$rd/go) {
			$repKey = $1;

			# If the tag exists replace the tag with it's corresponding value
			if (exists $cfg->{"$repKey"}) {
				$curline =~ s/$ld$repKey$rd/$cfg->{"$repKey"}/g;
			}
		}
		
		# Write line to work file
		print FOUT $curline;
	}

	# Close the files
	close(FIN);
	close(FOUT);

	# Replace original file with new file
	unlink($file);
	rename($newFile, $file);
}
