#!/usr/bin/python3
import argparse
import asyncio
import os
import sys
import threading
import traceback
from typing import List

import evdev
import notify2
from evdev import ecodes

import key_remapper
import tasktray

NAME = "Touchpad Cursor"
SCRIPT_PATH = os.path.dirname(os.path.realpath(__file__))
ICON = os.path.join(SCRIPT_PATH, 'trackpad.png')

DEFAULT_DEVICE_NAME = '^MOSART Semi. 2.4G Wireless Mouse$'

debug = False

notify2.init(NAME)


class TouchpadRemapper(key_remapper.BaseRemapper):
    sensitivity:float
    x: int
    y: int

    def __init__(self, device_name_regex: str, id_regex: str = '', *,
            sensitivity=1.0, enable_debug=False, quiet=False):
        super().__init__(device_name_regex,
            id_regex=id_regex, match_non_keyboards=True, grab_devices=True,
            write_to_uinput=True, enable_debug=enable_debug, force_quiet=quiet)

        self.__notification = notify2.Notification(NAME, '')
        self.__notification.set_urgency(notify2.URGENCY_NORMAL)
        self.__notification.set_timeout(3000)
        self.sensitivity = sensitivity
        self.x = 0
        self.y = 0

    def show_notification(self, message: str) -> None:
        self.__notification.update(NAME, message)
        self.__notification.show()

    def handle_events(self, device: evdev.InputDevice, events: List[evdev.InputEvent]) -> None:
        for ev in events:
            if ev.type == ecodes.EV_KEY:
                if ev.code == ecodes.BTN_LEFT and ev.value == 1:
                    self.press_key(ecodes.KEY_LEFT)
                    continue
                if ev.code == ecodes.BTN_RIGHT and ev.value == 1:
                    self.press_key(ecodes.KEY_RIGHT)
                    continue

            if ev.type != ecodes.EV_REL:
                continue
            if ev.code == ecodes.REL_X:
                self.x += ev.value
            elif ev.code == ecodes.REL_Y:
                self.y += ev.value

        while True:
            if self.x <= -self.sensitivity:
                self.press_key(ecodes.KEY_LEFT)
                self.x += self.sensitivity
            elif self.x >= self.sensitivity:
                self.press_key(ecodes.KEY_RIGHT)
                self.x -= self.sensitivity
            elif self.y <= -self.sensitivity:
                self.press_key(ecodes.KEY_UP)
                self.y += self.sensitivity
            elif self.y >= self.sensitivity:
                self.press_key(ecodes.KEY_DOWN)
                self.y -= self.sensitivity
            else:
                break

    def on_device_detected(self, devices: List[evdev.InputDevice]):
        self.show_notification('Device connected:\n'
                               + '\n'.join ('- ' + d.name for d in devices))

    def on_device_not_found(self):
        self.sthow_notification('Device not found')

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
    parser.add_argument('-s', '--sensitivity', metavar='S', type=float, default=32,
        help='Sensitivity; smaller value mean more sensitive')
    parser.add_argument('-d', '--debug', action='store_true', help='Enable debug output')
    parser.add_argument('-q', '--quiet', action='store_true', help='Quiet mode')

    args = parser.parse_args(args)

    global debug
    debug = args.debug

    remapper = TouchpadRemapper(
        device_name_regex=args.match_device_name,
        id_regex=args.match_id,
        sensitivity=args.sensitivity,
        enable_debug=debug,
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
    th.setDaemon(True)
    th.start()

    tasktray.start_quitting_tray_icon(NAME, ICON)


if __name__ == '__main__':
    main(sys.argv[1:])

# sample
# Event: time 1605411372.674160, type 2 (EV_REL), code 0 (REL_X), value 1
# Event: time 1605411372.674160, type 2 (EV_REL), code 1 (REL_Y), value -1
# Event: time 1605411372.674160, -------------- SYN_REPORT ------------
# Event: time 1605411375.670455, type 4 (EV_MSC), code 4 (MSC_SCAN), value 90001
# Event: time 1605411375.670455, type 1 (EV_KEY), code 272 (BTN_LEFT), value 1
# Event: time 1605411375.670455, -------------- SYN_REPORT ------------
# Event: time 1605411375.766465, type 4 (EV_MSC), code 4 (MSC_SCAN), value 90001
# Event: time 1605411375.766465, type 1 (EV_KEY), code 272 (BTN_LEFT), value 0
# Event: time 1605411375.766465, -------------- SYN_REPORT ------------
# Event: time 1605411376.110844, type 4 (EV_MSC), code 4 (MSC_SCAN), value 90002
# Event: time 1605411376.110844, type 1 (EV_KEY), code 273 (BTN_RIGHT), value 1
# Event: time 1605411376.110844, -------------- SYN_REPORT ------------
# Event: time 1605411376.222477, type 4 (EV_MSC), code 4 (MSC_SCAN), value 90002
# Event: time 1605411376.222477, type 1 (EV_KEY), code 273 (BTN_RIGHT), value 0
