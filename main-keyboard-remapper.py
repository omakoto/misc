#!/usr/bin/python3
import os
import sys
from typing import List, Tuple

import evdev
from evdev import ecodes, InputEvent

import key_remapper2

NAME = "Main Keyboard Remapper"
SCRIPT_PATH = os.path.dirname(os.path.realpath(__file__))
ICON = os.path.join(SCRIPT_PATH, '10key.png')

DEFAULT_DEVICE_NAME = "^(AT Translated Set 2 keyboard|Topre Corporation Realforce)"

debug = False

class Remapper(key_remapper2.SimpleRemapper):
    def __init__(self):
        super().__init__(NAME, ICON, DEFAULT_DEVICE_NAME)

    def is_chrome(self):
        return self.get_active_window()[1].startswith("google-chrome")

    def is_esc_pressed(self):
        return self.check_modifiers('e')

    def handle_events(self, device: evdev.InputDevice, events: List[evdev.InputEvent]):
        for ev in events:
            if ev.type != ecodes.EV_KEY:
                continue

            # For chrome:
            #  F5 -> back
            #  F6 -> forward
            if ev.code == ecodes.KEY_F5 and self.is_chrome():
                if ev.value == 1: self.press_key(ecodes.KEY_BACK)
                continue
            if ev.code == ecodes.KEY_F6 and self.is_chrome():
                if ev.value == 1: self.press_key(ecodes.KEY_FORWARD)
                continue
            # ESC + space -> shift-space (scroll back)
            if ev.code == ecodes.KEY_SPACE and self.is_chrome():
                if ev.value in [1, 2]:
                    if self.is_esc_pressed():
                        self.reset_all_keys()
                        self.press_key(ecodes.KEY_SPACE, 's')
                    else:
                        self.press_key(ecodes.KEY_SPACE)
                continue

            # ESC + HOME -> CTRL+ATL+1 -> work.txt
            if ev.code == ecodes.KEY_HOME:
                if ev.value == 1 and self.is_esc_pressed():
                    self.reset_all_keys()
                    self.press_key(ecodes.KEY_MINUS, 'ac')
                    continue

            # ESC + END -> CTRL+ATL+T -> terminal
            if ev.code == ecodes.KEY_END:
                if ev.value == 1 and self.is_esc_pressed():
                    self.reset_all_keys()
                    self.press_key(ecodes.KEY_T, 'ac')
                    continue

            # ESC + DEL -> CTRL+ATL+1 -> chrome
            if ev.code == ecodes.KEY_DELETE:
                if ev.value == 1 and self.is_esc_pressed():
                    self.reset_all_keys()
                    self.press_key(ecodes.KEY_C, 'ac')
                    continue

            self.uinput.write([InputEvent(0, 0, ecodes.EV_KEY, ev.code, ev.value)])


def main(args):
    remapper = Remapper()
    remapper.main(args)


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
