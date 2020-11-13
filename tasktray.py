#!/usr/bin/python3

import gi
gi.require_version('Gtk', '3.0')
gi.require_version('AppIndicator3', '0.1')
gi.require_version('Notify', '0.7')
from gi.repository import Gtk as gtk
from gi.repository import GLib as glib
from gi.repository import AppIndicator3 as appindicator


# Create a task tray icon with a given name and an icon, with a "quit" menu item.

class TaskTrayIcon:
    def __init__(self, name, icon_path):
        self.indicator = appindicator.Indicator.new(name, icon_path,
                                                    appindicator.IndicatorCategory.SYSTEM_SERVICES)
        self.indicator.set_status(appindicator.IndicatorStatus.ACTIVE)
        self.indicator.set_menu(self.__build_menu())

    def _add_menu_items(self, menu):
        item_quit = gtk.MenuItem('Quit')
        item_quit.connect('activate', self.quit)
        menu.append(item_quit)

    def __build_menu(self):
        menu = gtk.Menu()

        self._add_menu_items(menu)

        menu.show_all()
        return menu

    def _on_quit(self):
        pass

    def quit(self, source):
        def inner():
            self._on_quit()
            gtk.main_quit()
        glib.idle_add(inner)

    def set_icon(self, icon_path):
        def inner():
            self.indicator.set_icon_full(icon_path, '')
        glib.idle_add(inner)

    def run(self):
        gtk.main()
