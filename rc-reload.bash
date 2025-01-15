_reloaded_time=$(ramtmp)/$$-reload.tmp
_reload_needed=$(ramtmp)/reload-needed.tmp
_reload_rc_files_fingerprints=""

trap 'rm -f "$_reloaded_time"' EXIT

_use_signal_to_reload=0

_main_rc_files="
$HOME/cbin/makotorc
$HOME/cbin/interactive-setup.bash
$HOME/cbin/interactivefuncs.bash
$HOME/cbin/prompt.bash
$HOME/cbin/dot_bash_profile
$HOME/cbin/abin/android-commands.bash
$HOME/cbin/android-commands-pub.sh
$BASH_SOURCE
"

_rc_file_fingerprint() {
    echo $(md5sum $_main_rc_files)
}

_update_rc_file_fingerprint() {
    _reload_rc_files_fingerprints="$(_rc_file_fingerprint)"
}

rc_files_changed() {
    [[ "$_reload_rc_files_fingerprints" != "$(_rc_file_fingerprint)" ]]
}

reload_rc() {
    bgreen "Reloading .bashrc..."
    time source ~/.bashrc
    touch "$_reloaded_time"
    _update_rc_file_fingerprint
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

rc() {
    if (( ! $_use_signal_to_reload )) ; then
        # Non-signal version.
        touch "$_reload_needed"
        reload_rc

        # For each bash...
        for pid in $(pgrep -f -U $(id -u) -- '(^-bash$|^bash -l$|/bash -l$)') ; do
            if [[ $pid == $$ ]] ; then
                continue
            fi
            # If stdout is a terminal, show this message.
            (test -t 0 < /proc/$pid/fd/1) &&
                byellow "Detected .bashrc update, press enter to reload." >/proc/$pid/fd/1
        done 2>/dev/null
    else
        pkill -quit '^lbash$'
    fi
    return 0
}

(( $_use_signal_to_reload )) && trap reload_rc QUIT

touch $_reloaded_time
_update_rc_file_fingerprint
