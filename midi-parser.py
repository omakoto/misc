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
        return (self.readU16() << 16) + self.readU16()

    def readVar(self):
        ret = 0
        while True:
            val = self.readU8()
            ret += (val & 0x7f)
            if val < 128:
                return ret
            val <<= 7

    def skip(self, nbytes):
        for i in range(nbytes):
            self.readU8()

def parseFile(filename):
    print(f'Parsing {filename} ...')

    with BytesReader(filename) as rd:
        signature = rd.readU32()
        header_len = rd.readU32()
        type = rd.readU16()
        num_tracks = rd.readU16()
        ticks = rd.readU16()

        print(f'MIDI Header: {signature:02x} length={header_len}b type={type} #tracks={num_tracks} ticks={ticks}')

        track = 0

        while True:
            if track >= num_tracks:
                break
            track += 1
            signature = rd.readU32()
            track_len = rd.readU32()

            print(f'  Track #{track}: {signature:02x} length={track_len}b')

            last_status = 0

            tick = 0
            while True:
                delta = rd.readVar()
                status = rd.readU8()

                tick += delta

                print(f'    {tick:<6} ', end='')

                if status == 0xff:
                    type = rd.readU8()
                    len = rd.readVar()

                    print(f'Meta 0x{type:02x} len={len:<4}: ', end='')

                    if type == 0x2f:
                        print('End of track')
                        break
                    if type == 0x00:
                        print('Sequence number: {rd.readU16()}')
                        continue
                    if type == 0x20:
                        print('Channel prefix: {rd.readU8()}')
                        continue
                    if type == 0x58:  # Time signature
                        nn = rd.readU8()
                        dd = rd.readU8()
                        cc = rd.readU8()
                        bb = rd.readU8()
                        print(f'Time signature: {nn} / {dd}  {cc} / {bb}')
                        continue
                    if type == 0x51:
                        tempo = rd.readU24()
                        print(f'Tempo: {tempo} ({60 * 1000 * 1000 / tempo} BPM)')
                        continue
                    if type == 0x54:
                        hr = rd.readU8()
                        mn = rd.readU8()
                        se = rd.readU8()
                        fr = rd.readU8()
                        ff = rd.readU8()
                        print(f'SMPTE Offset: {hr}:{mn:02}:{se:02}.{fr:03}.{ff:03}')
                        continue
                    if type == 0x59:
                        sf= rd.readU8()
                        mi = rd.readU8()
                        print(f'Key signature: ', end='')
                        if sf == 0:
                            print(f'Key of C ', end='')
                        elif sf < 0:
                            print(f'{-sf} flat(s) ', end='')
                        else:
                            print(f'{sf} sharp(s) ', end='')

                        if mi:
                            print('Minor')
                        else:
                            print('Major')

                        continue

                    print('[unsupported]')
                    rd.skip(len)
                    continue

                if status == 0xf0 or status == 0xf7:
                    len = rd.readVar()
                    print('SysEx: len={len}')
                    rd.skip(len)
                    continue

                data1 = -1
                if status >= 0x80:
                    data1 = rd.readU8()
                else:
                    # Running status
                    data1 = status
                    status = last_status

                last_status = status

                status_type = status & 0xf0
                channel = status & 0x0f

                print(f'(ch={channel}) ', end='')

                if status_type == 0x80:
                    print(f'Note off: {data1} val={rd.readU8()}')
                    continue
                if status_type == 0x90:
                    print(f'Note on : {data1} val={rd.readU8()}')
                    continue
                if status_type == 0xa0:
                    print(f'After touch: {(data1 << 7) + rd.readU8()}')
                    continue
                if status_type == 0xb0:
                    print(f'Control change: control={data1} val={rd.readU8()}')
                    continue
                if status_type == 0xc0:
                    print(f'Program change: {data1}')
                    continue
                if status_type == 0xd0:
                    print(f'Channel pressure: va={data1}')
                    continue
                if status_type == 0xe0:
                    print(f'Pitch wheel: {(data1 << 7) + rd.readU8()}')
                    continue

                print(f'    Unknown status byte! {status}')








def main():
    for filename in sys.argv[1:]:
        parseFile(filename)


if __name__ == '__main__':
    main()
