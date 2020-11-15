#!/usr/bin/python3

# python-evdev: git@github.com:gvalkov/python-evdev.git
# pyudev: https://pyudev.readthedocs.io/en/latest/
# pip3 install evdev pyudev

# Event codes
# https://github.com/torvalds/linux/blob/master/include/uapi/linux/input-event-codes.h

import sys
import pyudev
import evdev
from evdev import UInput, ecodes as e

# udev device action monitoring test

if False:
    context = pyudev.Context()
    monitor = pyudev.Monitor.from_netlink(context)
    monitor.filter_by(subsystem='input')
    for action, device in monitor:
        print('{0}: {1}'.format(action, device))



# Event read test

if True:
    device = evdev.InputDevice(sys.argv[1])
    print(f'Device: {device}')
    print(f'Device.info: {device.info}')

    device.grab()

    for event in device.read_loop():
        print(f'Input: {event}')

if False:
    ui = UInput()
    ui.write(e.EV_KEY, e.KEY_VOLUMEUP, 1)  # KEY_A down
    ui.write(e.EV_KEY, e.KEY_VOLUMEUP, 0)  # KEY_A up
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

# # button 1 - 5
# Event: time 1603940595.109645, type 4 (EV_MSC), code 4 (MSC_SCAN), value 90005
# Event: time 1603940595.109645, type 1 (EV_KEY), code 260 (BTN_4), value 1
# Event: time 1603940595.109645, -------------- SYN_REPORT ------------
# Event: time 1603940595.269778, type 4 (EV_MSC), code 4 (MSC_SCAN), value 90005
# Event: time 1603940595.269778, type 1 (EV_KEY), code 260 (BTN_4), value 0
# Event: time 1603940595.269778, -------------- SYN_REPORT ------------
#
# Event: time 1603940595.789981, type 4 (EV_MSC), code 4 (MSC_SCAN), value 90006
# Event: time 1603940595.789981, type 1 (EV_KEY), code 261 (BTN_5), value 1
# Event: time 1603940595.789981, -------------- SYN_REPORT ------------
# Event: time 1603940595.861739, type 4 (EV_MSC), code 4 (MSC_SCAN), value 90006
# Event: time 1603940595.861739, type 1 (EV_KEY), code 261 (BTN_5), value 0
# Event: time 1603940595.861739, -------------- SYN_REPORT ------------
#
# Event: time 1603940596.302117, type 4 (EV_MSC), code 4 (MSC_SCAN), value 90007
# Event: time 1603940596.302117, type 1 (EV_KEY), code 262 (BTN_6), value 1
# Event: time 1603940596.302117, -------------- SYN_REPORT ------------
# Event: time 1603940596.398071, type 4 (EV_MSC), code 4 (MSC_SCAN), value 90007
# Event: time 1603940596.398071, type 1 (EV_KEY), code 262 (BTN_6), value 0
# Event: time 1603940596.398071, -------------- SYN_REPORT ------------
#
# Event: time 1603940596.734161, type 4 (EV_MSC), code 4 (MSC_SCAN), value 90008
# Event: time 1603940596.734161, type 1 (EV_KEY), code 263 (BTN_7), value 1
# Event: time 1603940596.734161, -------------- SYN_REPORT ------------
# Event: time 1603940596.878260, type 4 (EV_MSC), code 4 (MSC_SCAN), value 90008
# Event: time 1603940596.878260, type 1 (EV_KEY), code 263 (BTN_7), value 0
# Event: time 1603940596.878260, -------------- SYN_REPORT ------------
#
# Event: time 1603940597.174290, type 4 (EV_MSC), code 4 (MSC_SCAN), value 90009
# Event: time 1603940597.174290, type 1 (EV_KEY), code 264 (BTN_8), value 1
# Event: time 1603940597.174290, -------------- SYN_REPORT ------------
# Event: time 1603940597.310376, type 4 (EV_MSC), code 4 (MSC_SCAN), value 90009
# Event: time 1603940597.310376, type 1 (EV_KEY), code 264 (BTN_8), value 0

# # dial left
# Event: time 1603940643.232741, type 2 (EV_REL), code 7 (REL_DIAL), value 255
# Event: time 1603940643.232741, -------------- SYN_REPORT ------------
# Event: time 1603940644.616316, type 2 (EV_REL), code 7 (REL_DIAL), value 254
# Event: time 1603940644.616316, -------------- SYN_REPORT ------------
#
# # dial right
# Event: time 1603940647.015813, type 2 (EV_REL), code 7 (REL_DIAL), value 255
# Event: time 1603940647.015813, -------------- SYN_REPORT ------------
# Event: time 1603940648.031673, type 2 (EV_REL), code 7 (REL_DIAL), value 1
# Event: time 1603940648.031673, -------------- SYN_REPORT ------------

# # jog left / right
# Event: time 1603940679.100245, type 2 (EV_REL), code 8 (REL_WHEEL), value -1
# Event: time 1603940679.100245, type 2 (EV_REL), code 11 (REL_WHEEL_HI_RES), value -120
# Event: time 1603940679.100245, type 2 (EV_REL), code 7 (REL_DIAL), value 1
# Event: time 1603940679.100245, -------------- SYN_REPORT ------------
# Event: time 1603940679.236238, type 2 (EV_REL), code 8 (REL_WHEEL), value -2
# Event: time 1603940679.236238, type 2 (EV_REL), code 11 (REL_WHEEL_HI_RES), value -240
# Event: time 1603940679.236238, type 2 (EV_REL), code 7 (REL_DIAL), value 1
# Event: time 1603940679.236238, -------------- SYN_REPORT ------------
# Event: time 1603940679.500076, type 2 (EV_REL), code 8 (REL_WHEEL), value -1
# Event: time 1603940679.500076, type 2 (EV_REL), code 11 (REL_WHEEL_HI_RES), value -120
# Event: time 1603940679.500076, type 2 (EV_REL), code 7 (REL_DIAL), value 1
# Event: time 1603940679.500076, -------------- SYN_REPORT ------------
# Event: time 1603940679.507818, type 2 (EV_REL), code 7 (REL_DIAL), value 1
# Event: time 1603940679.507818, -------------- SYN_REPORT ------------
#
#
# Event: time 1603940682.155783, type 2 (EV_REL), code 8 (REL_WHEEL), value 1
# Event: time 1603940682.155783, type 2 (EV_REL), code 11 (REL_WHEEL_HI_RES), value 120
# Event: time 1603940682.155783, type 2 (EV_REL), code 7 (REL_DIAL), value 1
# Event: time 1603940682.155783, -------------- SYN_REPORT ------------
# Event: time 1603940684.252099, type 2 (EV_REL), code 8 (REL_WHEEL), value 2
# Event: time 1603940684.252099, type 2 (EV_REL), code 11 (REL_WHEEL_HI_RES), value 240
# Event: time 1603940684.252099, type 2 (EV_REL), code 7 (REL_DIAL), value 1
# Event: time 1603940684.252099, -------------- SYN_REPORT ------------
# Event: time 1603940685.228088, type 2 (EV_REL), code 8 (REL_WHEEL), value 1
# Event: time 1603940685.228088, type 2 (EV_REL), code 11 (REL_WHEEL_HI_RES), value 120
# Event: time 1603940685.228088, type 2 (EV_REL), code 7 (REL_DIAL), value 1
# Event: time 1603940685.228088, -------------- SYN_REPORT ------------
# Event: time 1603940685.243685, type 2 (EV_REL), code 7 (REL_DIAL), value 1
# Event: time 1603940685.243685, -------------- SYN_REPORT ------------
#
