#!/usr/bin/python3
import argparse
import asyncio
import collections
import os
import sys
import threading
import traceback
from typing import List

import evdev
import notify2
from evdev import ecodes, InputEvent

import key_remapper
import tasktray

NAME = "Satechi Media Buttons remapper"
SCRIPT_PATH = os.path.dirname(os.path.realpath(__file__))
ICON = os.path.join(SCRIPT_PATH, '10key.png')

DEFAULT_DEVICE_NAME = "^Satechi Media Button Consumer Control"

notify2.init(NAME)

debug = False

MAP = {
    ecodes.KEY_VOLUMEUP: ecodes.KEY_VOLUMEUP,
    ecodes.KEY_VOLUMEDOWN: ecodes.KEY_VOLUMEDOWN,
    ecodes.KEY_PLAYPAUSE: ecodes.KEY_SPACE,
    ecodes.KEY_PREVIOUSSONG: ecodes.KEY_LEFT,
    ecodes.KEY_NEXTSONG: ecodes.KEY_RIGHT,
}

class Remapper(key_remapper.BaseRemapper):
    __lock: threading.RLock
    __wheel_thread: threading.Thread

    def __init__(self, device_name_regex: str, *, enable_debug=False, quiet=False):
        super().__init__(device_name_regex,
                         id_regex='',
                         match_non_keyboards=True,
                         grab_devices=True,
                         write_to_uinput=True,
                         enable_debug=enable_debug)
        self.__quiet = quiet
        self.__notification = notify2.Notification(NAME, '')
        self.__notification.set_urgency(notify2.URGENCY_NORMAL)
        self.__notification.set_timeout(3000)
        self.__key_states = collections.defaultdict(int)
        self.__mode = 0

    def show_notification(self, message: str) -> None:
        if debug: print(message)
        self.__notification.update(NAME, message)
        self.__notification.show()


    def send_modifiers(self, val):
        self.uinput.write([
            InputEvent(0, 0, ecodes.EV_KEY, ecodes.KEY_LEFTCTRL, val),
            InputEvent(0, 0, ecodes.EV_KEY, ecodes.KEY_LEFTSHIFT, val),
        ])

    def handle_events(self, device: evdev.InputDevice, events: List[evdev.InputEvent]):
        for ev in events:
            if ev.type != ecodes.EV_KEY:
                continue

            key = MAP[ev.code]
            self.uinput.write([InputEvent(0, 0, ecodes.EV_KEY, key, ev.value)])

    def on_device_detected(self, devices: List[evdev.InputDevice]):
        self.show_notification('Device connected:\n'
                               + '\n'.join('- ' + d.name for d in devices))

    def on_device_not_found(self):
        self.show_notification('Device not found')

    def on_device_lost(self):
        self.show_notification('Device lost')

    def on_exception(self, exception: BaseException):
        self.show_notification('Device lost')

    def on_stop(self):
        self.show_notification('Closing...')


def main(args, description=NAME):
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument('-m', '--match-device-name', metavar='D', default=DEFAULT_DEVICE_NAME,
                        help='Use devices matching this regex')
    parser.add_argument('-d', '--debug', action='store_true', help='Enable debug output')
    parser.add_argument('-q', '--quiet', action='store_true', help='Quiet mode')

    args = parser.parse_args(args)

    global debug
    debug = args.debug

    remapper = Remapper(device_name_regex=args.match_device_name, enable_debug=debug,
                        quiet=args.quiet)

    def do():
        # evdev will complain if the thread has no event loop set.
        asyncio.set_event_loop(asyncio.new_event_loop())
        try:
            key_remapper.start_remapper(remapper)
        except BaseException as e:
            traceback.print_exc()
            tasktray.quit()

    th = threading.Thread(target=do)
    th.start()

    tasktray.start_quitting_tray_icon(NAME, ICON)
    key_remapper.stop_remapper()


if __name__ == '__main__':
    main(sys.argv[1:])

# Event: time 1607121528.602634, type 4 (EV_MSC), code 4 (MSC_SCAN), value c00e9
# Event: time 1607121528.602634, type 1 (EV_KEY), code 115 (KEY_VOLUMEUP), value 1
# Event: time 1607121528.602634, -------------- SYN_REPORT ------------
# Event: time 1607121528.715059, type 4 (EV_MSC), code 4 (MSC_SCAN), value c00e9
# Event: time 1607121528.715059, type 1 (EV_KEY), code 115 (KEY_VOLUMEUP), value 0
# Event: time 1607121528.715059, -------------- SYN_REPORT ------------
# Event: time 1607121529.367835, type 4 (EV_MSC), code 4 (MSC_SCAN), value c00ea
# Event: time 1607121529.367835, type 1 (EV_KEY), code 114 (KEY_VOLUMEDOWN), value 1
# Event: time 1607121529.367835, -------------- SYN_REPORT ------------
# Event: time 1607121529.502583, type 4 (EV_MSC), code 4 (MSC_SCAN), value c00ea
# Event: time 1607121529.502583, type 1 (EV_KEY), code 114 (KEY_VOLUMEDOWN), value 0
# Event: time 1607121529.502583, -------------- SYN_REPORT ------------
# Event: time 1607121530.493092, type 4 (EV_MSC), code 4 (MSC_SCAN), value c00b6
# Event: time 1607121530.493092, type 1 (EV_KEY), code 165 (KEY_PREVIOUSSONG), value 1
# Event: time 1607121530.493092, -------------- SYN_REPORT ------------
# Event: time 1607121530.605384, type 4 (EV_MSC), code 4 (MSC_SCAN), value c00b6
# Event: time 1607121530.605384, type 1 (EV_KEY), code 165 (KEY_PREVIOUSSONG), value 0
# Event: time 1607121530.605384, -------------- SYN_REPORT ------------
# Event: time 1607121533.710367, type 4 (EV_MSC), code 4 (MSC_SCAN), value c00cd
# Event: time 1607121533.710367, type 1 (EV_KEY), code 164 (KEY_PLAYPAUSE), value 1
# Event: time 1607121533.710367, -------------- SYN_REPORT ------------
# Event: time 1607121533.777349, type 4 (EV_MSC), code 4 (MSC_SCAN), value c00cd
# Event: time 1607121533.777349, type 1 (EV_KEY), code 164 (KEY_PLAYPAUSE), value 0
# Event: time 1607121533.777349, -------------- SYN_REPORT ------------
# Event: time 1607121536.409969, type 4 (EV_MSC), code 4 (MSC_SCAN), value c00b5
# Event: time 1607121536.409969, type 1 (EV_KEY), code 163 (KEY_NEXTSONG), value 1
# Event: time 1607121536.409969, -------------- SYN_REPORT ------------
# Event: time 1607121536.522338, type 4 (EV_MSC), code 4 (MSC_SCAN), value c00b5
# Event: time 1607121536.522338, type 1 (EV_KEY), code 163 (KEY_NEXTSONG), value 0
# Event: time 1607121536.522338, -------------- SYN_REPORT ------------
