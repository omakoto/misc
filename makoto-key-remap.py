#!/usr/bin/python3

# Remap keys using keymacroer.

import keymacroer
import sys
import evdev
from evdev import UInput, ecodes as e


def remapper(ui: UInput, device: evdev.InputDevice, ev: evdev.InputEvent):
    if ev.code == e.KEY_DELETE:
        if ev.value == 1:
            ui.write(e.EV_KEY, e.KEY_F20, 1)
            ui.syn()
            ui.write(e.EV_KEY, e.KEY_F20, 0)
            ui.syn()
        return True
    return False


if __name__ == '__main__':
    keymacroer.main(sys.argv[1:], remapper, 'Key remapper')
