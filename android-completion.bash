#!/bin/bash

for n in "$@" ; do
  if [[ "$n" == "--bash-completion" ]] ;then
    script="$(basename "$0")"
    echo "function _${script}_command() {"
    cat <<"EOF"
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"

    COMPREPLY=( $(compgen -W "$(adb shell "ls -dp1 '${cur}'* 2>/dev/null")" -- ${cur}) )
}
EOF
    echo "complete -o nospace -F _${script}_command ${script}"
    exit 0
  fi
done
