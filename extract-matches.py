#!/usr/bin/python3

import sys
from pprint import pprint
import json

# Use with `ahat -s` using http://ag/19698024.
# Extract strings from ahat string dump file that are in another file (e.g. package names)


def main():
    # First arg: file containing all packages, generate it with: pm list packages | sed -e 's/^package://'
    packages_file= sys.argv[1]

    # Second arg: ahat string dump, create with `ahat -s` using http://ag/19698024.
    ahat_json_file = sys.argv[2]

    packages = []
    with open(packages_file) as f:
        packages = [s.rstrip() for s in f.readlines()]

    packages_dict = {s: s for s in packages }

    # pprint(packages)
    # pprint(packages_dict)

    with open(ahat_json_file) as f:
        ahat_json = json.load(f)

    # pprint(ahat_json)

    for l in ahat_json:
        s = l[2]
        if s in packages_dict:
            print(s)


if __name__ == "__main__":
    main()
