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

import sys
import math
import evdev
import asyncio
import argparse
from evdev import UInput, ecodes as e
import sys, os, time, psutil, signal

DEFAULT_DEVICE_NAME = "Contour Design ShuttleXpress"

debug = False


def fatal(message):
    print(message, file=sys.stderr)
    sys.exit(1)


def run_remap(device_name, jog_multiplier):
    # Open the input device.
    device = None
    for d in [evdev.InputDevice(path) for path in evdev.list_devices()]:
        if d.name == device_name:
            device = d
            break

    # Open /dev/uinput.
    ui = UInput()

    if not device:
        fatal(f"Device '{device_name}' not found.")

    device.grab()

    current_wheel = 0

    arrow_keys = [e.KEY_LEFT, e.KEY_RIGHT, 'Left/Right']
    volume_keys = [e.KEY_VOLUMEDOWN, e.KEY_VOLUMEUP, 'VolUp/Down']
    key_modes = [arrow_keys, volume_keys]

    button1_pressed = False
    jog_mode = 0
    dial_mode = 1

    def print_help():
        key4 = 'KEY_F' if button1_pressed else 'KEY_F11'
        key2 = 'Toggle Dial' if button1_pressed else 'Toggle Jog'
        print(f'[ALT] [{key2}] [KEY_SPACE] [{key4}] [KEY_MUTE]')
        print(f'  Jog mode : {key_modes[jog_mode][2]}')
        print(f'  Dial mode: {key_modes[dial_mode][2]}')

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
                        dial_mode = 1 - dial_mode
                    else:
                        jog_mode = 1 - jog_mode
                    print_help()
                elif ev.code == e.BTN_6 and ev.value == 0: # button 2 -> space
                    key = e.KEY_SPACE
                    value = ev.value
                elif ev.code == e.BTN_7 and ev.value == 0: # button 4 -> F11
                    if button1_pressed:
                        key = e.KEY_F
                    else:
                        key = e.KEY_F11
                    value = ev.value
                elif ev.code == e.BTN_8 and ev.value == 0: # button 5 -> mute
                    key = e.KEY_MUTE
                    value = ev.value
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
            speed = math.pow(count, 1.5) + 1 # range 2 -
            sleep_duration = 1.0 / (jog_multiplier * speed)
            # print(f'{count}, {sleep_duration}')

            ui.write(e.EV_KEY, key, 1)
            ui.write(e.EV_KEY, key, 0)
            ui.syn()


    asyncio.ensure_future(read_loop())
    asyncio.ensure_future(periodic())
    loop = asyncio.get_event_loop()
    loop.run_forever()

# Howto make daemon in Python 3
# https://www.workaround.cz/howto-make-code-daemon-python-3/


class Daemon(object):
    """
    Usage: - create your own a subclass Daemon class and override the run() method. Run() will be periodically the calling inside the infinite run loop
           - you can receive reload signal from self.isReloadSignal and then you have to set back self.isReloadSignal = False
    """

    def __init__(self, stdin='/dev/null', stdout='/dev/null', stderr='/dev/null'):
        self.ver = 0.1  # version
        self.pauseRunLoop = 0    # 0 means none pause between the calling of run() method.
        self.restartPause = 1    # 0 means without a pause between stop and start during the restart of the daemon
        self.waitToHardKill = 3  # when terminate a process, wait until kill the process with SIGTERM signal

        self.isReloadSignal = False
        self._canDaemonRun = True
        self.processName = os.path.basename(sys.argv[0])
        self.stdin = stdin
        self.stdout = stdout
        self.stderr = stderr

    def _sigterm_handler(self, signum, frame):
        self._canDaemonRun = False

    def _reload_handler(self, signum, frame):
        self.isReloadSignal = True

    def _makeDaemon(self):
        """
        Make a daemon, do double-fork magic.
        """

        try:
            pid = os.fork()
            if pid > 0:
                # Exit first parent.
                sys.exit(0)
        except OSError as e:
            m = f"Fork #1 failed: {e}"
            print(m)
            sys.exit(1)

        # Decouple from the parent environment.
        os.chdir("/")
        os.setsid()
        os.umask(0)

        # Do second fork.
        try:
            pid = os.fork()
            if pid > 0:
                # Exit from second parent.
                sys.exit(0)
        except OSError as e:
            m = f"Fork #2 failed: {e}"
            print(m)
            sys.exit(1)

        m = "The daemon process is going to background."
        print(m)

        # Redirect standard file descriptors.
        sys.stdout.flush()
        sys.stderr.flush()
        si = open(self.stdin, 'r')
        so = open(self.stdout, 'a+')
        se = open(self.stderr, 'a+')
        os.dup2(si.fileno(), sys.stdin.fileno())
        os.dup2(so.fileno(), sys.stdout.fileno())
        os.dup2(se.fileno(), sys.stderr.fileno())

    def _getProces(self):
        procs = []

        for p in psutil.process_iter():
            if self.processName in [part.split('/')[-1] for part in p.cmdline()]:
                # Skip  the current process
                if p.pid != os.getpid():
                    procs.append(p)

        return procs

    def start(self):
        """
        Start daemon.
        """

        # Handle signals
        signal.signal(signal.SIGINT, self._sigterm_handler)
        signal.signal(signal.SIGTERM, self._sigterm_handler)
        signal.signal(signal.SIGHUP, self._reload_handler)

        # Check if the daemon is already running.
        procs = self._getProces()

        if procs:
            pids = ",".join([str(p.pid) for p in procs])
            m = f"Find a previous daemon processes with PIDs {pids}. Is not already the daemon running?"
            print(m)
            sys.exit(1)
        else:
            m = f"Start the daemon version {self.ver}"
            print(m)

        # Daemonize the main process
        self._makeDaemon()
        # Start a infinitive loop that periodically runs run() method
        self.run()

    def version(self):
        m = f"The daemon version {self.ver}"
        print(m)

    def status(self):
        """
        Get status of the daemon.
        """

        procs = self._getProces()

        if procs:
            pids = ",".join([str(p.pid) for p in procs])
            m = f"The daemon is running with PID {pids}."
            print(m)
        else:
            m = "The daemon is not running!"
            print(m)

    def reload(self):
        """
        Reload the daemon.
        """

        procs = self._getProces()

        if procs:
            for p in procs:
                os.kill(p.pid, signal.SIGHUP)
                m = f"Send SIGHUP signal into the daemon process with PID {p.pid}."
                print(m)
        else:
            m = "The daemon is not running!"
            print(m)

    def stop(self):
        """
        Stop the daemon.
        """

        procs = self._getProces()

        def on_terminate(process):
            m = f"The daemon process with PID {process.pid} has ended correctly."
            print(m)

        if procs:
            for p in procs:
                p.terminate()

            gone, alive = psutil.wait_procs(procs, timeout=self.waitToHardKill, callback=on_terminate)

            for p in alive:
                m = f"The daemon process with PID {p.pid} was killed with SIGTERM!"
                print(m)
                p.kill()
        else:
            m = "Cannot find some daemon process, I will do nothing."
            print(m)

    def restart(self):
        """
        Restart the daemon.
        """
        self.stop()

        if self.restartPause:
            time.sleep(self.restartPause)

        self.start()

    # this method you have to override
    def run(self):
        pass



def main(args):
    parser = argparse.ArgumentParser(description='ShuttleXPress key remapper')
    parser.add_argument('--device-name', metavar='D', default=DEFAULT_DEVICE_NAME, help='Device name shown by evtest(1)')
    parser.add_argument('-d', '--debug', action='store_true', help='Enable debug output')
    parser.add_argument('-s', '--jog-multiplier', type=float, default=1, help='Multipler for cursor speed for jog')
    parser.add_argument('command', nargs='?', help='[start | stop | restart]')

    args = parser.parse_args()

    global debug
    debug = args.debug

    device_name = args.device_name
    jog_multiplier = args.jog_multiplier
    command = args.command


    def run():
        run_remap(device_name, jog_multiplier)


    class MyDaemon(Daemon):
        def run(self):
            run()

    if command == "start":
        MyDaemon().start()
        sys.exit(0)
    elif command == "stop":
        MyDaemon().stop()
        pass
        sys.exit(0)
    elif command == "restart":
        MyDaemon().restart()
        pass
        sys.exit(0)

    run()


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
