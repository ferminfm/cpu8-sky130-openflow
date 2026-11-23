# Original timing constraints in standard SDC, for OpenROAD/OpenSTA.
# Clock period comes from CLOCK_PERIOD (set by LibreLane from config.json /
# config_8ns.json). Defaults to 5.0 ns if the variable is unset.
if {[info exists ::env(CLOCK_PERIOD)]} { set clk_val $::env(CLOCK_PERIOD) } else { set clk_val 5.0 }
create_clock -name clk -period $clk_val [get_ports clk]
set_clock_uncertainty -setup [expr {$clk_val*0.1}] [get_clocks clk]
set_clock_transition [expr {$clk_val*0.1}] [get_clocks clk]
set_clock_latency -source [expr {$clk_val*0.05}] [get_clocks clk]
# Ideal network latency before CTS. After CTS the real clock tree is
# propagated and this ideal latency no longer applies.
set_clock_latency [expr {$clk_val*0.03}] [get_clocks clk]
set clk_idx [lsearch [all_inputs] [get_ports clk]]
set in_ports [lreplace [all_inputs] $clk_idx $clk_idx]
set_input_delay  [expr {$clk_val*0.4}] -clock clk $in_ports
set_output_delay [expr {$clk_val*0.5}] -clock clk [all_outputs]
set_load 0.04 [all_outputs]
set_input_transition [expr {$clk_val*0.1}] $in_ports
