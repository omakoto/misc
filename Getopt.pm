use strict;
use Getopt::Long qw(:config gnu_compat bundling require_order);
# use Data::Dumper;

# use constant DEBUG => 0;

our $COMMAND_DESCRIPTION = "";

sub getopt {
  my (@spec) = @_;
  my $show_bash_completion = 0;
  my $help = 0;
  my $opts = {};

  if (@spec > 0 and $spec[0] =~ /^HASH/) {
    $opts = $spec[0];
    shift @spec;
  }
  # print STDERR Dumper($opts) if DEBUG;
  # print STDERR Dumper(\@spec) if DEBUG;

  my $take_files = !($opts->{nofiles} // 0);
  my $description = $opts->{description} // "";
  my $usage = $opts->{usage};

  # Make sure there's no unknown options.
  {
    for my $k (qw(nofiles description usage)) {
      delete $opts->{$k};
    }
    if (%$opts) {
      die "Invalid option(s) in: " . Dumper($opts);
    }
  }

  push @spec, ["h|help",
      \$help,
      "Show this help."];
  push @spec, ["bash-completion",
      \$show_bash_completion,
      "Print bash completion script."];

  # For backward compatibility.
  for my $arg (@ARGV) {
    $arg =~ s!^-bash-completion$!--bash-completion!;
  }

  my $show_usage = sub {
    my $command = $0 =~ s!^.*/!!r; #!
    print "\n";

    if ($usage) {
      &$usage;
    } else {
      print "  $command: $description\n\n";
      print "  Usage: $command [options]",
          ($take_files ? " FILES..." : ""), "\n\n";
    }
    for my $spec (@spec) {
      my $allow_no = $spec->[0] =~ m/\!$/;
      print "    ";
      $spec->[0] =~ m!^ ([^\=\!\+\:]+) (.*) !x;
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
      print $arg;
      print "\n\t\t";
      print $spec->[2], "\n";
    }
  };

  # Build arguments to
  my %parser_spec = ();
  for my $o (@spec) {
    $parser_spec{$o->[0]} = $o->[1];
  }

  # print STDERR Dumper(\%parser_spec) if DEBUG;

  if (!GetOptions(%parser_spec)) {
    &$show_usage;
    exit 1;
  }
  if ($help) {
    &$show_usage;
    exit 0;
  }
  if ($show_bash_completion) {
    # TODO If a flag ends with "!", add "--no-"
    my @flags = map {s!([\=\!\+\:].*)!!r} map {split /\|/, $_->[0]} @spec;
    system("bashcomp", "--command", ($0 =~ s!^.*/!!r), #!
        ($take_files ? ("--allow-files") : ()),
        "--flags", join(" ",
            map {
              if (/^../) { ## Long option?
                "--$_";
              } else {
                "-$_";
              }
            } @flags));
    exit 0;
  }
}

1;
