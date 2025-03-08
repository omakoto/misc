#!/usr/bin/python3


import sys
import time


def usage():
    print("Usage: work-timer.py REP DURATION [REST]")


def parse_args(args):
    if len(args) < 2:
        usage()
        sys.exit(1)
    
    rep = int(args[0])
    duration = int(args[1])
    rest = 3
    if len(args) >= 3:
        rest = int(args[2])

    return [rep, duration, rest]

def p(s):
    print(s, end="")
    sys.stdout.flush()


def beep():
    p("\x07")

def do_timer_1(prefix, duration, need_headsup_beeps):
    for i in range(duration, -1, -1):
        p(f"\r\x1b[K{prefix}{i}")
        if i == 0:
            beep()
            break
        if need_headsup_beeps and i <= 3:
            beep()

        time.sleep(1)
    p("\n")

def do_timer(n, duration, rest):
    do_timer_1(f"[\x1b[38;5;13;1mWORK\x1b[0m {n}] ", duration, True)

    if rest > 0:
        do_timer_1(f"[\x1b[38;5;10;1mREST\x1b[0m {n}] ", rest, False)


def main(args):
    [rep, duration, rest] = parse_args(args)
    print(f"Rep={rep}  Duration={duration}  Rest={rest}")

    for i in range(rep, 0, -1):
        r = rest
        if i == 1:
            r = 0
        do_timer(i, duration, r)


if __name__ == "__main__":
    main(sys.argv[1:])
