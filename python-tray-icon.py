#!/usr/bin/python3

# http://candidtim.github.io/appindicator/2014/09/13/ubuntu-appindicator-step-by-step.html

import gi
gi.require_version('Gtk', '3.0')
gi.require_version('AppIndicator3', '0.1')
gi.require_version('Notify', '0.7')
from gi.repository import Gtk as gtk
from gi.repository import AppIndicator3 as appindicator
from gi.repository import Notify as notify

import os
import signal


signal.signal(signal.SIGINT, signal.SIG_DFL)


APPINDICATOR_ID = 'myappindicator'


indicator = None

def build_menu():
    menu = gtk.Menu()

    item_joke = gtk.MenuItem('Joke')
    item_joke.connect('activate', joke)
    menu.append(item_joke)

    item_quit = gtk.MenuItem('Quit')
    item_quit.connect('activate', quit)
    menu.append(item_quit)

    menu.show_all()
    return menu


def joke(_):
    notify.Notification.new("<b>Joke</b>", 'abcdef', None).show()
    global indicator
    indicator.set_icon_full(os.path.abspath('microphone-muted.png'), '')


def quit(source):
    notify.uninit()
    gtk.main_quit()


def main():
    global indicator
    notify.init(APPINDICATOR_ID)
    indicator = appindicator.Indicator.new(APPINDICATOR_ID, os.path.abspath('microphone.png'), appindicator.IndicatorCategory.SYSTEM_SERVICES)
    indicator.set_status(appindicator.IndicatorStatus.ACTIVE)
    indicator.set_menu(build_menu())
    indicator.set_label('Mic Muter', 'Mic Muter')

    gtk.main()

if __name__ == "__main__":
    main()
