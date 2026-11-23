#!/usr/bin/env bash
# Gate-level simulation (GLS) of a sky130 netlist with Icarus Verilog.
# Usage: scripts/run_gls.sh <netlist.v> <tb_light|tb_nop> <output_dir>
# Writes sim.log and tb_cpu.vcd (activity for the OpenSTA power analysis).
set -euo pipefail
NL=$(realpath "$1"); TB=$2; OUT=$3
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PDK_ROOT=${PDK_ROOT:-$HOME/.ciel}
V=$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/verilog
mkdir -p "$OUT"; cd "$OUT"
# The gate netlist is a flattened module top (no WIDTH parameter).
sed -e 's/top #(.WIDTH(WIDTH)) dut/top dut/' "$ROOT/src/tb/$TB.sv" > tb.sv
iverilog -g2012 -DFUNCTIONAL -DUNIT_DELAY=#0.1 -o simv -s tb_cpu \
  "$V/primitives.v" "$V/sky130_fd_sc_hd.v" "$NL" tb.sv 2>&1 > comp.log 2>&1 || { tail -20 comp.log; exit 1; }
vvp -n simv +vcd > sim.log 2>&1; grep -E "TEST (PASS|FAIL)|FAIL\]" sim.log | head || true
