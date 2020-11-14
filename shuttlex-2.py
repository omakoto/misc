#!/usr/bin/python3
import argparse
import asyncio
import os
import sys
from threading import Thread
from typing import List, Optional, Dict

import evdev
import notify2

import tasktray
from key_remapper import main_loop, BaseRemapper

NAME = "ShuttleXpress media controller 2"
SCRIPT_PATH = os.path.dirname(os.path.realpath(__file__))
ICON = os.path.join(SCRIPT_PATH, 'knob.png')

DEFAULT_DEVICE_NAME = "Contour Design ShuttleXpress"

notify2.init(NAME)

class Remapper(BaseRemapper):

    def __init__(self, device_name_regex: str, match_non_keyboards=False, grab_devices=True,
                 write_to_uinput=True, uinput_events: Optional[Dict[int, List[int]]] = None,
                 global_lock_name: str = os.path.basename(sys.argv[0]), enable_debug=False):
        super().__init__(device_name_regex,
                         match_non_keyboards = True,
                         grab_devices = True,
                         write_to_uinput = True,
                         uinput_events = None,
                         global_lock_name = NAME,
                         enable_debug = enable_debug)

    def remap(self, device: evdev.InputDevice, events: List[evdev.InputEvent]
              ) -> List[evdev.InputEvent]:
        return super().remap(device, events)

    def on_device_detected(self, devices: List[evdev.InputDevice]):
        super().on_device_detected(devices)

    def on_device_lost(self):
        super().on_device_lost()

    def on_exception(self, exception: BaseException):
        super().on_exception(exception)

    def on_stop(self):
        super().on_stop()


def main(args, description=NAME):
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument('-m', '--match-device-name', metavar='D', default=DEFAULT_DEVICE_NAME,
                        help='Use devices matching this regex')
    parser.add_argument('-d', '--debug', action='store_true', help='Enable debug output')

    args = parser.parse_args(args)


    def do():
        # evdev will complain if the thread has no event loop set.
        asyncio.set_event_loop(asyncio.new_event_loop())

        main_loop(BaseRemapper(device_name_regex=args.match_device_name,
                               enable_debug=args.debug))

    th = Thread(target=do)
    th.setDaemon(True)
    th.start()

    tasktray.start_quitting_tray_icon(NAME, ICON)


if __name__ == '__main__':
    main(sys.argv[1:])
