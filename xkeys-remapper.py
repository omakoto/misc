#!/usr/bin/python3
import argparse
import asyncio
import collections
import math
import os
import sys
import threading
import time
import traceback
from typing import List, Optional

import evdev
import notify2
from evdev import ecodes, InputEvent

import key_remapper
import synced_uinput
import tasktray

NAME = "X-keys remapper"
SCRIPT_PATH = os.path.dirname(os.path.realpath(__file__))
ICON = os.path.join(SCRIPT_PATH, '10key.png')

DEFAULT_DEVICE_NAME = "^P. I. Engineering XK-16 HID"

notify2.init(NAME)

debug = False

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

            # print(f'{ev}')

            if ecodes.KEY_1 <= ev.code <= ecodes.KEY_8:
                if ev.value == 1:
                    self.send_modifiers(1)
                self.uinput.write([InputEvent(0, 0, ecodes.EV_KEY, ev.code, ev.value)])
                if ev.value == 0:
                    self.send_modifiers(0)

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

# ------------------------------
# 1
# Event: time 1605849332.729321, type 4 (EV_MSC), code 4 (MSC_SCAN), value 70010
# Event: time 1605849332.729321, type 1 (EV_KEY), code 50 (KEY_M), value 1
# Event: time 1605849332.729321, -------------- SYN_REPORT ------------
# Event: time 1605849332.825196, type 4 (EV_MSC), code 4 (MSC_SCAN), value 70010
# Event: time 1605849332.825196, type 1 (EV_KEY), code 50 (KEY_M), value 0
# Event: time 1605849332.825196, -------------- SYN_REPORT ------------
#
# 2
# Event: time 1605849333.141265, type 4 (EV_MSC), code 4 (MSC_SCAN), value 70013
# Event: time 1605849333.141265, type 1 (EV_KEY), code 25 (KEY_P), value 1
# Event: time 1605849333.141265, -------------- SYN_REPORT ------------
# Event: time 1605849333.229098, type 4 (EV_MSC), code 4 (MSC_SCAN), value 70013
# Event: time 1605849333.229098, type 1 (EV_KEY), code 25 (KEY_P), value 0
# Event: time 1605849333.229098, -------------- SYN_REPORT ------------
#
# 3
# Event: time 1605849333.425338, type 4 (EV_MSC), code 4 (MSC_SCAN), value 70018
# Event: time 1605849333.425338, type 1 (EV_KEY), code 22 (KEY_U), value 1
# Event: time 1605849333.425338, -------------- SYN_REPORT ------------
# Event: time 1605849333.533252, type 4 (EV_MSC), code 4 (MSC_SCAN), value 70018
# Event: time 1605849333.533252, type 1 (EV_KEY), code 22 (KEY_U), value 0
# Event: time 1605849333.533252, -------------- SYN_REPORT ------------
#
# 4
# Event: time 1605849334.165310, type 4 (EV_MSC), code 4 (MSC_SCAN), value 70005
# Event: time 1605849334.165310, type 1 (EV_KEY), code 48 (KEY_B), value 1
# Event: time 1605849334.165310, -------------- SYN_REPORT ------------
# Event: time 1605849334.257216, type 4 (EV_MSC), code 4 (MSC_SCAN), value 70005
# Event: time 1605849334.257216, type 1 (EV_KEY), code 48 (KEY_B), value 0
# Event: time 1605849334.257216, -------------- SYN_REPORT ------------
#
# 5
# Event: time 1605849334.525236, type 4 (EV_MSC), code 4 (MSC_SCAN), value 70028
# Event: time 1605849334.525236, type 1 (EV_KEY), code 28 (KEY_ENTER), value 1
# Event: time 1605849334.525236, -------------- SYN_REPORT ------------
# Event: time 1605849334.592810, type 4 (EV_MSC), code 4 (MSC_SCAN), value 70028
# Event: time 1605849334.592810, type 1 (EV_KEY), code 28 (KEY_ENTER), value 0
# Event: time 1605849334.592810, -------------- SYN_REPORT ------------
#
# 6
# Event: time 1605849334.921274, type 4 (EV_MSC), code 4 (MSC_SCAN), value 700e0
# Event: time 1605849334.921274, type 1 (EV_KEY), code 29 (KEY_LEFTCTRL), value 1
# Event: time 1605849334.921274, type 4 (EV_MSC), code 4 (MSC_SCAN), value 7001d
# Event: time 1605849334.921274, type 1 (EV_KEY), code 44 (KEY_Z), value 1
# Event: time 1605849334.921274, -------------- SYN_REPORT ------------
#
# 7
# Event: time 1605849364.224065, type 4 (EV_MSC), code 4 (MSC_SCAN), value 70019
# Event: time 1605849364.224065, type 1 (EV_KEY), code 47 (KEY_V), value 1
# Event: time 1605849364.224065, -------------- SYN_REPORT ------------
# Event: time 1605849364.324053, type 4 (EV_MSC), code 4 (MSC_SCAN), value 70019
# Event: time 1605849364.324053, type 1 (EV_KEY), code 47 (KEY_V), value 0
# Event: time 1605849364.324053, -------------- SYN_REPORT ------------
#
# 8
# Event: time 1605849364.732044, type 4 (EV_MSC), code 4 (MSC_SCAN), value 7000c
# Event: time 1605849364.732044, type 1 (EV_KEY), code 23 (KEY_I), value 1
# Event: time 1605849364.732044, -------------- SYN_REPORT ------------
# iEvent: time 1605849364.847988, type 4 (EV_MSC), code 4 (MSC_SCAN), value 7000c
# Event: time 1605849364.847988, type 1 (EV_KEY), code 23 (KEY_I), value 0
# Event: time 1605849364.847988, -------------- SYN_REPORT ------------
#
# 9
# Event: time 1605849365.024025, type 4 (EV_MSC), code 4 (MSC_SCAN), value 7002c
# Event: time 1605849365.024025, type 1 (EV_KEY), code 57 (KEY_SPACE), value 1
# Event: time 1605849365.024025, -------------- SYN_REPORT ------------
# Event: time 1605849365.139992, type 4 (EV_MSC), code 4 (MSC_SCAN), value 7002c
# Event: time 1605849365.139992, type 1 (EV_KEY), code 57 (KEY_SPACE), value 0
#
#
# left turn
# Event: time 1605849413.746328, type 4 (EV_MSC), code 4 (MSC_SCAN), value 700e0
# Event: time 1605849413.746328, type 1 (EV_KEY), code 29 (KEY_LEFTCTRL), value 1
# Event: time 1605849413.746328, type 4 (EV_MSC), code 4 (MSC_SCAN), value 70056
# Event: time 1605849413.746328, type 1 (EV_KEY), code 74 (KEY_KPMINUS), value 1
# Event: time 1605849413.746328, -------------- SYN_REPORT ------------
# Event: time 1605849413.749899, type 4 (EV_MSC), code 4 (MSC_SCAN), value 700e0
# Event: time 1605849413.749899, type 1 (EV_KEY), code 29 (KEY_LEFTCTRL), value 0
# Event: time 1605849413.749899, type 4 (EV_MSC), code 4 (MSC_SCAN), value 70056
# Event: time 1605849413.749899, type 1 (EV_KEY), code 74 (KEY_KPMINUS), value 0
# Event: time 1605849413.749899, -------------- SYN_REPORT ------------
#
#
# right turn
# Event: time 1605849414.946283, type 4 (EV_MSC), code 4 (MSC_SCAN), value 700e0
# Event: time 1605849414.946283, type 1 (EV_KEY), code 29 (KEY_LEFTCTRL), value 1
# Event: time 1605849414.946283, type 4 (EV_MSC), code 4 (MSC_SCAN), value 70057
# Event: time 1605849414.946283, type 1 (EV_KEY), code 78 (KEY_KPPLUS), value 1
# Event: time 1605849414.946283, -------------- SYN_REPORT ------------
# Event: time 1605849414.949907, type 4 (EV_MSC), code 4 (MSC_SCAN), value 700e0
# Event: time 1605849414.949907, type 1 (EV_KEY), code 29 (KEY_LEFTCTRL), value 0
# Event: time 1605849414.949907, type 4 (EV_MSC), code 4 (MSC_SCAN), value 70057
# Event: time 1605849414.949907, type 1 (EV_KEY), code 78 (KEY_KPPLUS), value 0
# Event: time 1605849414.949907, -------------- SYN_REPORT ------------
# Event: time 1605849415.758268, type 4 (EV_MSC), code 4 (MSC_SCAN), value 700e0
# Event: time 1605849415.758268, type 1 (EV_KEY), code 29 (KEY_LEFTCTRL), value 1
# Event: time 1605849415.758268, type 4 (EV_MSC), code 4 (MSC_SCAN), value 70057
# Event: time 1605849415.758268, type 1 (EV_KEY), code 78 (KEY_KPPLUS), value 1
# Event: time 1605849415.758268, -------------- SYN_REPORT ------------
# Event: time 1605849415.761837, type 4 (EV_MSC), code 4 (MSC_SCAN), value 700e0
# Event: time 1605849415.761837, type 1 (EV_KEY), code 29 (KEY_LEFTCTRL), value 0
# Event: time 1605849415.761837, type 4 (EV_MSC), code 4 (MSC_SCAN), value 70057
# Event: time 1605849415.761837, type 1 (EV_KEY), code 78 (KEY_KPPLUS), value 0
# Event: time 1605849415.761837, -------------- SYN_REPORT ------------
#
# center
# Event: time 1605849415.789813, type 4 (EV_MSC), code 4 (MSC_SCAN), value 700e1
# Event: time 1605849415.789813, type 1 (EV_KEY), code 42 (KEY_LEFTSHIFT), value 1
# Event: time 1605849415.789813, -------------- SYN_REPORT ------------
# Event: time 1605849415.910189, type 4 (EV_MSC), code 4 (MSC_SCAN), value 700e1
# Event: time 1605849415.910189, type 1 (EV_KEY), code 42 (KEY_LEFTSHIFT), value 0
# Event: time 1605849415.910189, -------------- SYN_REPORT ------------
