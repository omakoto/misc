#!/usr/bin/python3

# Library for a script to do "AHK"-ish key remapping.
# For now, only keyboards are supported, not mouse buttons.
#
# See makoto-key-remap.py for how to use it.

# Requires:
#   sudo pip3 install evdev pyudev
import argparse
import collections
import fcntl
import os
import random
import re
import selectors
import sys
import time
import threading

import evdev
import pyudev
import typing
from evdev import UInput, ecodes as e

debug = True

UINPUT_DEVICE_NAME_PREFIX = 'key-macro-uinput-'
UINPUT_DEVICE_NAME = f"{UINPUT_DEVICE_NAME_PREFIX}{int(time.time()*1000) :020}"


def null_remapper(
        device: evdev.InputDevice,
        events: typing.List[evdev.InputEvent]) -> typing.List[evdev.InputEvent]:
    return events

class deviceMonitor(threading.Thread):
    def __init__(self, new_device_detector_w):
        threading.Thread.__init__(self)
        self.w = new_device_detector_w

    def run(self):
        context = pyudev.Context()
        monitor = pyudev.Monitor.from_netlink(context)
        monitor.filter_by(subsystem='input')

        if debug: print('Device monitor started.')

        for action, device in monitor:
            if debug: print(f'udev: action={action} {device}')
            if action == "add":
                self.w.write(".\n")
                self.w.flush()


def start_device_monitor(new_device_detector_w):
    th = deviceMonitor(new_device_detector_w)
    th.setDaemon(True)
    th.start()


def is_syn(ev: evdev.InputEvent) -> bool:
    return ev and ev.type == e.EV_SYN and ev.code == e.SYN_REPORT and ev.value == 0

# Main loop.
def read_loop(ui, device_name_matcher, new_device_detector_r, remapper, match_all_devices=False):
    # Find all the keyboard devices. Ignore all the devices that support non-keyboard events.
    devices = []
    capabilities = []

    try:
        # Find the keyboard devices, except for the one that w  e created with /dev/uinput.
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

            # Make sure the device only supports key events -- i.e. ignore mice, trackpads, etc.
            # this is only for the sake of simplicity. It's possible to support these devices,
            # we need to propagete the right capabilities.
            # By default, python-uidev only make the device support key events.
            add = False
            caps = d.capabilities()
            for c in caps.keys():
                if match_all_devices:
                    add = True
                    break
                if match_all_devices or c not in (e.EV_SYN, e.EV_KEY, e.EV_MSC, e.EV_LED, e.EV_REP):
                    add = False
                    break
                if c == e.EV_KEY:
                    add = True

            if add:
                devices.append(d)
                capabilities.append(caps)

        if not devices:
            print("No keyboard devices found.")

        do_grab_devices = True # Only for debugging.

        key_states: typing.Dict[int, int] = collections.defaultdict(int) # Current state of each key

        # Start the main loop.
        try:
            # Prepare the selector, and also grab the devices.
            selector = selectors.DefaultSelector()
            selector.register(new_device_detector_r, selectors.EVENT_READ)

            for d in devices:
                print(f"Using device: {d}")
                if do_grab_devices:
                    try:
                        d.grab()
                    except:
                        print(f"  Unable to grab, skipping")
                        continue
                selector.register(d, selectors.EVENT_READ)

            # Before starting, drain the all the data new_device_detector_r.
            while new_device_detector_r.readline():
                pass

            # Start the loop.
            stop = False
            while not stop:
                for key, mask in selector.select():
                    device = key.fileobj

                    # See if a new device hsa been detected.
                    if device == new_device_detector_r:
                        print('A new device has been detected.')
                        # Wait a bit because udev sends multiple add events in a row.
                        time.sleep(random.uniform(1, 2))
                        stop = True
                        break

                    # Read all the queued events.
                    events = []
                    for ev in device.read():
                        events.append(ev)
                    if debug:
                        for ev in events:
                            if debug: print(f'-> Event: {ev}')

                    # Send all of them to remapper.
                    events = remapper(device, events)

                    if not ui:
                        continue

                    last_event = None
                    for ev in events:
                        if is_syn(ev) and is_syn(last_event):
                            # Don't send syn twice in a row.
                            # (Not sure if it matters but just in case.)
                            continue

                        # When sending a KEY event, only send what'd make sense given the current
                        # key state.
                        if ev.type == e.EV_KEY:
                            old_state = key_states[ev.code]
                            if ev.value == 0:
                                if old_state == 0: # Don't send if already released.
                                    continue
                            elif ev.value == 1:
                                if old_state > 0: # Don't send if already pressed.
                                    continue
                            elif ev.value == 2:
                                if old_state == 0: # Don't send if not pressed.
                                    continue

                            key_states[ev.code] = ev.value

                        if debug: print(f'Event -> : {ev}')
                        ui.write_event(ev)
                        last_event = ev

                    # If the last event isn't a syn, send one.
                    if not is_syn(last_event):
                        ui.syn()

        except OSError as ex:
            print(f'Device lost: {ex}')
            return False
        finally:
            if ui:
                # Release all pressed keys.
                try:
                    for key in key_states.keys():
                        if key_states[key] > 0:
                            ui.write(e.EV_KEY, key, 0)
                            ui.syn()
                except:
                    pass # ignore any exception
    finally:

        for d in devices:
            print(f"Releasing device: {d}")
            try:
                if do_grab_devices: d.ungrab()
            except:
                pass # Ignore any exception


def run(match_device_name, remapper, match_all_devices=False, no_output = False, force_debug=False,
        lock_global_name=os.path.basename(sys.argv[0])):
    global debug
    debug = force_debug

    # Prevent multiple instances.
    lockfile = f'/tmp/{lock_global_name}.lock'
    if debug:
        print(f'Lockfile: {lockfile}')
    try:
        os.umask(0o000)
        lock = open(lockfile, 'w')
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except IOError as err:
        raise SystemExit(f'Unable to obtain file lock {lockfile}')

    device_name_matcher = re.compile(match_device_name)

    ui = None
    if not no_output:
        # Create our /dev/uinput device.
        ui = UInput(name=UINPUT_DEVICE_NAME)
        if debug: print(f'Synthesized device name: {UINPUT_DEVICE_NAME}')

    # Create a worker thread that detects new devices.
    pipe_r, pipe_w = os.pipe()

    os.set_blocking(pipe_r, False)
    new_device_detector_r = os.fdopen(pipe_r)
    new_device_detector_w = os.fdopen(pipe_w, 'w')

    start_device_monitor(new_device_detector_w)

    while True:
        try:
            read_loop(ui, device_name_matcher, new_device_detector_r, remapper, match_all_devices)
        except BaseException as ex:
            print(f'Unhandled exception (retrying in 1 second): {ex}', file=sys.stderr)
            time.sleep(1)


def main(args, remapper=null_remapper, description="key remapper"):
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument('-m', '--match-device-name', metavar='D', default='', help='Only use devices matching this regex')
    parser.add_argument('-d', '--debug', action='store_true', help='Enable debug output')

    args = parser.parse_args(args)

    run(args.match_device_name, remapper, args.debug)


if __name__ == '__main__':
    main(sys.argv[1:])
