#!/usr/bin/python3

# Install python-evdev:
#   python-evdev: git@github.com:gvalkov/python-evdev.git
#   pip3 install --user evdev

import sys
import evdev
import argparse

DEFAULT_DEVICE_NAME = "Contour Design ShuttleXpress"

debug = False

def fatal(message):
    print(message, file=sys.stderr)
    sys.exit(1)

def main(args):
    parser = argparse.ArgumentParser(description='FFT example with sox + numpy')
    parser.add_argument('--device-name', metavar='D', default=DEFAULT_DEVICE_NAME, help='Device name shown by evtest(1)')
    parser.add_argument('-d', '--debug', action='store_true', help='Enable debug output')

    args = parser.parse_args()

    global debug
    debug = args.debug

    device_name = args.device_name

    device = None
    for d in [evdev.InputDevice(path) for path in evdev.list_devices()]:
        if d.name == device_name:
            device = d
            break

    if not device:
        fatal(f"Device '{device_name}' not found.")

    device.grab()

    for event in device.read_loop():
        print(f'Input: {event}')

if __name__ == '__main__':
    main(sys.argv[1:])
