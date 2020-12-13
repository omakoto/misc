#!/usr/bin/python3
import argparse
import asyncio
import os
import random
import re
import selectors
import sys
import threading
import time
import traceback
from typing import Optional, Dict, List, TextIO, cast

import evdev
import gi
import notify2
import pyudev
from evdev import UInput, ecodes as e, ecodes

import singleton
import synced_uinput
import tasktray

gi.require_version('Gtk', '3.0')
from gi.repository import Gtk as gtk
gi.require_version('Wnck', '3.0')
from gi.repository import Wnck as wnck
from gi.repository import GLib as glib

NAME = "Test"
SCRIPT_PATH = os.path.dirname(os.path.realpath(__file__))
ICON = os.path.join(SCRIPT_PATH, 'trackpad.png')



def main(args):
    dev_matcher = re.compile('^(AT Translated Set 2 keyboard|UGEE TABLET TABLET KT01)')

    def on_device_readable(device:evdev.InputDevice, condition):
        print(f'# {device}')
        for ev in device.read():
            print(f'- {ev}')
        return True

    devices = {}
    for device in [evdev.InputDevice(path) for path in sorted(evdev.list_devices())]:
        use = dev_matcher.search(device.name)
        print(f'{"Using" if use else "  Not using"} device: {device}')
        if not use:
            continue

        tag = glib.io_add_watch(device , glib.IO_IN, on_device_readable)
        devices[device.path] = [tag]



    tray_icon = tasktray.QuittingTaskTrayIcon(NAME, ICON)
    tray_icon.run()


if __name__ == '__main__':
    main(sys.argv[1:])
