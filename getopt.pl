#!/usr/bin/perl -w

# Bash option parser.

use strict;
use Getopt::Long qw(:config gnu_compat bundling require_order);
# use Data::Dumper;  # Little slow to load.

# Start.

sub usage() {
  print STDERR <<EOF;

  $0: getopts.bash helper

    -d --description       : Specify short command description.
    -u --usage FUNC        : Specify usage command name.
    -F --allow-files       : Build command completion that allows files.
    -N --no-allow-files    : Build command completion that doesn't allows files.
    -f -i --in-func        : Assume caller is a function.

EOF
  exit 1
}

# Parse options to this script itself.

my $command_desc = "";
my $complete_allow_files = 1;
my $no_complete_allow_files = 0;
my $in_func = 0;
my $usage_command = "";
my $debug = 0;
my $ignore = 0;

GetOptions(
  "F|allow-files+" => \$complete_allow_files,
  "N" => \$no_complete_allow_files,
  "f|l|in-func" => \$in_func,
  "d|description=s" => \$command_desc,
  "u|usage=s" => \$usage_command,
  "debug" => \$debug,
  "x" => \$ignore, # For backward compatibility.
  ) or usage;

$complete_allow_files = 0 if $no_complete_allow_files;

if ($debug) {
  my %opts = (
    command_desc => $command_desc,
    complete_allow_files => $complete_allow_files,
    in_func => $in_func,
    usage_command => $usage_command,
  );
  # print STDERR Dumper(\%opts) if $debug;
}

# See script '1' for example.
my $option_spec = $ARGV[0];
shift;

if (!$option_spec) {
  print STDERR "$0: Missing option spec.\n";
  usage;
}

# Helper functions.

print <<'EOF';
# Succeeds if called by a function.
_go_infunc() {
  caller 1 >/dev/null 2>&1
}

# Get the command name, used for usage and completion.
_go_command=""
if _go_infunc ; then
  _go_command="$FUNCNAME"
else
  _go_command="${0##*\/}"
fi

EOF

sub print_exit($) {
  my ($rc) = @_;
  print <<EOF
if _go_infunc ; then
  return $rc
else
  exit $rc
fi
EOF
}

sub shell_quote(@) {
  my $ret = "'";
  $ret .= $_[0] =~ s!'!'\\''!gr; #!
  $ret .= "'";
  return $ret;
}

# It's like die(), except it's meant be used in eval'ed bash script.
sub meta_die($) {
  my ($msg) = @_;
  chomp $msg;
  print "echo ", shell_quote($msg), " 1>&2\n";
  print_exit 1;
}

# Parse the option spec.

# Parsed option spec.
my @spec = ();

## Then, actually parse the option spec and build @spec.
for my $line (split(/\r*\n/, $option_spec)) {
  chomp $line;

  my $help = "";

  if ($line =~ s!\s*\#\s*(.*)!!) {
    $help = $1;
  }
  $line =~ s!^\s+!!;
  $line =~ s!\s+$!!;
  next if $line =~ m!^$!;
  my ($flag, $command) = split(/\s+/, $line, 2);

  meta_die "$0: Missing command for flag '$flag'\n" unless $command;

  $flag =~ s!\:$!=s!;

  push @spec, {flag => $flag, command => $command, help => $help};
}

## Always support "-h" and "--bash-completion".
my $HELP_OPTION_INDEX = @spec;
push @spec, {flag => "h|help", command => "",
    help => "Show this help."};

my $BASH_COMPLETION_OPTION_INDEX = @spec;
push @spec, {flag => "bash-completion", command => "",
    help => "Print bash completion script."};


# print STDERR Dumper(\@spec) if $debug;

# Parse the actual arguments.

## For backward compatibility, replace "-bash-completion" with
## "--bash-completion".

for my $arg (@ARGV) {
  $arg =~ s!^-bash-completion$!--bash-completion!;
}

my @set_flags = ();

## Build options spec.
my %parser_spec = ();
my $i = 0;
for my $spec (@spec) {
  my $flag = $spec->{flag};
  my $index = $i;
  $parser_spec{$flag} = sub {
    print STDERR "Found: $index, $flag\n" if $debug;
    $set_flags[$index] = $_[1];
  };
  $i++;
}
# print STDERR Dumper(\%parser_spec) if $debug;

print STDERR "Parsing [", join(" ", @ARGV), "] ...\n" if $debug;

my $parse_success = GetOptions(%parser_spec);

# print STDERR Dumper(\@set_flags) if $debug;

# Show help, if "-h" is given or failed to parse the arguments.
print "function getopt_usage() {\n";
if (!$usage_command) {
  print "echo\n";
  print "echo \"  \$_go_command: \"";
  print " ", shell_quote($command_desc), "\n";
  print "echo\n";
  print "echo '  Usage:'\n";
} else {
  print $usage_command, "\n";
}

for my $spec (@spec) {
  print "echo '    '";

  $spec->{flag} =~ m!^ ([^=]+) (?:(\=.*))? !x;
  my ($flags, $arg) = ($1, $2);
  my $sep = "";
  for my $f (split(m{\|}, $flags)) {
    print $sep;
    $sep = " ";
    if (length($f) == 1) {
      print "-", $f;
    } else {
      print "--", $f;
    }
  }
  print $arg if defined $arg;
  print "\n";
  print "echo -e '\\t\\t'";
  print shell_quote($spec->{help});
  print "\n";
}
print "}\n";

if (!$parse_success or $set_flags[$HELP_OPTION_INDEX]) {
  print "getopt_usage\n";
  print_exit 1;
  exit 0;
}

# Show bash completion script.
if ($set_flags[$BASH_COMPLETION_OPTION_INDEX]) {
  my @all_flags = ();
  for my $spec (@spec) {
    $spec->{flag} =~ m!^([^=]+)(?:\=(.*))?!;
    my ($flags, $arg) = ($1, $2);
    for my $f (split(/\|/, $flags)) {
      if (length($f) == 1) {
        push @all_flags, "-$f";
      } else {
        push @all_flags, "--$f";
      }
    }
  }
  my $allow_files_flag = $complete_allow_files ? "-F" : "";
  my $flags_flag = join(" ", @all_flags);

  print <<EOF;
bashcomp -c "\$_go_command" -f "$flags_flag" $allow_files_flag
EOF
  print_exit 0;
  exit 0;
}

for (my $i = 0; $i < @spec; $i++) {
  print STDERR $i, "\n" if $debug;
  next unless defined $set_flags[$i];

  my $command = $spec[$i]->{command};
  $command =~ s!%! shell_quote($set_flags[$i]) !ge;
  print $command, "\n";
}

print "set --";
for my $arg (@ARGV) {
  print " ";
  print shell_quote($arg);
}
print "\n";
