#!/usr/bin/python3

# Requires:
#   sudo pip3 install evdev pyudev
import argparse
import os
import re
import selectors
import sys
import time
import threading

import evdev
import pyudev
from evdev import UInput, ecodes as e

debug = True

UINPUT_DEVICE_NAME = "key-macro-uinput"


def null_remapper(ui, device, event):
    pass
    return False


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


# Main loop.
def read_loop(ui, device_name_matcher, new_device_detector_r, remapper):
    # Find all the keyboard devices. Ignore all the devices that support non-keyboard events.
    devices = []
    capabilities = []

    try:
        # Find the keyboard devices, except for the one that we created with /dev/uinput.
        for d in [evdev.InputDevice(path) for path in sorted(evdev.list_devices())]:
            if d.name == UINPUT_DEVICE_NAME: # This is our own /dev/uinput device.
                continue

            if debug:
                print(f'Device: {d}')
                print(f'  Capabilities: {d.capabilities(verbose=True)}')

            # Reject the ones that don't match the name filter.
            if not device_name_matcher.search(d.name):
                if debug: print(f'  Skipping {d.name}')
                continue

            # Make sure the device only supports key events -- i.e. ignore mice, trackpads, etc.
            # this is only for the sake of simplicity. It's possible to support these devices, but
            # intercepting only the interesting events and pass-throughing the rest would be hard.
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

        do_grab_devices = True

        # Start the main loop.
        try:
            # Prepare the selector, and also grab the devices.
            selector = selectors.DefaultSelector()
            selector.register(new_device_detector_r, selectors.EVENT_READ)

            for d in devices:
                print(f"Using device: {d}")
                if do_grab_devices: d.grab()
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
                        time.sleep(1) # Wait a bit because udev sends multiple add events in a row.
                        stop = True
                        break

                    for ev in device.read():
                        if ev.type != e.EV_KEY:
                            continue
                        if debug: print(f'Device: {device}  event: {ev}')

                        if ev.type in (e.EV_KEY, e.EV_REP): # Only intercept key events.
                            if remapper(ui, device, ev):
                                continue

                        ui.write_event(ev)
                        ui.syn()

        except OSError as ex:
            print(f'Device lost: {ex}')
            return False
    finally:
        for d in devices:
            print(f"Releasing device: {d}")
            try:
                if do_grab_devices: d.ungrab()
            except:
                pass # Ignore any exception


def main(args, remapper):
    parser = argparse.ArgumentParser(description='ShuttleXPress key remapper')
    parser.add_argument('-m', '--match-device-name', metavar='D', default='', help='Only use devices matching this regex')
    parser.add_argument('-d', '--debug', action='store_true', help='Enable debug output')

    args = parser.parse_args()

    global debug
    debug = args.debug

    device_name_matcher = re.compile(args.match_device_name)

    # Create our /dev/uinput device.
    ui = UInput(name=UINPUT_DEVICE_NAME)

    # Create a worker thread that detects new devices.
    pipe_r, pipe_w = os.pipe()

    os.set_blocking(pipe_r, False)
    new_device_detector_r = os.fdopen(pipe_r)
    new_device_detector_w = os.fdopen(pipe_w, 'w')

    start_device_monitor(new_device_detector_w)

    if not remapper:
        remapper = null_remapper

    while True:
        try:
            read_loop(ui, device_name_matcher, new_device_detector_r, remapper)
        except BaseException as ex:
            print(f'Unhandled exception (retrying in 1 second): {ex}', file=sys.stderr)
            time.sleep(1)


if __name__ == '__main__':
    main(sys.argv[1:], None)
