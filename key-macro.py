#!/usr/bin/python3

# Requires:
#   sudo pip3 install evdev pyudev
import argparse
import os
import re
import selectors
import sys
import time

import evdev
import pyudev
from evdev import UInput, ecodes as e

debug = True


def do_remap(ui, device, ev):
    # ui.write(e.EV_KEY, ev.code, ev.value)
    # ui.syn()
    return False


# Wait for new input devices to be added.
def wait_for_new_device():
    print('Waiting for new devices...')
    context = pyudev.Context()
    monitor = pyudev.Monitor.from_netlink(context)
    monitor.filter_by(subsystem='input')
    for action, device in monitor:
        if debug: print('{0}: {1}'.format(action, device))
        if action == "add":
            break
    time.sleep(2)


# Main loop.
def read_loop(device_name_matcher):
    # Find all the keyboard devices. Ignore all the devices that support non-keyboard events.
    devices = []
    capabilities = []
    for d in [evdev.InputDevice(path) for path in sorted(evdev.list_devices())]:
        if debug:
            print(f'Device: {d}')
            print(f'  Capabilities: {d.capabilities(verbose=True)}')

        if not device_name_matcher.search(d.name):
            if debug: print(f'  Skipping {d.name}')
            continue

        add = False
        caps = d.capabilities()
        for c in caps.keys():
            if c not in (e.EV_SYN, e.EV_KEY, e.EV_MSC, e.EV_LED, e.EV_REP):
                add = False
                break
            if c == e.EV_KEY:
                add = True

        if add:
            devices.append(d)
            capabilities.append(caps)

    if not devices:
        print("No keyboard devices found.")
        return False

    do_grab_devices = True

    try:
        ui = UInput()

        selector = selectors.DefaultSelector()
        for d in devices:
            print(f"Using device: {d}")
            if do_grab_devices: d.grab()
            selector.register(d, selectors.EVENT_READ)

        while True:
            for key, mask in selector.select():
                device = key.fileobj
                for ev in device.read():
                    if ev.type != e.EV_KEY:
                        continue
                    if debug: print(f'Device: {device}  event: {ev}')

                    if ev.type in (e.EV_KEY, e.EV_REP): # Only intercept key events.
                        if do_remap(ui, device, ev):
                            continue

                    ui.write_event(ev)
                    ui.syn()

    except OSError as ex:
        print(f'Device lost: {ex}')
        return False


def main(args):
    parser = argparse.ArgumentParser(description='ShuttleXPress key remapper')
    parser.add_argument('-m', '--match-device-name', metavar='D', default='', help='Only use devices matching this regex')
    parser.add_argument('-d', '--debug', action='store_true', help='Enable debug output')

    args = parser.parse_args()

    global debug
    debug = args.debug

    device_name_matcher = re.compile(args.match_device_name)

    while True:
        try:
            read_loop(device_name_matcher)
            wait_for_new_device()
        except BaseException as ex:
            print(f'Unhandled exception (retrying in 1 second): {ex}', file=sys.stderr)
            time.sleep(1)


if __name__ == '__main__':
    main(sys.argv[1:])
