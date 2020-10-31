#!/usr/bin/python3

# Simulate "push-to-talk" by reading raw key input events
#
#   See https://bit.ly/37XRSuy for the details.
#
# Requires:
#   pip3 install evdev pyudev

import selectors
import sys
import time

import evdev
import pyudev
from evdev import UInput, ecodes as e

debug = False


# Wait for new input devices to be added.
def wait_for_new_device():
    context = pyudev.Context()
    monitor = pyudev.Monitor.from_netlink(context)
    monitor.filter_by(subsystem='input')
    for action, device in monitor:
        if debug: print('{0}: {1}'.format(action, device))
        if action == "add":
            break
    time.sleep(2)

# Main loop.
def read_loop(device_name, key_code):

    # Some devices registers multiple /dev/input/event* devices with the exact same name,
    # so let's read all of them.
    devices = []
    for n in range(10):
        devices = []
        for d in [evdev.InputDevice(path) for path in sorted(evdev.list_devices())]:
            if d.name == device_name:
                if debug: print(f'Device found: {d}')
                devices.append(d)
        if devices:
            break
        else:
            print(f"Device '{device_name}' not found, retrying...")
            time.sleep(1)

    if not devices:
        # Give up, fall back to waiting for udev new device events...
        print(f"Device '{device_name}' not found.")
        return False

    try:
        ui = UInput()

        selector = selectors.DefaultSelector()
        for d in devices:
            d.grab()
            selector.register(d, selectors.EVENT_READ)

        last_key_value = 0
        while True:
            for key, mask in selector.select():
                device = key.fileobj
                for ev in device.read():
                    if ev.type != e.EV_KEY: # ignore non-key events.
                        continue

                    if debug: print(f'Device: {device}  event: {ev}')

                    if ev.code == key_code: # push-to-talk key
                        if ev.value > 1:
                            continue # ignore repeat events

                        if ev.value != last_key_value:
                            last_key_value = ev.value

                            # Press the mute key and release it.
                            ui.write(e.EV_KEY, e.KEY_F20, 1)
                            ui.syn()
                            ui.write(e.EV_KEY, e.KEY_F20, 0)
                            ui.syn()
                        continue

                    # Pass-through all the key events (except for the ppt key).
                    ui.write(e.EV_KEY, ev.code, ev.value)
                    ui.syn()

    except OSError as ex:
        print(f'Device lost: {ex}')
        return False


def main(args):
    if len(args) < 2:
        print(f'Usage: {sys.argv[0]} DEVICE-NAME KEY-CODE', file=sys.stderr)
        sys.exit(1)

    while True:
        read_loop(args[0], int(args[1], 10))
        wait_for_new_device()


if __name__ == '__main__':
    main(sys.argv[1:])
