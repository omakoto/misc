#!/usr/bin/python3

import sys

class BytesReader:
    def __init__(self, filename):
        self.filename = filename
        self.file = open(filename, 'rb')

    def __enter__(self):
        return self

    def __exit__(self, type, value, traceback):
        self.file.close()

    def readU8(self):
        return ord(self.file.read(1))

    def readU16(self):
        return (self.readU8() << 8) + self.readU8()

    def readU24(self):
        return (self.readU16() << 8) + self.readU8()

    def readU32(self):
        return (self.readU16() << 16) + self.readU8()

    def readVar(self):
        ret = 0
        while True:
            val = self.readU8()
            ret += (val & 0x7f)
            if val >= 128:
                return ret
            val <<= 7

def parseFile(filename):
    print(f'Parsing {filename} ...')

    with BytesReader(filename) as rd:
        signature = rd.readU32()
        header_len = rd.readU32()
        type = rd.readU16()
        num_tracks = rd.readU16()
        ticks = rd.readU16()

        print(f'MIDI Header: {signature:02x} {header_len} type={type} #tracks={num_tracks} ticks={ticks}')




def main():
    for filename in sys.argv[1:]:
        parseFile(filename)


if __name__ == '__main__':
    main()
