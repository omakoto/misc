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

# Whitelist of environment variables to keep
keep_vars=(
  # Display and GUI variables
  DISPLAY
  WAYLAND_DISPLAY
  XAUTHORITY
  GNOME_SETUP_DISPLAY
  
  # Session and DBus variables
  DBUS_SESSION_BUS_ADDRESS
  DESKTOP_SESSION
  GDMSESSION
  GNOME_DESKTOP_SESSION_ID
  GNOME_KEYRING_CONTROL
  GNOME_TERMINAL_SCREEN
  GNOME_TERMINAL_SERVICE
  SYSTEMD_EXEC_PID
  XDG_RUNTIME_DIR
  XDG_SESSION_TYPE
  XDG_CURRENT_DESKTOP
  XDG_SESSION_CLASS
  XDG_SESSION_DESKTOP
  XDG_DATA_DIRS
  XDG_CONFIG_DIRS
  XDG_MENU_PREFIX
  
  # Input and Theme variables
  QT_ACCESSIBILITY
  QT_IM_MODULE
  QT_IM_MODULES
  GTK_IM_MODULE
  GTK_MODULES
  XMODIFIERS
  
  # System / Shell basics
  USER
  USERNAME
  LOGNAME
  HOME
  PATH
  TERM
  SHELL
  LANG
  LC_ALL
  LC_CTYPE
  LC_COLLATE
  LC_MESSAGES
  LC_MONETARY
  LC_NUMERIC
  LC_TIME
  
  # Authentication
  SSH_AUTH_SOCK
  GPG_AGENT_INFO
  
  # Terminal version
  VTE_VERSION
)

# Convert whitelist to an associative array for fast lookup
declare -A keep
for var in "${keep_vars[@]}"; do
  keep["$var"]=1
done

# Build the env command arguments using compgen -e to find all exported vars
env_args=()
while read -r var; do
  if [[ -n "$var" && -z "${keep[$var]}" ]]; then
    env_args+=("-u" "$var")
  fi
done < <(compgen -e)

# Run gnome-terminal with the cleared environment
exec env "${env_args[@]}" gnome-terminal "$@"
