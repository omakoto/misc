#!/usr/bin/python3
import argparse
import asyncio
import math
import os
import sys
import threading
from threading import Thread
from typing import List, Optional, Dict

import evdev
import notify2
from evdev import ecodes

import synced_uinput
import tasktray
from key_remapper import main_loop, BaseRemapper

NAME = "ShuttleXpress media controller 2"
SCRIPT_PATH = os.path.dirname(os.path.realpath(__file__))
ICON = os.path.join(SCRIPT_PATH, 'knob.png')

DEFAULT_DEVICE_NAME = "Contour Design ShuttleXpress"

notify2.init(NAME)

debug = False

LEFT_RIGHT_KEYS = [ecodes.KEY_LEFT, ecodes.KEY_RIGHT, 'Left/Right']
VOLUME_KEYS = [ecodes.KEY_VOLUMEDOWN, ecodes.KEY_VOLUMEUP, 'VolUp/Down']
UP_DOWN_KEYS = [ecodes.KEY_UP, ecodes.KEY_DOWN, 'Up/Down']
KEY_MODES = [LEFT_RIGHT_KEYS, UP_DOWN_KEYS, VOLUME_KEYS]


def get_next_key_mode(mode: int) -> int:
    return (mode + 1) % len(KEY_MODES)

class ShuttlexRemapper(BaseRemapper):
    uinput: synced_uinput.SyncedUinput
    __lock: threading.RLock
    __wheel_thread: threading.Thread

    def __init__(self, device_name_regex: str, enable_debug=False):
        super().__init__(device_name_regex,
            match_non_keyboards=True,
            grab_devices=True,
            write_to_uinput=True,
            enable_debug=enable_debug)
        self.device_notification = notify2.Notification(NAME, '')
        self.device_notification.set_urgency(notify2.URGENCY_NORMAL)
        self.device_notification.set_timeout(3000)
        self.__lock = threading.RLock
        self.__wheel_pos = 0
        self.__wheel_thread = threading.Thread(name='wheel-thread', target=self.__handle_wheel)
        self.__wheel_thread.setDaemon(True)
        self.__jog_mode = 0 # left / right keys
        self.__wheel_mode = 1 # vol up/down keys

    def __set_wheel_pos(self, pos: int) -> None:
        with self.__lock:
            self.__wheel_pos = pos

    def __get_wheel_pos(self) -> int:
        with self.__lock:
            return self.__wheel_pos

    def __get_jog_mode(self):
        with self.__lock:
            return KEY_MODES[self.__jog_mode]

    def __get_wheel_mode(self):
        with self.__lock:
            return KEY_MODES[self.__wheel_mode]

    def __toggle_jog_mode(self):
        with self.__lock:
            self.__jog_mode = get_next_key_mode(self.__jog_mode)

    def __toggle_wheel_mode(self):
        with self.__lock:
            self.__wheel_mode = get_next_key_mode(self.__wheel_mode)

    def on_initialize(self, ui: Optional[synced_uinput.SyncedUinput]):
        self.uinput = ui
        self.__wheel_thread.start()

    def show_device_notification(self, message: str) -> None:
        if debug: print(message)
        self.device_notification.update(NAME, message)
        self.device_notification.show()

    def handle_events(self, device: evdev.InputDevice, events: List[evdev.InputEvent]):
        print(f'-> Event: {events}')

    def __handle_wheel(self):
        jog_multiplier = 1.0

        sleep_duration = 0.1

        while True:
            threading.sleep(sleep_duration)
            sleep_duration = 0.1

            current_wheel = self.__get_wheel_pos()

            # -7 <= current_wheel <= 7 is the range.
            if -1 <= current_wheel <= 1:
                continue

            if debug: print(f'Wheel={current_wheel}')

            key = 0
            count = 0
            keys = self.__get_jog_mode()
            if current_wheel < 0:
                key = keys[0]
                count = -current_wheel
            elif current_wheel > 0:
                key = keys[1]
                count = current_wheel

            # Special case the small angles. Always make a single key event, and
            # don't repeat too fast.

            # range will be [1 - 7] * multiplier
            count = count - 1
            speed = math.pow(count, 2) + 1 # range 2 -
            sleep_duration = 0.8 / (jog_multiplier * speed)
            # print(f'{count}, {sleep_duration}')

            self.uinput.write([
                evdev.InputEvent(0, 0, ecodes.EV_KEY, key, 1),
                evdev.InputEvent(0, 0, ecodes.EV_KEY, key, 0),
            ])

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

    remapper = ShuttlexRemapper(device_name_regex=args.match_device_name, enable_debug=debug)

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
