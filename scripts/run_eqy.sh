#!/usr/bin/env bash
# Usage: scripts/run_eqy.sh <netlist.v> <formal_pdk.v> <output_dir>
# formal_pdk.v is the sky130 functional models LibreLane writes under
# runs/<tag>/*-yosys-eqy/ during a flow run.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NL=$(realpath "$1"); PDKV=$(realpath "$2"); OUT=$3
mkdir -p "$(dirname "$OUT")"
sed -e "s#@NETLIST@#$NL#" -e "s#@PDKV@#$PDKV#" "$ROOT/scripts/eqy_template.eqy" > "$OUT.eqy"
cd "$ROOT" && eqy -f "$OUT.eqy" -d "$OUT" -j 6
