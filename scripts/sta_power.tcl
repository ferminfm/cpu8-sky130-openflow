# Sign-off STA and power with OpenSTA.
# Usage: NL=... SPEF=... VCD=... OUT=... sta -no_init -exit scripts/sta_power.tcl
# (Inside OpenROAD, LEF must be read first; the standalone "sta" binary does not need that.)
set pdk  [expr {[info exists ::env(PDK_ROOT)] ? $::env(PDK_ROOT) : "$::env(HOME)/.ciel"}]
set root [file dirname [file dirname [file normalize [info script]]]]
read_liberty $pdk/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_verilog $::env(NL)
link_design top
read_spef $::env(SPEF)
read_sdc $root/constraints/top.sdc
set_propagated_clock [all_clocks]
set out $::env(OUT)
report_checks -path_delay max -fields {slew cap input_pin} -digits 3 > $out/timing_max.rpt
report_checks -path_delay min -digits 3 > $out/timing_min.rpt
report_tns  -digits 3 >  $out/summary.rpt
report_wns  -digits 3 >> $out/summary.rpt
report_worst_slack -max -digits 3 >> $out/summary.rpt
report_worst_slack -min -digits 3 >> $out/summary.rpt
report_power -digits 4 > $out/power_default_activity.rpt
if {[info exists ::env(VCD)] && $::env(VCD) ne ""} {
  # Switching activity from the tb_light gate-level simulation VCD.
  read_vcd -scope tb_cpu/dut $::env(VCD)
  report_power -digits 4 > $out/power_vcd.rpt
}
