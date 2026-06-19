#!/bin/bash
# Start gnome-terminal with an almost clean environment.
# Run t_test.bash after making any changes.

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  cat <<EOF
Usage: ${0##*/} [gnome-terminal-options] [command]

Start gnome-terminal with an almost clean environment, preserving only essential
GUI and session environment variables (like DISPLAY, WAYLAND_DISPLAY,
DBUS_SESSION_BUS_ADDRESS, HOME, USER, etc.).

All other exported environment variables are removed.

Examples:
  # Start a shell in gnome-terminal with a clean environment
  ${0##*/}

  # Run a command inside a clean environment (automatically inserts --)
  ${0##*/} man fzf

  # Pass gnome-terminal flags with '=' and run a command
  ${0##*/} --geometry=80x24 --title="Clean Terminal" man fzf
EOF
  exit 0
fi

# Determine if a variable should be kept
should_keep() {
  case "$1" in
    # Exact matches for essential variables
    DISPLAY | WAYLAND_DISPLAY | XAUTHORITY | DESKTOP_SESSION | GDMSESSION | \
    SYSTEMD_EXEC_PID | XMODIFIERS | USER | USERNAME | LOGNAME | HOME | PATH | \
    SHELL | LANG | SSH_AUTH_SOCK | GPG_AGENT_INFO)
      return 0
      ;;
    # Wildcard matches for specific groups
    DBUS_* | GNOME_* | XDG_* | GTK_* | QT_* | LC_* | GIT_*)
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

new_args=()
has_double_dash=0

for arg in "$@"; do
  if [[ "$arg" == "--" ]]; then
    has_double_dash=1
    break
  fi
done

if (( has_double_dash )); then
  new_args=("$@")
else
  i=1
  while (( i <= $# )); do
    arg="${!i}"
    if [[ "$arg" == -?* ]]; then
      new_args+=("$arg")
    else
      new_args+=("--")
      while (( i <= $# )); do
        new_args+=("${!i}")
        ((i++))
      done
      break
    fi
    ((i++))
  done
fi

# Find the index of "--" in new_args
double_dash_idx=-1
for idx in "${!new_args[@]}"; do
  if [[ "${new_args[idx]}" == "--" ]]; then
    double_dash_idx=$idx
    break
  fi
done

# If a command is specified, execute it via bash -c
if (( double_dash_idx != -1 )); then
  options=("${new_args[@]:0:double_dash_idx}")
  cmd_start=$((double_dash_idx + 1))
  cmd=("${new_args[@]:cmd_start}")

  script='"$@"'
  # # In tt mode, wait for keypress before closing the window
  # if [[ "$(basename "$0")" == "tt" ]]; then
  #   script+='; echo; echo "Press [ENTER] to close the window"; read'
  # fi

  new_args=(
    "${options[@]}"
    "--"
    "bash"
    "-c"
    "$script"
    # t-wrapper is passed as $0 so that "${cmd[@]}" elements start at $1 and are correctly expanded by "$@"
    "t-wrapper"
    "${cmd[@]}"
  )
fi

# In .bash_profile (~/cbin/dot_bash_profile), we check it and do a cd if set.
export NEW_PWD="$PWD"

# Run gnome-terminal with the cleared environment
exec env "${env_args[@]}" gnome-terminal "${new_args[@]}"
