# Build an 8-bit CPU chip layout with open-source tools (SkyWater SKY130)

This is a hands-on, student-friendly walkthrough. It takes a small 8-bit CPU from **SystemVerilog source code** to a **GDSII layout**, the file a foundry uses to make a chip. Every step uses free, open-source tools and the public SkyWater **sky130A** process design kit (PDK).

Every picture below comes from this design. The pictures are screenshots and plots made by the same open tools that run the flow (OpenROAD, KLayout, Yosys, Icarus Verilog and OpenSTA). The script that remakes them is [`docs/scripts/make_figures.sh`](docs/scripts/make_figures.sh). Every number comes from a report file named in the text.

> **Who is this for?** Students who know a little digital logic (gates, flip-flops, a clock) and want to see how a design becomes a physical chip. You do not need to have used any EDA tool before.

This repository does not ship a foundry PDK or any proprietary files. The PDK is downloaded with `make pdk`. The checked-in results come from LibreLane 3.0.17 (Classic flow) and sky130A (ciel pin `8afc8346a57fe1ab7934ba5a6056ea8b43078e71`).

## Contents

0. [The big picture](#0-the-big-picture)
1. [The design: an 8-bit CPU](#1-the-design-an-8-bit-cpu)
2. [Verification: does the logic work?](#2-verification-does-the-logic-work)
3. [Logic synthesis: from code to logic gates](#3-logic-synthesis-from-code-to-logic-gates)
4. [Physical design: floorplan](#4-physical-design-floorplan)
5. [Physical design: power grid](#5-physical-design-power-grid)
6. [Physical design: placement](#6-physical-design-placement)
7. [Physical design: clock tree synthesis (CTS)](#7-physical-design-clock-tree-synthesis-cts)
8. [Physical design: routing](#8-physical-design-routing)
9. [Physical design: fill and the final GDS](#9-physical-design-fill-and-the-final-gds)
10. [Timing convergence: from synthesis to sign-off](#10-timing-convergence-from-synthesis-to-sign-off)
11. [Sign-off: timing, power, DRC, LVS](#11-sign-off-timing-power-drc-lvs)
12. [Design-space exploration (PPA)](#12-design-space-exploration-power-performance-and-area-ppa)
13. [Summary](#13-summary)
14. [Results tables](#14-results-tables)
15. [Limitations, common errors and fixes](#15-limitations-common-errors-and-fixes)
16. [Try it yourself](#16-try-it-yourself)
17. [How the figures were made](#17-how-the-figures-were-made)
18. [Glossary](#18-glossary)

---

## 0. The big picture

![The RTL-to-GDS flow used here, from RTL to sign-off](docs/img/00_flow.png)

A digital chip is designed in two halves:

- **Front end** (steps 1–3): describe the behaviour in a hardware language, simulate it, and *synthesize* it into a list of real logic gates (a **netlist**).
- **Back end**, also called **physical design** (steps 4–10): decide where every gate sits on the silicon, connect them with metal wires, and check that the result is fast enough, uses sensible power and obeys the factory's rules.

LibreLane runs all the back-end steps for you, one after another, from one config file ([`config.json`](config.json)). Each step writes its own folder under `runs/<tag>/`, such as `13-openroad-floorplan` or `35-openroad-cts`, so you can open the design at any stage. This tutorial does exactly that.

| Step | What it does | Open-source tool |
|---|---|---|
| RTL simulation | Runs testbenches on the source code | Icarus Verilog, Verilator |
| Synthesis | Turns code into sky130 standard cells | Yosys + ABC |
| Floorplan, power grid, placement, clock tree, routing | Builds the physical layout | OpenROAD (run by LibreLane) |
| Parasitic extraction | Measures wire resistance and capacitance | OpenRCX |
| Static timing and power | Checks speed and estimates power | OpenSTA |
| DRC | Checks the factory's geometry rules | Magic, KLayout |
| LVS | Checks that the layout matches the netlist | Netgen |
| Layout viewing and GDS | Draws and writes the final layout | KLayout, Magic |
| Formal equivalence (optional, partial) | Proves RTL and netlist do the same thing | Yosys EQY |

---

## 1. The design: an 8-bit CPU

**What it is.** A small CPU written in SystemVerilog. The top-level module is `top` ([`src/rtl/top.sv`](src/rtl/top.sv)). Its parts are:

- **ALU** ([`alu.sv`](src/rtl/alu.sv)): add, subtract, multiply and divide on 8-bit numbers, with a 16-bit result and `zero` and `error` flags (error is set on divide-by-zero).
- **Register banks** ([`register_bank.sv`](src/rtl/register_bank.sv)): hold the two operands (A and B), the instruction, the flags and the 16-bit output.
- **Memory** ([`memory.sv`](src/rtl/memory.sv)): eight 16-bit words, with LOAD and STORE.
- **Control** ([`control.sv`](src/rtl/control.sv)): a finite-state machine (FSM) that steps through `RST → FETCH → EXECUTE → STORE`.
- **Input muxes** ([`mux4.sv`](src/rtl/mux4.sv)): pick each operand from `din_1`, `din_2`, `din_3` or the previous result.

![Block diagram of the CPU: inputs, muxes, registers, ALU, memory, control and outputs](docs/img/01_architecture.png)

**The instruction word.** `cmdin` is 7 bits wide:

| Bits | Meaning |
|---|---|
| `cmdin[6:5]` | Operand A source: `00` din_1, `01` din_2, `10` din_3, `11` dout_high (previous result) |
| `cmdin[4:3]` | Operand B source: `00` din_1, `01` din_2, `10` din_3, `11` dout_low (previous result) |
| `cmdin[2:0]` | Operation: `000` ADD, `001` SUB, `010` MUL, `011` DIV, `101` LOAD, `110` STORE. `100` and `111` act as NOPs (the testbench expects `dout = 0xFFFF`, `error = 1`) |

For LOAD and STORE, the memory address is operand A.

**The control FSM.** Each instruction takes three clock cycles: FETCH loads the operands, EXECUTE computes and registers the result, and STORE writes memory (for the STORE instruction) and raises `cpu_rdy` so the next instruction can start.

![Control FSM: RST, FETCH, EXECUTE, STORE](docs/img/02_fsm.png)

**Why it matters.** Before you write any code, know your data path (where the numbers flow) and your control (who decides when). Every later step, even the timing report in step 10, is easier to read with this picture in mind.

**One change for synthesis.** `src/rtl/` is the original RTL. `src/rtl_synth/` is the copy used for synthesis, generated by `make prep` ([`scripts/prep_rtl.sh`](scripts/prep_rtl.sh)). Its only change is a default `out = '0;` at the start of the ALU's `always_comb` block. Without it, the ALU leaves `out` unassigned for unused opcodes, which creates a **latch** by accident, and Yosys turns that into a combinational loop. The testbenches pass on both copies. `src/rtl/mux4_registered.sv` is a small unused helper; `top` does not use it.

---

## 2. Verification: does the logic work?

### 2.1 The testbench and the waveforms

**What it is.** A **testbench** ([`src/tb/tb_light.sv`](src/tb/tb_light.sv), [`src/tb/tb_nop.sv`](src/tb/tb_nop.sv)) drives the CPU's inputs, waits for the clock edges, and compares the outputs with expected values. For example, `ADD 10+20` must give `dout = 0x001e`, and `DIV 10/0` must give `error = 1`.

**Why it matters.** Bugs are cheapest to fix here. Once the design is a layout, a logic bug means redoing everything.

**Command:**

```bash
make sim   # Icarus and Verilator, on src/rtl and src/rtl_synth
```

**The picture.** This is the waveform of `tb_light` (rendered from the simulator's VCD file). Read it top to bottom:

- `rst` goes low, and the FSM starts cycling FETCH → EXEC → STORE.
- `cpu_rdy` is high only in STORE, when a new instruction may be given.
- In the first instruction `cmdin = 0001000` (A = din_1, B = din_2, ADD), and `dout` becomes `0x001e` (10 + 20 = 30).
- The second instruction is SUB 20 − 20, so `dout = 0x0000` and `zero` goes high.
- Later, MUL 200 × 200 gives `0x9c40` (40,000), DIV 100 / 5 gives `0x0014`, and DIV 10 / 0 sets `error`.

![RTL waveform of tb_light: clk, rst, cmdin, operands, FSM state, cpu_rdy, dout, zero, error](docs/img/03_rtl_waveform.png)

Zoom in on single instructions to see the three-cycle rhythm. ADD 10 + 20: the operands are loaded in FETCH, the result appears when EXECUTE ends, and `cpu_rdy` rises in STORE:

![Zoom on ADD 10+20](docs/img/29_wave_add.png)

DIV 10 / 0: the ALU refuses to divide by zero, so the result is `0xffff` and `error` goes to 1:

![Zoom on DIV 10/0](docs/img/30_wave_div0.png)

**Result:** `tb_light` passes 16/16 checks and `tb_nop` passes 19/19, on the original RTL and the synthesis copy, with both Icarus Verilog and Verilator 5.044.

---

### 2.2 How much can we trust the RTL?

No test can prove that a design has no bugs. What you can do is stack up independent kinds of evidence:

| Evidence | What it checks | Status in this repo |
|---|---|---|
| Self-checking testbenches | Every instruction's `dout`, `zero` and `error` against expected values; `cpu_rdy` at every FETCH, EXECUTE and STORE | 16/16 and 19/19 checks |
| Two different simulators | That the result does not depend on one tool's interpretation of SystemVerilog | Icarus and Verilator agree |
| Gate-level simulation | That synthesis and place-and-route did not change the behaviour | 35/35 on the final netlist (section 11.1) |
| Formal equivalence | A mathematical proof that RTL and netlist match | Partial: 32 PASS, 19 UNKNOWN (section 11.7) |
| Code coverage | Which lines, branches, toggles and FSM transitions the tests exercised | **Not measured yet** (see exercise 7) |

To raise confidence further: measure coverage, add constrained-random stimulus, and add assertions that check the `cpu_rdy` protocol on every cycle.

### 2.3 Findings while writing the tests

- **`tb_light` covers the six real operations.** `tb_nop` adds the two NOP codes (`100`, `111`), which give `dout = 0xFFFF` and `error = 1`, and checks that memory keeps its value afterwards.
- **LOAD sets `error = 1`.** During a LOAD's EXECUTE the ALU sees `nvalid_data = 1`, and the flags are still registered. The testbench expects this; it is a design choice worth knowing.
- **STORE does not change `dout`,** and the memory write takes effect when the FSM leaves STORE.
- **A hidden latch in the ALU**, found during synthesis (section 3.3).

---

## 3. Logic synthesis: from code to logic gates

**What it is.** Synthesis reads the SystemVerilog and builds a circuit from the **standard cells** of the sky130 library (`sky130_fd_sc_hd`). A standard cell is a small, pre-drawn gate such as a NAND, a flip-flop or a multiplexer. Yosys does this in two phases:

1. It turns the code into generic logic: comparators, multiplexers and registers.
2. It **maps** that logic to real library cells (ABC picks the gates, `dfflibmap` picks the flip-flops), using the cell timing and area from the Liberty file `sky130_fd_sc_hd__tt_025C_1v80.lib`.

**Why it matters.** This is where your code becomes hardware. The cells chosen here decide most of the area and much of the speed.

### 3.1 Two small examples

**Small example 1: the 4-to-1 mux (`mux4`, with WIDTH = 1).** First Yosys sees the `case` statement as generic logic: three comparisons of `select` and a parallel mux (`$pmux`):

![Yosys schematic of mux4 after proc/opt: three $eq comparators and a $pmux](docs/img/04_yosys_mux4_rtl.png)

After mapping to sky130, the whole thing becomes **one** library cell, `sky130_fd_sc_hd__mux4_2`:

![Yosys schematic of mux4 mapped to sky130: a single mux4_2 cell](docs/img/05_yosys_mux4_gates.png)

**Small example 2: a 2-bit register (`register_bank`, with WIDTH = 2).** Each bit becomes a `dfrtp` flip-flop (a D flip-flop with active-low reset, so the reset goes through an inverter) and a `mux2` that either keeps the old value or loads a new one when `wr_en = 1`:

![Yosys schematic of a 2-bit register: dfrtp flip-flops, mux2 enable muxes, clkinv on reset](docs/img/06_yosys_regbank_gates.png)

### 3.2 Quality of results (QoR)

**Commands and settings:**

```bash
make synth   # standalone Yosys run: scripts/synth_yosys.tcl, report in synth/stat_tt.rpt
make flow    # the full flow; its synthesis uses "SYNTH_STRATEGY": "DELAY 1" from config.json
```

**Results:**

- Standalone Yosys, area-oriented, does not close timing ([`reports/yosys_standalone/stat_tt.rpt`](reports/yosys_standalone/stat_tt.rpt)): **1,004 cells, 10,188.5 µm²**, of which 48.79 % is flip-flops.
- Yosys inside the LibreLane 5 ns flow, delay-oriented (`DELAY 1`): **1,352 cells, 15,269.6 µm²** (from the run's `06-yosys-synthesis/reports/stat.rpt`, not checked in).

The delay-oriented run is about 50 % larger, because it uses bigger, faster gates. That is the usual **area-versus-speed trade-off**.

Where does the area go? A separate, non-flattened Yosys run (made only for this figure, so its total of 1,003 cells is close to but not the same as the runs above) shows that the **memory** (8 × 16 flip-flops with write enable) and the **ALU** (adder, subtractor, multiplier and divider) take about 78 % of its 10,695.3 µm²:

![Cell area per module from a hierarchical Yosys run](docs/img/31_area_by_module.png)

### 3.3 The ALU latch

With the original `src/rtl/alu.sv`, Yosys stops with:

```text
ERROR: Latch inferred for signal `\ALU.\out' from always_comb process ...
```

The `always_comb` block does not assign `out` for every opcode, so the hardware must *remember* the old value, which needs a latch. That is not what `always_comb` promises. The fix in `src/rtl_synth/alu.sv` is one line, a default `out = '0;` at the top of the block (section 1). Lesson: in combinational code, give every output a value on every path.

---

## 4. Physical design: floorplan

**What it is.** The floorplan sets the size of the **die** (the whole chip) and the **core** (the inner area where cells go), and fills the core with **rows**. Every standard cell in sky130_fd_sc_hd is the same height (one row, 2.72 µm), so cells sit in rows like books on shelves.

**Why it matters.** Too small, and the tools cannot fit or route the cells. Too big, and you waste silicon.

**Config** ([`config.json`](config.json)):

```json
"FP_SIZING": "relative",
"FP_CORE_UTIL": 50
```

This tells OpenROAD to size the core so that the synthesized cells fill 50 % of it, leaving room for buffers and wires. The result (from `metrics.json` and the floorplan log):

- Die: **185.795 × 196.515 µm = 36,511.5 µm²**
- Core: **30,349.1 µm²**, with **64 rows**

![Floorplan: die outline, core and 64 empty placement rows](docs/img/07_floorplan.png)

Next, OpenROAD adds **tap cells** (they tie the silicon wells to power and ground, which prevents latch-up; here one every 13 µm, `FP_TAPCELL_DIST`) and **end caps** at both ends of every row. The final layout has 429 tap cells and 128 end caps (2 × 64 rows):

![Rows after tap-cell and end-cap insertion](docs/img/08_tap_endcap.png)

The input and output pins are placed around the edge in a later step (`25-openroad-ioplacement`). You can see them as small triangles in the placement pictures below.

---

## 5. Physical design: power grid

**What it is.** The power distribution network (PDN) is a grid of metal that carries VPWR (1.8 V) and VGND (0 V) to every cell. In this design (from the run's resolved configuration):

- **met1 rails**, 0.48 µm wide, along every row. Each cell touches them at its top and bottom edges.
- **met4 vertical stripes**, 1.6 µm wide, with a 153.6 µm pitch.
- **met5 horizontal stripes**, 1.6 µm wide, with a 153.18 µm pitch.
- **Vias** that connect the layers where they cross.

**Why it matters.** A weak grid causes **IR drop**: the voltage sags, cells slow down, and in bad cases the chip fails. Section 10 checks this.

![Power grid: met1 rails on every row, met4 vertical and met5 horizontal straps](docs/img/09_pdn.png)

Zoomed in on the top-left corner, you can see the met1 rails along the rows, the stripes, and the vias where they connect:

![Close-up of the power grid corner: rails, stripes and vias](docs/img/10_pdn_zoom.png)

---

## 6. Physical design: placement

**What it is.** Placement gives every logic cell (about 1,650 in the final layout) a location in the rows. It happens in two phases:

1. **Global placement** (RePlAce, step `28-openroad-globalplacement`) spreads the cells out like charged particles, pulling connected cells together. Cells can overlap a bit at this stage.
2. **Detailed placement** (step `34-openroad-detailedplacement`) **legalizes** them: it snaps every cell onto a row and a site, with no overlaps.

Between the two, OpenROAD also resizes gates and adds buffers to fix long wires and slow paths (`repair_design`).

**Why it matters.** Good placement means short wires, which means faster timing, less power and easier routing.

**Config:** `"PL_TARGET_DENSITY_PCT": 60`. The placer aims for about 60 % cell density in every region.

Global placement (power nets hidden so you can see the cells):

![Global placement: cells spread across the core](docs/img/11_global_placement.png)

The **placement density** heat map shows where the cells are crowded (red) and where they are sparse (blue):

![Placement density heat map after global placement](docs/img/12_placement_density.png)

Detailed placement: every cell is now legal, inside a row:

![Detailed placement of the whole core](docs/img/13_detailed_placement.png)

Close up, you can see each cell's outline and pins, the cell names, and the met1 power rails between the rows:

![Close-up of legal placement with cell names](docs/img/14_detailed_placement_zoom.png)

Coloured by cell type (from the final database), the 173 flip-flops (red) sit mostly in the left half, with the logic gates (blue) and buffers (orange) around them:

![Final placement coloured by cell type](docs/img/15_placement_by_type.png)

---

## 7. Physical design: clock tree synthesis (CTS)

**What it is.** The `clk` pin has to drive all **173 flip-flops**. One wire cannot do that: it would be far too slow and the clock edge would reach each flip-flop at a different time (**skew**). Clock tree synthesis (TritonCTS, step `35-openroad-cts`) builds a tree of clock buffers instead.

For this design (read from the post-CTS database): the `clk` pin drives a root buffer, which drives **16** leaf buffers, which drive the flip-flops. That is **17 clock buffers**, **18 clock nets** and **3 levels**. The coloured lines show which buffer drives what. They are drawn straight; the real wires are routed in step 8.

![Clock tree after CTS: clk pin, root buffer, leaf buffers and flip-flops](docs/img/16_cts_tree.png)

**Why it matters.** Skew eats into your timing budget. After CTS the timing tool uses the real clock arrival times, not ideal ones. The `metrics.json` file reports a worst setup skew of 0.518 ns and a hold slack of **+0.453 ns**, so there are no hold violations.

After CTS, the **pin density** map shows where many cell pins crowd together; those spots are harder to route:

![Pin density heat map after CTS](docs/img/32_cts_pin_density.png)

---

## 8. Physical design: routing

**What it is.** Routing turns every logical connection into real metal. sky130 has a local-interconnect layer (li1) and five metal layers (met1–met5), and this flow may route on met1 to met5 (`RT_MIN_LAYER`, `RT_MAX_LAYER`). Routing happens in two phases:

1. **Global routing** (FastRoute, step `39-openroad-globalrouting`) divides the chip into tiles and decides which tiles each net passes through. Its **congestion** map shows where wiring demand is highest:

   ![Global routing congestion heat map](docs/img/17_global_route_congestion.png)

2. **Detailed routing** (TritonRoute, step `45-openroad-detailedrouting`) draws the exact wires and vias on the routing tracks and fixes rule violations over several passes. In this run the violation count went 34 → 2 → 4 → 0 → 0 over iterations 0 to 4 (`metrics.json`, `route__drc_errors__iter:*`).

![Fully routed design](docs/img/18_detailed_routing.png)

Close up (about 12 × 9 µm), you can see horizontal and vertical wires on different layers, connected by vias:

![Close-up of detailed routing: wires on several metal layers and vias](docs/img/19_detailed_routing_zoom.png)

**Results** (`metrics.json`): routed wirelength **51,969 µm** (about 5.2 cm of wire in a chip 0.19 mm wide), **13,457 vias**, **0 routing DRC errors** and **0 antenna violations**.

---

## 9. Physical design: fill and the final GDS

**What it is.** The empty gaps in the rows are filled with **fill** and **decap** cells (decaps are small capacitors that steady the supply). Then the layout is written as **GDSII**: polygons on numbered layers, which is what the mask shop uses. Magic and KLayout both write a GDS, and LibreLane compares the two (**XOR**). Here they match exactly.

The OpenROAD view of the final database, including fill:

![Final OpenROAD database with fill cells](docs/img/20_final_with_fill.png)

The real GDS, as KLayout shows it with the sky130 layer colours:

![Final GDS of the CPU rendered by KLayout](docs/img/21_gds_full.png)

At high zoom (12 × 9 µm), you see the shapes inside the cells (diffusion, polysilicon and local interconnect) with the metal wires and vias on top:

![Close-up of the final GDS showing transistors, local interconnect and metal](docs/img/22_gds_zoom.png)

For comparison, here is a single standard cell from the sky130 library, `sky130_fd_sc_hd__nand2_1` (a 2-input NAND), rendered from the PDK's own GDS. Two polysilicon gates (the vertical red strips) cross the PMOS diffusion at the top and the NMOS diffusion at the bottom, and the power rails run along the top and bottom edges:

![Layout of the sky130 nand2_1 standard cell](docs/img/23_std_cell_nand2.png)

```bash
klayout runs/final_5ns/final/gds/top.gds   # open the GDS yourself
```

---

## 10. Timing convergence: from synthesis to sign-off

The flow measures timing several times as the design becomes more real. Each STA step in the run writes WNS and TNS (from `state_out.json` of steps `*-openroad-staprepnr`, `*-openroad-stamidpnr*` and `*-openroad-stapostpnr`):

![Setup WNS and TNS at each stage of the 5 ns run](docs/img/33_timing_convergence.png)

How to read it:

- **After synthesis** the clock is ideal and there are no wires yet, and WNS is already −2.811 ns.
- **After placement and CTS**, real distances and a real clock tree make it worse (−3.788 and −3.861 ns).
- **The post-CTS resizer** swaps in bigger gates and adds buffers on the slow paths, which helps a lot (−1.096 ns).
- **After global routing** the wire estimates get more realistic (−1.235 ns).
- **Sign-off** uses the real extracted wires (SPEF) and ends at **−1.506 ns**.

The repairs cost area, because every added buffer or bigger gate takes space (section 11.2 shows the final mix). Timing that looks fine early in the flow can still fail at sign-off, which is why you check it at every stage.

---

## 11. Sign-off: timing, power, DRC, LVS

Sign-off asks four questions. Is the chip fast enough? How much power does it use? Does it obey the factory's rules? Does the layout match the netlist?

### 11.1 Gate-level simulation

The same two testbenches are run on the **final routed netlist** (`make gls`). The outputs match the RTL simulation exactly: **tb_light 16/16 and tb_nop 19/19, 35/35 checks.** (The netlist is flattened, so internal signals such as the FSM state are no longer visible by name.)

![Gate-level simulation of the final netlist: same outputs as RTL](docs/img/24_gls_waveform.png)

### 11.2 What ended up on the chip

![Instance count and area by cell type in the final layout](docs/img/25_cell_composition.png)

The final layout has 5,441 instances. About 1,650 of them are logic cells (gates, flip-flops, buffers, inverters and the clock buffers). The rest are tap, end-cap, fill and decap cells.

### 11.3 Static timing analysis (STA)

**What it is.** OpenSTA adds up the delay of every gate and wire on every path between flip-flops, using the real wire parasitics extracted by OpenRCX (a SPEF file). It compares each path with the clock period. **Slack** = required time − arrival time. A positive slack means the path is fast enough; a negative one means it is too slow.

The constraints are in [`constraints/top.sdc`](constraints/top.sdc): a 5 ns clock (200 MHz) with 10 % uncertainty, and input and output delays.

```bash
make sta   # reports/final_5ns/summary.rpt, power reports
```

At 5 ns, **10 of the 191 timing endpoints fail** (the endpoints are 172 flip-flop data inputs and 19 output ports; all 10 failures are flip-flop inputs). The worst slack (**WNS**) is **−1.506 ns** and the total negative slack (**TNS**) is **−7.527 ns**:

![Histogram of setup slack over all timing endpoints at 5 ns](docs/img/26_timing_slack_histogram.png)

The worst path ([`docs/critical_path_5ns.txt`](docs/critical_path_5ns.txt)) starts at the operand-B register (`ALU_inst.in2[2]`). It passes through **32 gates and buffers** and ends at the result-register bit that drives `dout_low[0]`. Its data arrives at 6.459 ns, but it is needed by 4.953 ns:

```text
Startpoint: _2494_ (rising edge-triggered flip-flop clocked by clk)
Endpoint: _2507_ (rising edge-triggered flip-flop clocked by clk)
...
                   4.953   data required time
                  -6.459   data arrival time
-----------------------------------------------------------------
                  -1.506   slack (VIOLATED)
```

Drawn on the layout, the same path wanders across the chip. Each long hop is a long wire, and long wires add delay:

![The worst path drawn on the final placement](docs/img/34_critical_path_layout.png)

And in time, each bar is one cell's delay. You can see where the 6.459 ns go:

![The worst path as a timeline of cell delays](docs/img/35_critical_path_time.png)

**Lesson:** a single-cycle 8-bit multiplier and divider is too much logic for 5 ns in this flow. The 8 ns run ([`config_8ns.json`](config_8ns.json)) comes much closer: WNS **−0.437 ns**, 2 violating endpoints. The real fix is architectural: pipeline the MUL/DIV over several cycles, or relax the clock. **Hold** timing passes in both runs (+0.453 ns).

### 11.4 Power

Using switching activity from the `tb_light` gate-level simulation (VCD), OpenSTA reports **3.74 mW** at 5 ns ([`reports/final_5ns/power_vcd.rpt`](reports/final_5ns/power_vcd.rpt)). Flip-flops use the most, and the clock tree alone uses about a quarter:

![Power breakdown: sequential, combinational and clock](docs/img/27_power_breakdown.png)

Without a VCD, OpenSTA assumes a default activity and reports 6.14 mW. Real activity matters!

### 11.5 IR drop

OpenROAD's power-grid analyzer (PSM, step `57-openroad-irdropreport`) solves the grid as a resistor network. With default activity, the worst drop on VPWR is **1.57 mV** (0.09 % of 1.8 V) and on VGND **1.18 mV**. The grid in section 5 is more than strong enough for this small design.

![Static IR-drop map of VPWR](docs/img/28_ir_drop_vpwr.png)

### 11.6 Physical verification: DRC, LVS, antenna and XOR

| Check | What it asks | Tool | Result |
|---|---|---|---|
| DRC | Are all widths, spacings and overlaps legal for the factory? | Magic, KLayout | **0** and **0** |
| LVS | Does the layout contain exactly the transistors and connections of the netlist? | Netgen | **0** errors |
| Antenna | Could a long wire collect charge during manufacturing and damage a gate? | OpenROAD | **0** nets, **0** pins |
| XOR | Are the Magic and KLayout GDS files identical? | KLayout | **0** differences |

(These come from `metrics.json`: `magic__drc_error__count`, `klayout__drc_error__count`, `design__lvs_error__count`, `antenna__violating__nets`, `antenna__violating__pins` and `design__xor_difference__count`.) There are no DRC markers to show in a picture, because there are none.

### 11.7 Formal equivalence (optional)

`make eqy` tries to *prove* that the RTL and the final netlist are the same logic. It is only partly successful: 51 partitions, 167 matched comparison points, **32 PASS**, **19 UNKNOWN** (not proven either way). Functional confidence rests on the 35/35 gate-level checks above.

---

## 12. Design-space exploration: power, performance and area (PPA)

**PPA** is the triangle every chip designer balances: **P**ower, **P**erformance (speed) and **A**rea. Ten LibreLane variants were tried (synthesis strategy, fanout limits, Booth multiplier, buffering and clock period) and logged in [`reports/librelane_experiments.csv`](reports/librelane_experiments.csv):

![WNS versus area for the ten LibreLane trials](docs/img/36_design_space.png)

At 5 ns, no setting closes timing. The best WNS at 5 ns was `tuned_5ns` (−1.351 ns), but `rt_d1` (−1.506 ns) had a much better TNS (−7.527 against −11.59 ns) and was kept as the final configuration. Relaxing the clock helps most: 7 ns gives −0.38 ns and 8 ns gives −0.437 ns, each with a different variant. A clean sweep of the clock period (the same settings at 3, 4, 5, 6, 8, 10 … ns, with power and energy per cycle) has not been run yet; see exercise 2.

---

## 13. Summary

- **The complete open-source flow ran end to end:** Icarus/Verilator → Yosys → OpenROAD (floorplan, PDN, placement, CTS, routing) → OpenRCX → OpenSTA → Magic/KLayout/Netgen, on sky130A.
- **It is functionally correct and physically clean:** 35/35 gate-level checks, and 0 DRC, LVS, antenna and XOR errors.
- **It does not meet 200 MHz:** at 5 ns, WNS is −1.506 ns. The bottleneck is the single-cycle multiply/divide logic (sections 11.3 and 12).
- **Size and power:** die 36,511.5 µm², 3.74 mW with real activity at 5 ns.
- **Next steps:** pipeline MUL/DIV, run a clean clock-period sweep, and measure coverage.

---

## 14. Results tables

All numbers are for the typical corner `nom_tt_025C_1v80`. The 5 ns target (200 MHz) is not met. The 8 ns run is closer, but still has a small setup violation.

### Sign-off, 5 ns target (`config.json`, run `final_5ns`)

| Metric | Value | Source |
|---|---|---|
| Setup WNS / TNS | **−1.506 ns / −7.527 ns** (10 violating endpoints) | `reports/final_5ns/summary.rpt` and `reports/final_5ns/metrics.json` (`timing__setup__ws`, `timing__setup__tns`, `timing__setup_vio__count`) |
| Hold worst slack | **+0.453 ns** (0 violations) | same files (`timing__hold__ws`, `timing__hold_vio__count`) |
| Die | **185.795 × 196.515 µm**, **36,511.5 µm²** | `metrics.json` (`design__die__bbox`, `design__die__area`) |
| Core area | **30,349.1 µm²** | `metrics.json` (`design__core__area`) |
| Standard-cell area | **19,444.9 µm²** (2,081 standard cells; 5,441 instances including fill and tap) | `metrics.json` (`design__instance__area__stdcell`, `design__instance__count__stdcell`, `design__instance__count`) |
| Routed wirelength | **51,969 µm** | `metrics.json` (`route__wirelength`) |
| Routing DRC | **0** | `metrics.json` (`route__drc_errors`) |
| Antenna violations | **0** nets, **0** pins | `metrics.json` (`antenna__violating__nets`, `antenna__violating__pins`, `route__antenna_violation__count`) |
| Magic DRC / KLayout DRC / Netgen LVS / Magic–KLayout XOR | **0 / 0 / 0 / 0** | `metrics.json` (`magic__drc_error__count`, `klayout__drc_error__count`, `design__lvs_error__count`, `design__xor_difference__count`) |
| Power, default activity | **6.14 mW** | `reports/final_5ns/power_default_activity.rpt` and `metrics.json` (`power__total` = 0.00613656 W) |
| Power, VCD from `tb_light` GLS | **3.74 mW** (clock tree 1.03 mW) | `reports/final_5ns/power_vcd.rpt` |

### Sign-off, 8 ns target (`config_8ns.json`, run `final_8ns`)

| Metric | Value | Source |
|---|---|---|
| Setup WNS / TNS | **−0.437 ns / −0.751 ns** (2 violating endpoints) | `reports/final_8ns/metrics.json` |
| Hold worst slack | **+0.453 ns** (0 violations) | same file |
| Die | same as 5 ns: **185.795 × 196.515 µm**, **36,511.5 µm²** | same file |
| Standard-cell area | **16,879.9 µm²** (1,870 standard cells; 5,904 instances including fill and tap) | same file |
| Routed wirelength | **46,164 µm** | same file |
| Routing DRC / antenna / Magic DRC / KLayout DRC / LVS / XOR | **0** | same file |
| Power, default activity | **3.30 mW** | `metrics.json` (`power__total` = 0.00330044 W). No VCD sign-off report was kept for this run. |

A table of ten LibreLane trials (ABC strategies, fanout, Booth, period) is in [`reports/librelane_experiments.csv`](reports/librelane_experiments.csv). Its `logic_area_um2` column is the area recorded during each trial (18,894.3 µm² for `final_5ns`, 16,343.2 µm² for `final_8ns`). That is close to, but not the same as, standard-cell area minus fill in `metrics.json`. More detail is in [`reports/results_summary.md`](reports/results_summary.md).

### Simulation

All of the following printed `TEST PASS`:

| Source | `tb_light` | `tb_nop` |
|---|---|---|
| Original RTL, Icarus Verilog | 16/16 | 19/19 |
| Original RTL, Verilator 5.044 | 16/16 | 19/19 |
| Synthesis copy, Icarus and Verilator | 16/16 | 19/19 |
| Gate-level sim of the `final_5ns` netlist (Icarus) | 16/16 | 19/19 |

---

## 15. Limitations, common errors and fixes

**Limitations of this version**

- Setup timing is not met at 5 ns or 8 ns.
- Only the typical corner (`nom_tt_025C_1v80`) is analysed (`STA_CORNERS` in `config.json`). A real sign-off also checks the slow and fast corners.
- Formal equivalence is partial (19 UNKNOWN partitions).
- Code coverage was not measured.
- IR drop was computed with default activity, not with the VCD.
- The design is a hard block with pins, not a full chip with I/O pads.

**Errors you may hit, and what fixed them here**

| Error or symptom | Cause | Fix |
|---|---|---|
| Yosys: `Latch inferred for signal \ALU.\out` (and, in the flow, a combinational loop) | `always_comb` does not assign `out` for every opcode | Default `out = '0;` (`scripts/prep_rtl.sh` → `src/rtl_synth/`) |
| `make pdk` fails with HTTP 500 | The default PDK mirror is down | The Makefile already uses `--data-source github-releases:…` |
| GLS does not compile: no parameter `WIDTH` on `top` | The final netlist is flattened and has no parameters | `scripts/run_gls.sh` drops `#(.WIDTH(WIDTH))` from the testbench copy |
| EQY cannot match the FSM state bits | Synthesis re-encodes the FSM as one-hot | `scripts/eqy_template.eqy` applies the same recoding to the RTL side |
| STA inside `openroad` fails to link cells | OpenROAD needs the LEF (or an `.odb`) before the Liberty | Read the `.odb` first (`docs/scripts/sta_endpoints.tcl`), or use the standalone `sta` binary |
| Timing still fails after changing ABC options | The long path is in the architecture (MUL/DIV), not in the tool settings | Pipeline or relax the clock (section 12) |

---

## 16. Try it yourself

### Set up and run the whole flow

Use a LibreLane environment (this flow was run with LibreLane 3.0.17):

```bash
cd ~/librelane && nix-shell
cd /path/to/cpu8-sky130-openflow

make pdk      # once: install sky130A at the pinned ciel version under ~/.ciel
make sim      # RTL simulation: Icarus and Verilator, original RTL and synthesis copy
make synth    # standalone Yosys (area)
make flow     # RTL to GDS, default tag final_5ns / config.json (about 3–6 min on 8 cores)
make gls      # gate-level simulation of the final netlist
make sta      # OpenSTA sign-off (SPEF + VCD from tb_light)
make eqy      # optional formal check; needs the PDK formal models from a flow run
docs/scripts/make_figures.sh   # remake every picture in this README
```

If ciel returns a 500 error from the default mirror, `make pdk` already uses the GitHub releases source. The `runs/` directory is not checked in; `make flow` regenerates it.

### Open any stage in the OpenROAD GUI

```bash
openroad -gui
# then, in the OpenROAD Tcl console:
read_db runs/final_5ns/34-openroad-detailedplacement/top.odb
```

Swap in any stage folder: `13-openroad-floorplan`, `21-openroad-generatepdn`, `35-openroad-cts`, `45-openroad-detailedrouting` or `final/odb`.

### Exercises

1. **Write a new test.** Add a `run_op` call to `tb_light.sv` for `SUB 5-10`. What 16-bit value do you expect? (Hint: two's complement.) Run `make sim`.
2. **Sweep the clock.** Run `make flow TAG=final_8ns CONFIG=config_8ns.json`, then copy `config.json` and try 4, 6 and 10 ns yourself. At what period does WNS become positive? How do the area and power change?
3. **Change the utilization.** Set `"FP_CORE_UTIL": 35` or `65`. What happens to the die size, the wirelength and the routing congestion map?
4. **Find the critical path.** Open `docs/critical_path_5ns.txt`. Which gates add the most delay? How many are buffers (`rebuffer*`) that the tool added?
5. **Pipeline the ALU.** Split MUL/DIV over two cycles (this also needs a change in the FSM), rerun the testbenches, then rerun the flow at 5 ns.
6. **Compare synthesis strategies.** Change `SYNTH_STRATEGY` to `"AREA 0"` and compare the cell area and WNS with the trials in `reports/librelane_experiments.csv`.
7. **Measure coverage.** Build `tb_nop` with Verilator using `--coverage`, run it, and read the result with `verilator_coverage`. Which lines and FSM transitions are never exercised?

---

## 17. How the figures were made

Every image in [`docs/img/`](docs/img/) is generated from this design's own open-source flow outputs by [`docs/scripts/make_figures.sh`](docs/scripts/make_figures.sh):

| Figures | Made with |
|---|---|
| Flow, block and FSM diagrams | Graphviz (`docs/diagrams/*.dot`) |
| Waveforms | The simulators' VCD files, plotted with matplotlib (`docs/scripts/plot_waves.py`) |
| Synthesis schematics | Yosys `show` (`docs/scripts/yosys_show.tcl`) |
| Floorplan, power grid, placement, density and congestion maps, routing | Headless OpenROAD `save_image` on each stage's `.odb` (`docs/scripts/or_shot.sh`) |
| Clock tree and cell-type views | `.odb` exported with OpenROAD's Python API (`docs/scripts/export_odb.py`), plotted with matplotlib |
| Final GDS and standard cell | KLayout in batch mode (`docs/scripts/kl_render.py`, `kl_cell.py`) |
| Slack histogram, power and IR drop | OpenSTA and OpenROAD reports, plotted with matplotlib (`docs/scripts/plot_reports.py`) |
| Timing convergence, critical path on the layout and in time, trials, area per module | Flow metrics, OpenSTA path report, `.odb` geometry and a hierarchical Yosys run (`docs/scripts/plot_extras.py`) |

The standard-cell picture is drawn from the sky130 library GDS in the PDK (Apache-2.0, SkyWater/Google), which `make pdk` downloads. It is not included in this repository.

---

## 18. Glossary

### Design and verification

| Term | Meaning |
|---|---|
| **Coverage** | How much of the design the tests exercised: lines, branches, conditions, toggles, FSM states and transitions. |
| **FSM** | Finite-state machine: the controller that steps through RST, FETCH, EXECUTE and STORE. |
| **GLS** | Gate-level simulation: simulating the synthesized or routed netlist instead of the RTL. |
| **Latch (inferred)** | Memory created by accident when combinational code does not assign an output in every case. |
| **RTL** | Register-transfer level: hardware described as registers and the logic between them (here, SystemVerilog). |
| **Self-checking testbench** | A testbench that compares outputs with expected values and prints PASS or FAIL by itself. |
| **VCD** | Value change dump: a waveform file from simulation. Here it is also used for power analysis. |

### Simulation, synthesis and power

| Term | Meaning |
|---|---|
| **ABC** | The logic optimizer inside Yosys that maps logic to library gates. |
| **IR drop** | The voltage lost across the resistance of the power grid (V = I × R). |
| **Liberty (.lib)** | A file with the timing, power and function of each standard cell at one corner. |
| **Netlist** | A list of cells and the wires (nets) that connect them. |
| **PDK** | Process design kit: everything the foundry provides to design for its process (cells, rules, models). sky130A is open source. |
| **PPA** | Power, performance and area: the three quantities a design trades against each other. |
| **QoR** | Quality of results: the area, timing and power a tool achieved. |
| **SDC** | The standard Tcl-based constraints format for clocks, input and output delays and loads. |
| **Standard cell** | A pre-designed gate (NAND, flip-flop, mux and so on) of fixed height that fits in a row. |

### Physical design and sign-off

| Term | Meaning |
|---|---|
| **Antenna effect** | Charge that collects on a long metal wire during manufacturing and can damage a transistor gate. Fixed with diodes or by changing layers. |
| **Clock-to-Q** | The delay from a clock edge to the flip-flop output changing. |
| **CTS** | Clock tree synthesis: building a buffer tree so the clock reaches every flip-flop at nearly the same time. |
| **Decap / fill** | Cells that fill empty row space. Decaps also add capacitance that steadies the supply. |
| **DEF / ODB** | Files that describe a placed and routed design. DEF is text; ODB is OpenROAD's database. |
| **Die / core** | The die is the whole chip rectangle. The core is the inner area where standard cells are placed. |
| **DRC** | Design rule check: are all the shapes legal for the factory? |
| **GDSII** | The final layout file format: polygons on numbered layers. |
| **Hold time / setup time** | A flip-flop's data must be stable for some time *before* the clock edge (setup) and *after* it (hold). |
| **LEF** | A file with the size, pins and blockages of each cell and the routing layers, used by place and route. |
| **LVS** | Layout versus schematic: does the layout implement exactly the netlist? |
| **Path group** | A set of timing paths reported together, e.g. register-to-register, or the asynchronous reset paths. |
| **PDN** | Power distribution network: the metal grid for VPWR and VGND. |
| **Skew** | The difference in clock arrival time between two flip-flops. |
| **Slack, WNS, TNS** | Slack = required − arrival time. WNS is the worst slack; TNS is the sum of all negative slacks. |
| **SPEF** | A file with the resistance and capacitance of every routed wire, used by STA. |
| **STA** | Static timing analysis: checking every path's delay without simulation. |
| **Tap cell** | A cell that connects the transistor wells to power and ground, which prevents latch-up. |
| **Utilization** | The fraction of the core area covered by cells. |
| **Via** | A vertical connection between two metal layers. |
| **XOR check** | A comparison of two GDS files, shape by shape. |

---

## Notes

- Timing is limited by a long combinational path through the multiplier and divider. Pipelining MUL/DIV, or relaxing the clock period beyond 8 ns, would be the natural next step in this open flow.
- `constraints/top.sdc` uses `CLOCK_PERIOD` from the LibreLane config, so the same file serves both the 5 ns and 8 ns runs.

## Credits

Design and implementation:

- **Fermín Franco** (project lead): Ensenada Flow; Universidad Autónoma de Baja California (UABC).
- **Luis Alberto Burgos Acosta, M.Sc.**: Ensenada Flow; Universidad Autónoma de Baja California (UABC), Facultad de Pedagogía e Innovación Educativa, Mexicali.

## License

MIT. See `LICENSE`. The sky130A PDK is a separate work, obtained with `make pdk`, and is not included here.
