#!/usr/bin/perl -w

use strict;
use FindBin;
use lib "$FindBin::Bin";
use MCommon;
use IsFile;

$| = 1;

my $text_only = $ENV{TEXT_ONLY};

sub tokenize {
  my ($line) = @_;

  $line =~ s![^$ENV{FILE_RE_CHARS}]! !go;
  for my $tok (split /\s+/, $line) {
    if (isfile($tok)) {
      my $text = -T $tok;
      if ($text_only && !$text) {
        next;
      }

      print $tok, "\n";
    }
  }
}

while (<>) {
  chomp;
  if (/^Running\: (.*)/) {
    # Special case for command lines from "ee".
    print "$1\n";
    tokenize $1;
  } else {
    tokenize $_;
  }
}
