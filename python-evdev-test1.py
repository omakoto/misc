#!/usr/bin/python3

# python-evdev: https://github.com/gvalkov/python-evdev/blob/master/docs/index.rst
# pip3 install --user evdev

import sys
import evdev
from evdev import UInput, ecodes as e
import time


# Event read test

if True:
    device = evdev.InputDevice(sys.argv[1])
    print(f'Device: {device}')

    device.grab()

    for event in device.read_loop():
        print(f'Input: {event}')

if True:
    ui = UInput()
    ui.write(e.EV_KEY, e.KEY_A, 1)  # KEY_A down
    time.sleep(0.02)
    ui.write(e.EV_KEY, e.KEY_A, 0)  # KEY_A up
    ui.syn()
    ui.close()


# # left
# Input: event at 1603930942.836911, code 04, type 04, val 458832
# Input: event at 1603930942.836911, code 105, type 01, val 01
# Input: event at 1603930942.836911, code 00, type 00, val 00
# Input: event at 1603930943.036909, code 04, type 04, val 458832
# Input: event at 1603930943.036909, code 105, type 01, val 00
# Input: event at 1603930943.036909, code 00, type 00, val 00
#
# # right
# Input: event at 1603930952.564860, code 04, type 04, val 458831
# Input: event at 1603930952.564860, code 106, type 01, val 01
# Input: event at 1603930952.564860, code 00, type 00, val 00
# Input: event at 1603930952.668911, code 04, type 04, val 458831
# Input: event at 1603930952.668911, code 106, type 01, val 00
# Input: event at 1603930952.668911, code 00, type 00, val 00
#
# # up
# Input: event at 1603930989.644899, code 04, type 04, val 458834
# Input: event at 1603930989.644899, code 103, type 01, val 01
# Input: event at 1603930989.644899, code 00, type 00, val 00
# Input: event at 1603930989.772886, code 04, type 04, val 458834
# Input: event at 1603930989.772886, code 103, type 01, val 00
# Input: event at 1603930989.772886, code 00, type 00, val 00
#
# # down
# Input: event at 1603930990.340882, code 04, type 04, val 458833
# Input: event at 1603930990.340882, code 108, type 01, val 01
# Input: event at 1603930990.340882, code 00, type 00, val 00
# Input: event at 1603930990.468883, code 04, type 04, val 458833
# Input: event at 1603930990.468883, code 108, type 01, val 00
# Input: event at 1603930990.468883, code 00, type 00, val 00
#
# # vol-up
# Input: event at 1603930875.772917, code 04, type 04, val 786665
# Input: event at 1603930875.772917, code 115, type 01, val 01
# Input: event at 1603930875.772917, code 00, type 00, val 00
# Input: event at 1603930875.892911, code 04, type 04, val 786665
# Input: event at 1603930875.892911, code 115, type 01, val 00
# Input: event at 1603930875.892911, code 00, type 00, val 00
#
# # vol-down
# Input: event at 1603930892.052903, code 04, type 04, val 786666
# Input: event at 1603930892.052903, code 114, type 01, val 01
# Input: event at 1603930892.052903, code 00, type 00, val 00
# Input: event at 1603930892.180896, code 04, type 04, val 786666
# Input: event at 1603930892.180896, code 114, type 01, val 00
# Input: event at 1603930892.180896, code 00, type 00, val 00
#
