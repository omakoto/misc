#!/usr/bin/python3
import argparse
import os
import threading
import typing

import keymacroer
import sys
import evdev
from evdev import ecodes as e
import alsaaudio

import gi
gi.require_version('Gtk', '3.0')
gi.require_version('AppIndicator3', '0.1')
gi.require_version('Notify', '0.7')
from gi.repository import Gtk as gtk
from gi.repository import GLib as glib
from gi.repository import AppIndicator3 as appindicator
from gi.repository import Notify as notify
import tasktray

NAME = 'Push-to-talk'

default_mic_muted = True
button_pressed = False

DEFAULT_MIXER_NAME = 'Capture'
USE_MUTE = False

SCRIPT_PATH = os.path.dirname(os.path.realpath(__file__))
MIC_ICON = os.path.join(SCRIPT_PATH, 'microphone.png')
MIC_MUTED_ICON = os.path.join(SCRIPT_PATH, 'microphone-muted.png')


class Ui(tasktray.TaskTrayIcon):
    def __init__(self):
        super().__init__(NAME, MIC_ICON)
        notify.init(NAME)
        self.notification = notify.Notification.new(NAME, '', None)

    def update_muted(self, muted=False):
        icon = MIC_MUTED_ICON if muted else MIC_ICON
        self.set_icon(icon)

    def notify(self, message):
        def inner():
            # nonlocal self, muted
            self.notification.update(NAME, message, None)
            self.notification.show()
        glib.idle_add(inner)

    def _on_quit(self):
        notify.uninit()

    def run(self):
        gtk.main()


UI = Ui()


class Muter(object):
    def __init__(self, mixer_name):
        try:
            self.__rec_mixer = alsaaudio.Mixer(mixer_name)
        except alsaaudio.ALSAAudioError:
            print(f'No such mixer: {mixer_name}', file=sys.stderr)
            sys.exit(1)

        self.__last_volume = self.__get_volume()
        self.__channel = alsaaudio.MIXER_CHANNEL_ALL

        self.__default_mute = True
        self.__pushed = False
        self.__was_muted = False

        self.update_mute()

    def __get_volume(self):
        return self.__rec_mixer.getvolume(alsaaudio.PCM_CAPTURE)[0]

    def __set_volume(self, value):
        self.__rec_mixer.setvolume(value)

    def __do_mute(self, mute):
        if self.__was_muted == mute:
            return
        self.__was_muted = mute

        if USE_MUTE:
            if mute:
                self.__rec_mixer.setrec(0, self.__channel)
            else:
                self.__rec_mixer.setrec(1, self.__channel)
            return

        if mute:
            self.__last_volume = self.__get_volume()
            # print(f'Last volume: {self.__last_volume}')
            # if self.__last_volume < 10:
            #     self.__last_volume = 100
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

        UI.update_muted(mute)

        message = "Mic Muted" if mute else "Mic Unmuted"

        if not mute and self.__get_volume() < 50:
            message += " But Volume Too Low!"

        UI.notify(message)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='push-to-talk with alsa')
    parser.add_argument('-d', '--debug', action='store_true', help='Enable debug output')
    parser.add_argument('-m', '--mixer-name', default=DEFAULT_MIXER_NAME, help='Capture mixer name')
    parser.add_argument('device', help='Regex for the device name')
    parser.add_argument('key_toggle', help='Key codes (csv) for toggle mute')
    parser.add_argument('key_ppt', help='Key codes (csv) for push-to-talk')

    args = parser.parse_args()
    muter = Muter(args.mixer_name)

    device = args.device
    keys_toggle = [int(n) for n in args.key_toggle.split(',')]
    keys_ppt = [int(n) for n in args.key_ppt.split(',')]

    class MyRemapper(keymacroer.BaseRemapper):

        def __init__(self):
            super().__init__(device_name_regex=device,
                             output_to_uinput=False, match_all_devices=True, grab_devices=True,
                             force_debug=args.debug)

        def remap(self, device: evdev.InputDevice, events: typing.List[evdev.InputEvent]
                  ) -> typing.List[evdev.InputEvent]:
            for ev in events:
                if ev.type == e.EV_KEY and ev.code in keys_ppt:
                    muter.set_pushed(ev.value >= 1)
                elif (ev.type == e.EV_KEY and
                      ev.code in keys_toggle and
                      ev.value == 1):
                    muter.toggle_default_mute()
            return [] # eat all events

        def on_device_detected(self, devices: typing.List[evdev.InputDevice]):
            if not devices:
                return
            message = 'Device detected:\n' + '\n'.join([d.name for d in devices])
            UI.notify(message)

        def on_exception(self, exception: BaseException):
            UI.notify(f'Unhandled exception: {exception}')

        def on_device_lost(self, exception: BaseException):
            UI.notify(f'Device lost: {exception}')

    class RemapperThread(threading.Thread):
        def __init__(self):
            super().__init__()

        def run(self):
            try:
                keymacroer.run2(MyRemapper())
            finally:
                UI.quit(None)

    th = RemapperThread()
    th.setDaemon(True)
    th.start()

    try:
        UI.run()
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


# FM8PU83-Ver0E-0000 RF 2.4G
