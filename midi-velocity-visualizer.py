#!/usr/bin/python3

import sys
import os

import pygame as pg
import pygame.midi as pgm
from pprint import pprint
import colorsys
import math

DEBUG = False


def print_device_info():
    for i in range(pgm.get_count()):
        r = pgm.get_device_info(i)
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
    for i in range(pgm.get_count()):
        r = pgm.get_device_info(i)
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

HORIZONTAL_MARGIN = 0.01  # Margin at each side
VERTICAL_MARGIN = 0.01  # Margin at top and bottom
SPACING = 0.01 # Space between each bar

LINE_WIDTH = 4

DECAY = 0.002

MID_LINE_COLOR = (200, 200, 255)
BASE_LINE_COLOR = (200, 255, 200)

BAR_RATIO = 1 - 1 / 1.6

class Main:
    def __init__(self, midi_input_id = None):
        self.midi_input_id = midi_input_id
        self.screen = None
        self.initialized = False
        self.min_note = 21
        self.max_note = 108

        # notes = [[0 or 1, velocity, timestamp], ....]
        self.notes = [[0, 0, 0] for n in range(0, NOTES_COUNT)]


    def init(self):
        pg.init()
        pgm.init()

        pg.fastevent.init()
        self.event_get = pg.fastevent.get
        self.event_post = pg.fastevent.post

        # print_device_info()

        print(f'Available resolutions: {pg.display.list_modes()}')
        if not self.midi_input_id:
            self.midi_input_id = detect_input_device()
        self.midi_in = pgm.Input(self.midi_input_id)

        infoObject = pg.display.Info()

        self.w = infoObject.current_w
        self.h = infoObject.current_h

        # FULLSCREEN has this problem: https://github.com/pygame/pygame/issues/2538
        # Using the workaround there.
        self.screen = pg.display.set_mode([0, 0],
                                    pg.NOFRAME | pg.DOUBLEBUF | pg.HWSURFACE)
        pg.display.toggle_fullscreen()
        pprint(self.screen)
        pg.display.set_caption('Velocity Visualizer')

        # self.w = self.screen.get_width()
        # self.h = self.screen.get_height()
        # print(f"{w} x {h}")
        self.hm = self.w * HORIZONTAL_MARGIN
        self.vm = self.h * VERTICAL_MARGIN

        print(int(self.w - self.hm * 2), int(self.h - self.vm * 2))
        self.roll = pg.Surface((int(self.w - self.hm * 2), int(self.h - self.vm * 2)))
        self.roll.fill((50, 50, 50))

        self.initialized = True
        return self


    def __del__(self):
        if self.initialized:
            del self.midi_in
            pgm.quit()
            pg.quit()


    def run(self):
        running = True
        while running:

            self.t = pg.time.get_ticks()

            if self.midi_in.poll():
                midi_events = self.midi_in.read(10)
                # convert them into pygame events.
                midi_evs = pgm.midis2events(
                    midi_events, self.midi_in.device_id)

                for m_e in midi_evs:
                    self.event_post(m_e)

            # Did the user click the window close button?
            for event in self.event_get():
                # pprint(event)
                if event.type == pg.QUIT:
                    running = False
                elif event.type == pg.KEYDOWN and event.key == pg.K_ESCAPE:
                    running = False
                elif event.type == pg.MOUSEBUTTONDOWN and event.button == 3:
                    running = False
                elif event.type in [pgm.MIDIIN]:
                    if DEBUG: print(event)

                    if event.status == 144: # Note on
                        self.notes[event.data1][0] = 1
                        self.notes[event.data1][1] = event.data2
                        self.notes[event.data1][2] = self.t

                        # Don't update the min / max notes dynamically
                        # if event.data1 < self.min_note:
                        #     self.min_note = event.data1
                        # elif event.data1 > self.max_note:
                        #     self.max_note = event.data1
                    elif event.status == 128:  # Note off
                        self.notes[event.data1][0] = 0
                        self.notes[event.data1][2] = self.t


# Key-on
# <Event(32771-MidiIn {'status': 144, 'data1': 48, 'data2': 80, 'data3': 0, 'timestamp': 1111, 'vice_id': 3}) >
# Key-off
# <Event(32771-MidiIn {'status': 128, 'data1': 48, 'data2': 0, 'data3': 0, 'timestamp': 1364, 'vice_id': 3}) >

            self._draw()


    def _get_color(self, note):
        MAX_H = 0.5
        h = MAX_H - (MAX_H * note[1] / 127)
        s = 0.6
        l = 1
        if note[0]:
            l = 1
        else:
            l = max(0, 1 - (self.t - note[2] + 500) * DECAY)
        if l <= 0:
            return None
        rgb = colorsys.hsv_to_rgb(h, s, l)
        return (rgb[0] * 255, rgb[1] * 255, rgb[2] * 255)

    def _draw(self):
        w = self.w
        h = self.h
        hm = self.hm
        vm = self.vm

        # Available width and height
        aw = w - hm * 2
        ah = (h - vm * 2) * BAR_RATIO

        # Black background
        self.screen.fill((0, 0, 0))

        # bar width
        bw = aw / (self.max_note - self.min_note + 1) - SPACING

        # Bars
        for i in range(self.min_note, self.max_note + 1):
            note = self.notes[i]
            color = self._get_color(note)
            if not color:
                continue

            # bar left
            bl = hm + aw * (i - self.min_note) / (self.max_note - self.min_note + 1)

            # bar height
            bh = ah * note[1] / 127

            # print(f'{i}: {bl} {bh}')
            # pg.draw.rect(self.screen, (255, 255, 200), (bl, h - vm, bw, -bh))
            pg.draw.rect(self.screen, color, (bl, vm + ah - bh, bw, bh))

        # Lines
        pg.draw.rect(self.screen, MID_LINE_COLOR,
                         (hm, vm + ah * 0.5, w - hm * 2, 0), LINE_WIDTH)
        pg.draw.rect(self.screen, MID_LINE_COLOR,
                         (hm, vm + ah * 0.25, w - hm * 2, 0), LINE_WIDTH)
        pg.draw.rect(self.screen, BASE_LINE_COLOR,
                         (hm, vm + ah, w - hm * 2, 0), LINE_WIDTH)

        self.screen.blit(self.roll, (hm, vm + ah + LINE_WIDTH))


        # Flip the display
        pg.display.flip()


def main():
    m = Main().init()
    m.run()


if __name__ == '__main__':
    main()
