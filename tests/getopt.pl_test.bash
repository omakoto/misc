#!/bin/bash

. testutil.bash

flag1=0
eval "$(getopt.pl -xu usage '
a   flag1=1 # comment
' "$@")"

assert '(( $flag1 == 0 ))'
assert '(( $# == 0 ))'

