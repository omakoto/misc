#!/usr/bin/python3
import argparse
import asyncio
import math
import os
import sys
import threading
import time
import traceback
from typing import List, Optional

import evdev
import notify2
from evdev import ecodes

import key_remapper
import synced_uinput
import tasktray

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

class ShuttlexRemapper(key_remapper.BaseRemapper):
    __lock: threading.RLock
    __wheel_thread: threading.Thread

    def __init__(self, device_name_regex: str, *, enable_debug=False, quiet=False):
        super().__init__(device_name_regex,
            id_regex='',
            match_non_keyboards=True,
            grab_devices=True,
            write_to_uinput=True,
            enable_debug=enable_debug)
        self.__quiet = quiet
        self.__notification = notify2.Notification(NAME, '')
        self.__notification.set_urgency(notify2.URGENCY_NORMAL)
        self.__notification.set_timeout(5000)
        self.__lock = threading.RLock()
        self.__wheel_pos = 0
        self.__wheel_thread = threading.Thread(name='wheel-thread', target=self.__handle_wheel)
        self.__wheel_thread.setDaemon(True)
        self.__jog_mode = 0 # left / right keys
        self.__wheel_mode = 1 # vol up/down keys
        self.__button1_pressed = False
        self.__last_dial = 0

    # Thread safe
    def __set_wheel_pos(self, pos: int) -> None:
        with self.__lock:
            self.__wheel_pos = pos

    # Thread safe
    def __get_wheel_pos(self) -> int:
        with self.__lock:
            return self.__wheel_pos

    # Thread safe
    def __get_jog_mode(self):
        with self.__lock:
            return KEY_MODES[self.__jog_mode]

    # Thread safe
    def __get_wheel_mode(self):
        with self.__lock:
            return KEY_MODES[self.__wheel_mode]

    # Thread safe
    def __toggle_jog_mode(self):
        with self.__lock:
            self.__jog_mode = get_next_key_mode(self.__jog_mode)

    # Thread safe
    def __toggle_wheel_mode(self):
        with self.__lock:
            self.__wheel_mode = get_next_key_mode(self.__wheel_mode)

    def on_initialize(self):
        self.__wheel_thread.start()
        self.show_help()

    def show_notification(self, message: str) -> None:
        if debug: print(message)
        self.__notification.update(NAME, message)
        self.__notification.show()

    def show_help(self):
        key4 = 'KEY_F' if self.__button1_pressed else 'KEY_F11'
        key2 = 'Toggle Dial' if self.__button1_pressed else 'Toggle Jog'

        help = (f'[ALT] [{key2}] [KEY_SPACE] [{key4}] [KEY_MUTE]\n' +
                f'  Jog mode : {self.__get_jog_mode()[2]}\n' +
                f'  Dial mode: {self.__get_wheel_mode()[2]}')

        if not self.__quiet:
            print(help)

        self.show_notification(help)

    def handle_events(self, device: evdev.InputDevice, events: List[evdev.InputEvent]):
        for ev in events:
            if debug: print(f'Input: {ev}')

            if ev.type == ecodes.EV_KEY:
                key = None
                value = 0

                # Remap the buttons.
                if ev.code == ecodes.BTN_4: # button 1 pressed
                    self.__button1_pressed = ev.value == 1
                    self.show_help()
                if ev.code == ecodes.BTN_5 and ev.value == 0: # toggle jog/dial mode
                    if self.__button1_pressed:
                        self.__toggle_wheel_mode()
                    else:
                        self.__toggle_jog_mode()
                    self.show_help()
                elif ev.code == ecodes.BTN_6 and ev.value == 0: # button 2 -> space
                    key = ecodes.KEY_SPACE
                elif ev.code == ecodes.BTN_7 and ev.value == 0: # button 4 -> F11
                    if self.__button1_pressed:
                        key = ecodes.KEY_F
                    else:
                        key = ecodes.KEY_F11
                elif ev.code == ecodes.BTN_8 and ev.value == 0: # button 5 -> mute
                    key = ecodes.KEY_MUTE

                if key:
                    self.press_key(key)
                continue

            # Handle the dial
            if ev.type == ecodes.EV_REL and ev.code == ecodes.REL_DIAL:
                now_dial = ev.value
                delta = now_dial - self.__last_dial
                self.__last_dial = now_dial

                key = 0
                if delta < 0:
                    key = self.__get_wheel_mode()[0]
                if delta > 0:
                    key = self.__get_wheel_mode()[1]

                if key != 0:
                    self.press_key(key)

            # Handle the jog
            if ev.type == ecodes.EV_REL and ev.code == ecodes.REL_WHEEL:
                self.__set_wheel_pos(ev.value)

    def __handle_wheel(self):
        jog_multiplier = 1.0

        sleep_duration = 0.1

        while True:
            time.sleep(sleep_duration)
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

            self.press_key(key)

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
    parser.add_argument('-d', '--debug', action='store_true', help='Enable debug output')
    parser.add_argument('-q', '--quiet', action='store_true', help='Quiet mode')

    args = parser.parse_args(args)

    global debug
    debug = args.debug

    remapper = ShuttlexRemapper(device_name_regex=args.match_device_name, enable_debug=debug,
            quiet=args.quiet)

    def do():
        # evdev will complain if the thread has no event loop set.
        asyncio.set_event_loop(asyncio.new_event_loop())
        try:
            key_remapper.start_remapper(remapper)
        except BaseException as e:
            traceback.print_exc()
            tasktray.quit()

    th = threading.Thread(target=do)
    th.start()

    tasktray.start_quitting_tray_icon(NAME, ICON)
    key_remapper.stop_remapper()


if __name__ == '__main__':
    main(sys.argv[1:])
