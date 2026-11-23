#!/usr/bin/env bash
# Regenerate every figure in docs/img/ from a finished flow run.
# Run from the repository root, inside the LibreLane environment, after `make sim flow gls`:
#   docs/scripts/make_figures.sh            (uses runs/final_5ns and sim/)
#   RUN=runs/final_5ns SIM=sim docs/scripts/make_figures.sh
# Needs: openroad, klayout, yosys, dot (graphviz), python3 with matplotlib + pillow; pngquant is optional.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd); cd "$ROOT"
RUN=$(realpath "${RUN:-runs/final_5ns}"); SIM=$(realpath "${SIM:-sim}")
export PDK_ROOT=${PDK_ROOT:-$HOME/.ciel}
LIB=$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
S=$ROOT/docs/scripts; IMG=$ROOT/docs/img; TMP=$(mktemp -d); mkdir -p "$IMG"
export QT_QPA_PLATFORM=offscreen
shot() { "$S/or_shot.sh" "$@"; }
st() { ls -d "$RUN"/*-"$1" | head -1; }   # stage directory by step name, e.g. st openroad-cts

echo "== diagrams (graphviz)"
dot -Tpng -Gdpi=110 docs/diagrams/flow.dot         -o "$TMP/00_flow.png"
dot -Tpng -Gdpi=110 docs/diagrams/architecture.dot -o "$TMP/01_architecture.png"
dot -Tpng -Gdpi=110 docs/diagrams/fsm.dot          -o "$TMP/02_fsm.png"

echo "== waveforms (VCD -> matplotlib)"
python3 "$S/plot_waves.py" "$SIM/rtl/iverilog/tb_light/tb_cpu.vcd" "$TMP/03_rtl_waveform.png" "RTL simulation (Icarus Verilog), tb_light: first instructions" 100
python3 "$S/plot_waves.py" "$SIM/gls_final_5ns/tb_light/tb_cpu.vcd" "$TMP/24_gls_waveform.png" "Gate-level simulation of the final routed netlist (Icarus), tb_light: same inputs, same results" 100

echo "== synthesis schematics (yosys show)"
LIB=$LIB SRC=$ROOT/src/rtl_synth OUT=$TMP yosys -q -c "$S/yosys_show.tcl" > /dev/null
dot -Tpng -Gdpi=100 -Grankdir=LR "$TMP/yosys_mux4_rtl.dot"     -o "$TMP/04_yosys_mux4_rtl.png"
dot -Tpng -Gdpi=100 -Grankdir=LR "$TMP/yosys_mux4_gates.dot"   -o "$TMP/05_yosys_mux4_gates.png"
dot -Tpng -Gdpi=100 -Grankdir=LR "$TMP/yosys_regbank_gates.dot" -o "$TMP/06_yosys_regbank_gates.png"

echo "== OpenROAD stage screenshots"
SB='"Misc/Scale bar" true'; NOPG=('"Nets/Power" false' '"Nets/Ground" false')
AREA="-5 -5 191 202" shot "$(st openroad-floorplan)/top.odb"        "$TMP/07_floorplan.png" '"Rows/unithd" true' "$SB"
shot "$(st openroad-tapendcapinsertion)/top.odb"                     "$TMP/08_tap_endcap.png" '"Rows/unithd" true' "$SB"
shot "$(st openroad-generatepdn)/top.odb"                            "$TMP/09_pdn.png" "$SB"
AREA="0 150 60 200" shot "$(st openroad-generatepdn)/top.odb"        "$TMP/10_pdn_zoom.png" '"Rows/unithd" true' "$SB"
shot "$(st openroad-globalplacement)/top.odb"                        "$TMP/11_global_placement.png" "${NOPG[@]}" "$SB"
shot "$(st openroad-globalplacement)/top.odb"                        "$TMP/12_placement_density.png" "${NOPG[@]}" '"Heat Maps/Placement Density" true' "$SB"
shot "$(st openroad-detailedplacement)/top.odb"                      "$TMP/13_detailed_placement.png" "${NOPG[@]}" "$SB"
AREA="70 70 95 88" shot "$(st openroad-detailedplacement)/top.odb"   "$TMP/14_detailed_placement_zoom.png" "${NOPG[@]}" '"Misc/Instances/Names" true' "$SB"
shot "$(st openroad-globalrouting)/top.odb"                          "$TMP/17_global_route_congestion.png" "${NOPG[@]}" '"Heat Maps/Routing Congestion" true' "$SB"
shot "$(st openroad-detailedrouting)/top.odb"                        "$TMP/18_detailed_routing.png" "$SB"
AREA="74 74 86 83" W=1200 shot "$(st openroad-detailedrouting)/top.odb" "$TMP/19_detailed_routing_zoom.png" "$SB"
shot "$RUN/final/odb/top.odb"                                        "$TMP/20_final_with_fill.png" "$SB"

echo "== clock tree and cell mix (ODB -> JSON -> matplotlib)"
ODB="$(st openroad-cts)/top.odb" OUT=$TMP/cts.json openroad -python -exit "$S/export_odb.py" > /dev/null 2>&1
ODB="$RUN/final/odb/top.odb"     OUT=$TMP/final.json openroad -python -exit "$S/export_odb.py" > /dev/null 2>&1
python3 "$S/plot_layout_data.py" "$TMP/cts.json" "$TMP/final.json" "$TMP"
mv "$TMP/cts_tree.png" "$TMP/16_cts_tree.png"; mv "$TMP/placement_by_type.png" "$TMP/15_placement_by_type.png"; mv "$TMP/cell_composition.png" "$TMP/25_cell_composition.png"

echo "== final GDS (KLayout) and one standard cell"
G=$RUN/final/gds/top.gds
klayout -zz -r "$S/kl_render.py" -rd inp="$G" -rd out="$TMP/21_gds_full.png" -rd width=1400 > /dev/null
klayout -zz -r "$S/kl_render.py" -rd inp="$G" -rd out="$TMP/22_gds_zoom.png" -rd width=1200 -rd box=74,74,86,83 > /dev/null
klayout -zz -r "$S/kl_cell.py" -rd cell=sky130_fd_sc_hd__nand2_1 -rd out="$TMP/23_std_cell_nand2.png" -rd width=600 > /dev/null

echo "== timing, power, IR drop charts"
RUN=$RUN OUT=$TMP openroad -no_init -exit "$S/sta_endpoints.tcl" | grep -E "^(wns|tns)"
python3 "$S/plot_reports.py" "$TMP/endpoints_max.txt" reports/final_5ns/power_vcd.rpt "$(st openroad-irdropreport)/net-VPWR.csv" "$TMP"
mv "$TMP/timing_slack_histogram.png" "$TMP/26_timing_slack_histogram.png"; mv "$TMP/power_breakdown.png" "$TMP/27_power_breakdown.png"; mv "$TMP/ir_drop_vpwr.png" "$TMP/28_ir_drop_vpwr.png"
cp "$TMP/critical_path.txt" "$IMG/../critical_path_5ns.txt"

echo "== shrink and copy to docs/img"
python3 - "$TMP" "$IMG" <<'EOF'
import sys, glob, os, shutil, subprocess
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
for f in sorted(glob.glob(os.path.join(src, "[0-9][0-9]_*.png"))):
    im = Image.open(f); w = im.size[0]
    if w > 1100: im = im.resize((1100, round(im.size[1] * 1100 / w)), Image.LANCZOS)
    out = os.path.join(dst, os.path.basename(f))
    while True:   # keep each image under ~480 KiB: quantize, and shrink dense layouts if still too big
        im.convert("RGB").save(out, optimize=True)
        if shutil.which("pngquant"):
            subprocess.run(["pngquant", "--force", "--skip-if-larger", "--quality=30-90", "--speed=1", "--output", out, out])
        if os.path.getsize(out) < 480 * 1024 or im.size[0] < 700: break
        im = im.resize((round(im.size[0] * 0.85), round(im.size[1] * 0.85)), Image.LANCZOS)
    print(f"{os.path.basename(out):40s} {os.path.getsize(out)//1024:5d} KiB")
EOF
rm -rf "$TMP"
