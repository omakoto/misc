#!/usr/bin/python3

import gi
gi.require_version('Wnck', '3.0')
from gi.repository import Wnck as wnck

screen = wnck.Screen.get_default()
screen.force_update()
window = screen.get_active_window()

print(window.get_name())
print(window.get_class_instance_name())
