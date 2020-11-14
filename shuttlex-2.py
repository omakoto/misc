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

debug = False


class Remapper(BaseRemapper):

    def __init__(self, device_name_regex: str, enable_debug=False):
        super().__init__(device_name_regex,
            match_non_keyboards=True,
            grab_devices=True,
            write_to_uinput=True,
            enable_debug=enable_debug)
        self.device_notification = notify2.Notification(NAME, '')
        self.device_notification.set_urgency(notify2.URGENCY_NORMAL)
        self.device_notification.set_timeout(3000)

    def show_device_notification(self, message: str) -> None:
        if debug: print(message)
        self.device_notification.update(NAME, message)
        self.device_notification.show()

    def remap(self, device: evdev.InputDevice, events: List[evdev.InputEvent]) \
            -> List[evdev.InputEvent]:
        return super().remap(device, events)

    def on_device_detected(self, devices: List[evdev.InputDevice]):
        self.show_device_notification('Device connected:\n'
                + '\n'.join ('- ' + d.name for d in devices))

    def on_device_not_found(self):
        self.show_device_notification('Device not found')

    def on_device_lost(self):
        self.show_device_notification('Device lost')

    def on_exception(self, exception: BaseException):
        self.show_device_notification('Device lost')

    def on_stop(self):
        self.show_device_notification('Closing...')


def main(args, description=NAME):
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument('-m', '--match-device-name', metavar='D', default=DEFAULT_DEVICE_NAME,
        help='Use devices matching this regex')
    parser.add_argument('-d', '--debug', action='store_true', help='Enable debug output')

    args = parser.parse_args(args)

    global debug
    debug = args.debug

    remapper = Remapper(device_name_regex=args.match_device_name, enable_debug=debug)

    def do():
        # evdev will complain if the thread has no event loop set.
        asyncio.set_event_loop(asyncio.new_event_loop())

        main_loop(remapper)

    th = Thread(target=do)
    th.setDaemon(True)
    th.start()

    tasktray.start_quitting_tray_icon(NAME, ICON)


if __name__ == '__main__':
    main(sys.argv[1:])
