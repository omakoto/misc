#!/usr/bin/python3
import collections
import threading
from typing import Dict, Iterable

import evdev
from evdev import ecodes


def is_syn(ev: evdev.InputEvent) -> bool:
    return ev and ev.type == ecodes.EV_SYN and ev.code == ecodes.SYN_REPORT and ev.value == 0


class SyncedUinput:
    wrapped: evdev.uinput
    __lock: threading.RLock
    __key_states: Dict[int, int]

    def __init__(self, uinput: evdev.UInput):
        self.wrapped = uinput
        self.__lock = threading.RLock()
        self.__key_states = collections.defaultdict(int)

    def write(self, events: Iterable[evdev.InputEvent]):
        self.__lock.acquire()
        try:
            last_event = None
            for ev in events:
                if is_syn(ev) and is_syn(last_event):
                    # Don't send syn twice in a row.
                    # (Not sure if it matters but just in case.)
                    continue

                # When sending a KEY event, only send what'd make sense given the
                # current key state.
                if ev.type == ecodes.EV_KEY:
                    old_state = self.__key_states[ev.code]
                    if ev.value == 0:
                        if old_state == 0:  # Don't send if already released.
                            continue
                    elif ev.value == 1:
                        if old_state > 0:  # Don't send if already pressed.
                            continue
                    elif ev.value == 2:
                        if old_state == 0:  # Don't send if not pressed.
                            continue

                    self.__key_states[ev.code] = ev.value

                self.wrapped.write_event(ev)
                last_event = ev

            # If any event was written, and the last event isn't a syn, send one.
            if last_event and not is_syn(last_event):
                self.wrapped.syn()

        finally:
            self.__lock.release()

    def reset(self):
        # Release all pressed keys.
        self.__lock.acquire()
        try:
            for key in self.__key_states.keys():
                if self.__key_states[key] > 0:
                    self.wrapped.write(ecodes.EV_KEY, key, 0)
                    self.wrapped.syn()
        except:
            pass  # ignore any exception
        finally:
            self.__key_states.clear()
            self.__lock.release()


