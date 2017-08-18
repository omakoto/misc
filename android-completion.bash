#!/bin/bash

for n in "$@" ; do
  if [[ "$n" == "--bash-completion" ]] ;then
    script="$(basename "$0")"
    echo "function _${script}_command() {"
    cat <<"EOF"
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"

    COMPREPLY=( $(compgen -W "$(adb shell ls -d -p "${cur}*" 2>&1)" -- ${cur}) )
}
EOF
    echo "complete -o nospace -F _${script}_command ${script}"
    exit 0
  fi
done
