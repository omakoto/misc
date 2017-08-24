#!/bin/bash

set -e
. mutil.sh

irb --noprompt <<< "$*"
