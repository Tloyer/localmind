#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$ROOT/build"
if [ ! -x "$ROOT/build/localmind-capture" ]; then
  swiftc -parse-as-library "$ROOT/native/Capture.swift" -O -o "$ROOT/build/localmind-capture"
fi
export LOCALMIND_ROOT="$ROOT"
export LOCALMIND_DATA_DIR="$ROOT/data"
export LOCALMIND_CAPTURE_BIN="$ROOT/build/localmind-capture"
exec python3 "$ROOT/localmind/server.py"
