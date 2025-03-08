#!/usr/bin/perl -w

use strict;
use FindBin;
use lib "$FindBin::Bin";
use MCommon;

my $MIN_TOKEN_LEN = 6;

my $last = "";

sub print_cand {
  my ($cand) = @_;
  $cand =~ s/^\s+//;
  $cand =~ s/\s+$//;
  if ($cand ne $last) {
    print $cand, "\n";
  }
}

sub show {
  my ($word) = @_;
  (length($word) < $MIN_TOKEN_LEN) and return;
  ($word =~ /[a-zA-Z0-9]/) or return;
  print_cand $word;

  # also show each word
  while ($word =~ /([a-zA-Z0-9_]+)/g) {
    if (length($1) >= $MIN_TOKEN_LEN) {
      print_cand $1;
    }
  }
}

sub tokenize {
  my ($line) = @_;

  for my $word (split /\s+/, $line) {
    show $word;
    $word =~ s![^$ENV{FILE_RE_CHARS}]! !go;
    for my $tok (split /\s+/, $word) {
      show $tok;
    }
  }
}

while (<>) {
  chomp;
  tokenize $_;
}

