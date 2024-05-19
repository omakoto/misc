#!/usr/bin/python3

import sys

def shift(note):
    match note.lower():
        case 'c': return 'c#'
        case 'c#': return 'd'
    return 'x'






def main(args):
    pass
    print(shift('c'))

if __name__ == '__main__':
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        sys.exit(1)
    except IOError as e:
        if e.errno == errno.EPIPE:
            sys.stderr.write('%s: Broken pipe.\n' % sys.argv[0])
            sys.exit(1)
        else:
            raise
