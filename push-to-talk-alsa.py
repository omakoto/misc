#!/usr/bin/python3
import argparse
import typing

import keymacroer
import sys
import evdev
from evdev import ecodes as e
import alsaaudio
import notify2

default_mic_muted = True
button_pressed = False

default_mixer_name = 'Capture'
in_mixer = None
channel = alsaaudio.MIXER_CHANNEL_ALL

last_notification = None
notification_summary = "Push-to-talk"
last_volume = 100

USE_MUTE = False

def do_mute(mute):
    global last_volume
    if mute:
        if USE_MUTE:
            in_mixer.setrec(0, channel)
        else:
            last_volume = in_mixer.getvolume(alsaaudio.PCM_CAPTURE)[0]
            # print(f'Last volume={last_volume}')
            in_mixer.setvolume(0)
    else:
        if USE_MUTE:
            in_mixer.setrec(1, channel)
        elif last_volume >= 0:
            in_mixer.setvolume(last_volume)


def update(mute=None):
    global last_notification

    if mute is None:
        mute = button_pressed != default_mic_muted

    do_mute(mute)

    message = ""
    if mute:
        message = "Mic Muted"
    else:
        message = "Mic Unmuted"

    global last_notification
    if last_notification:
        n = last_notification
        n.update(notification_summary, message)
    else:
        n = notify2.Notification(notification_summary, message)

    n.set_urgency(notify2.URGENCY_NORMAL)
    n.set_timeout(1000)

    n.show()

    last_notification = n

def remapper(
        device: evdev.InputDevice,
        events: typing.List[evdev.InputEvent]) -> typing.List[evdev.InputEvent]:
    for ev in events:
        global button_pressed, default_mic_muted
        if ev.type == e.EV_KEY and ev.code == e.BTN_LEFT:
            button_pressed = ev.value == 1
            update()
        elif (ev.type == e.EV_KEY and
              ev.code in (e.KEY_ESC, e.KEY_LEFT, e.BTN_RIGHT) and
              ev.value == 1):
            default_mic_muted = not default_mic_muted
            update()
    return [] # eat all events


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='push-to-talk with alsa')
    parser.add_argument('-d', '--debug', action='store_true', help='Enable debug output')
    parser.add_argument('-c', '--in-mixer', default=default_mixer_name, help='Input mixer name')

    args = parser.parse_args()

    mixer_name = args.in_mixer

    notify2.init("Push-to-talk")

    try:
        in_mixer = alsaaudio.Mixer(mixer_name)
    except alsaaudio.ALSAAudioError:
        print(f'No such mixer: {mixer_name}', file=sys.stderr)
        sys.exit(1)

    update(True)
    try:
        keymacroer.run('^Smart Smart dongle', remapper,
                       force_debug=args.debug, match_all_devices=True, no_output=True)
    finally:
        update(False)

# /dev/input/event17:	Smart Smart dongle
# /dev/input/event18:	Smart Smart dongle
# /dev/input/event20:	Smart Smart dongle System Control
# /dev/input/event21:	Smart Smart dongle Consumer Control


# top left and right buttons
# Event: time 1604716328.886729, type 4 (EV_MSC), code 4 (MSC_SCAN), value 70029
# Event: time 1604716328.886729, type 1 (EV_KEY), code 1 (KEY_ESC), value 1
# Event: time 1604716328.886729, -------------- SYN_REPORT ------------
# Event: time 1604716329.070721, type 4 (EV_MSC), code 4 (MSC_SCAN), value 70029
# Event: time 1604716329.070721, type 1 (EV_KEY), code 1 (KEY_ESC), value 0
# Event: time 1604716329.070721, -------------- SYN_REPORT ------------
# Event: time 1604716330.438730, type 4 (EV_MSC), code 4 (MSC_SCAN), value 70028
# Event: time 1604716330.438730, type 1 (EV_KEY), code 28 (KEY_ENTER), value 1
# Event: time 1604716330.438730, -------------- SYN_REPORT ------------
# Event: time 1604716330.614732, type 4 (EV_MSC), code 4 (MSC_SCAN), value 70028
# Event: time 1604716330.614732, type 1 (EV_KEY), code 28 (KEY_ENTER), value 0
# Event: time 1604716330.614732, -------------- SYN_REPORT ------------

# trigger
# Event: time 1604716357.784751, type 4 (EV_MSC), code 4 (MSC_SCAN), value 90001
# Event: time 1604716357.784751, type 1 (EV_KEY), code 272 (BTN_LEFT), value 1
# Event: time 1604716357.784751, -------------- SYN_REPORT ------------
# Event: time 1604716357.976476, type 4 (EV_MSC), code 4 (MSC_SCAN), value 90001
# Event: time 1604716357.976476, type 1 (EV_KEY), code 272 (BTN_LEFT), value 0
