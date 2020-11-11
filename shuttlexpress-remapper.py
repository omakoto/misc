#!/usr/bin/python3

# Remaps the "ShuttleXpress" device for media consumption:

# Install python-evdev:
#   python-evdev: git@github.com:gvalkov/python-evdev.git
#   pip3 install --user evdev
#   doc: https://python-evdev.readthedocs.io/en/latest/

# Usage:
#  shuttlexpress-remapper.py # run as a normal program
#  shuttlexpress-remapper.py start # run as a daemon
#  shuttlexpress-remapper.py stop  # stop the daemon

# Device
# Bus 001 Device 049: ID 0b33:0020 Contour Design, Inc. ShuttleXpress

import argparse
import asyncio
import math
import os
import sys
import time

import evdev
import notify2
from evdev import UInput, ecodes as e

last_notification = None
notification_summary = "ShuttleXPress"

DEFAULT_DEVICE_NAME = "Contour Design ShuttleXpress"

debug = False
quiet = False

notify2.init(notification_summary)


def fatal(message):
    print(message, file=sys.stderr)
    sys.exit(1)


def run_remap(ui, device_name, jog_multiplier):
    # Open the input device.
    device = None

    for n in range(10):
        for d in [evdev.InputDevice(path) for path in evdev.list_devices()]:
            if d.name == device_name:
                device = d
                break
        if device:
            break
        else:
            print(f"Device '{device_name}' not found, retrying...")
            time.sleep(1)

    if not device:
        fatal(f"Device '{device_name}' not found.")

    device.grab()
    current_wheel = 0

    left_right_keys = [e.KEY_LEFT, e.KEY_RIGHT, 'Left/Right']
    volume_keys = [e.KEY_VOLUMEDOWN, e.KEY_VOLUMEUP, 'VolUp/Down']
    up_down_keys = [e.KEY_UP, e.KEY_DOWN, 'Up/Down']
    key_modes = [left_right_keys, up_down_keys, volume_keys]

    button1_pressed = False
    jog_mode = 0
    dial_mode = 1

    def print_help():
        global last_notification
        key4 = 'KEY_F' if button1_pressed else 'KEY_F11'
        key2 = 'Toggle Dial' if button1_pressed else 'Toggle Jog'

        help = (f'[ALT] [{key2}] [KEY_SPACE] [{key4}] [KEY_MUTE]\n' +
            f'  Jog mode : {key_modes[jog_mode][2]}\n' +
            f'  Dial mode: {key_modes[dial_mode][2]}')

        global  quiet
        if not quiet:
            print(help)

        if last_notification:
            n = last_notification
            n.update(notification_summary, help)
        else:
            n = notify2.Notification(notification_summary, help)
            last_notification = n

        n.set_urgency(notify2.URGENCY_NORMAL)
        n.set_timeout(3000)
        n.show()

    print_help()

    async def read_loop():
        nonlocal button1_pressed
        nonlocal jog_mode
        nonlocal dial_mode

        last_dial = 0
        async for ev in device.async_read_loop():
            if debug: print(f'Input: {ev}')

            if ev.type == e.EV_KEY:
                key = None
                value = 0

                # Remap the buttons.
                if ev.code == e.BTN_4: # button 1 pressed
                    button1_pressed = ev.value == 1
                    print_help()
                if ev.code == e.BTN_5 and ev.value == 0: # toggle jog/dial mode
                    if button1_pressed:
                        dial_mode = (dial_mode + 1) % len(key_modes)
                    else:
                        jog_mode = (jog_mode + 1) % len(key_modes)
                    print_help()
                elif ev.code == e.BTN_6 and ev.value == 0: # button 2 -> space
                    key = e.KEY_SPACE
                elif ev.code == e.BTN_7 and ev.value == 0: # button 4 -> F11
                    if button1_pressed:
                        key = e.KEY_F
                    else:
                        key = e.KEY_F11
                elif ev.code == e.BTN_8 and ev.value == 0: # button 5 -> mute
                    key = e.KEY_MUTE
                if key:
                    ui.write(e.EV_KEY, key, 1)
                    ui.write(e.EV_KEY, key, 0)
                    ui.syn()
                continue

            # Handle the dial
            if ev.type == e.EV_REL and ev.code == e.REL_DIAL:
                now_dial = ev.value
                delta = now_dial - last_dial
                last_dial = now_dial

                key = 0
                if delta < 0:
                    key = key_modes[dial_mode][0]
                if delta > 0:
                    key = key_modes[dial_mode][1]

                if key != 0:
                    ui.write(e.EV_KEY, key, 1)
                    ui.write(e.EV_KEY, key, 0)
                    ui.syn()

            # Handle the jog
            if ev.type == e.EV_REL and ev.code == e.REL_WHEEL:
                nonlocal current_wheel
                current_wheel = ev.value

    # Monitor the jog dial (reported as a wheel), and as long as the jog is rotated,
    # send the left or right keys repeatedly. The rotation angle decides the repeat frequency.
    async def periodic():
        sleep_duration = 0.1

        while True:
            nonlocal current_wheel
            nonlocal jog_mode

            await asyncio.sleep(sleep_duration)
            sleep_duration = 0.1

            # -7 <= current_wheel <= 7 is the range.
            if -1 <= current_wheel <= 1:
                continue

            if debug: print(f'Wheel={current_wheel}')

            key = 0
            count = 0
            if current_wheel < 0:
                key = key_modes[jog_mode][0]
                count = -current_wheel
            elif current_wheel > 0:
                key = key_modes[jog_mode][1]
                count = current_wheel

            # Special case the small angles. Always make a single key event, and
            # don't repeat too fast.

            # range will be [1 - 7] * multiplier
            count = count - 1
            speed = math.pow(count, 2) + 1 # range 2 -
            sleep_duration = 0.8 / (jog_multiplier * speed)
            # print(f'{count}, {sleep_duration}')

            ui.write(e.EV_KEY, key, 1)
            ui.write(e.EV_KEY, key, 0)
            ui.syn()


    def exception_handler(loop, context):
        print(f'Exception detected: {context}')
        if context['exception'].__class__ == OSError:
            print('Device disconnected.')
            os._exit(4)
        else:
            os._exit(1)

    try:
        asyncio.ensure_future(read_loop())
        asyncio.ensure_future(periodic())
        loop = asyncio.get_event_loop()
        loop.set_exception_handler(exception_handler)
        loop.run_forever()
    finally:
        if device:
            try:
                device.ungrab()
            except:
                pass # Ignore exceptions.

def main(args):
    parser = argparse.ArgumentParser(description='ShuttleXPress key remapper')
    parser.add_argument('--device-name', metavar='D', default=DEFAULT_DEVICE_NAME, help='Device name shown by evtest(1)')
    parser.add_argument('-d', '--debug', action='store_true', help='Enable debug output')
    parser.add_argument('-q', '--quiet', action='store_true', help='Quet mode')
    parser.add_argument('-s', '--jog-multiplier', type=float, default=1, help='Multipler for cursor speed for jog')

    args = parser.parse_args(args=args)

    global debug, quiet
    debug = args.debug
    quiet = args.quiet

    # Open /dev/uinput.
    ui = UInput(name='ShuttleXPress-remapper-uinput')

    run_remap(ui, args.device_name, args.jog_multiplier)


if __name__ == '__main__':
    main(sys.argv[1:])

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
