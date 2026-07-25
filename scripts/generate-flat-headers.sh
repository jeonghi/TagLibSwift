#!/bin/bash
#
# generate-flat-headers.sh
#
# Populates Sources/CTagLibCore/include/taglib/ with a FLAT copy of every
# public TagLib C++ header (*.h / *.tcc) found under Sources/CTagLibCore/taglib/**,
# plus config.h. This mirrors TagLib's own `make install` layout (all headers
# land in a single include/taglib/ dir).
#
# Why: SwiftPM only exposes a target's `publicHeadersPath` (as -I) to dependents,
# NOT its internal cxxSettings.headerSearchPath entries. TagLib headers use FLAT
# includes (e.g. fileref.h does `#include "tfile.h"`) but the source is scattered
# across ~25 subdirs. Flattening into one dir makes both `<taglib/fileref.h>` and
# its sibling `#include "tfile.h"` resolve deterministically for dependent targets
# (CTagLibBridge and TagLibSwiftCxx).
#
# Regenerate this whenever the vendored TagLib source is updated. See UPDATING.md.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$REPO_ROOT/Sources/CTagLibCore/taglib"
CONFIG_DIR="$REPO_ROOT/Sources/CTagLibCore/config"
OUT_DIR="$REPO_ROOT/Sources/CTagLibCore/include/taglib"

if [ ! -d "$SRC_DIR" ]; then
  echo "error: $SRC_DIR not found" >&2
  exit 1
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

count=0
while IFS= read -r -d '' header; do
  base="$(basename "$header")"
  if [ -e "$OUT_DIR/$base" ]; then
    echo "error: basename collision flattening headers: $base" >&2
    exit 1
  fi
  cp "$header" "$OUT_DIR/$base"
  count=$((count + 1))
done < <(find "$SRC_DIR" \( -name '*.h' -o -name '*.tcc' \) -print0)

# config.h is pulled by some headers (e.g. tdebug.h) via `#include "config.h"`.
cp "$CONFIG_DIR/config.h" "$OUT_DIR/config.h"
cp "$CONFIG_DIR/taglib_config.h" "$OUT_DIR/taglib_config.h"

echo "Flattened $count taglib headers (+config) into $OUT_DIR"
