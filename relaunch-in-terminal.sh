# Sourced helper to detect if running under an AI agent and relaunch the command in a terminal.
# Simple script, no help needed.
#
# Usage: . relaunch-in-terminal.sh [options] -- command [args...]
# Options:
#   -g, --geometry GEOMETRY   Terminal geometry (default: 140x45)
#   -c, --command COMMAND     Terminal runner command (default: gnome-terminal)

# This script must be sourced!
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "Error: relaunch-in-terminal.sh must be sourced, not executed directly." >&2
  exit 1
fi

_relaunch_dir=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
if ! "$_relaunch_dir/is-in-agent"; then
  return 0 # Return early to continue parent script
fi

if [[ -z "$DISPLAY" ]]; then
  echo "Error: DISPLAY is not set. Cannot launch terminal from a headless agent session." >&2
  exit 1 # Exit the parent shell since it's a hard error
fi

# Parse options passed to the sourced script
_relaunch_TEMP=$(getopt -o 'g:c:' --long 'geometry:,command:' -n 'relaunch-in-terminal.sh' -- "$@")
if [[ $? -ne 0 ]]; then
  exit 1
fi
eval set -- "$_relaunch_TEMP"

_relaunch_geom="140x45"
_relaunch_cmd="gnome-terminal"
while true; do
  case "$1" in
    '-g'|'--geometry')
      _relaunch_geom="$2"
      shift 2
      continue
      ;;
    '-c'|'--command')
      _relaunch_cmd="$2"
      shift 2
      continue
      ;;
    '--')
      shift
      break
      ;;
    *)
      echo "Internal error in relaunch-in-terminal.sh!" >&2
      exit 1
      ;;
  esac
done

if [[ $# -eq 0 ]]; then
  echo "Error: No command specified for relaunch-in-terminal.sh" >&2
  exit 1
fi

export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:+$FZF_DEFAULT_OPTS }--color=bg:#222222,bg+:#262626"

exec env -u ANTIGRAVITY_AGENT -u CLAUDE_AGENT -u IS_IN_AGENT "$_relaunch_cmd" --geometry="$_relaunch_geom" -- "$@"
