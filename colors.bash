_do_color() {
  local color="$1"
  shift

  local nl_opt=""
  local force=0
  local continuation=0
  local opt
  local OPTIND
  local attributes=""
  local prefix="3"

  while getopts bihnfcGukx opt; do
    case "$opt" in
      n) nl_opt="-n" ;;
      f) force=1 ;;
      c) continuation=1 ;;
      b) attributes="${attributes}1;" ;;
      i) attributes="${attributes}3;" ;;
      u) attributes="${attributes}4;" ;;
      k) attributes="${attributes}5;" ;;
      x) attributes="${attributes}9;" ;;
      G) prefix="4" ;;
      h)
        echo "Options: -n [no newline] -f [force color] -c [don't reset color] -G [bg]  -b [bold/intense] -i [italic] -k [blink] -u [underline]" 1>&2
        ;;
      *)
        echo "Unknown flag $opt" 1>&2
        return
        ;;
    esac
  done
  shift $(($OPTIND - 1))

  if iscon || (( $force )) ; then
    if (( $color == -1 )) ; then
      echo -ne "\e[0m"
    else
      echo -ne "\e[${attributes}${prefix}${color}m"
    fi
  fi

  if (( $# == 0 )) ; then
    continuation=1 # implied
  else
    echo $nl_opt "$@"
  fi

  if (( ! $continuation )) ; then
    if iscon || (( $force )) ; then
      echo -ne '\e[0m'
    fi
  fi
}

nocolor() {
  _do_color -1 "$@"
}

black() {
  _do_color 0 "$@"
}

red() {
  _do_color 1 "$@"
}

green() {
  _do_color 2 "$@"
}

yellow() {
  _do_color 3 "$@"
}

blue() {
  _do_color 4 "$@"
}

magenta() {
  _do_color 5 "$@"
}

cyan() {
  _do_color 6 "$@"
}

white() {
  _do_color 7 "$@"
}

bred() {
  _do_color 1 -b "$@"
}

bgreen() {
  _do_color 2 -b "$@"
}

byellow() {
  _do_color 3 -b "$@"
}

bblue() {
  _do_color 4 -b "$@"
}

bmagenta() {
  _do_color 5 -b "$@"
}

bcyan() {
  _do_color 6 -b "$@"
}

bwhite() {
  _do_color 7 -b "$@"
}