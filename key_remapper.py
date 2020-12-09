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
from typing import Optional, Dict, List, TextIO, cast

import evdev
import notify2
import pyudev
from evdev import UInput, ecodes as e, ecodes

import singleton
import synced_uinput
import tasktray

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

    def on_initialize(self, ui: Optional[synced_uinput.SyncedUinput]):
        if debug:
            print(f'on_initialize: {ui}')

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

    # Thread safe
    def press_key(self, key: int) -> None:
        if debug:
            print(f'Press: f{evdev.InputEvent(0, 0, ecodes.EV_KEY, key, 1)}')
        self.uinput.write([
            evdev.InputEvent(0, 0, ecodes.EV_KEY, key, 1),
            evdev.InputEvent(0, 0, ecodes.EV_KEY, key, 0),
        ])



def _start_udev_monitor() -> TextIO:
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
        except BaseException as e:
            traceback.print_exc()
            stop_remapper()

    th = threading.Thread(target=run)
    th.setDaemon(True)
    th.start()

    return reader


class _Stopper:
    stopped = False

    def __init__(self) -> None:
        pr, pw = os.pipe()
        os.set_blocking(pr, False)
        self.stop_fd = os.fdopen(pr)
        self.__writer = os.fdopen(pw, 'w')

    def stop(self):
        self.stopped = True
        self.__writer.write('stop\n')
        self.__writer.flush()
        if debug: print('Stop!')


STOPPER = _Stopper()


def stop_remapper():
    STOPPER.stop()


def _open_devices(
        device_name_regex: str,
        id_regex: str,
        match_non_keyboards=False) \
        -> [List[evdev.InputDevice], Optional[Dict[int, List[int]]]]:
    devices = []
    all_capabilities = []

    device_name_matcher = re.compile(device_name_regex)
    id_matcher = re.compile(id_regex)

    # Find the keyboard devices, except for the one that we created with /dev/uinput.
    for d in [evdev.InputDevice(path) for path in sorted(evdev.list_devices())]:
        # Ignore our own device, and "any younger" devices.
        if d.name.startswith(UINPUT_DEVICE_NAME_PREFIX) and d.name >= UINPUT_DEVICE_NAME:
            continue

        id_info = f'v{d.info.vendor :04x} p{d.info.product :04x}'
        if debug:
            print(f'Device: {d} / {id_info}')
            print(f'  Capabilities: {d.capabilities(verbose=True)}')

        # Reject the ones that don't match the name filter.
        if not (device_name_matcher.search(d.name) and id_matcher.search(id_info)):
            if debug: print(f'  Skipping {d.name}')
            continue

        add = False
        caps = d.capabilities()
        if match_non_keyboards:
            add = True
        else:
            for c in caps.keys():
                if c not in (e.EV_SYN, e.EV_KEY, e.EV_MSC, e.EV_LED, e.EV_REP):
                    add = False
                    break
                if c == e.EV_KEY:
                    add = True

        if add:
            print(f"Found device: {d}")
            devices.append(d)
            all_capabilities.append(caps)
        else:
            d.close()

    if not devices:
        print("No matching devices found.")

    return [devices, all_capabilities]


def _try_grab(device: evdev.InputDevice) -> bool:
    try:
        device.grab()
        return True
    except IOError:
        return False


def _try_ungrab(device: evdev.InputDevice) -> bool:
    try:
        device.ungrab()
        return True
    except IOError:
        return False


def start_remapper(remapper: BaseRemapper) -> None:
    global debug, quiet
    debug = remapper.enable_debug
    quiet = remapper.force_quiet

    singleton.ensure_singleton(remapper.global_lock_name, debug=debug)

    ui = None
    if remapper.write_to_uinput:
        # Create our /dev/uinput device.
        uinput = UInput(name=UINPUT_DEVICE_NAME, events=remapper.uinput_events)
        if debug: print(f'Uinput device name: {UINPUT_DEVICE_NAME}')
        ui = synced_uinput.SyncedUinput(uinput)

    udev_monitor = _start_udev_monitor()

    remapper.uinput = ui
    remapper.on_initialize(ui)

    while not STOPPER.stopped:
        # Drain all the udev events
        udev_monitor.readlines()

        # Find the devivces.
        devices, all_capabilities = _open_devices(
            remapper.device_name_regex,
            remapper.id_regex,
            remapper.match_non_keyboards)
        try:
            # Prepare the selector.
            selector = selectors.DefaultSelector()
            selector.register(udev_monitor, selectors.EVENT_READ)
            selector.register(STOPPER.stop_fd, selectors.EVENT_READ)

            # Grab the devices if needed, and add them to the selector.
            reading_devices = []
            for d in devices:
                if remapper.grab_devices and not _try_grab(d):
                    print(f"  Unable to grab, skipping device {d}", file=sys.stderr)
                    continue
                reading_devices.append(d)
                selector.register(d, selectors.EVENT_READ)

            devices = reading_devices

            if devices:
                remapper.on_device_detected(devices)
            else:
                remapper.on_device_not_found()

            try:
                # Start the main loop.
                stop = False
                while not stop and not STOPPER.stopped:
                    for key, mask in selector.select():
                        device = cast(evdev.InputDevice, key.fileobj)

                        if device == STOPPER.stop_fd:
                            break

                        # See if a new device hsa been detected.
                        if device == udev_monitor:
                            if (action := udev_monitor.readline()) != 'add':
                                continue  # ignore the event
                            print('A new device has been detected.')
                            # Wait a bit because udev sends multiple add events in a row.
                            # Also randomize to avoid multiple instances of keymapper
                            # clients don't race.
                            time.sleep(random.uniform(1, 2))
                            stop = True
                            break

                        # Read all the queued events.
                        events = []
                        for ev in device.read():
                            events.append(ev)
                        if debug:
                            for ev in events:
                                if debug: print(f'-> Event: {ev}')

                        remapper.handle_events(device, events)

            except OSError as ex:
                print(f'Device lost: {ex}')
                remapper.on_device_lost()
            finally:
                if ui:
                    ui.reset()
        except KeyboardInterrupt:
            break
        except BaseException as ex:
            traceback.print_exc()
            remapper.on_exception(ex)
        finally:
            if debug: print('Stopping...')
            for d in devices:
                print(f"Releasing device: {d}")
                if remapper.grab_devices:
                    _try_ungrab(d)
                d.close()
            remapper.on_device_lost()
    remapper.on_stop()


class SimpleRemapper(BaseRemapper):
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

    def start(self, args):
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

        self.on_arguments_parsed(args)

        notify2.init(self.remapper_name)

        def do():
            # evdev will complain if the thread has no event loop set.
            asyncio.set_event_loop(asyncio.new_event_loop())
            try:
                start_remapper(self)
            except BaseException as e:
                traceback.print_exc()
                tasktray.quit()

        th = threading.Thread(target=do)
        th.start()

        tasktray.start_quitting_tray_icon(self.remapper_name, self.remapper_icon)
        stop_remapper()


def _main(args, description="key remapper test"):
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument('-m', '--match-device-name', metavar='D', default='',
        help='Only use devices matching this regex')
    parser.add_argument('-d', '--debug', action='store_true', help='Enable debug output')

    args = parser.parse_args(args)

    start_remapper(BaseRemapper(device_name_regex=args.match_device_name,
        enable_debug=args.debug))


if __name__ == '__main__':
    _main(sys.argv[1:])
