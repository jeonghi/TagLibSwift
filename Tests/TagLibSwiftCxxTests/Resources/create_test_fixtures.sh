#!/bin/bash
#
# Generates the multi-format smoke-test fixtures used by MultiFormatTests.
# Each is a ~1s silent clip carrying title/artist metadata:
#
#   test.flac  — FLAC        (Vorbis comments)
#   test.m4a   — MP4 / AAC   (iTunes-style atoms)
#   test.ogg   — Ogg Vorbis  (Vorbis comments)
#
# The test suite generates equivalent fixtures into a temp dir at runtime, so
# running this by hand is optional — it just mirrors what the tests do and is
# handy for manual inspection. Requires ffmpeg with aac + libvorbis encoders.
#
# Fixtures are gitignored (see .gitignore); this script and the .mp3 loader are
# the source of truth.
set -euo pipefail

gen() {
  local ext="$1" codec="$2"
  ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i anullsrc=r=44100:cl=mono -t 1 \
    -c:a "$codec" \
    -metadata title="Original Title" \
    -metadata artist="Original Artist" \
    -metadata album="Original Album" \
    "test.$ext"
  echo "created test.$ext"
}

gen flac flac
gen m4a  aac
gen ogg  libvorbis
