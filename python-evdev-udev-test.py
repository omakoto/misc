#!/usr/bin/python3

import sys
import pyudev
import evdev
from evdev import UInput, ecodes as e
import time
import selectors

DEVICE_NAME = "MOSART Semi. 2.4G Keyboard Mouse"

debug = True


def fatal(message):
    print(message, file=sys.stderr)
    sys.exit(1)


def wait_for_new_device():
    context = pyudev.Context()
    monitor = pyudev.Monitor.from_netlink(context)
    monitor.filter_by(subsystem='input')
    for action, device in monitor:
        if debug: print('{0}: {1}'.format(action, device))
        if action == "add":
            break
    time.sleep(2)

def read_loop(device_name):
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
        print(f"Device '{device_name}' not found.")
        return False

    try:
        selector = selectors.DefaultSelector()
        for d in devices:
            d.grab()
            selector.register(d, selectors.EVENT_READ)

        while True:
            for key, mask in selector.select():
                device = key.fileobj
                for ev in device.read():
                    print(f'Device: {device}  event: {ev}')
    except OSError as e:
        print(f'Device lost: {e}')
        return False


def main(args):
    while True:
        read_loop(DEVICE_NAME)
        wait_for_new_device()


if __name__ == '__main__':
    main(sys.argv[1:])