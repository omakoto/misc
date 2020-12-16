#!/usr/bin/python3
import argparse
import asyncio
import collections
import os
import random
import re
import selectors
import sys
import threading
import time
import traceback
from typing import Optional, Dict, List, TextIO, cast, Tuple, Union

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

debug = False
quiet = False

UINPUT_DEVICE_NAME_PREFIX = 'key-remapper-uinput-'
UINPUT_DEVICE_NAME = f"{UINPUT_DEVICE_NAME_PREFIX}{int(time.time() * 1000) :020}-{random.randint(0, 1000000) :06}"


class BaseRemapper(object):
    uinput: synced_uinput.SyncedUinput

    device_name_regex: str
    id_regex: str

    def __init__(self,
            device_name_regex: str,
            *,
            id_regex = '',
            match_non_keyboards = False,
            grab_devices = True,
            write_to_uinput = True,
            uinput_events: Optional[Dict[int, List[int]]] = None,
            global_lock_name: str = os.path.basename(sys.argv[0]),
            enable_debug = False,
            force_quiet = False):
        self.device_name_regex = device_name_regex
        self.id_regex = id_regex
        self.match_non_keyboards = match_non_keyboards
        self.grab_devices = grab_devices
        self.write_to_uinput = write_to_uinput
        self.uinput_events = uinput_events
        self.global_lock_name = global_lock_name
        self.enable_debug = enable_debug
        self.force_quiet = force_quiet

    def on_initialize(self):
        if debug:
            print(f'on_initialize')

    def handle_events(self, device: evdev.InputDevice, events: List[evdev.InputEvent]) -> None:
        pass

    def on_device_detected(self, devices: List[evdev.InputDevice]):
        if debug:
            print(f'on_device_detected: {devices}')

    def on_device_not_found(self):
        if debug:
            print('on_device_not_found')

    def on_device_lost(self):
        if debug:
            print('on_device_lost:')

    def on_exception(self, exception: BaseException):
        if debug:
            print(f'on_exception: {exception}')

    def on_stop(self):
        if debug:
            print('on_stop:')


def die_on_exception(func):
    def wrapper(*args, **kwargs):
        try:
            func(*args, **kwargs)
        except:
            traceback.print_exc()
            sys.exit(1)

    return wrapper

class SimpleRemapper(BaseRemapper ):
    tray_icon: tasktray.TaskTrayIcon
    __devices: Dict[str, Tuple[evdev.InputDevice, int]]
    __orig_key_states: Dict[int, int] = collections.defaultdict(int)

    def __init__(self,
                 remapper_name: str,
                 remapper_icon: str,
                 device_name_regex: str,
                 *,
                 id_regex = '',
                 match_non_keyboards = True,
                 grab_devices = True,
                 write_to_uinput = True,
                 uinput_events: Optional[Dict[int, List[int]]] = None,
                 global_lock_name: str = os.path.basename(sys.argv[0]),
                 enable_debug = False,
                 force_quiet = False):
        super().__init__(device_name_regex,
                         id_regex=id_regex,
                         match_non_keyboards=match_non_keyboards,
                         grab_devices=grab_devices,
                         write_to_uinput=write_to_uinput,
                         uinput_events=uinput_events,
                         global_lock_name=global_lock_name,
                         enable_debug=enable_debug,
                         force_quiet=force_quiet)
        self.remapper_name = remapper_name
        self.remapper_icon = remapper_icon
        self.__quiet = force_quiet
        self.__notification = notify2.Notification(remapper_name, '')
        self.__notification.set_urgency(notify2.URGENCY_NORMAL)
        self.__notification.set_timeout(3000)
        self.__mode = 0
        self.__devices = {}
        self.tray_icon = tasktray.QuittingTaskTrayIcon(self.remapper_name, self.remapper_icon)

    def show_notification(self, message: str) -> None:
        if self.enable_debug: print(message)
        self.__notification.update(self.remapper_name, message)
        self.__notification.show()

    def on_device_detected(self, devices: List[evdev.InputDevice]):
        self.show_notification('Device connected:\n'
                               + '\n'.join('- ' + d.name for d in devices))

    def on_device_not_found(self):
        self.show_notification('Device not found')

    def on_device_lost(self):
        self.show_notification('Device lost')

    def on_exception(self, exception: BaseException):
        self.show_notification('Device lost')

    def on_stop(self):
        self.show_notification('Closing...')

    def on_init_arguments(self, parser):
        pass

    def on_arguments_parsed(self, args):
        pass

    def get_active_window(self) -> Tuple[str, str]: # title, class
        screen = wnck.Screen.get_default()
        screen.force_update()
        w = screen.get_active_window()

        return (w.get_name(), w.get_class_instance_name())

    def __parse_args(self, args):
        parser = argparse.ArgumentParser(description=self.remapper_name)
        parser.add_argument('-m', '--match-device-name', metavar='D', default=self.device_name_regex,
                            help='Use devices matching this regex')
        parser.add_argument('-d', '--debug', action='store_true', help='Enable debug output')
        parser.add_argument('-q', '--quiet', action='store_true', help='Quiet mode')

        self.on_init_arguments(parser)

        args = parser.parse_args(args)

        self.device_name_regex = args.match_device_name
        self.enable_debug = args.debug
        self.force_quiet = args.quiet

        global debug, quiet
        debug = self.enable_debug
        quiet = self.force_quiet

        self.on_arguments_parsed(args)

    def __start_udev_monitor(self) -> TextIO:
        """Returns udev event names, such as 'add' and 'remove'.
        """
        pr, pw = os.pipe()
        os.set_blocking(pr, False)
        reader = os.fdopen(pr)
        writer = os.fdopen(pw, 'w')

        def run():
            try:
                context = pyudev.Context()
                monitor = pyudev.Monitor.from_netlink(context)
                monitor.filter_by(subsystem='input')
                if debug: print('Device monitor started.')

                for action, device in monitor:
                    if debug: print(f'udev: action={action} {device}')
                    writer.writelines(action)
                    writer.flush()
            except:
                traceback.print_exc()
                sys.exit(1)

        th = threading.Thread(target=run)
        th.setDaemon(True)
        th.start()

        return reader

    def __release_devices(self):
        if not self.__devices:
            return
        if debug: print('# Releasing devices...')
        for path, t in self.__devices.items():
            if debug: print(f'  Releasing {path}')
            glib.source_remove(t[1])
            try:
                t[0].ungrab()
            except IOError: pass # ignore
            try:
                t[0].close()
            except IOError: pass # ignore

    def __open_devices(self):
        self.__release_devices()

        if debug: print('# Detecting devices...')

        device_name_matcher = re.compile(self.device_name_regex)
        id_matcher = re.compile(self.id_regex)

        for device in [evdev.InputDevice(path) for path in sorted(evdev.list_devices())]:
            if device.name.startswith(UINPUT_DEVICE_NAME_PREFIX) and device.name >= UINPUT_DEVICE_NAME:
                continue

            id_info = f'v{device.info.vendor :04x} p{device.info.product :04x}'
            if debug:
                print(f'Device: {device} / {id_info}')
                print(f'  Capabilities: {device.capabilities(verbose=True)}')

            # Reject the ones that don't match the name filter.
            if not (device_name_matcher.search(device.name) and id_matcher.search(id_info)):
                if debug: print(f'  Skipping {device.name}')
                continue

            add = False
            caps = device.capabilities()
            if self.match_non_keyboards:
                add = True
            else:
                for c in caps.keys():
                    if c not in (e.EV_SYN, e.EV_KEY, e.EV_MSC, e.EV_LED, e.EV_REP):
                        add = False
                        break
                    if c == e.EV_KEY:
                        add = True

            if add and self.grab_devices:
                try:
                    device.grab()
                except IOError:
                    if not quiet: print(f'Unable to grab {device.path}', file=sys.stderr)

            if add:
                if debug: print(f"Using device: {device}")
            else:
                try:
                    device.close()
                except IOError: pass
                continue

            tag = glib.io_add_watch(device, glib.IO_IN, self.__on_input_event)
            self.__devices[device.path] = [device, tag]

        if self.__devices:
            self.on_device_detected([t[0] for t in self.__devices.values()])
        else:
            self.on_device_not_found()

    # @die_on_exception
    def __on_udev_event(self, udev_monitor: TextIO , condition):
        if udev_monitor.readline() in ['add', 'remove']:
            if debug:
                print('# Udev device change detected.')
                sys.stdout.flush()

            self.uinput.reset()

            # Wait a bit because udev sends multiple add events in a row.
            # Also randomize the delay to avoid multiple instances of keymapper
            # clients don't race.
            time.sleep(random.uniform(1, 2))

            # Re-init the device.
            self.__open_devices()

            # Drain all udev events.
            udev_monitor.readlines()
        return True

    # @die_on_exception
    def __on_input_event(self, device: evdev.InputDevice, condition):
        events = []
        for ev in device.read():
            events.append(ev)
            self.__orig_key_states[ev.code] = ev.value

        if debug:
            for ev in events:
                print(f'-> Event: {ev}')

        try:
            self.handle_events(device, events)
        except:
            traceback.print_exc()
            sys.exit(1)

        return True

    def press_key(self, key: int, value: Union[int, str] =-1, *, reset_all_keys=True) -> None:
        if debug:
            print(f'Press: f{evdev.InputEvent(0, 0, ecodes.EV_KEY, key, 1)}')

        if value == -1:
            if reset_all_keys:
                self.reset_all_keys()
            self.uinput.write([
                evdev.InputEvent(0, 0, ecodes.EV_KEY, key, 1),
                evdev.InputEvent(0, 0, ecodes.EV_KEY, key, 0),
            ])
            return
        if isinstance(value, int):
            self.uinput.write([
                evdev.InputEvent(0, 0, ecodes.EV_KEY, key, value),
            ])
            return
        if isinstance(value, str):
            if reset_all_keys:
                self.reset_all_keys()
            alt = 'a' in value
            ctrl = 'c' in value
            shift = 's' in value
            win = 'w' in value

            if alt: self.press_key(ecodes.KEY_LEFTALT, 1, reset_all_keys=False)
            if ctrl: self.press_key(ecodes.KEY_LEFTCTRL, 1, reset_all_keys=False)
            if shift: self.press_key(ecodes.KEY_LEFTSHIFT, 1, reset_all_keys=False)
            if win: self.press_key(ecodes.KEY_LEFTMETA, 1, reset_all_keys=False)
            self.press_key(key, reset_all_keys=False)
            if win: self.press_key(ecodes.KEY_LEFTMETA, 0, reset_all_keys=False)
            if shift: self.press_key(ecodes.KEY_LEFTSHIFT, 0, reset_all_keys=False)
            if ctrl: self.press_key(ecodes.KEY_LEFTCTRL, 0, reset_all_keys=False)
            if alt: self.press_key(ecodes.KEY_LEFTALT, 0, reset_all_keys=False)


    def send_keys(self, keys: List[Tuple[int, int]]) -> None:
        for k in keys:
            self.uinput.write([evdev.InputEvent(0, 0, ecodes.EV_KEY, k[0], k[1])])

    def get_out_key_state(self, key: int) -> int:
        return self.uinput.get_key_state(key)

    def reset_all_keys(self) -> None:
        self.uinput.reset()

    def get_in_key_state(self, key: int) -> int:
        return self.__orig_key_states[key]

    def is_key_pressed(self, key: int) -> bool:
        return self.get_in_key_state(key) > 0

    def check_modifiers(self, keys: str):
        alt = 'a' in keys
        ctrl = 'c' in keys
        shift = 's' in keys
        win = 'w' in keys
        esc = 'e' in keys

        if ((self.is_key_pressed(ecodes.KEY_LEFTALT) or self.is_key_pressed(ecodes.KEY_RIGHTALT))
                != alt):
            return False

        if ((self.is_key_pressed(ecodes.KEY_LEFTCTRL) or self.is_key_pressed(ecodes.KEY_RIGHTCTRL))
                != ctrl):
            return False

        if ((self.is_key_pressed(ecodes.KEY_LEFTSHIFT) or self.is_key_pressed(ecodes.KEY_RIGHTSHIFT))
                != shift):
            return False

        if ((self.is_key_pressed(ecodes.KEY_LEFTMETA) or self.is_key_pressed(ecodes.KEY_RIGHTMETA))
                != win):
            return False

        if (self.is_key_pressed(ecodes.KEY_ESC) != esc):
            return False

        return True

    def main(self, args):
        singleton.ensure_singleton(self.global_lock_name, debug=debug)
        notify2.init(self.remapper_name)

        self.__parse_args(args)

        if self.write_to_uinput:
            # Create our /dev/uinput device.
            uinput = UInput(name=UINPUT_DEVICE_NAME, events=self.uinput_events)
            if debug: print(f'# Uinput device name: {UINPUT_DEVICE_NAME}')
            self.uinput = synced_uinput.SyncedUinput(uinput)

        udev_monitor = self.__start_udev_monitor()
        glib.io_add_watch(udev_monitor, glib.IO_IN, self.__on_udev_event)

        self.on_initialize()

        self.__open_devices()

        try:
            gtk.main()
        finally:
            self.reset_all_keys()


def _main(args, description="key remapper test"):
    pass

if __name__ == '__main__':
    _main(sys.argv[1:])
