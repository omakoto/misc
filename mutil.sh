#-*- mode:shell-script -*-

# shopt -s failglob # breaks completion

# fails if called by non-bash

_interactive=0
if [[ "$-" == *i* ]] ; then
  _interactive=1
fi

_is_wsl=0
if uname -a | grep -q microsoft ; then
  _is_wsl=1
fi

#. <( ~/cbin/zenlog -s )
. ~/cbin/misc/colors.bash
. ~/cbin/getopts.bash # Legacy one

interactive() {
  (( $_interactive ))
}

iswsl() {
  (( $_is_wsl ))
}

if ! interactive && (( $# == 1 )) ; then
  if [[ "$1" == "--l" ]] ; then
    less "$0"
    exit 0
  fi
  if [[ "$1" == "--1" ]] ; then
    1 "$0"
    exit 0
  fi
fi


function prologue() {
    SCRIPT="${0##*/}"
    SCRIPT_DIR="${0%/*}"

    local OPTIND
    local OPTARG
    while getopts "d" opt; do
      case "$opt" in
        d) cd "$SCRIPT_DIR" ;;
      esac
    done
    shift $(($OPTIND - 1))
}

die() {
  {
    echo -n "${0##*/}: "
    bred "$*"
  } 1>&2
  exit 1
}

dief() {
  {
    echo -n "${FUNCNAME[1]}: "
    bred "$*"
  } 1>&2
  return 0
}

iscon() {
  [[ -t ${1:-1} || $FORCE_CON = 1 ]]
}

fixcon() {
  local fd=${1:-1}
  if iscon $fd ; then
    export FORCE_CON=1
    export C${fd}=1
  else
    unset FORCE_CON
    unset C${fd}
  fi
}

fixcon2() {
  fixcon 2
}

firstdir() {
  local d
  for d in "${@}" ; do
    if [[ -d "$d" ]] ; then
      echo "$d"
      return 0
    fi
  done
  return 0
}

firstbin() {
  local f
  for f in "${@}" ; do
    if [[ -x "$f" ]] ; then
      echo "$f"
      return 0
    fi
  done
  return 0
}

haspath() {
  case ":$PATH:" in
  *:${1}:*) return 0;;
  esac
  return 1
}

hasmanpath() {
  case ":$MANPATH:" in
  *:${1}:*) return 0;;
  esac
  return 1
}

addpath() {
  local d
  for d in "$@" ; do
    if [[ -d "$d" ]] && ! haspath "$d" ; then
      export PATH="$PATH:$d"
    fi
  done
}

prependpath() {
  local d
  local idx
  for (( idx = $# ; idx >= 1 ; idx-- )) ; do
      d="${!idx}"
      if [[ -d "$d" ]] && ! haspath "$d" ; then
        export PATH="$d:$PATH"
      fi
  done
}

addmanpath() {
  local d
  for d in "$@" ; do
    if [[ -d "$d" ]] && ! hasmanpath "$d" ; then
      export MANPATH="$MANPATH:$d"
    fi
  done
}

con() {
#  LD_LIBRARY_PATH=${LD_LIBRARY_PATH}${LD_LIBRARY_PATH:+:}$HOME/cbin/so/32:$HOME/cbin/so/64 \
#      LD_PRELOAD=fake_isatty.so \
      "$@"
}

c1() {
  C1=1 con "$@"
}

likely-command() {
  (( $# == 0 )) && return 1

  type -t "$1" >/dev/null
  return $?
}

log() {
  if (( $# == 0)) && [[ -t 0 ]] ; then
    zenlog_open_last_log
    return $?
  fi
  {
    if (( $# > 0 )) ; then
      "$@" 2>&1
    else
      cat
    fi
  } | {
    log="${TEMP:-/tmp}"/log-$(date8)-$(tr ' /|' '_-_' <<<"$*").log
    _log_print_filename() {
      {
        byellow -n "Log filename: "
        bcyan "$log"
      } 1>&2
    }

    trap _log_print_filename EXIT SIGHUP

    _log_print_filename

    tee $log
  }
  return ${PIPESTATUS[0]}
}

timestamp() {
  {
    if (( $# > 0 )) ; then
      "$@"
    else
      cat
    fi
  } 2>&1 | {
    perl -e '
      use Time::HiRes qw(time);
      use POSIX qw(strftime);

      $| = 1;

      my $start = time;
      my $last = $start;
      while (defined(my $l = <>)) {
        my $t = time;
        print(strftime("%Y/%m/%d %H:%M:%S", localtime ($t)),
            sprintf(".%03d %8.3f %6.3f",
                ($t-int($t))*1000, $t - $start, $t - $last),
            $p, "  ", $l);

        $last = $t;
      }
      '
  }
  return ${PIPESTATUS[0]}
}

logt() {
  log timestamp "${@}"
}

dry-run() {
  return 0
}

echo-and-exec() {
  local to=1
  local dry=0
  local dry_opts=""
  local notify_opts=""
  local bg_opts=""
  local with_time=1
  local raw_marker=""
  local marker="Running"
  local pwd=0
  local tty=0
  local quiet=0
  local child_quiet=0
  local show_result=0
  eval "$(bashgetopt -d 'Echo and execute' '
      2|stderr         to=2               # Show message on stderr instead of stdout.
      tty tty=1                           # Show message directly to TTY instead of stdout.
      f|notify-failure notify_opts=nf     # Notify when command fails.
      s                notify_opts=""     # Don'\''t notify (default).
      b|bg             bg_opts="bg-start" # Start in the background.
      d|dry-run        dry=1              # Dry run.
      v|notify         notify_opts="nf -v" # Verbose: Notify the result.
      t|timestamp      with_time=1        # Display timestamp too.
      n|no-timestamp   with_time=0        # Don'\''t display timestamp.
      m: marker=%                         # Set marker.
      r: raw_marker=%                     # Set raw-marker.
      pwd pwd=1                           # Show current directory too.
      q|quiet          quiet=1;child_quiet=1  # Don'\''t echo back command line.
      Q|child-quiet    child_quiet=1      # Silence inner ee executions.
      R|show-result    show_result=1      # Show result code
      ' "$@")"

  if (( $DRYRUN )) || (( $DRY )) || (( $EE_DRY )) ; then
    dry=1
    dry_opts=dry-run
  fi
  if (( $EE_QUIET )) ; then
    quiet=1
    child_quiet=1
  fi
  if (( $tty )); then
    # Open the tty and assign FD 3.
    to=3
    exec 3>/dev/tty
  fi
  if ! (( $quiet )) ; then
    {
      if (( $pwd )) ; then
        byellow -nc
        echo -n "CWD: "
        bcyan -nc
        pwd | sed -e 's!\n$!!'
        nocolor -n ""
      fi
      byellow -nc
      (( $dry )) && echo -n "(DRY) "
      if [[ -n "$raw_marker" ]] ; then
        echo -n "${raw_marker}"
      elif (( $with_time )) ; then
        echo -n "${marker} [$(date +%Y/%m/%d-%H:%M:%S)]: "
      else
        echo -n "${marker}: "
      fi
      bcyan -nc
      shescapen "$@"
      nocolor ""
    } 1>&$to
  fi
  local rc=0
  EE_QUIET="${EE_QUIET:-$child_quiet}" $dry_opts $bg_opts $notify_opts "${@}"
  rc=$?

  if (( $show_result )) ; then
    {
      byellow -n "Status: "
      if (( $rc == 0 )) ; then
        bcyan -nc
      else
        bred -nc
      fi
      echo -n "$rc"
      white "" # reset the color
    } 1>&$to
  fi
  return $rc
}

ee() {
  echo-and-exec "${@}"
}

eet() {
  echo-and-exec -t "${@}"
}

# Variation; used to intercept a command execution and show
# what command is being executed where.
function showcommand() {
  ee --tty --pwd "$@"
}

wb() {
  ee adb wait-for-device

  echo -n "Waiting for device to boot up."

  while ! adb shell getprop sys.boot_completed | grep -q '^1' ; do
    echo -n "."
    if adb logcat -b main -d -s 'Zygote:E' | grep -q 'Exit zygote' ; then
      echo ""
      notify -f "!!! Detected reboot loop !!!"
      logcat -d | android-grep-restart
      return 1
    fi
    sleep 0.5
  done

  echo "Booted."

  if (( $# > 0 )) ; then
    ee "${@}"
  fi
}

android-wait-for-boot-complete() {
  wb "${@}"
}

nox() {
  DISPLAY="" "$@"
}

nf() {
  if (( $# == 0 )) ; then
    cat <<EOF 1>&2

  Usage: nf COMMAND [options...]

    Execute the command, and show an error dialog when it fails.

EOF
    return 1
  fi

  local verbose=0
  eval "$(getopt.pl '
    v verbose=1 # Verbose mode.
  ' "$@")"

  local rc
  "${@}"
  rc=$?
  if (( $rc != 0 )) ; then
    notify -cf "Command failed: $*"
  elif (( $verbose )) ; then
    notify -f "Command successfully finished: $*"
  fi
  return $rc
}

forever() {
  local stop_on_failure=0
  local stop_on_success=0

  local interval=1

  eval "$(getopt.pl '
  f|stop-on-failure stop_on_failure=1 # Stop when the command fails.
  s|stop-on-success stop_on_success=1 # Stop when the command succeeds.
  i|interval=i      interval=%        # Interval between execution, in seconds.
  ' "$@")"

  i=1

  if [ "$*" == "" ] ; then
    echo "Command missing" 1>& 2
    exit 1
  fi

  while true; do
    date8
    {
      bcyan -n "forever ($i)..."
      nocolor ""
    } 1>&2
    ee -s "$@"
    rc=$?
    {
      byellow "[exited with $rc at attempt #$i]" 1>&2
    } 1>&2
    if (( $stop_on_success )) && (( $rc == 0 )) ; then
      notify "Successfully finished:" "${@}"
      return 0
    fi
    if (( $stop_on_failure )) && (( $rc != 0 )) ; then
      notify "Command failed:" "${@}"
      return 0
    fi
    i=$(( i + 1 ))
    sleep $interval
  done
}

retry-until-success() {
  forever -s "${@}"
}

retry-until-failure() {
  forever -f "${@}"
}

bg-start() {
  ( nohup "$@" </dev/null >&/dev/null & )
}

function zenlog-nolog-out() {
  echo "$(zenlog outer-tty 2>/dev/null || tty)"
}

# Note this version is a bit slow. See also prompt.bash.
title() {
  echo -n $'\e]0;'"${*}"$'\007' | zenlog write-to-outer
}

bash-enable-debug() {
  if (( "${1:-1}" )) ; then
    set -x
  else
    set +x
  fi
}

bash-disable-debug() {
  bash-enable-debug 0
}

find-root-dir() {
  local dir="$1"
  local predicate="$2"

  [[ -z "$predicate" ]] && dief "Missing arguments." && return 1

  while [[ "$dir" != "/" ]] ; do
    if $predicate "$dir" ; then
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

# function fzf() {
#   local rc
#   # hmm.. ugly.
#   if command fzf "$@"; then
#     rc=0
#   else
#     rc=$?
#   fi
#   return $?
# }

function generate-core() {
  # to generate core
  ulimit -c $(( 1 * 1024 * 1024  * 1024 ))
}

function called-by-func() {
  if caller 2 >/dev/null 2>&1 ; then
    return 0
  else
    return 1
  fi
}

function pipestatus() {
  return ${PIPESTATUS[${1:-0}]}
}

function withalt() {
  if (( $META_EXEC )); then
    return 0
  else
    return 1
  fi
}

function rust_backtrace {
  RUST_BACKTRACE=1 "$@"
}

function ll() {
  ls -l "$@"
}

function la() {
  ls -la "$@"
}

function ls() {
  command ls -F --color=auto "$@"
}


function less() {
  unset LESS
#      --quit-if-one-screen \
#      --no-init \
# -S to disable line-wrapping
  command less \
      --ignore-case \
      --line-numbers \
      "$@"
}

function qgit() {
  qgit >/dev/null 2>&1 &
}

function install-bashcomp() {
  for c in "$@"; do
    . <("$c" --bash-completion)
  done
}

function .e() {
  local f="$1"
  if [[ -f "$f" ]] ; then
    . "$f"
  fi
}

function wd() {
  dir="/tmp/work-$(date8)${1+-}$1"

  mkdir -p "$dir" && cd "$dir"

  echo "$dir"
  if ! [[ -t 1 ]] ; then # If it was eaten, then print on stderr too.
    echo "$dir" 1>&2
  fi
}

function atop() {
    echo ${ANDROID_X_BUILD_TOP:-${ANDROID_BUILD_TOP:?ANDROID_BUILD_TOP not set}}/
}

function aroot() {
  local top=$(atop)
  [[ -d "$top" ]] || return 1
  cd "$top" || return 1
}

curdir() {
    if [[ "$PWD" != "" ]]; then
        echo "$PWD"
        return 0
    fi
    pwd
}

export _prompt_pid
function set-prompt-pid() {
  export _prompt_pid=$$
}

source-setup() {
  local dir="$PWD"

  while [[ "$dir" != "/" ]] ; do
    local script="$(readlink -f "$dir")/.auto-dir-setup"
    if [[ -f "$script" ]] ; then
      if [[ "$last_auto_sourced_script" != "$script" ]]; then
        INFO "Automatically running:" "$script"
        last_auto_sourced_script="$script"
        EE_QUIET=1 . "$script"
      fi
      return 0
    fi
    dir="$(readlink -f "$dir/..")"
  done
  return 0
}

function _schedule_cd_file() {
  echo "/tmp/schedule-cd-${_prompt_pid:?}.txt"
}

# Use this command to 'cd' to a directory, *when the next prompt shows up*.
# See also cd-to-scheduled-dir
function schedule-cd() {
  local dir="$(abspath "$1")"
  local file=$(_schedule_cd_file)
  if [[ -d "$dir" ]] ; then
    echo "$dir" > $file
    INFO "Scheduled to CD to:" "$dir"
    return 0
  else
    echo "schedule-to: Directory '$dir' doesn't exist." 1>&2
    return 1
  fi
}

# This is executed from PROMPT_COMMAND
function cd-to-scheduled-dir() {
  # Change to the directory set by schedule-cd()
  local file=$(_schedule_cd_file)
  if [[ -f $file ]] ; then
    local next_dir=$(cat $file 2>/dev/null)
    rm -f $file
    if [[ -d "$next_dir" ]] ; then
      if cd "$next_dir" ; then
        INFO "Current directory:" "$PWD"
        source-setup
      fi
    fi
  fi
}

# Wrap a multi-line shell command and remove all the tokens "//" and the following tokens.
function remove-comments-helper() {
  local args=()
  local skip=0
  for arg in "$@"; do
    if [[ "$arg" = "//" ]] ; then
      skip=1
      continue
    fi
    if ! (( $skip )) ; then
      args+=("$arg")
    fi
    skip=0
  done
  "${args[@]}"
}
