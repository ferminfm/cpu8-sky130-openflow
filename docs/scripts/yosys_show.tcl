# Small schematics with Yosys "show". Usage: LIB=<liberty> SRC=src/rtl_synth OUT=<dir> yosys -c yosys_show.tcl
set lib $::env(LIB); set src $::env(SRC); set out $::env(OUT)
# 1) mux4 with WIDTH=1 after proc/opt: generic RTL cells
yosys read_verilog -sv $src/mux4.sv
yosys chparam -set WIDTH 1 mux4
yosys hierarchy -top mux4
yosys proc
yosys opt -full
yosys clean
yosys show -format dot -prefix $out/yosys_mux4_rtl -notitle -colors 3 mux4
# 2) the same mux4 mapped to sky130_fd_sc_hd standard cells
yosys synth -top mux4 -flatten
yosys abc -liberty $lib
yosys opt_clean
yosys show -format dot -prefix $out/yosys_mux4_gates -notitle -colors 3 mux4
yosys design -reset
# 3) register_bank with WIDTH=2 mapped to cells: flip-flops with async reset + enable mux
yosys read_verilog -sv $src/register_bank.sv
yosys chparam -set WIDTH 2 register_bank
yosys synth -top register_bank -flatten
yosys dfflibmap -liberty $lib
yosys abc -liberty $lib
yosys opt_clean
yosys show -format dot -prefix $out/yosys_regbank_gates -notitle -colors 3 register_bank
