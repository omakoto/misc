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

DEFAULT_MIXER_NAME = 'Capture'
USE_MUTE = False


class Muter(object):
    def __init__(self, mixer_name):
        try:
            self.__rec_mixer = alsaaudio.Mixer(mixer_name)
        except alsaaudio.ALSAAudioError:
            print(f'No such mixer: {mixer_name}', file=sys.stderr)
            sys.exit(1)

        self.__notification_summary = "Push-to-talk"
        self.__last_notification = None
        self.__last_volume = self.__get_volume()
        self.__channel = alsaaudio.MIXER_CHANNEL_ALL

        self.__default_mute = True
        self.__pushed = False

        self.update_mute()

    def __get_volume(self):
        return self.__rec_mixer.getvolume(alsaaudio.PCM_CAPTURE)[0]

    def __set_volume(self, value):
        self.__rec_mixer.setvolume(value)

    def __do_mute(self, mute):
        if USE_MUTE:
            if mute:
                self.__rec_mixer.setrec(0, self.__channel)
            else:
                self.__rec_mixer.setrec(1, self.__channel)
            return

        if mute:
            self.__last_volume = self.__get_volume()
            self.__set_volume(0)
        elif self.__last_volume >= 0:
            self.__rec_mixer.setvolume(self.__last_volume)

    def toggle_default_mute(self):
        self.__default_mute = not self.__default_mute
        self.update_mute()

    def set_pushed(self, value):
        self.__pushed = value
        self.update_mute()

    def update_mute(self, mute=None):
        if mute is None:
            mute = self.__default_mute != self.__pushed

        self.__do_mute(mute)

        message = "Mic Muted" if mute else "Mic Unmuted"

        if not mute and self.__get_volume() < 10:
            message += " But Volume Too Low!"

        if self.__last_notification:
            n = self.__last_notification
            n.update(self.__notification_summary, message)
        else:
            n = notify2.Notification(self.__notification_summary, message)

        n.set_urgency(notify2.URGENCY_NORMAL)
        n.set_timeout(1000)

        n.show()

        self.__last_notification = n


if __name__ == '__main__':
    notify2.init("Push-to-talk")

    parser = argparse.ArgumentParser(description='push-to-talk with alsa')
    parser.add_argument('-d', '--debug', action='store_true', help='Enable debug output')
    parser.add_argument('-m', '--mixer-name', default=DEFAULT_MIXER_NAME, help='Capture mixer name')
    parser.add_argument('device', help='Regex for the device name')
    parser.add_argument('key_toggle', type=int, help='Key code for toggle mute')
    parser.add_argument('key_ppt', type=int, help='Key code for push-to-talk')

    args = parser.parse_args()
    muter = Muter(args.mixer_name)

    device = args.device
    key_toggle = int(args.key_toggle)
    key_ppt = int(args.key_ppt)


    def remapper(
            device: evdev.InputDevice,
            events: typing.List[evdev.InputEvent]) -> typing.List[evdev.InputEvent]:
        for ev in events:
            if ev.type == e.EV_KEY and ev.code == key_ppt:
                muter.set_pushed(ev.value >= 1)
            elif (ev.type == e.EV_KEY and
                  ev.code == key_toggle and
                  ev.value == 1):
                muter.toggle_default_mute()
        return [] # eat all events

    try:
        keymacroer.run(device, remapper,
                       force_debug=args.debug, match_all_devices=True, no_output=True)
    finally:
        muter.update_mute(False)

# Use with the ten-key. 0 for PPT, enter to toggle.
# push-to-talk-alsa.py '^MOSART Semi. 2.4G Keyboard Mouse$' 96 82

# Use with the handheld trackball. Trigger for PPT, top-left to toggle.
# push-to-talk-alsa.py '^Smart Smart dongle$' 105 272


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
