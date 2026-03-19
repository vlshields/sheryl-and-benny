#!/bin/bash -eu

OUT_DIR="build/desktop"
mkdir -p $OUT_DIR
odin build src/main_desktop -out:$OUT_DIR/sheryl_and_benny -vet -strict-style -disallow-do -warnings-as-errors
cp -R ./assets/ ./$OUT_DIR/
echo "Desktop build created in ${OUT_DIR}"
