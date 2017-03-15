#!/bin/bash

. testutil.bash

#-----------------------------------
flag=0
eval "$(getopt.pl '
a   flag=1 # comment
')"

assert "(( $flag == 0 ))"
assert "[[ '$*' == '' ]]"

#-----------------------------------
flag=0
eval "$(getopt.pl '
a   flag=1 # comment
' -a)"

assert "(( $flag == 1 ))"
assert "[[ '$*' == '' ]]"

#-----------------------------------
flag=0
long=0
eval "$(getopt.pl '
a        flag=1 # comment
b|long   long=1 # comment
' --long a  'b  c'  def)"

assert "(( $flag == 0 ))"
assert "(( $long == 1 ))"
assert "(( $# == 3 ))"
assert "[[ '$2' == 'b  c' ]]"
assert "[[ '$*' == 'a b  c def' ]]"

#-----------------------------------
flag=0
long=0

actual() {
  eval "$(getopt.pl '
  a        flag=1 # comment1
  b|long   long=1 # comment2
  c=s      long=1 # comment3
  long=s   long=1 # more flag
  d:       long=1 # even more flag
  ' -h)"
}

assert_out actual <<'EOF'

  actual:

  Usage:
    -a
                comment1
    -b --long
                comment2
    -c=s
                comment3
    --long=s
                more flag
    -d=s
                even more flag
    -h --help
                Show this help.
    --bash-completion
                Print bash completion script.
EOF
