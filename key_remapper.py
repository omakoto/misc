#!/usr/bin/python3
import argparse
import collections
import os
import re
import sys
import time
from typing import Optional, Dict, List

import evdev
from evdev import UInput, ecodes as e

import singleton

debug = False

UINPUT_DEVICE_NAME_PREFIX = 'key-remapper-uinput-'
UINPUT_DEVICE_NAME = f"{UINPUT_DEVICE_NAME_PREFIX}{int(time.time()*1000) :020}"


class BaseRemapper:
    pass


class NullRemapper(BaseRemapper):
    pass


def find_devices(
        device_name_regex: str,
        match_non_keyboards=False,
        grab_devices=True,
        ) -> [List[evdev.InputDevice], Optional[Dict[int, List[int]]]]:
    devices = []
    all_capabilities = []

    device_name_matcher = re.compile(device_name_regex)

    # Find the keyboard devices, except for the one that we created with /dev/uinput.
    for d in [evdev.InputDevice(path) for path in sorted(evdev.list_devices())]:
        # Ignore our own device, and "any younger" devices.
        if d.name.startswith(UINPUT_DEVICE_NAME_PREFIX) and d.name >= UINPUT_DEVICE_NAME:
            continue

        if debug:
            print(f'Device: {d}')
            print(f'  Capabilities: {d.capabilities(verbose=True)}')

        # Reject the ones that don't match the name filter.
        if not device_name_matcher.search(d.name):
            if debug: print(f'  Skipping {d.name}')
            continue

        add = False
        caps = d.capabilities()
        if match_non_keyboards:
            add = True
        else:
            for c in caps.keys():
                if c not in (e.EV_SYN, e.EV_KEY, e.EV_MSC, e.EV_LED, e.EV_REP):
                    add = False
                    break
                if c == e.EV_KEY:
                    add = True

        if add:
            print(f"Using device: {d}")
            if grab_devices:
                try:
                    d.grab()
                except:
                    print(f"  Unable to grab, skipping")
                    continue
            devices.append(d)
            all_capabilities.append(caps)

    if not devices:
        print("No keyboard devices found.")

    return [devices, all_capabilities]


def main_loop(
        device_name_regex: str,
        match_non_keyboards=False,
        grab_devices=True,
        write_to_uinput=False,
        global_lock_name:str=os.path.basename(sys.argv[0]),
        debug=False,
        events: Optional[Dict[int, List[int]]]=None,
        ) -> None:

    singleton.ensure_singleton(global_lock_name, debug=debug)

    ui = None
    if write_to_uinput:
        # Create our /dev/uinput device.
        ui = UInput(name=UINPUT_DEVICE_NAME, events=events)
        if debug: print(f'Uinput device name: {UINPUT_DEVICE_NAME}')

    devices, all_capabilities = find_devices(device_name_regex, match_non_keyboards,
                                             grab_devices)


def main(args, description="key remapper test"):
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument('-m', '--match-device-name', metavar='D', default='',
                        help='Only use devices matching this regex')
    parser.add_argument('-d', '--debug', action='store_true', help='Enable debug output')

    args = parser.parse_args(args)


    main_loop(args.match_device_name, match_non_keyboards=False, grab_devices=True,
              write_to_uinput=True, global_lock_name="key_remapper_test",
              debug=args.debug, events=None)


if __name__ == '__main__':
    main(sys.argv[1:])
