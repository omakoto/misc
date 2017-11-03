_reloaded_time=${RAMTMP:-/tmp}/$$-reload.tmp
_reload_needed=${RAMTMP:-/tmp}/reload-needed.tmp

trap 'rm -f "$_reloaded_time"' EXIT

_use_signal_to_reload=0

reload_rc() {
  bgreen "Reloading .bashrc..."
  time source ~/.bashrc
  touch "$_reloaded_time"
  bgreen "Reloaded .bashrc."
}

# Call it in PROMPT_COMMAND
reload_rc_if_changed() {
    if [[ "$_reloaded_time" -ot "$_reload_needed" ]] ; then
        reload_rc
    fi
}

rc() {
    if (( ! $_use_signal_to_reload )) ; then
        # Non-signal version.
        touch "$_reload_needed"
        reload_rc
        for pid in $(pgrep '^lbash$') ; do
            if [[ $pid == $$ ]] ; then
                continue
            fi
            (test -t < /proc/$pid/fd/1 >&/dev/null) &&
                byellow "Detected .bashrc update, press enter to reload." >/proc/$pid/fd/1
        done
    else
        pkill -quit '^lbash$'
    fi
    return 0
}

(( $_use_signal_to_reload )) && trap reload_rc QUIT

touch $_reloaded_time
