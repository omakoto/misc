#!/usr/bin/python3
import os
import sys
from typing import List

import evdev
from evdev import ecodes, InputEvent

import key_remapper2

NAME = "Main Keyboard Remapper"
SCRIPT_PATH = os.path.dirname(os.path.realpath(__file__))
ICON = os.path.join(SCRIPT_PATH, 'keyboard.png')

DEFAULT_DEVICE_NAME = "^(AT Translated Set 2 keyboard|Topre Corporation Realforce)"

debug = False


class Remapper(key_remapper2.SimpleRemapper):
    def __init__(self):
        super().__init__(NAME, ICON, DEFAULT_DEVICE_NAME)

    def is_chrome(self):
        active_window = self.get_active_window()
        cls = active_window[1]
        return cls == "Google-chrome"

    def handle_event(self, device: evdev.InputDevice, ev: evdev.InputEvent):
        if ev.type != ecodes.EV_KEY:
            return

        is_thinkpad = device.name.startswith('AT')

        # Thinkpad only: Use ins/del as pageup/down, unless CAPS is pressed.
        if is_thinkpad:
            if ev.code == ecodes.KEY_INSERT and not self.is_caps_pressed(): ev.code = ecodes.KEY_PAGEUP
            elif ev.code == ecodes.KEY_DELETE and not self.is_caps_pressed(): ev.code = ecodes.KEY_PAGEDOWN

        # Also shift or esc + backspace -> delete
        if self.matches_key(ev, ecodes.KEY_BACKSPACE, 1, 's'): self.press_key(ecodes.KEY_DELETE, done=True)
        if self.matches_key(ev, ecodes.KEY_BACKSPACE, 1, 'e'): self.press_key(ecodes.KEY_DELETE, done=True)

        # For chrome: -----------------------------------------------------------------------------------
        #  F5 -> back
        #  F6 -> forward
        if self.matches_key(ev, ecodes.KEY_F5, 1, '', self.is_chrome): self.press_key(ecodes.KEY_BACK, done=True)
        if self.matches_key(ev, ecodes.KEY_F6, 1, '', self.is_chrome): self.press_key(ecodes.KEY_FORWARD, done=True)

        # Global ----------------------------------------------------------------------------------------

        # ESC + F11 -> CTRL+ATL+1 -> work.txt
        if self.matches_key(ev, ecodes.KEY_F11, 1, 'e'): self.press_key(ecodes.KEY_MINUS, 'ac', done=True)

        # ESC + F12 -> CTRL+ATL+T -> terminal
        if self.matches_key(ev, ecodes.KEY_F12, 1, 'e'): self.press_key(ecodes.KEY_T, 'ac', done=True)

        # ESC + ENTER -> CTRL+ATL+1 -> chrome
        if self.matches_key(ev, ecodes.KEY_ENTER, 1, 'e'): self.press_key(ecodes.KEY_C, 'ac', done=True)

        # ESC + home/end -> ATL+Left/Right (back / forwward)
        if self.matches_key(ev, ecodes.KEY_HOME, 1, 'e'): self.press_key(ecodes.KEY_LEFT, 'a', done=True)
        if self.matches_key(ev, ecodes.KEY_END, 1, 'e'): self.press_key(ecodes.KEY_RIGHT, 'a', done=True)

        # ESC + space -> page up. (for chrome and also in-process browser, such as Markdown Preview in vs code)
        if self.matches_key(ev, ecodes.KEY_SPACE, (1, 2), 'e'): self.press_key(ecodes.KEY_PAGEUP, done=True)

        #  ESC + Pageup -> ctrl + pageup (prev tab)
        #  ESC + Pagedown -> ctrl + pagedown (next tab)
        if self.matches_key(ev, ecodes.KEY_PAGEUP, 1, 'e'): self.press_key(ecodes.KEY_PAGEUP, 'c', done=True)
        if self.matches_key(ev, ecodes.KEY_PAGEDOWN, 1, 'e'): self.press_key(ecodes.KEY_PAGEDOWN, 'c', done=True)

        # esc + caps -> caps
        if self.matches_key(ev, ecodes.KEY_CAPSLOCK, 1, 'ep'): self.press_key(ecodes.KEY_CAPSLOCK, done=True)

        # Don't use capslock
        if ev.code == ecodes.KEY_CAPSLOCK: return # don't use capslock

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
