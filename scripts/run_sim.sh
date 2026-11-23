#!/usr/bin/env bash
# RTL simulation with Icarus Verilog or Verilator.
# Usage: scripts/run_sim.sh [iverilog|verilator] [tb_light|tb_nop] [rtl|rtl_synth]
set -euo pipefail
SIM=${1:-iverilog}; TB=${2:-tb_light}; RTLDIR=${3:-rtl}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/sim/$RTLDIR/$SIM/$TB; mkdir -p "$OUT"; cd "$OUT"
RTL="$ROOT/src/$RTLDIR/alu.sv $ROOT/src/$RTLDIR/control.sv $ROOT/src/$RTLDIR/memory.sv $ROOT/src/$RTLDIR/mux4.sv $ROOT/src/$RTLDIR/register_bank.sv $ROOT/src/$RTLDIR/top.sv"
cp "$ROOT/src/tb/$TB.sv" tb.sv
case $SIM in
  iverilog)
    iverilog -g2012 -o simv -s tb_cpu tb.sv $RTL 2>&1 | tee comp.log
    vvp -n simv +vcd 2>&1 | tee sim.log ;;
  verilator)
    verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style --top-module tb_cpu \
      --trace -o simv tb.sv $RTL 2>&1 | tee comp.log >/dev/null
    ./obj_dir/simv +vcd 2>&1 | tee sim.log ;;
esac
grep -E "TEST (PASS|FAIL)" sim.log || { echo "NO RESULT"; exit 1; }
