#!/bin/bash
# Start gnome-terminal with an almost clean environment.
# Run t_test.bash after making any changes.

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  cat <<EOF
Usage: ${0##*/} [gnome-terminal-options]

Start gnome-terminal with an almost clean environment, preserving only essential
GUI, session, and terminal environment variables (like DISPLAY, WAYLAND_DISPLAY,
DBUS_SESSION_BUS_ADDRESS, PATH, HOME, USER, etc.).

All other exported environment variables are removed.
EOF
  exit 0
fi

# Determine if a variable should be kept
should_keep() {
  case "$1" in
    # Exact matches for essential variables
    DISPLAY | WAYLAND_DISPLAY | XAUTHORITY | DESKTOP_SESSION | GDMSESSION | \
    SYSTEMD_EXEC_PID | XMODIFIERS | USER | USERNAME | LOGNAME | HOME | PATH | \
    TERM | SHELL | LANG | SSH_AUTH_SOCK | GPG_AGENT_INFO | VTE_VERSION)
      return 0
      ;;
    # Wildcard matches for specific groups
    DBUS_* | GNOME_* | XDG_* | GTK_* | QT_* | LC_*)
      return 0
      ;;
  esac
  return 1
}

# Build the env command arguments using compgen -e to find all exported vars
env_args=()
while read -r var; do
  if [[ -n "$var" ]] && ! should_keep "$var"; then
    env_args+=("-u" "$var")
  fi
done < <(compgen -e)

export NEW_PWD=$PWD

# Run gnome-terminal with the cleared environment
exec env "${env_args[@]}" gnome-terminal "$@"
