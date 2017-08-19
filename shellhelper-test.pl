#!/usr/bin/perl -w

use strict;
use FindBin; use lib "$FindBin::Bin";

use MCommon;
use Getopt;
use ShellHelper;

my $command = ShellHelper::parse( q(a b cdef#@ "aav'") );

print($command->rebuild(), "\n");
