#!/usr/bin/python3

import csv
import sys
from signal import signal, SIGPIPE, SIG_DFL  

def main(files):
    signal(SIGPIPE, SIG_DFL) # Don't show stacktrace on SIGPIPE

    for f in files:
        with open(f, newline='') as csvfile:
            rd = csv.reader(csvfile, delimiter=',', quotechar='"')

            for cols in rd:
                prefix = ""
                for col in cols:
                    print(prefix + col)
                    prefix = "    "

if __name__ == "__main__":
    main(sys.argv[1:])
