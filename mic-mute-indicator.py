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

NAME = "Shortcut Remote remapper"
SCRIPT_PATH = os.path.dirname(os.path.realpath(__file__))
ICON = os.path.join(SCRIPT_PATH, '10key.png')

DEFAULT_DEVICE_NAME = ""

debug = False

KEY_LABELS = [
    "1",
    "2",
    "3",
    "4",
    "5",
    "6",
    "7",
    "8",
    "9",

    "Left",
    "Right",
    "Button",
]

MODE_1 = [-1, "Cursor mode"]
MODE_2 = [-2, "Volume mode"]
MODE_3 = [-3, "Scroll mode"]

HALF_TOGGLE = 0x1_000_000

CURSOR_MODE = collections.OrderedDict([
    [ecodes.KEY_M, [ecodes.KEY_F, "F"]],
    [ecodes.KEY_P, [ecodes.KEY_F11, "F11"]],
    [ecodes.KEY_U, [ecodes.KEY_ENTER, "Enter"]],
    [ecodes.KEY_B, [ecodes.KEY_VOLUMEDOWN, "Vol Down"]],
    [ecodes.KEY_ENTER, [ecodes.KEY_MUTE, "Mute"]],
    [ecodes.KEY_Z, [ecodes.KEY_VOLUMEUP, "Vol Up"]],

    [ecodes.KEY_V, MODE_1],
    [ecodes.KEY_I, MODE_2],
    [ecodes.KEY_SPACE, MODE_3],

    [ecodes.KEY_KPMINUS, [ecodes.KEY_LEFT, "Left"]],
    [ecodes.KEY_KPPLUS, [ecodes.KEY_RIGHT, "Right"]],
    [ecodes.KEY_LEFTSHIFT, [ecodes.KEY_SPACE, "Space"]],
])

VOLUME_MODE = collections.OrderedDict([
    [ecodes.KEY_M, [ecodes.KEY_F20, "Mic Mute"]],
    [ecodes.KEY_P, [0, ""]],
    [ecodes.KEY_U, [ecodes.KEY_F20 | HALF_TOGGLE, "Mic Mute PPT"]],
    [ecodes.KEY_B, [ecodes.KEY_LEFT, "Left"]],
    [ecodes.KEY_ENTER, [ecodes.KEY_ENTER, "Enter"]],
    [ecodes.KEY_Z, [ecodes.KEY_RIGHT, "Right"]],

    [ecodes.KEY_V, MODE_1],
    [ecodes.KEY_I, MODE_2],
    [ecodes.KEY_SPACE, MODE_3],

    [ecodes.KEY_KPMINUS, [ecodes.KEY_VOLUMEDOWN, "Vol Down"]],
    [ecodes.KEY_KPPLUS, [ecodes.KEY_VOLUMEUP, "Vol Up"]],
    [ecodes.KEY_LEFTSHIFT, [ecodes.KEY_MUTE, "Mute"]],
])

SCROLL_MODE = collections.OrderedDict([
    [ecodes.KEY_M, [0, ""]],
    [ecodes.KEY_P, [ecodes.KEY_DOWN, "Down"]],
    [ecodes.KEY_U, [ecodes.KEY_ENTER, "Enter"]],
    [ecodes.KEY_B, [ecodes.KEY_LEFT, "Left"]],
    [ecodes.KEY_ENTER, [ecodes.KEY_UP, "Up"]],
    [ecodes.KEY_Z, [ecodes.KEY_RIGHT, "Right"]],

    [ecodes.KEY_V, MODE_1],
    [ecodes.KEY_I, MODE_2],
    [ecodes.KEY_SPACE, MODE_3],

    [ecodes.KEY_KPMINUS, [ecodes.KEY_PAGEUP, "Page Down"]],
    [ecodes.KEY_KPPLUS, [ecodes.KEY_PAGEDOWN, "Page Up"]],
    [ecodes.KEY_LEFTSHIFT, [ecodes.KEY_SPACE, "Space"]],
])

ALL_MODES = [CURSOR_MODE, VOLUME_MODE, SCROLL_MODE]


class Remapper(key_remapper.SimpleRemapper):
    def __init__(self):
        super().__init__(NAME, ICON, DEFAULT_DEVICE_NAME)

    def get_current_mode(self):
        return ALL_MODES[self.__mode]

    def show_help(self):
        descs = [v[1] for v in self.get_current_mode().values()]

        help = NAME + "\n" + "\n".join(f'[{v[0]}] {v[1]}' for v in zip(KEY_LABELS, descs))

        if not self.force_quiet:
            print(help)

        self.show_notification(help)

    def handle_events(self, device: evdev.InputDevice, events: List[evdev.InputEvent]):
        for ev in events:
            if ev.type != ecodes.EV_KEY:
                continue
            if ev.code == ecodes.KEY_LEFTCTRL:
                continue  # ignore it
            if ev.value not in [0, 1]:
                continue

            key = self.get_current_mode()[ev.code][0]
            if key == 0:
                self.show_help()
                continue

            if key <= 0:
                self.__mode = -key - 1
                self.show_help()
                continue

            half_toggle = (key & HALF_TOGGLE) != 0
            key = key & ~HALF_TOGGLE

            if half_toggle or ev.value == 1:
                self.press_key(key)

    def on_device_detected(self, devices: List[evdev.InputDevice]):
        super().on_device_detected(devices)
        self.show_help()

    def on_init_arguments(self, parser):
        parser.add_argument('--mode', type=int, default=0, help='Specify the initial mode (0-2)')

    def on_arguments_parsed(self, args):
        self.__mode = args.mode
        if self.__mode < 0 or self.__mode >= len(ALL_MODES):
            raise ValueError(f'Invalid mode {self.__mode}. Must be 0 <= mode < {len(ALL_MODES)}')


def main(args):
    remapper = Remapper()
    remapper.start(args)


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

# wheel
# Event: time 1606370588.253422, type 2 (EV_REL), code 8 (REL_WHEEL), value -1
# Event: time 1606370588.253422, type 2 (EV_REL), code 11 (REL_WHEEL_HI_RES), value -120
