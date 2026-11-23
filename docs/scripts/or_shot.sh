#!/usr/bin/env bash
# Headless OpenROAD screenshot of one flow stage.
# Usage: [AREA="x1 y1 x2 y2"] [W=1400] or_shot.sh <stage.odb> <out.png> ['"Display/Control" true|false' ...]
set -euo pipefail
odb=$1 png=$2; shift 2; opts=""
for a in "$@"; do opts="$opts -display_option [list $a]"; done
area=""; [ -n "${AREA:-}" ] && area="-area {$AREA}"
tcl=$(mktemp --suffix=.tcl)
printf 'read_db %s\nsave_image -width %s %s %s %s\n' "$odb" "${W:-1400}" "$area" "$opts" "$png" > "$tcl"
QT_QPA_PLATFORM=offscreen openroad -no_init -exit "$tcl" 2>&1 | grep -E "ERROR|WARN" || true
rm -f "$tcl"
