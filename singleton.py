import fcntl
import os


# Prevent multiple instances.
def ensure_singleton(global_lock_name, debug=False):
    lockfile = f'/tmp/{global_lock_name}.lock'
    if debug:
        print(f'Lockfile: {lockfile}')
    try:
        os.umask(0o000)
        lock = open(lockfile, 'w')
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except IOError:
        raise SystemExit(f'Unable to obtain file lock {lockfile}. Previous process running.')
