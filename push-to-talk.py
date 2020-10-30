#!/usr/bin/python3

# Simulate "push-to-talk" by reading raw key input events
# See https://bit.ly/37XRSuy for the details.

# Requires python-evdev. Install with: pip3 install evdev

import sys
import time

import evdev
from evdev import UInput, ecodes as e

debug = False


def fatal(message):
    print(message, file=sys.stderr)
    sys.exit(1)


def run_remap(device_name, key_code):
    # Open the input device.
    device = None

    for n in range(10):
        for d in [evdev.InputDevice(path) for path in evdev.list_devices()]:
            if d.name == device_name:
                device = d
                break
        if device:
            break
        else:
            print(f"Device '{device_name}' not found, retrying...")
            time.sleep(1)

    # Open /dev/uinput.
    ui = UInput()

    if not device:
        fatal(f"Device '{device_name}' not found.")

    device.grab()

    if debug: print(f"Starting...")

    last_value = 0
    for ev in device.read_loop():
        if debug: print(f'Input: {ev}')

        if ev.type != e.EV_KEY:
            continue

        # Pass-through the F20 key.
        if ev.code == e.KEY_F20 and ev.value == 1:
            ui.write(e.EV_KEY, e.KEY_F20, 1)
            ui.write(e.EV_KEY, e.KEY_F20, 0)
            ui.syn()
            continue

        if ev.code == key_code and ev.value != last_value and ev.value <= 1:
            last_value = ev.value

            ui.write(e.EV_KEY, e.KEY_F20, 1)
            ui.write(e.EV_KEY, e.KEY_F20, 0)
            ui.syn()
            continue


def main(args):
    if len(args) < 2:
        print(f'Usage: {sys.argv[0]} DEVICE-NAME KEY-CODE', file=sys.stderr)
        sys.exit(1)

    run_remap(args[0], int(args[1], 10))


if __name__ == '__main__':
    main(sys.argv[1:])
