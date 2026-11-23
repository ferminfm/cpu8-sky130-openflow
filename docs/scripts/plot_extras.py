"""Extra figures: timing convergence per flow stage, critical path on the layout and in time,
LibreLane trials, and area per module. Usage:
  plot_extras.py <run_dir> <final.json> <critical_path.txt> <experiments.csv> <hier_stat.txt> <outdir>"""
import sys, json, re, csv, glob, os
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle
from matplotlib.collections import PatchCollection
run, finj, cp, exp, hier, out = sys.argv[1:7]

# 1) timing convergence: WNS/TNS measured by each STA step of the run
steps = [("openroad-staprepnr", "after synthesis\n(ideal clock,\nno wires)"), ("openroad-stamidpnr", "after global\nplacement"),
         ("openroad-stamidpnr-1", "after CTS"), ("openroad-stamidpnr-2", "after post-CTS\nresizing"),
         ("openroad-stamidpnr-3", "after global route\n+ post-GRT repair"), ("openroad-stapostpnr", "sign-off\n(routed, SPEF)")]
lab, wns, tns = [], [], []
for st, l in steps:
    d = [x for x in glob.glob(f"{run}/*-{st}") if re.search(rf"/\d+-{re.escape(st)}$", x)][0]
    m = json.load(open(f"{d}/state_out.json"))["metrics"]
    lab.append(l); wns.append(m["timing__setup__ws"]); tns.append(m["timing__setup__tns"])
    print(st, round(wns[-1], 3), round(tns[-1], 3))
fig, ax = plt.subplots(figsize=(11, 4.3), dpi=110); x = range(len(lab))
ax.plot(x, wns, "o-", color="#e45756", label="WNS (worst slack)"); ax.set_ylabel("WNS (ns)", color="#e45756")
for i, v in enumerate(wns): ax.annotate(f"{v:.3f}", (i, v), xytext=(0, 8), textcoords="offset points", ha="center", fontsize=8, color="#e45756")
ax2 = ax.twinx(); ax2.plot(x, tns, "s--", color="#4c78a8", label="TNS (sum of negative slack)"); ax2.set_ylabel("TNS (ns)", color="#4c78a8")
for i, v in enumerate(tns): ax2.annotate(f"{v:.2f}", (i, v), xytext=(0, -14), textcoords="offset points", ha="center", fontsize=8, color="#4c78a8")
ax.axhline(0, color="black", lw=0.6); ax.set_xticks(list(x)); ax.set_xticklabels(lab, fontsize=8)
ax.set_title("Setup timing at each stage of the 5 ns run (OpenSTA inside LibreLane)", fontsize=10)
h1, l1 = ax.get_legend_handles_labels(); h2, l2 = ax2.get_legend_handles_labels(); ax.legend(h1 + h2, l1 + l2, fontsize=8, loc="lower right", frameon=False)
fig.tight_layout(); fig.savefig(f"{out}/timing_convergence.png"); plt.close(fig)

# 2) critical path on the layout + 3) in time
first = open(cp).read().split("Startpoint:")[1]
pts = []
for line in first.splitlines():
    m = re.match(r"\s*(\d+)?\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+[\^v]\s+(\S+)/(\w+) \((\S+)\)", line)
    if m: pts.append((m.group(4), m.group(5), float(m.group(2)), float(m.group(3)), m.group(6).replace("sky130_fd_sc_hd__", "")))
req = float(re.search(r"(-?\d+\.\d+)\s+data required time", first).group(1))
slack = float(re.search(r"(-?\d+\.\d+)\s+slack", first).group(1))
d = json.load(open(finj)); pos = {i[0]: i[3:7] for i in d["insts"]}
fig, ax = plt.subplots(figsize=(8.5, 9), dpi=110)
ax.add_collection(PatchCollection([Rectangle((a, b), c - a, e - b) for n, mm, t, a, b, c, e in d["insts"] if not re.match(r"sky130_fd_sc_hd__(fill|decap|tap)", mm)], facecolor="#dddddd", edgecolor="none"))
path = []
for inst, pin, dl, t, cell in pts:
    if inst in pos and (not path or path[-1][0] != inst):
        a, b, c, e = pos[inst]; path.append((inst, (a + c) / 2, (b + e) / 2, t, cell))
xs, ys = [p[1] for p in path], [p[2] for p in path]
ax.plot(xs, ys, "-", color="#e45756", lw=1.3); ax.scatter(xs, ys, c=[p[3] for p in path], cmap="plasma", s=28, zorder=3, edgecolor="black", lw=0.3)
ax.annotate("start: operand register\n(ALU_inst.in2[2])", (xs[0], ys[0]), xytext=(10, 10), textcoords="offset points", fontsize=8)
ax.annotate("end: result register\n(drives dout_low[0])", (xs[-1], ys[-1]), xytext=(10, -22), textcoords="offset points", fontsize=8)
x0, y0, x1, y1 = d["die"]; ax.add_patch(Rectangle((x0, y0), x1 - x0, y1 - y0, fill=False)); ax.set_aspect("equal")
ax.set_xlim(x0 - 3, x1 + 3); ax.set_ylim(y0 - 3, y1 + 3); ax.set_xlabel("x (µm)"); ax.set_ylabel("y (µm)")
ax.set_title(f"Worst setup path at 5 ns drawn on the final placement: {len(path)} cells, slack {slack:.3f} ns\n(dots coloured by arrival time; lines join cells in path order, not the real wires)", fontsize=9)
fig.tight_layout(); fig.savefig(f"{out}/critical_path_layout.png"); plt.close(fig)

fig, ax = plt.subplots(figsize=(11, 5), dpi=110)
stages = [p for p in pts if p[1] in ("Q", "X", "Y") or p[1] == "D"]
for k, (inst, pin, dl, t, cell) in enumerate(stages):
    ax.barh(k, dl, left=t - dl, color="#f2a541" if cell.startswith("buf") else ("#e45756" if cell.startswith("df") else "#4c78a8"))
ax.axvline(req, color="black", ls="--", lw=1); ax.text(req, -1.2, f" required {req:.3f} ns", fontsize=8)
ax.axvline(stages[-1][3], color="#e45756", lw=1); ax.text(stages[-1][3], len(stages) + 0.3, f" arrives {stages[-1][3]:.3f} ns", fontsize=8, color="#e45756")
ax.set_yticks(range(len(stages))); ax.set_yticklabels([f"{p[0]}  {p[4]}" for p in stages], fontsize=6, family="monospace")
ax.invert_yaxis(); ax.set_xlabel("time from the clock edge (ns)")
ax.set_title(f"The same path in time: each bar is one cell's delay (blue logic, orange buffers, red flip-flop clock-to-Q); slack {slack:.3f} ns", fontsize=9)
ax.spines[["top", "right"]].set_visible(False)
fig.tight_layout(); fig.savefig(f"{out}/critical_path_time.png"); plt.close(fig)

# 4) LibreLane trials (design-space exploration)
rows = list(csv.DictReader(open(exp)))
fig, ax = plt.subplots(figsize=(10, 5), dpi=110)
cols = {"5": "#4c78a8", "7": "#f2a541", "8": "#54a24b"}
for r in rows:
    if r["run"] == "final_5ns": continue   # same numbers as rt_d1
    x, y = float(r["logic_area_um2"]), float(r["WNS_ns"])
    ax.scatter(x, y, s=60, color=cols[r["period_ns"]], edgecolor="black", lw=0.4, zorder=3)
    ax.annotate(r["run"] + (" (final 5 ns)" if r["run"] == "rt_d1" else ""), (x, y), xytext=(6, 4), textcoords="offset points", fontsize=8)
for p, c in cols.items(): ax.scatter([], [], color=c, label=f"{p} ns clock")
ax.axhline(0, color="black", lw=0.6); ax.legend(frameon=False, fontsize=8)
ax.set_xlabel("logic area recorded in the trial (µm²)"); ax.set_ylabel("setup WNS (ns)")
ax.set_title("Ten LibreLane trials (reports/librelane_experiments.csv): faster is up, smaller is left", fontsize=10)
ax.spines[["top", "right"]].set_visible(False)
fig.tight_layout(); fig.savefig(f"{out}/design_space.png"); plt.close(fig)

# 5) area per module from a hierarchical Yosys run
nice = {"ALU": "ALU", "memory": "memory (8 x 16 bit)", "mux4": "mux4 (each of 2)", "control": "control FSM", "top": "top-level glue"}
area = []
for mod, a in re.findall(r"Chip area for module '(.+)': ([\d.]+)$", open(hier).read(), re.M):
    mod = mod.replace("$paramod\\", "").lstrip("\\"); base = mod.split("\\")[0]; w = re.search(r"WIDTH=s32'(\d+)", mod)
    name = nice.get(base, base)
    if base == "register_bank":
        bits = int(w.group(1), 2); name = f"register_bank {bits}-bit" + (" (each of 2)" if bits == 8 else "")
    area.append((name, float(a)))
area.sort(key=lambda t: t[1])
fig, ax = plt.subplots(figsize=(9, 4.2), dpi=110)
ax.barh([a[0] for a in area], [a[1] for a in area], color="#4c78a8")
for k, (n, a) in enumerate(area): ax.text(a, k, f" {a:,.1f}", va="center", fontsize=8)
ax.set_xlabel("cell area (µm²)"); ax.set_xlim(0, max(a for _, a in area) * 1.15); ax.spines[["top", "right"]].set_visible(False)
ax.set_title("Where the area goes, module by module (hierarchical Yosys run made for this figure)", fontsize=10)
fig.tight_layout(); fig.savefig(f"{out}/area_by_module.png"); plt.close(fig)
print("modules", area)
