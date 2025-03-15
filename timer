#!/usr/bin/python3


import os
import sys
import time


def usage():
    print("Usage: work-timer.py DURATION [REP] [REST]")

tick = float(os.environ.get('TIMER_TICK', "1"))

def parse_sec(v):
    unit = 1
    if v.endswith("m"):
        v = v[0:-1]
        unit = 60
    elif v.endswith("s"):
        v = v[0:-1]

    return int(v) * unit

def parse_args(args):
    if len(args) < 1:
        usage()
        sys.exit(1)

    duration = parse_sec(args[0])
    rep = 1
    rest = 3
    if len(args) >= 3:
        rest = int(args[2])
    if len(args) >= 2:
        rep = parse_sec(args[1])

    return [rep, duration, rest]

def p(s):
    print(s, end="")
    sys.stdout.flush()


def beep():
    p("\x07")

def do_timer_1(prefix, duration, need_headsup_beeps):
    beep()
    for i in range(duration, -1, -1):
        p(f"\r\x1b[K{prefix}{i}")
        if i == 0:
            beep()
            break
        if need_headsup_beeps and i <= 3:
            beep()

        time.sleep(tick)
    p("\n")

def do_timer(n, duration, rest):
    do_timer_1(f"[\x1b[38;5;13;1mWORK\x1b[0m {n}] ", duration, True)

    if rest > 0:
        do_timer_1(f"[\x1b[38;5;10;1mREST\x1b[0m] ", rest, rest >= 10)


def main(args):
    [rep, duration, rest] = parse_args(args)
    if rep > 1:
        print(f"Rep={rep}  Duration={duration}  Rest={rest}")

    if rep == 1:
        do_timer_1("[\x1b[38;5;13;1mTIMER\x1b[0m] ", duration, True)
    else:
        for i in range(rep, 0, -1):
            r = rest
            if i == 1:
                r = 0
            do_timer(i, duration, r)

    for i in range(3):
        beep()
        time.sleep(0.2)


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except KeyboardInterrupt:
        pass
