# rc-reload.bash - Detects changes to files loaded by *rc and reloads them.
# Notifies other bash instances (that are idle / not running subprocesses) to
# press Enter to reload.
# Run rc-reload_test.bash to test.
_reloaded_time=$ramtmp_path/$$-reload.tmp
_reload_needed=$ramtmp_path/reload-needed.tmp

trap 'rm -f "$_reloaded_time"' EXIT

_use_signal_to_reload=0

_main_rc_files="
$HOME/cbin/makotorc
$HOME/cbin/common_rc
$HOME/cbin/interactive-setup.bash
$HOME/cbin/interactivefuncs.bash
$HOME/cbin/prompt.bash
$HOME/cbin/dot_bash_profile
$HOME/cbin/abin/android-commands.bash
$BASH_SOURCE
"

# Called from every prompt; must not fork. [[ -nt ]] is a bash builtin,
# unlike stat.
rc_files_changed() {
    local f
    for f in $_main_rc_files ; do
        [[ "$f" -nt "$_reloaded_time" ]] && return 0
    done
    return 1
}

reload_rc() {
    bgreen "Reloading .bashrc..."
    time source ~/.bashrc
    >"$_reloaded_time"
    bgreen "Reloaded .bashrc."
}

_reload_needed() {
    if [[ "$_reloaded_time" -ot "$_reload_needed" ]] ; then
        return 0
    fi
    return 1
}

reload_rc_if_changed() {
    if _reload_needed ; then
        reload_rc
    fi
}

# Returns true (0) if the given bash PID has no running child processes.
# Uses /proc/<pid>/task/<pid>/children when available (Linux, no fork needed),
# falling back to pgrep -P otherwise.
_bash_is_idle() {
    local pid=$1
    local children=""
    if [[ -f "/proc/$pid/task/$pid/children" ]]; then
        read -r children < "/proc/$pid/task/$pid/children" 2>/dev/null
    else
        children=$(pgrep -P "$pid" 2>/dev/null)
    fi
    [[ -z "$children" ]]
}

rc() {
    if (( ! $_use_signal_to_reload )) ; then
        # Non-signal version.
        >"$_reload_needed"
        reload_rc

        # For each bash...
        for pid in $(pgrep -f -U $(id -u) -- '(^-bash$|^bash -l$|/bash -l$)') ; do
            if [[ $pid == $$ ]] ; then
                continue
            fi
            # Only notify bash instances that:
            #   1. have stdout connected to a terminal, and
            #   2. are idle (not running any subprocesses).
            (test -t 0 < /proc/$pid/fd/1) &&
                _bash_is_idle "$pid" &&
                byellow "Detected .bashrc update, press enter to reload." >/proc/$pid/fd/1
        done 2>/dev/null
    else
        pkill -quit '^lbash$'
    fi
    return 0
}

(( $_use_signal_to_reload )) && trap reload_rc QUIT

>"$_reloaded_time"
