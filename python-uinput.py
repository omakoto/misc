#!/usr/bin/python3

# Uinput test. Need python-evdev to run.
# sudo pip3 install evdev

import sys
from evdev import UInput, ecodes as e

ui = UInput(name='uinput-test')

# Toggle mute and press the "1" key every time [enter] is pressed.

for s in sys.stdin:
    print('Toggle mute!')
    ui.write(e.EV_KEY, e.KEY_F20, 1)
    ui.syn()
    ui.write(e.EV_KEY, e.KEY_F20, 0)
    ui.syn()
    print('Write "1"')
    ui.write(e.EV_KEY, e.KEY_1, 1)
    ui.syn()
    ui.write(e.EV_KEY, e.KEY_1, 0)
    ui.syn()
