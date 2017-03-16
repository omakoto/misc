#!/usr/bin/perl -w

use strict;

# Read filenames from STDIN, and show them only
# when their 1st line does *not* contain the word "rgm".

while (defined(my $f = <>)) {
  chomp $f;
  open(my $in, $f) or next;

  # Get the 2nd line.
  my $line = <$in>;
  defined($line) and $line = <$in>;
  close $in;

  if (defined($line) and $line =~ /^rgm\: start$/) {
    next;
  }
  print $f, "\n"
}
