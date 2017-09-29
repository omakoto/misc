#!/bin/bash

cd "${0%/*}"

for t in *.test; do
  echo "Running $t:"
  ./"$t"
  echo
done
