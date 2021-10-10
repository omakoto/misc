#!/usr/bin/python3

import random

r = range(2, 10)

all = [(x, y) for x in r for y in r ]

random.shuffle(all)

# print(all)

for i, q in enumerate(all):
    print(f'{i + 1}: {q[0]} x {q[1]}')
