# Per-endpoint setup slack and the critical path, after routing (OpenSTA inside OpenROAD).
# Usage: RUN=runs/final_5ns OUT=<dir> openroad -no_init -exit sta_endpoints.tcl
set pdk  [expr {[info exists ::env(PDK_ROOT)] ? $::env(PDK_ROOT) : "$::env(HOME)/.ciel"}]
set root [file dirname [file dirname [file dirname [file normalize [info script]]]]]
set run $::env(RUN); set out $::env(OUT)
read_db $run/final/odb/top.odb
read_liberty $pdk/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_spef $run/final/spef/nom/top.nom.spef
read_sdc $root/constraints/top.sdc
set_propagated_clock [all_clocks]
report_wns -digits 3
report_tns -digits 3
report_checks -path_delay max -group_path_count 2000 -endpoint_path_count 1 -format end -digits 3 > $out/endpoints_max.txt
report_checks -path_delay max -group_path_count 1 -path_group clk -fields {fanout} -digits 3 > $out/critical_path.txt
