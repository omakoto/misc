#!/usr/bin/python3

# Prevent multiple instances.

import fcntl
import os
import time

lockfiles = []

def ensure_singleton(global_lock_name, debug=False):
    lockfile = f'/tmp/{global_lock_name}.lock'
    if debug:
        print(f'Lockfile: {lockfile}')
    try:
        os.umask(0o000)
        lock = open(lockfile, 'w')
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        lockfiles.append(lock)
    except IOError:
        raise SystemExit(f'Unable to obtain file lock {lockfile}. Previous process running.')


if __name__ == '__main__':
    ensure_singleton("test_lock")
    time.sleep(1000000)
