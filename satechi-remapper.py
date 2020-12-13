#!/usr/bin/python3
import os
import sys
from typing import List

import evdev
from evdev import ecodes, InputEvent

import key_remapper2

NAME = "Satechi Media Buttons remapper"
SCRIPT_PATH = os.path.dirname(os.path.realpath(__file__))
ICON = os.path.join(SCRIPT_PATH, '10key.png')

DEFAULT_DEVICE_NAME = "^Satechi Media Button Consumer Control"

MAP = {
    ecodes.KEY_VOLUMEUP: ecodes.KEY_VOLUMEUP,
    ecodes.KEY_VOLUMEDOWN: ecodes.KEY_VOLUMEDOWN,
    ecodes.KEY_PLAYPAUSE: ecodes.KEY_SPACE,
    ecodes.KEY_PREVIOUSSONG: ecodes.KEY_LEFT,
    ecodes.KEY_NEXTSONG: ecodes.KEY_RIGHT,
}

class Remapper(key_remapper2.SimpleRemapper):
    def __init__(self):
        super().__init__(NAME, ICON, DEFAULT_DEVICE_NAME)

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


def main(args):
    remapper = Remapper()
    remapper.main(args)


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
