#!/usr/bin/python3
import argparse
import select
import sys
import time

import alsaaudio

DEFAULT_MIXER_NAME = 'Capture'
DEBUG = False

def main(args):
    parser = argparse.ArgumentParser(description='push-to-talk with alsa')
    parser.add_argument('-d', '--debug', action='store_true', help='Enable debug output')
    parser.add_argument('-m', '--mixer-name', default=DEFAULT_MIXER_NAME, help='Capture mixer name')

    args = parser.parse_args(args)
    DEBUG = args.debug

    mixer_name = args.mixer_name

    if DEBUG: print(args)

    mixer = alsaaudio.Mixer(mixer_name)

    if DEBUG:
        print('mixer', mixer)
        print(mixer.switchcap())
        print(mixer.volumecap())
        print("All mixers")


    pdesc = mixer.polldescriptors()
    if DEBUG: print('pdesc', pdesc)
    
    p = select.poll()
    p.register(pdesc[0][0], pdesc[0][1])

    # mixer.setrec(0)

    while True:
        events = p.poll()
        mixer.handleevents()
        print(f'Events: {events}')

        # mixer = alsaaudio.Mixer(mixer_name)
        print(mixer.getrec())
        # print(mixer.getvolume())
        time.sleep(30)




if __name__ == '__main__':
    main(sys.argv[1:])

