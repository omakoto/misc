#!/usr/bin/python3

import sys
import os

import pygame
import pygame.midi
from pprint import pprint


def print_device_info():
    for i in range(pygame.midi.get_count()):
        r = pygame.midi.get_device_info(i)
        (interf, name, input, output, opened) = r

        in_out = ""
        if input:
            in_out = "(input)"
        if output:
            in_out = "(output)"

        print(
            "%2i: interface :%s:, name :%s:, opened :%s:  %s"
            % (i, interf, name, opened, in_out)
        )

def detect_input_device():
    for i in range(pygame.midi.get_count()):
        r = pygame.midi.get_device_info(i)
        (interf, name, input, output, opened) = r

        if not input:
            continue

        if b'Midi Through' in name:
            continue

        print(f'Using device #{i}: {name}')
        return i

    raise Exception('MIDI input device not found')

# class Note:
#     def __init__(self, ):
#         self._velocity = 0
#         self._timestamp = 0

#     @property
#     def velocity(self):
#         return self._velocity

#     @velocity.setter
#     def velocity(self, value):
#         self._velocity = value

#     @property
#     def timestamp(self):
#         return self._timestamp

#     @timestamp.setter
#     def timestamp(self, value):
#         self._timestamp = value

#     def __repr__(self):
#         return f'{self._velocity} @{self._timestamp}'



# class Model:
#     def __init__(self, ):
#         self.notes = [Note() for n in range(0, NOTES_COUNT)]


#     def dump(self):
#         pprint(vars(self))
# Model().dump()
# sys.exit(0)

NOTES_COUNT = 128
MIN_NOTE = 36
MAX_NOTE = 84

HORIZONTAL_MARGIN = 0.04  # Margin at each side
VERTICAL_MARGIN = 0.06  # Margin at top and bottom
SPACING = 0.01 # Space between each bar

LINE_WIDTH = 4

class Main:
    def __init__(self, midi_input_id = None):
        self.midi_input_id = midi_input_id
        self.screen = None
        self.initialized = False

        # notes = [[0 or 1, velocity, timestamp], ....]
        self.notes = [[0, 0, 0] for n in range(0, NOTES_COUNT)]


    def init(self):
        pygame.init()
        pygame.midi.init()

        pygame.fastevent.init()
        self.event_get = pygame.fastevent.get
        self.event_post = pygame.fastevent.post

        # print_device_info()

        if not self.midi_input_id:
            self.midi_input_id = detect_input_device()
        self.midi_in = pygame.midi.Input(self.midi_input_id)

        infoObject = pygame.display.Info()

        screen_w = int(infoObject.current_w/2.5)
        screen_h = int(infoObject.current_w/2.5)

        self.screen = pygame.display.set_mode([screen_w, screen_h], pygame.RESIZABLE)

        self.initialized = True
        return self


    def __del__(self):
        if self.initialized:
            del self.midi_in
            pygame.midi.quit()
            pygame.quit()


    def run(self):
        running = True
        while running:

            self.t = pygame.time.get_ticks()

            # Did the user click the window close button?
            for event in self.event_get():
                if event.type == pygame.QUIT:
                    running = False
                elif event.type in [pygame.midi.MIDIIN]:
                    print(event)

                    if event.status == 144: # Note on
                        self.notes[event.data1][0] = 1
                        self.notes[event.data1][1] = event.data2
                        self.notes[event.data1][2] = self.t
                    elif event.status == 128:  # Note off
                        self.notes[event.data1][0] = 0
                        self.notes[event.data1][2] = self.t

            if self.midi_in.poll():
                midi_events = self.midi_in.read(10)
                # convert them into pygame events.
                midi_evs = pygame.midi.midis2events(
                    midi_events, self.midi_in.device_id)

                for m_e in midi_evs:
                    self.event_post(m_e)

# Key-on
# <Event(32771-MidiIn {'status': 144, 'data1': 48, 'data2': 80, 'data3': 0, 'timestamp': 1111, 'vice_id': 3}) >
# Key-off
# <Event(32771-MidiIn {'status': 128, 'data1': 48, 'data2': 0, 'data3': 0, 'timestamp': 1364, 'vice_id': 3}) >

            self._draw()


    def _draw(self):
        w = self.screen.get_width()
        h = self.screen.get_height()
        hm = w * HORIZONTAL_MARGIN
        vm = h * VERTICAL_MARGIN

        # Black background
        self.screen.fill((0, 0, 0))

        # Base line
        pygame.draw.rect(self.screen, (200, 255, 200), (hm, h - vm, w - hm * 2, 0), LINE_WIDTH)

        # Bars
        for i in range(MIN_NOTE, MAX_NOTE + 1):
            note = self.notes[i]

        # Flip the display
        pygame.display.flip()


def main():
    m = Main().init()
    m.run()


if __name__ == '__main__':
    main()
