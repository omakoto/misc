#!/bin/bash

set -e
. mutil.sh

in=/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf
out=/boot/grub/fonts/DejaVuSansMono36.pf2


# Generate a GRUB-compatible font with specified size
# from a TTF (type-type font)
ee sudo grub-mkfont --output=$out --size=36 $in

grub_file=/etc/default/grub

# Edit high-level GRUB configuration file
# Add/modify the variable `GRUB_FONT`
# GRUB_FONT=/boot/grub/fonts/DejaVuSansMono36.pf2
ee sudo sed -i -e '/^GRUB_FONT=/d' $grub_file

ee bash -c "echo GRUB_FONT=$out | sudo tee -a $grub_file"

# Regenerate low-level GRUB configurations
ee sudo update-grub
