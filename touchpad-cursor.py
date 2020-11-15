#!/usr/bin/python3
import argparse
import asyncio
import os
import sys
import threading
from typing import List, Optional, Dict

import evdev
import notify2

import key_remapper
import synced_uinput
import tasktray

NAME = "ShuttleXpress media controller 2"
SCRIPT_PATH = os.path.dirname(os.path.realpath(__file__))
ICON = os.path.join(SCRIPT_PATH, 'knob.png')

DEFAULT_DEVICE_NAME = '^MOSART Semi. 2.4G Wireless Mouse$'

debug = False

notify2.init(NAME)


class TouchpadRemapper(key_remapper.BaseRemapper):

    def __init__(self, device_name_regex: str, id_regex: str = '', *, enable_debug=False,
            quiet=False):
        super().__init__(device_name_regex,
            id_regex=id_regex, match_non_keyboards=True, grab_devices=True,
            write_to_uinput=True, enable_debug=enable_debug, force_quiet=quiet)

        self.__notification = notify2.Notification(NAME, '')
        self.__notification.set_urgency(notify2.URGENCY_NORMAL)
        self.__notification.set_timeout(3000)

    def show_notification(self, message: str) -> None:
        self.__notification.update(NAME, message)
        self.__notification.show()

    def handle_events(self, device: evdev.InputDevice, events: List[evdev.InputEvent]) -> None:
        super().handle_events(device, events)

    def on_device_detected(self, devices: List[evdev.InputDevice]):
        self.show_notification('Device connected:\n'
                               + '\n'.join ('- ' + d.name for d in devices))

    def on_device_not_found(self):
        self.show_notification('Device not found')

    def on_device_lost(self):
        self.show_notification('Device lost')

    def on_exception(self, exception: BaseException):
        self.show_notification('Device lost')

    def on_stop(self):
        self.show_notification('Closing...')


def main(args, description=NAME):
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument('-m', '--match-device-name', metavar='D', default=DEFAULT_DEVICE_NAME,
        help='Use devices matching this regex')
    parser.add_argument('-i', '--match-id', metavar='D', default='',
        help='Use devices with info ("vXXX pXXX") matching this regex')
    parser.add_argument('-d', '--debug', action='store_true', help='Enable debug output')
    parser.add_argument('-q', '--quiet', action='store_true', help='Quiet mode')

    args = parser.parse_args(args)

    global debug
    debug = args.debug

    remapper = TouchpadRemapper(
        device_name_regex=args.match_device_name,
        id_regex=args.match_id,
        enable_debug=debug,
        quiet=args.quiet)

    def do():
        # evdev will complain if the thread has no event loop set.
        asyncio.set_event_loop(asyncio.new_event_loop())

        key_remapper.main_loop(remapper)

    th = threading.Thread(target=do)
    th.setDaemon(True)
    th.start()

    tasktray.start_quitting_tray_icon(NAME, ICON)


if __name__ == '__main__':
    main(sys.argv[1:])
