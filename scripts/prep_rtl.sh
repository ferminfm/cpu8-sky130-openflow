#!/usr/bin/env bash
# Build the synthesis copy of the RTL (src/rtl_synth/).
# The only change is in alu.sv: the always_comb block does not assign "out"
# for opcodes other than ADD/SUB/MUL/DIV, which infers a 16-bit latch.
# Because "out" is also read in the same block (out == 0), Yosys turns that
# into a combinational loop and the place-and-route flow stops.
# Fix: a default "out = '0;" at the start of the block. The control unit only
# issues those four opcodes, so observable behavior is unchanged
# (tb_light / tb_nop still pass on this copy).
# The same default assignment can be applied to the original RTL if desired.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$ROOT/src/rtl_synth"
cp "$ROOT"/src/rtl/{control,memory,mux4,register_bank,top}.sv "$ROOT/src/rtl_synth/"
awk '{print} /^[[:space:]]*always_comb begin/ && !done {print "\t\tout = '"'"'0; // default assignment to avoid an inferred latch (see scripts/prep_rtl.sh)"; done=1}' "$ROOT/src/rtl/alu.sv" > "$ROOT/src/rtl_synth/alu.sv"
diff "$ROOT/src/rtl/alu.sv" "$ROOT/src/rtl_synth/alu.sv" || true
