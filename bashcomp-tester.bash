# Source this file on bash.

# Installs an empty "comptest" command with a debug completion.

function comptest() {
  : # Empty command
}

function __comptest_comp() {
# COMP_CWORD
# COMP_KEY
# COMP_LINE
# COMP_POINT
# COMP_TYPE
# COMP_WORDBREAKS
# COMP_WORDS

  cat-alt <(
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
  )
}

complete -F __comptest_comp comptest
