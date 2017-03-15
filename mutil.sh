#-*- mode:shell-script -*-

# shopt -s failglob # breaks completion

# fails if called by non-bash

_interactive=0
if [[ "$-" == *i* ]] ; then
  _interactive=1
fi

. <( ~/cbin/zenlog -s )
. colors.bash
. getopts.bash # Legacy one

interactive() {
  (( $_interactive ))
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

die() {
  echo "$0: $*" 1>&2
  exit 1
}

dief() {
  echo "${FUNCNAME[1]}: $*" 1>&2
  return 0
}

iscon() {
  if [[ -t 1 ]] || (( $FORCE_CON )); then
    return 0
  fi
  return 1
}

fixcon() {
  local fd=${1:-1}
  if [[ -t $fd || "$FORCE_CON" = 1 ]] ; then
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

addpath() {
  if [[ -d "$1" ]] && ! haspath "$1" ; then
    export PATH="$PATH:$1"
  fi
}

prependpath() {
  if [[ -d "$1" ]] && ! haspath "$1" ; then
    export PATH="$1:$PATH"
  fi
}

con() {
  LD_LIBRARY_PATH=${LD_LIBRARY_PATH}${LD_LIBRARY_PATH:+:}$HOME/cbin/so/32:$HOME/cbin/so/64 \
      LD_PRELOAD=fake_isatty.so \
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

echo-and-exec() {
  local to=1
  local notify=0
  local dry=0
  local notify_opts=""
  local with_time=0
  local marker="Running"
  eval "$(getopt.pl -d 'Echo and execute' '
      2 to=2         # Show message on stderr instead of stdout.
      f notify=1     # Notify when command fails.
      s notify=0     # Don'\''t notify (default).
      d dry=1        # Dry run.
      v notify=1 ; notify_opts="-v" # Verbose: Notify the result.
      t with_time=1; # Display timestamp too.
      m: marker=%    # Set marker.
      ' "$@")"

  if (( $DRYRUN )) || (( $DRY )) ; then
    dry=1
  fi
  {
    byellow -nc
    (( $dry )) && echo -n "(DRY) "
    if (( $with_time )) ; then
      echo -n "${marker} $(date8): "
    else
      echo -n "${marker}: "
    fi
    bcyan -nc
    shescapen "$@"
    nocolor ""
  } 1>&$to
  if (( $dry )) ; then
    return 0
  fi
  if (( $notify )) ; then
    nf $notify_opts "${@}"
  else
    "$@"
  fi
}

ee() {
  echo-and-exec "${@}"
}

eet() {
  echo-and-exec -t "${@}"
}

wb() {
  ee adb wait-for-device

  echo -n "Waiting for device to boot up."

  while ! adb shell getprop sys.boot_completed | grep -q '^1' ; do
    echo -n "."
    if adb logcat -b main -d -s 'Zygote:E' | grep -q 'Exit zygote' ; then
      echo ""
      notify -c "!!! Detected reboot loop !!!"
      return 1
    fi
    sleep 3
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
  local stop_on_failure=$(( ${opts[f]} + 0 ))
  local stop_on_success=$(( ${opts[s]} + 0 ))

  eval "$(getopt.pl '
  f|stop-on-failure stop_on_failure=1 # Stop when the command fails.
  s|stop-on-success stop_on_success=1 # Stop when the command succeeds.
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
      byellow "[exited with $rc]" 1>&2
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
    sleep 1
  done
}

retry-until-sucess() {
  forever -s "${@}"
}

retry-until-failure() {
  forever -f "${@}"
}

function zenlog-nolog-out() {
  echo "$(zenlog_outer_tty 2>/dev/null || tty)"
}

title() {
  echo -ne "\033]0;${*}\007" > $(zenlog-nolog-out)
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

function fzf() {
  zenlog_pause
  local rc
  # hmm.. ugly.
  if command fzf "$@"; then
    rc=0
  else
    rc=$?
  fi
  zenlog_resume
  return $?
}

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

adb() {
  ~/cbin/adb "$@"
}

function rb {
  RUST_BACKTRACE=1 "$@"
}

function set-now() {
  touch /tmp/$$.now
}

function has-changed() {
  if [[ "$1" -nt "/tmp/$$.now" ]] ; then
    return 0
  fi
  return 1
}

function adb-install-if-changed() {
  if has-changed "$1" || (( $FORCE_INSTALL )) ; then
    android-install "$1"
  else
    {
      red "Not installing '$1' because it hasn't changed."
      byellow "Use FORCE_INSTALL=1 to force install. (Or rerun the command with FI)"
    } 1>&2
  fi
}

function android-install-if-changed() {
  adb-install-if-changed "$@"
}

function FI() {
  FORCE_INSTALL=1 "$@"
}

# Use with "bind -x", like:
# bind -x '"\e1": "insert_bash_command_line zenlog-last-n-contents -n 1 -o"'
# (This opens the last zenlog with the '1' command.)
function insert_bash_command_line() {
  local line="$($*)"

  # Add a space at the end unless there's one already.
  line="$(sed -e 's!  *$! !' <<< "$line")"
  READLINE_LINE="${READLINE_LINE:0:$READLINE_POINT}${line}${READLINE_LINE:$READLINE_POINT}"
  READLINE_POINT=$(( $READLINE_POINT + ${#line} ))
}

if interactive && isbash ; then
  complete -F _command log
  complete -F _command logt
  complete -F _command timestamp
  complete -F _command echo-and-exec
  complete -F _command ee
  complete -F _command eet
  complete -F _command Test:
  complete -F _command Running:
  complete -F _command wb
  complete -F _command android-wait-for-boot-complete
  complete -F _command nox
  complete -F _command nf
  complete -F _command wat
  complete -F _command retry-until-sucess
  complete -F _command retry-until-failure
  complete -F _command forever
  complete -F _command 1script
  complete -F _command FI
fi