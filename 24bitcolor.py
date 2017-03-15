#!/usr/bin/python2.7
# -*- coding: utf-8 -*-

import sys

for i in xrange(0, 255):
    sys.stdout.write('\x1b[48;2;%d;0;0m' % i)
    sys.stdout.write(' ')

sys.stdout.write('\n')

for i in xrange(0, 255):
    sys.stdout.write('\x1b[48;2;0;%d;0m' % i)
    sys.stdout.write(' ')

sys.stdout.write('\n')

for i in xrange(0, 255):
    sys.stdout.write('\x1b[48;2;0;0;%dm' % i)
    sys.stdout.write(' ')

sys.stdout.write('\n')

for i in xrange(0, 255):
    sys.stdout.write('\x1b[48;2;%d;%d;%dm' % (i, i, i))
    sys.stdout.write(' ')

sys.stdout.write('\n')
