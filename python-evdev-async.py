#!/usr/bin/python3

import asyncio
import sys
import threading

import evdev
import os

import asyncio_glib
import gi
import pyudev

import tasktray

gi.require_version('Gtk', '3.0')
from gi.repository import Gtk as gtk


SCRIPT_PATH = os.path.dirname(os.path.realpath(__file__))
MIC_ICON = os.path.join(SCRIPT_PATH, 'microphone.png')
MIC_MUTED_ICON = os.path.join(SCRIPT_PATH, 'microphone-muted.png')

class TaskTray(tasktray.TaskTrayIcon):
    def __init__(self):
        super().__init__("Test", MIC_ICON)

    def _add_menu_items(self, menu):
        item_test = gtk.MenuItem('Test')
        item_test.connect('activate', self.test)
        menu.append(item_test)

        super()._add_menu_items(menu)

    def test(self, _):
        print("XXX")

    def _on_quit(self):
        sys.exit(0)

trayicon = TaskTray()


class deviceMonitor(threading.Thread):
    def __init__(self):
        threading.Thread.__init__(self)
        self.setDaemon(True)

    def run(self):
        context = pyudev.Context()
        monitor = pyudev.Monitor.from_netlink(context)
        monitor.filter_by(subsystem='input')

        print('Device monitor started.')

        for action, device in monitor:
            print(f'udev: action={action} {device}')
            if action == "add":
                pass

keybd = evdev.InputDevice('/dev/input/event3')

async def print_events(device):
    async for event in device.async_read_loop():
        print(device.path, evdev.categorize(event), sep=': ')

asyncio.ensure_future(print_events(keybd))

asyncio.set_event_loop_policy(asyncio_glib.GLibEventLoopPolicy())
loop = asyncio.get_event_loop()
loop.run_forever()
