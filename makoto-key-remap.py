#!/usr/bin/python3

# Remap keys using keymacroer. Sample code.
import typing

import keymacroer
import sys
import evdev
from evdev import UInput, ecodes as e


def remapper(
        device: evdev.InputDevice,
        events: typing.List[evdev.InputEvent]) -> typing.List[evdev.InputEvent]:
    ret = []
    for ev in events:
        if ev.type == e.EV_KEY:
            if ev.code == e.KEY_CAPSLOCK:
                # Intercept a capslock key press, and toggle mic-mute.
                if ev.value == 1: # Only handle key-down.
                    ret.append(evdev.InputEvent(0, 0, e.EV_KEY, e.KEY_F20, 1))
                    ret.append(evdev.InputEvent(0, 0, e.EV_KEY, e.KEY_F20, 0))
            else:
                # Pass through other keys.
                ret.append(evdev.InputEvent(0, 0, e.EV_KEY, ev.code, ev.value))
    return ret

if __name__ == '__main__':
    keymacroer.main(sys.argv[1:], remapper, 'Key remapper')
