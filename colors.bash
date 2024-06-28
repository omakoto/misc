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
  local out=${COLOR_OUT:-1}

  while getopts bihnfcGukx2 opt; do
    case "$opt" in
      n) nl_opt="-n" ;;
      f) force=1 ;;
      c) continuation=1 ;;
      b) attributes="${attributes}1;" ;; # bold
      i) attributes="${attributes}3;" ;; # italic
      u) attributes="${attributes}4;" ;; # underline
      k) attributes="${attributes}5;" ;; # blink - slow
      x) attributes="${attributes}9;" ;; # crossed-out
      G) prefix="4" ;;
      2) out=2 ;;
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

  local use_color=0
  if [[ -t $out ]] || (( $force )) || (( $FORCE_COLOR )) ; then
    use_color=1
  fi

  {
    if (( $use_color )) ; then
      if (( $color == -1 )) ; then
        echo -ne "\e[0m"
      else
        echo -ne "\e[${attributes}${prefix}${color}m"
      fi
    fi

    if (( $# == 0 )) ; then
      return 0 # no argument, just start a color and finish.
    else
      echo $nl_opt "$@"
    fi

    if (( ! $continuation && $use_color )) ; then
      echo -ne '\e[0m'
    fi
  } >& $out
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

function INFO() {
    byellow -n "$1"
    shift
    if [[ -n "$1" ]] ; then
        bcyan -n " $1"
    fi
    if shift ; then
      local msg="$*"
      if [[ -n "$msg" ]] ; then
          echo -n " $msg"
      fi
    fi
    echo
}

function ERROR() {
    echo -n "${0##*/}:"
    bred -n " [error] "
    bred -n "$1"
    if shift ; then
      local msg="$*"
      if [[ -n "$msg" ]] ; then
          echo -n " $msg"
      fi
    fi
    echo
}

function WARN() {
    echo -n "${0##*/}:"
    byellow -n " [warning] "
    byellow -n "$1"
    shift
    if [[ -n "$2" ]] ; then
        shift
        byellow -n " $2"
    fi
    local msg="$*"
    if [[ -n "$msg" ]] ; then
        echo -n " $msg"
    fi
    echo
}
