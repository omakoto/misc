_do_color() {
  local color="$1"
  shift

  local args=()
  local arg
  local parsing_opts=1
  for arg in "$@"; do
    if (( parsing_opts )); then
      if [[ "$arg" == "--" ]]; then
        parsing_opts=0
      elif [[ "$arg" == "--help" ]]; then
        arg="-h"
      elif [[ "$arg" != -* ]]; then
        parsing_opts=0
      fi
    fi
    args+=("$arg")
  done
  set -- "${args[@]}"

  local nl_opt=""
  local force=0
  local continuation=0
  local opt
  local OPTIND
  local attributes=""
  local prefix="3"
  local out=${COLOR_OUT:-1}
  local esc_opt=0

  while getopts bihnfcGukx2e opt; do
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
      e) esc_opt=1 ;;
      h)
        cat <<'EOF' 1>&2
Options:
  -n  no newline
  -f  force color
  -c  don't reset color
  -G  bg
  -b  bold/intense
  -i  italic
  -k  blink
  -u  underline
  -x  crossed-out
  -2  redirect to stderr
  -e  reusable escape sequence
EOF
        ;;
      *)
        echo "Unknown flag $opt" 1>&2
        return
        ;;
    esac
  done
  shift $(($OPTIND - 1))

  local use_color=0
  if [[ -t $out ]] || (( $force )) || (( $FORCE_COLOR )) || (( $esc_opt )) ; then
    use_color=1
  fi

  {
    local color_seq=""
    local reset=""
    if (( $use_color )) ; then
      if [[ $color == "" ]] ; then
        color_seq=$'\e[0m'
      else
        color_seq=$'\e['"${attributes}${prefix}${color}m"
        if (( ! $continuation )) ; then
          reset=$'\e[0m'
        fi
      fi
    fi

    if (( $use_color )) ; then
      printf '%s' "$color_seq"
    fi
    if (( $# == 0 )) ; then
      if (( ! $esc_opt )) ; then
        return 0 # no argument, just start a color and finish.
      fi
    else
      echo $nl_opt "$@""$reset"
    fi

    if (( $esc_opt )) ; then
      # Print the raw escape sequence too
      local str=""
      if (( $# == 0 )) ; then
        str="$color_seq"
      else
        str="${color_seq}${*}${reset}"
      fi
      # Escape str for $'...' format
      str="${str//\\/\\\\}"
      str="${str//\'/\\\'}"
      str="${str//$'\e'/\\e}"
      str="${str//$'\n'/\\n}"
      str="${str//$'\r'/\\r}"
      str="${str//$'\t'/\\t}"
      
      if [[ $nl_opt == "-n" ]] ; then
        printf '%s' "\$'$str'"
      else
        printf '%s\n' "\$'$str'"
      fi
    fi
  } >& $out
}

nocolor() {
  _do_color "" "$@"
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

gray() {
  _do_color "8;5;8" "$@"
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

function DEBUG() {
  gray "$*"
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
    if [[ -n "$1" ]] ; then
        byellow -n " $1"
    fi
    if shift ; then
      local msg="$*"
      if [[ -n "$msg" ]] ; then
          echo -n " $msg"
      fi
    fi
    echo
}

export -f _do_color nocolor black red green yellow blue magenta cyan white gray bred bgreen byellow bblue bmagenta bcyan bwhite DEBUG INFO ERROR WARN
