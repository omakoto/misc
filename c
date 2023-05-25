#!/bin/bash

# Smart "open with chrome".

set -e

. mutil.sh

app=0
profdir=""
wait=0
no_ibus=0
maximized=0

eval "$(bashgetopt -d 'Run Chrome' '
p|profile=s  profdir=%      # specify profile directory name
a|app        app=1          # start as app
w|wait       wait=1         # wait until all Chrome instances stop before starting
c|corp       profdir=chrome-corp         # use the "corp" profile
n|personal   profdir=chrome-personal     # use the "personal" profile
m|maximized  maximized=1    # Start maximized
no-ibus      no_ibus=1      # Disable ibus
' "$@")"

# Parse the argument.

url="$1"
shift || true

function temphtml() {
    tempfile --suffix=.html
}


# If there's no argument, and STDIN is not terminal, #'
# read from stdin.
if [[ -z "$url" ]] && ! [[ -t 0 ]] ; then
  url=$( temphtml )
  cat > "$url"
  if ! [[ -s "$url" ]] ; then
    # File empty.
    rm -f "$url"
    url=""
  fi
fi

if [[ -f "$url" ]]; then
  case "$url" in
  *.gif|*.png|*.webp|*.jpeg|*.jpg|*.mp4|*.pdf) ;;
  *)
    if ! isbin "$url" && has-ansi "$url" ; then
      url2=$( temphtml )
      head="$(head -1 "$url" 2>/dev/null | ansi-remove | sed -e 's/^\$ *//')"
      a2h -font-size 8pt -title "$head [a2h]" < "$url" > "$url2"
      url="$url2"
    fi
    ;;
  esac
fi

if [[ -e "$url" ]]; then
  if ! [[ "$url" =~ ^/ ]] ; then
    url="$PWD/$url"
  fi
  url="$(l2w "$url")"
fi


# build the parameters.

params=()
params+=("--force-color-profile=srgb")

if [[ -n "$profdir" ]]; then
  if ! [[ "$profdir" =~ / ]] ; then
    profdir="$(readlink -f $HOME/.config/$profdir)"
  fi
  profdir="$(readlink -m "$profdir")"
  profdir="$(l2w "$profdir")"
  if ! [[ -d "$profdir" ]] ;then
    echo "Profile directory \"$profdir\" doesn't exist" 1>&2
    exit 1
  fi

  params+=("--user-data-dir=${profdir}")
  echo "profile=$profdir"
  # if ! [[ -d "$profdir/" ]] ; then
  #   mkdir -p "$profdir"
  # fi
  # params+=("--profile-directory=Default")
fi

# This file is written by pc-config-update
dpi=$(cat ~/.chromedpi 2>/dev/null || true)

if (( $maximized )) ; then
  params+=("--start-maximized")
fi

if [[ -n "$dpi" ]] ; then
  params+=("--force-device-scale-factor=$dpi")
fi

if (( $app )) ; then
  params+=("--app=$url")
else
  params+=("$url")
fi

if (( $wait )) ; then
    while true; do
        n=$(pgrep -U $(id -u) -x chrome | wc -l)
        if (( $n == 0 )) ; then
            break
        fi
        echo "Waiting until running Chrome instance(s) to finish... ($n running)"
        sleep 1
    done
fi


if (( $no_ibus != 0 )) ; then
    ee unset XMODIFIERS
    ee unset QT_IM_MODULE
    ee unset XMODIFIERS
    ee unset GTK_IM_MODULE
fi

chrome=google-chrome

if iswsl ; then
  chrome="$(w2l 'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe')"
fi

if (( $verbose )) ; then
  INFO 'Running' "$chrome" "${params[@]}" "$@"
fi

cd $HME
ee -b "$chrome" "${params[@]}" "$@"
