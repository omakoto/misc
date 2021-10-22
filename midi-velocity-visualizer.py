#!/usr/bin/python3

import sys
import os

import pygame as pg
import pygame.midi as pgm
from pprint import pprint
import colorsys
import math

DEBUG = False # or True


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

        print(f'Using input device #{i}: {name}')
        return i

    raise Exception('MIDI input device not found')

def detect_output_device():
    for i in range(pgm.get_count()):
        r = pgm.get_device_info(i)
        (interf, name, input, output, opened) = r

        if not output:
            continue

        if b'Midi Through' in name:
            continue

        print(f'Using output device #{i}: {name}')
        return i

class Recorder:
    def __init__(self):
        self._events = []
        self._current_index = 0
        self._is_recording = False
        self._is_playing = False
        self._first_t = 0

    def start_recording(self):
        if self.is_recording:
            return
        self._events = []
        self._current_index = 0
        self._is_recording = True

    def stop_recording(self):
        if not self.is_recording:
            return
        self._is_recording = False

    def record(self, t, event):
        if not self.is_recording:
            return # not recording
        if len(self._events) == 0:
            # First event
            self._first_t = t
        self._events.append((t - self._first_t, event))

    def start_playing(self, start_t):
        self._is_playing = True
        if start_t < 0:
            start_t = 0
        self._current_index = -1
        for i in range(0, len(self._events)):
            if self._events[i][0] >= start_t:
                self._current_index = i
                break

    def stop_playing(self):
        self._is_playing = False

    def next_event(self, t):
        if self._current_index < 0 or self._current_index >= len(self._events):
            self._is_playing = False
            return None
        next_event = self._events[self._current_index]
        if next_event[0] <= t:
            self._current_index += 1
            return next_event[1]

    @property
    def is_recording(self):
        return self._is_recording

    @property
    def is_playing(self):
        return self._is_playing


NOTES_COUNT = 128

HORIZONTAL_MARGIN = 0.01  # Margin at each side
VERTICAL_MARGIN = 0.01  # Margin at top and bottom
SPACING = 0.01 # Space between each bar

LINE_WIDTH = 4

MID_LINE_COLOR = (200, 200, 255)
BASE_LINE_COLOR = (200, 255, 200)

BAR_RATIO = 0.3

ROLL_SCROLL_TICKS = 1
ROLL_SCROLL_AMOUNT = 4

class Main:
    def __init__(self, midi_input_id = None, midi_output_id = None):
        self.midi_input_id = midi_input_id
        self.midi_output_id = midi_output_id
        self.screen = None
        self.initialized = False
        self.min_note = 21
        self.max_note = 108

        self.recorder = Recorder()
        self.reset_notes()

    def reset_notes(self):
        # notes = [[0 or 1, velocity, timestamp], ....]
        self.notes = [[0, 0, 0] for n in range(0, NOTES_COUNT)]
        self.pedal = 0

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
        if not self.midi_output_id:
            self.midi_output_id = detect_output_device()
        self.midi_in = pgm.Input(self.midi_input_id)
        self.midi_out = pgm.Output(self.midi_output_id)


        infoObject = pg.display.Info()

        self.w = infoObject.current_w
        self.h = infoObject.current_h

        # FULLSCREEN has this problem: https://github.com/pygame/pygame/issues/2538
        # Using the workaround there.
        self.screen = pg.display.set_mode([0, 0],
                                    pg.NOFRAME | pg.DOUBLEBUF | pg.HWSURFACE)
        # pg.display.toggle_fullscreen()
        pprint(self.screen)
        pg.display.set_caption('Velocity Visualizer')

        self.w = self.screen.get_width()
        self.h = self.screen.get_height()
        # print(f"{w} x {h}")
        self.hm = self.w * HORIZONTAL_MARGIN
        self.vm = self.h * VERTICAL_MARGIN

        print(int(self.w - self.hm * 2), int(self.h - self.vm * 2))
        self.roll = pg.Surface((int(self.w - self.hm * 2), int(self.h - self.vm * 2)))
        self.roll.fill((0, 0, 0))
        self.roll_tick = 0

        self.reset_midi_out()

        self.initialized = True

        return self


    def __del__(self):
        if self.initialized:
            del self.midi_in
            pgm.quit()
            pg.quit()

    def reset_midi_out(self):
        self.midi_out.write_short(176, 123, 0) # All notes off
        self.midi_out.write_short(176, 121, 0) # Reset all controllers
        self.midi_out.write_short(255) # All reset
        self.reset_notes()

    def run(self):

        self.playing_t = 0

        running = True
        last_t = pg.time.get_ticks()

        self.on = 0
        self.off = 0

        paint_t = 0
        pausing = False
        while running:
            self.t = pg.time.get_ticks()
            delta_t = self.t - last_t
            self.roll_tick += delta_t
            if not pausing:
                self.playing_t += delta_t
            paint_t += delta_t
            last_t = self.t

            if self.midi_in.poll():
                midi_events = self.midi_in.read(10)
                # convert them into pygame events.
                midi_evs = pgm.midis2events(
                    midi_events, self.midi_in.device_id)

                for m_e in midi_evs:
                    self.event_post(m_e)

            if self.recorder.is_playing:
                while True:
                    ev = self.recorder.next_event(self.playing_t)
                    if not ev:
                        if not self.recorder.is_playing:
                            self.reset_midi_out()
                        break
                    self.midi_out.write([[[ev.status, ev.data1, ev.data2], 0]])
                    self.event_post(ev)

            # Did the user click the window close button?
            for event in self.event_get():
                # pprint(event)
                if event.type == pg.QUIT:
                    running = False
                elif event.type == pg.KEYDOWN and event.key == pg.K_ESCAPE:
                    running = False
                elif event.type == pg.KEYDOWN and event.key == pg.K_r and not self.recorder.is_playing:
                    if self.recorder.is_recording:
                        self.recorder.stop_recording()
                    else:
                        self.recorder.start_recording()
                elif event.type == pg.KEYDOWN and event.key == pg.K_LEFT and not self.recorder.is_recording:
                    self.playing_t -= 1000

                    self.reset_midi_out()
                    self.recorder.start_playing(self.playing_t)
                elif event.type == pg.KEYDOWN and event.key == pg.K_RIGHT and not self.recorder.is_recording:
                    self.playing_t += 1000

                    self.reset_midi_out()
                    self.recorder.start_playing(self.playing_t)
                elif event.type == pg.KEYDOWN and event.key == pg.K_RETURN and self.recorder.is_playing:
                    pausing = not pausing
                elif event.type == pg.KEYDOWN and event.key == pg.K_SPACE and not self.recorder.is_recording:
                    self.reset_midi_out()
                    if self.recorder.is_playing:
                        self.recorder.stop_playing()
                    else:
                        self.playing_t = 0
                        self.recorder.start_playing(self.playing_t)
                elif event.type == pg.MOUSEBUTTONDOWN and event.button == 3:
                    running = False
                elif event.type in [pgm.MIDIIN]:
                    if DEBUG: print(event)

                    do_record = False
                    if event.status == 144: # Note on
                        do_record = True
                        self.on += 1
                        self.notes[event.data1][0] = 1
                        self.notes[event.data1][1] = event.data2
                        self.notes[event.data1][2] = self.t

                        # Don't update the min / max notes dynamically
                        # if event.data1 < self.min_note:
                        #     self.min_note = event.data1
                        # elif event.data1 > self.max_note:
                        #     self.max_note = event.data1
                    elif event.status == 128:  # Note off
                        do_record = True
                        self.off += 1
                        self.notes[event.data1][0] = 0
                        self.notes[event.data1][2] = self.t
                    elif event.status == 176 and event.data1 == 64: # pedal
                        do_record = True
                        self.pedal = event.data2

                    if do_record and self.recorder.is_recording:
                        self.recorder.record(self.t, event)



# Key-on
# <Event(32771-MidiIn {'status': 144, 'data1': 48, 'data2': 80, 'data3': 0, 'timestamp': 1111, 'vice_id': 3}) >
# Key-off
# <Event(32771-MidiIn {'status': 128, 'data1': 48, 'data2': 0, 'data3': 0, 'timestamp': 1364, 'vice_id': 3}) >

            if paint_t < 16:
                continue
            while paint_t >= 16:
                paint_t -= 16
            self._maybe_scroll_roll()

            self._draw()
            self.on = 0
            self.off = 0

        self.reset_midi_out()

    def _maybe_scroll_roll(self):
        if self.roll_tick < ROLL_SCROLL_TICKS:
            return
        self.roll_tick -= ROLL_SCROLL_TICKS

        self.roll.blit(self.roll, (0, ROLL_SCROLL_AMOUNT))
        pg.draw.rect(self.roll, self._get_pedal_color(self.pedal), (0, 0, self.w, ROLL_SCROLL_AMOUNT))


    def _get_color(self, vel):
        MAX_H = 0.4
        h = MAX_H - (MAX_H * vel / 127)
        s = 0.9
        l = 1
        rgb = colorsys.hsv_to_rgb(h, s, l)
        return (rgb[0] * 255, rgb[1] * 255, rgb[2] * 255)

    def _get_on_color(self, count):
        h = max(0, 0.2 - count * 0.03)
        s = min(1, 0.3 + 0.2 * count)
        l = min(1, 0.4 + 0.2 * count)
        rgb = colorsys.hsv_to_rgb(h, s, l)
        return (rgb[0] * 255, rgb[1] * 255, rgb[2] * 255)

    def _get_pedal_color(self, value):
        if value <= 10:
            return [0, 0, 0]
        h = 0.6 - (0.06 * value / 127)
        s = 0.7
        l = 0.2
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

        # on/off bar
        # if self.off:
        #     pg.draw.rect(self.roll, (10, 10, 50), (0, 0, aw, 1))
        if self.on:
            # c = min(255, 128 + self.on * 64)
            pg.draw.rect(self.roll, self._get_on_color(self.on), (0, ROLL_SCROLL_AMOUNT - 1, aw, 1))

        # Bars
        for i in range(self.min_note, self.max_note + 1):
            note = self.notes[i]
            if not note[0]:
                continue
            color = self._get_color(note[1])
            if not color:
                continue

            # bar left
            bl = hm + aw * (i - self.min_note) / (self.max_note - self.min_note + 1)

            # bar height
            bh = ah * note[1] / 127

            # print(f'{i}: {bl} {bh}')
            # pg.draw.rect(self.screen, (255, 255, 200), (bl, h - vm, bw, -bh))
            pg.draw.rect(self.screen, color, (bl, vm + ah - bh, bw, bh))
            pg.draw.rect(self.roll, color, (bl - hm, 0, bw, ROLL_SCROLL_AMOUNT))


        # Lines # TODO clean up
        pg.draw.rect(self.screen, self._get_color(128 * (1 - 0.70)),
                         (hm, vm + ah * 0.70, w - hm * 2, 0), LINE_WIDTH)
        pg.draw.rect(self.screen, self._get_color(64),
                         (hm, vm + ah * 0.5, w - hm * 2, 0), LINE_WIDTH)
        pg.draw.rect(self.screen, self._get_color(96),
                         (hm, vm + ah * 0.25, w - hm * 2, 0), LINE_WIDTH)
        pg.draw.rect(self.screen, BASE_LINE_COLOR,
                         (hm, vm + ah, w - hm * 2, 0), LINE_WIDTH)

        self.screen.blit(self.roll, (hm, vm + ah + LINE_WIDTH))

        if self.recorder.is_recording:
            pg.draw.circle(self.screen, (255, 64, 64), (30, 30), 20)
        elif self.recorder.is_playing:
            pg.draw.polygon(self.screen, (64, 255, 64), ((10, 10), (40, 30), (10, 50)))

        # Flip the display
        pg.display.flip()


def main():
    m = Main().init()
    m.run()


if __name__ == '__main__':
    main()
