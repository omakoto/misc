#!/bin/bash


TODO: Start gnome-terminal with "almost" clean environment, but we can't use -i because we do need to inherit certain variables, such as DISPLAY
so we need to use `env -u` and clear all unneeded vars. Get all vars using `compgen -e`, and remove everything unneeded.
We need to figure out what to keep. DISPLAY, USER, HOME? Anything else?

