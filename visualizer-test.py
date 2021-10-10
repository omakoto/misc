#!/usr/bin/python3

import sys
import os

import pygame
import pygame.midi
import time


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


def main():
    pygame.init()
    pygame.midi.init()

    pygame.fastevent.init()
    event_get = pygame.fastevent.get
    event_post = pygame.fastevent.post

    # print_device_info()

    input_id = detect_input_device()
    midi_in = pygame.midi.Input(input_id)

    infoObject = pygame.display.Info()

    screen_w = int(infoObject.current_w/2.5)
    screen_h = int(infoObject.current_w/2.5)

    screen = pygame.display.set_mode([screen_w, screen_h], pygame.RESIZABLE)

    t = pygame.time.get_ticks()
    getTicksLastFrame = t

    running = True
    while running:

        t = pygame.time.get_ticks()
        deltaTime = (t - getTicksLastFrame) / 1000.0
        getTicksLastFrame = t

        # Did the user click the window close button?
        for event in event_get():
            if event.type == pygame.QUIT:
                running = False
            elif event.type in [pygame.midi.MIDIIN]:
                print(event)

        if midi_in.poll():
            midi_events = midi_in.read(10)
            # convert them into pygame events.
            midi_evs = pygame.midi.midis2events(
                midi_events, midi_in.device_id)

            for m_e in midi_evs:
                event_post(m_e)


# Key-on
# <Event(32771-MidiIn {'status': 144, 'data1': 48, 'data2': 80, 'data3': 0, 'timestamp': 1111, 'vice_id': 3}) >
# Key-off
# <Event(32771-MidiIn {'status': 128, 'data1': 48, 'data2': 0, 'data3': 0, 'timestamp': 1364, 'vice_id': 3}) >


        w = screen.get_width()
        h = screen.get_height()

        screen.fill((0, 0, 0))

        # Flip the display
        pygame.display.flip()

    del midi_in
    pygame.midi.quit()
    pygame.quit()


if __name__ == '__main__':
    main()
