#!/usr/bin/python3
import argparse
import sys

from key_remapper import main_loop, BaseRemapper


def main(args, description="ShuttleXpress media controller 2"):
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument('-m', '--match-device-name', metavar='D', default='',
                        help='Only use devices matching this regex')
    parser.add_argument('-d', '--debug', action='store_true', help='Enable debug output')

    args = parser.parse_args(args)

    main_loop(BaseRemapper(device_name_regex=args.match_device_name,
                           enable_debug=args.debug))


if __name__ == '__main__':
    main(sys.argv[1:])
