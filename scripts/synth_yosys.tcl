# Standalone Yosys synthesis (area-oriented, 5 ns ABC delay target).
# Usage: yosys -c scripts/synth_yosys.tcl   (LIB and ROOT must be set in the environment)
yosys -import
set lib $::env(LIB)
set root $::env(ROOT)
foreach f {alu control memory mux4 register_bank top} {
  read_verilog -sv $root/src/rtl_synth/$f.sv
}
hierarchy -check -top top
synth -top top -flatten
dfflibmap -liberty $lib
abc -liberty $lib -D 5000
opt_clean -purge
hilomap -hicell sky130_fd_sc_hd__conb_1 HI -locell sky130_fd_sc_hd__conb_1 LO
setundef -zero
opt_clean
tee -o $root/synth/stat_tt.rpt stat -liberty $lib
write_verilog -noattr $root/synth/top_yosys.v
