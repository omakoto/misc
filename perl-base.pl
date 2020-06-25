#!/usr/bin/perl

use utf8;
use strict;
use warnings;
use open qw(:std :utf8);
no feature qw(indirect);
use feature qw(signatures say state switch);
# state: https://perldoc.perl.org/perlsub.html#Persistent-Private-Variables
# switch: https://perldoc.perl.org/perlsyn.html#Switch-Statements
# signatures: https://perldoc.perl.org/perlsub.html#Signatures
no warnings qw(experimental::signatures);
