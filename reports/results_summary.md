# Results summary

Verified figures for the 8-bit CPU open-source flow. All paths are relative to the repository root.

## 5 ns sign-off (run final_5ns, config.json, corner nom_tt_025C_1v80)

From reports/final_5ns/summary.rpt (OpenSTA after SPEF):

- tns max -7.527
- wns max -1.506
- worst slack max -1.506
- worst slack min 0.453

From reports/final_5ns/metrics.json (LibreLane):

- timing__setup__ws = -1.5059389717047442
- timing__setup__tns = -7.526914415902214
- timing__setup_vio__count = 10
- timing__hold__ws = 0.45284499654110005
- timing__hold_vio__count = 0
- design__die__bbox = 0.0 0.0 185.795 196.515
- design__die__area = 36511.5
- design__core__area = 30349.1
- design__instance__area__stdcell = 19444.9
- design__instance__count__stdcell = 2081
- design__instance__count = 5441
- route__wirelength = 51969
- route__drc_errors = 0
- antenna__violating__nets = 0
- antenna__violating__pins = 0
- route__antenna_violation__count = 0
- magic__drc_error__count = 0
- klayout__drc_error__count = 0
- design__lvs_error__count = 0
- design__xor_difference__count = 0
- power__total = 0.006136560346931219  (default activity, watts)

From reports/final_5ns/power_vcd.rpt (OpenSTA, VCD from tb_light GLS):

- Total 3.7402e-03 W (clock 1.0343e-03 W)

From reports/final_5ns/power_default_activity.rpt:

- Total 6.1366e-03 W  (matches metrics.json power__total)

## 8 ns sign-off (run final_8ns, config_8ns.json)

From reports/final_8ns/metrics.json only (no separate OpenSTA report was kept):

- timing__setup__ws = -0.4374669639251892
- timing__setup__tns = -0.7511049772520847
- timing__setup_vio__count = 2
- timing__hold__ws = 0.4534879267128438
- timing__hold_vio__count = 0
- design__die__bbox = 0.0 0.0 185.795 196.515
- design__die__area = 36511.5
- design__instance__area__stdcell = 16879.9
- design__instance__count__stdcell = 1870
- design__instance__count = 5904
- route__wirelength = 46164
- route__drc_errors = 0
- antenna__violating__nets = 0
- antenna__violating__pins = 0
- route__antenna_violation__count = 0
- magic__drc_error__count = 0
- klayout__drc_error__count = 0
- design__lvs_error__count = 0
- design__xor_difference__count = 0
- power__total = 0.003300443524494767  (default activity, watts)

## Simulation

Original RTL and synthesis copy, Icarus Verilog and Verilator 5.044:

- tb_light: TEST PASS (16 checks)
- tb_nop: TEST PASS (19 checks)

Gate-level simulation of the final_5ns netlist (Icarus):

- tb_light: TEST PASS (16 checks)
- tb_nop: TEST PASS (19 checks)
- Combined: 35/35 checks

These counts were read from the simulation logs of the source flow run (logs are not checked in; rerun with make sim / make gls).

## Synthesis area

- Standalone Yosys (reports/yosys_standalone/stat_tt.rpt): Chip area 10188.521600 µm², 1004 cells.
- LibreLane Yosys in the 5 ns flow (DELAY 1), from the run's 06-yosys-synthesis/reports/stat.rpt (not checked in): Chip area 15269.644800 µm², 1352 cells.

## Experiments CSV

reports/librelane_experiments.csv lists ten trials. The final rows record:

- final_5ns: WNS -1.506, TNS -7.527, hold WS 0.453, logic_area_um2 18894.3, DRC/LVS 0
- final_8ns: WNS -0.437, TNS -0.751, hold WS 0.453, logic_area_um2 16343.2, DRC/LVS 0

logic_area_um2 is the value recorded during those trials and is not identical to design__instance__area__stdcell in metrics.json.

## PDK pin

ciel 8afc8346a57fe1ab7934ba5a6056ea8b43078e71 (sky130A), from the Makefile and from the resolved flow configuration of the source run.
