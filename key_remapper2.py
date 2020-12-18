#!/usr/bin/python3
import argparse
import collections
import os
import random
import re
import sys
import threading
import time
import traceback
from typing import Optional, Dict, List, TextIO, Tuple, Union, Collection, Iterable, Callable

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

_at_exists = []


def add_at_exit(callback):
    _at_exists.append(callback)


def call_at_exists():
    for callback in _at_exists:
        callback()
    _at_exists.clear()


def exit(status_code):
    call_at_exists()
    sys.exit(status_code)


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
        try:
            for event in events:
                try:
                    self.handle_event(device, event)
                except DoneEvent:
                    pass
        except DoneEvent:
            pass

    def handle_event(self, device: evdev.InputDevice, event: evdev.InputEvent) -> None:
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
            exit(1)

    return wrapper


class RemapperTrayIcon(tasktray.TaskTrayIcon):
    def __init__(self, name, icon_path):
        super().__init__(name, icon_path)

    def _add_menu_items(self, menu):
        item = gtk.MenuItem(f'Restart {self.name}')
        item.connect('activate', self.restart)
        menu.append(item)

        super()._add_menu_items(menu)

    def restart(self, source):
        call_at_exists()
        os.execv(sys.argv[0], sys.argv)

class DoneEvent(Exception):
    pass

class SimpleRemapper(BaseRemapper ):
    tray_icon: tasktray.TaskTrayIcon
    __devices: Dict[str, Tuple[evdev.InputDevice, int]]
    __orig_key_states: Dict[int, int] = collections.defaultdict(int)
    __udev_monitor: Optional[TextIO]

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
        self.tray_icon = RemapperTrayIcon(self.remapper_name, self.remapper_icon)
        self.__refresh_scheduled = False

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

    def get_active_window(self) -> Tuple[str, str, str]: # title, class_group_name, class_instance_name
        # Note: use `wmctrl -lx` to list window classes.
        # Example: For the following window,
        # 0x03a00007  0 www.amazon.co.jp__kindle-dbs_library_manga.Google-chrome  x1c7u マンガ本棚
        # This method returns:
        # ('マンガ本棚', 'www.amazon.co.jp__kindle-dbs_library_manga', 'Google-chrome')
        #
        # See https://lazka.github.io/pgi-docs/Wnck-3.0/classes/Window.html for wnck
        screen = wnck.Screen.get_default()
        screen.force_update()
        w = screen.get_active_window()

        return (w.get_name(), w.get_class_group_name(), w.get_class_instance_name())

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

    def __start_udev_monitor(self):
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
                exit(1)

        th = threading.Thread(target=run)
        th.setDaemon(True)
        th.start()

        self.__udev_monitor = reader

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

        # We just opened the devices, so drain all udev monitor events.
        if self.__udev_monitor:
            # Drain all udev events.
            self.__udev_monitor.readlines()

        if self.__devices:
            self.on_device_detected([t[0] for t in self.__devices.values()])
        else:
            self.on_device_not_found()

    def __schedule_refresh_devices(self):
        if self.__refresh_scheduled:
            return
        self.__refresh_scheduled = True

        def call_refresh():
            self.__refresh_scheduled = False
            self.__open_devices()
            return False

        # Re-open the devices, but before that, wait a bit because udev sends multiple add events in a row.
        # Also randomize the delay to avoid multiple instances of keymapper
        # clients don't race.
        glib.timeout_add(random.uniform(1, 2) * 1000, call_refresh)

    # @die_on_exception
    def __on_udev_event(self, udev_monitor: TextIO , condition):
        refresh_devices = False
        for event in udev_monitor.readlines(): # drain all the events
            if event in ['add', 'remove']:
                if debug:
                    print('# Udev device change detected.')
                    sys.stdout.flush()
                refresh_devices = True

        if refresh_devices:
            self.uinput.reset()
            self.__schedule_refresh_devices()

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
            exit(1)

        return True

    def press_key_and_done(self, key: int, value: Union[int, str] =-1, *, reset_all_keys=True) -> None:
        self.press_key(key, value, reset_all_keys=reset_all_keys)
        raise DoneEvent()

    def press_key(self, key: int, value: Union[int, str] =-1, *, reset_all_keys=True, done=False) -> None:
        if debug:
            print(f'Press: f{evdev.InputEvent(0, 0, ecodes.EV_KEY, key, 1)}')

        if value == -1:
            if reset_all_keys:
                self.reset_all_keys()
            self.uinput.write([
                evdev.InputEvent(0, 0, ecodes.EV_KEY, key, 1),
                evdev.InputEvent(0, 0, ecodes.EV_KEY, key, 0),
            ])
        elif isinstance(value, int):
            # Intentionally not resetting in this case.
            self.uinput.write([
                evdev.InputEvent(0, 0, ecodes.EV_KEY, key, value),
            ])
        elif isinstance(value, str):
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
        if done:
            raise DoneEvent()

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
        caps = 'p' in keys

        if self.is_alt_pressed() != alt:
            return False

        if self.is_ctrl_pressed() != ctrl:
            return False

        if self.is_shift_pressed() != shift:
            return False

        if self.is_win_pressed() != win:
            return False

        if self.is_esc_pressed() != esc:
            return False

        if self.is_caps_pressed() != caps:
            return False

        return True

    def is_alt_pressed(self):
        return self.is_key_pressed(ecodes.KEY_LEFTALT) or self.is_key_pressed(ecodes.KEY_RIGHTALT)

    def is_ctrl_pressed(self):
        return self.is_key_pressed(ecodes.KEY_LEFTCTRL) or self.is_key_pressed(ecodes.KEY_RIGHTCTRL)

    def is_shift_pressed(self):
        return self.is_key_pressed(ecodes.KEY_LEFTSHIFT) or self.is_key_pressed(ecodes.KEY_RIGHTSHIFT)

    def is_win_pressed(self):
        return self.is_key_pressed(ecodes.KEY_LEFTMETA) or self.is_key_pressed(ecodes.KEY_RIGHTMETA)

    def is_esc_pressed(self):
        return self.is_key_pressed(ecodes.KEY_ESC)

    def is_caps_pressed(self):
        return self.is_key_pressed(ecodes.KEY_CAPSLOCK)

    def matches_key(self,
            ev:evdev.InputEvent,
            expected_key:int,
            expected_values:Union[int, Collection[int]],
            expected_modifiers:Optional[str] = None,
            predecate:Callable[[], bool] = None) -> bool:
        if ev.code != expected_key:
            return False

        if isinstance(expected_values, int) and ev.value != expected_values:
            return False
        elif isinstance(expected_values, Iterable) and ev.value not in expected_values:
            return False

        if expected_modifiers is not None and not self.check_modifiers(expected_modifiers):
            return False

        if predecate and not predecate():
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
            add_at_exit(self.uinput.close)

        self.__start_udev_monitor()
        glib.io_add_watch(self.__udev_monitor, glib.IO_IN, self.__on_udev_event)

        self.on_initialize()

        self.__open_devices()
        add_at_exit(self.__release_devices)

        try:
            gtk.main()
        finally:
            self.reset_all_keys()

        exit(0)


def _main(args, description="key remapper test"):
    pass

if __name__ == '__main__':
    _main(sys.argv[1:])
