# Source this file on bash.

# Installs an empty "comptest" command with a debug completion.

function comptest() {
  shescape "$@"
}

function __comptest_comp() {
  {
    for n in \
        COMP_CWORD \
        COMP_KEY \
        COMP_LINE \
        COMP_POINT \
        COMP_TYPE \
        COMP_WORDBREAKS \
        COMP_WORDS \
        ; do
      declare -p "$n"
    done
  } >/tmp/compin.txt
  IFS=$'\n' COMPREPLY=($(cat /etc/compreply.txt 2>/dev/null))
}

complete -F __comptest_comp comptest
