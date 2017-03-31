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
long2=""
eval "$(getopt.pl '
a        flag=1 # comment
b|long   long=1 # comment
long2:   long2=% # aa bb c
' --long --long2 'x y  z' a 'b  c'  def)"

assert "(( $flag == 0 ))"
assert "(( $long == 1 ))"
assert "[[ '$long2' == 'x y  z' ]]"
assert "(( $# == 3 ))"
assert "[[ '$2' == 'b  c' ]]"
assert "[[ '$*' == 'a b  c def' ]]"

#-----------------------------------
actual() {
  eval "$(getopt.pl '
  a        flag=1 # comment1
  b|long   long=1 # comment2
  c=s      long=1 # comment3
  long2=s   long=1 # more flag
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
    --long2=s
                more flag
    -d=s
                even more flag
    -h --help
                Show this help.
    --bash-completion
                Print bash completion script.
EOF

#-----------------------------------
usage() {
  echo aaa
}

actual() {
  eval "$(getopt.pl -u usage '
  a        flag=1 # comment1
  ' --help)"
}

assert_out actual <<'EOF'
aaa

    -a
                comment1
    -h --help
                Show this help.
    --bash-completion
                Print bash completion script.
EOF

#-----------------------------------
actual() {
  eval "$(getopt.pl -d 'this is the command   description.' '
  a        flag=1 # comment1
  ' -h)"
}

assert_out actual <<'EOF'

  actual:  this is the command   description.

  Usage:
    -a
                comment1
    -h --help
                Show this help.
    --bash-completion
                Print bash completion script.
EOF

#-----------------------------------
# Not calling from a function changes the command name
# to the actual script file name.
help="$(eval "$(getopt.pl '
a        flag=1 # comment1
' -h)")"

assert_out echo "$help" <<'EOF'
  getopt.pl_test.bash:

  Usage:
    -a
                comment1
    -h --help
                Show this help.
    --bash-completion
                Print bash completion script.
EOF

#-----------------------------------
actual() {
  eval "$(getopt.pl '
  a        flag=1 # comment1
  b|long   long=1 # comment2
  c=s      long=1 # comment3
  long2=s   long=1 # more flag
  d:       long=1 # even more flag
  ' --bash-completion)"
}

assert_out actual <<'EOF'
# Bash autocomplete script for the actual command.
# Source it with the following command:
# . <(actual --bash-completion)
_actual_complete() {
  local cur="${COMP_WORDS[COMP_CWORD]}"

  COMPREPLY=()

  local flags="-a -b --long -c --long2 -d -h --help "

  local cand=""
  case "$cur" in
    "")
      # Uncomment it to make empty completion show help.
      # actual -h >/dev/tty
      # return 0
      ;;
    -*)
      cand="$flags"
      ;;
  esac
  if [ "x$cand" = "x" ] ; then
    if (( 1 )) ; then
      COMPREPLY=(
          $(compgen -f -- ${cur})
          )
    else
      COMPREPLY=(
          $(compgen -W "$flags" -- ${cur})
          )
    fi
  else
    COMPREPLY=($(compgen -W "$cand" -- ${cur}))
  fi
}

complete -o filenames -o bashdefault -F _actual_complete actual
EOF

#-----------------------------------
# hmm, can't intercept the error message...
actual() {
  local x
  eval "$(getopt.pl '
  i=i x=%
  ' -i x)"
}

assert_out actual <<'EOF'

  actual:

  Usage:
    -i=i

    -h --help
                Show this help.
    --bash-completion
                Print bash completion script.

EOF

done_testing
