# Open-source RTL-to-GDS flow for the 8-bit CPU (sky130_fd_sc_hd).
# Run inside the LibreLane environment:  cd ~/librelane && nix-shell  ->  cd <this directory>
PDK_ROOT ?= $(HOME)/.ciel
LIB      := $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
TAG      ?= final_5ns
CONFIG   ?= config.json
FINAL    := runs/$(TAG)/final

.PHONY: all pdk prep sim synth flow gls sta eqy clean
all: sim synth flow gls sta

pdk:      ## Download the sky130A PDK pin used by this project (GitHub source if the default mirror fails)
	ciel enable --pdk-family sky130 --data-source github-releases:fossi-foundation/ciel-releases 8afc8346a57fe1ab7934ba5a6056ea8b43078e71

prep:     ## Build the synthesis RTL copy (ALU latch fix)
	scripts/prep_rtl.sh

sim: prep ## 1) RTL simulation (Icarus and Verilator), original RTL and synthesis copy
	for r in rtl rtl_synth; do for s in iverilog verilator; do for t in tb_light tb_nop; do \
	  echo "== $$r $$s $$t"; scripts/run_sim.sh $$s $$t $$r | tail -1; done; done; done

synth: prep ## 2) Standalone Yosys synthesis (area)
	mkdir -p synth && LIB=$(LIB) ROOT=$(CURDIR) yosys -q -c scripts/synth_yosys.tcl -l synth/yosys.log
	grep -E "Chip area|cells$$" synth/stat_tt.rpt | tail -2

flow: prep ## 3) RTL-to-GDS with LibreLane (Yosys, OpenROAD, OpenSTA, Magic, KLayout, Netgen)
	librelane --run-tag $(TAG) --overwrite $(CONFIG) || true
	python3 -c "import json;m=json.load(open('$(FINAL)/metrics.json'));[print(k,m[k]) for k in ['timing__setup__ws','timing__setup__tns','timing__hold__ws','magic__drc_error__count','klayout__drc_error__count','design__lvs_error__count','route__drc_errors','power__total']]"

gls:      ## 4) Gate-level simulation of the final netlist (same testbenches)
	for t in tb_light tb_nop; do scripts/run_gls.sh $(FINAL)/nl/top.nl.v $$t sim/gls_$(TAG)/$$t; done

sta:      ## 5) Sign-off STA and power with OpenSTA (OpenRCX SPEF + GLS VCD)
	mkdir -p reports/$(TAG)
	NL=$(FINAL)/nl/top.nl.v SPEF=$(FINAL)/spef/nom/top.nom.spef VCD=sim/gls_$(TAG)/tb_light/tb_cpu.vcd \
	  OUT=reports/$(TAG) sta -no_init -exit scripts/sta_power.tcl
	cat reports/$(TAG)/summary.rpt; grep ^Total reports/$(TAG)/power_vcd.rpt

eqy:      ## 6) Formal equivalence, RTL vs final netlist (Yosys EQY) -- partial, see README
	scripts/run_eqy.sh $(FINAL)/nl/top.nl.v formal/formal_pdk_sky130_fd_sc_hd.v formal/eqy_$(TAG) || true

clean:
	rm -rf sim synth formal/eqy_* formal/*.eqy formal/*.log runs
