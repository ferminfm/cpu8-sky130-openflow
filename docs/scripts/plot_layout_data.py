"""Plots from exported ODB JSON: clock tree (post-CTS) and cell composition (final). Usage: plot_layout_data.py cts.json final.json outdir"""
import sys, json, re, collections
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle
from matplotlib.collections import PatchCollection, LineCollection

cts, fin, out = json.load(open(sys.argv[1])), json.load(open(sys.argv[2])), sys.argv[3]

def category(master, clockdrivers, name):
    m = master.replace("sky130_fd_sc_hd__", "").replace("sky130_ef_sc_hd__", "")
    if re.match(r"(fill|decap)", m) and name.startswith("PHY_EDGE"): return "End caps"
    if re.match(r"tapvpwrvgnd", m): return "Tap cells"
    if re.match(r"(fill|decap)", m): return "Fill / decap"
    if name in clockdrivers: return "Clock tree buffers"
    if re.match(r"(dfr|dfs|dfx|edf|dfb|sdf|dl)", m): return "Flip-flops"
    if re.match(r"(buf|clkbuf|clkdlybuf|dlygate|dlymetal)", m): return "Buffers (timing / IO)"
    if re.match(r"(inv|clkinv)", m): return "Inverters"
    if re.match(r"conb", m): return "Tie cells"
    return "Logic gates"

COL = {"Logic gates": "#4c78a8", "Flip-flops": "#e45756", "Buffers (timing / IO)": "#f2a541", "Inverters": "#9c755f",
       "Clock tree buffers": "#2ca02c", "Tie cells": "#bab0ac", "Tap cells": "#7f7f7f", "End caps": "#555555", "Fill / decap": "#d9d9d9"}

def drivers(d): return {c["driver"][2] for c in d["clock_nets"] if c["driver"] and c["driver"][3] != "PORT"}

def draw_cells(ax, d, alpha=1.0, only=None, grey=False):
    cd = drivers(d); groups = collections.defaultdict(list)
    for name, master, typ, x0, y0, x1, y1 in d["insts"]:
        c = category(master, cd, name)
        if only and c not in only: continue
        groups[c].append(Rectangle((x0, y0), x1 - x0, y1 - y0))
    for c, rs in groups.items():
        ax.add_collection(PatchCollection(rs, facecolor="#cfcfcf" if grey else COL[c], edgecolor="none", alpha=alpha))
    return groups

def frame(ax, d):
    x0, y0, x1, y1 = d["die"]; ax.add_patch(Rectangle((x0, y0), x1 - x0, y1 - y0, fill=False, ec="black", lw=1))
    x0, y0, x1, y1 = d["core"]; ax.add_patch(Rectangle((x0, y0), x1 - x0, y1 - y0, fill=False, ec="#888888", lw=0.6, ls="--"))
    ax.set_xlim(d["die"][0] - 3, d["die"][2] + 3); ax.set_ylim(d["die"][1] - 3, d["die"][3] + 3)
    ax.set_aspect("equal"); ax.set_xlabel("x (µm)"); ax.set_ylabel("y (µm)")

# ---- 1) clock tree after CTS
fig, ax = plt.subplots(figsize=(9, 9.3), dpi=110)
frame(ax, cts)
cd = drivers(cts)
draw_cells(ax, cts, only={"Logic gates", "Buffers (timing / IO)", "Inverters", "Tie cells"}, grey=True)
draw_cells(ax, cts, only={"Flip-flops"}, alpha=0.9)
# level of each clock net = distance from the clock port
bydrv = {c["driver"][2]: c for c in cts["clock_nets"] if c["driver"]}
level = {}
def walk(net, lv):
    level[net["net"]] = lv
    for s in net["sinks"]:
        if s[2] in bydrv and bydrv[s[2]]["net"] not in level: walk(bydrv[s[2]], lv + 1)
root = [c for c in cts["clock_nets"] if c["driver"] and c["driver"][3] == "PORT"]
for r in root: walk(r, 0)
cmap = plt.get_cmap("viridis")
maxlv = max(level.values()) if level else 1
for c in cts["clock_nets"]:
    if not c["driver"]: continue
    lv = level.get(c["net"], maxlv)
    dx, dy = c["driver"][:2]
    segs = [[(dx, dy), (s[0], s[1])] for s in c["sinks"]]
    leaf = all(s[2] not in bydrv for s in c["sinks"])
    ax.add_collection(LineCollection(segs, colors=[cmap(lv / max(maxlv, 1))], lw=0.6 if leaf else 1.6, alpha=0.9))
draw_cells(ax, cts, only={"Clock tree buffers"})
for c in cts["clock_nets"]:
    if c["driver"] and c["driver"][3] == "PORT":
        ax.plot(*c["driver"][:2], marker="v", color="black", ms=9); ax.annotate("clk pin", c["driver"][:2], xytext=(5, -14), textcoords="offset points", fontsize=9)
nbuf = len(cd); nff = sum(1 for i in cts["insts"] if category(i[1], cd, i[0]) == "Flip-flops")
from matplotlib.lines import Line2D
h = [Rectangle((0, 0), 1, 1, fc=COL["Clock tree buffers"]), Rectangle((0, 0), 1, 1, fc=COL["Flip-flops"]), Rectangle((0, 0), 1, 1, fc="#cfcfcf"),
     Line2D([0], [0], color=cmap(0.0), lw=1.6), Line2D([0], [0], color=cmap(1.0), lw=0.8)]
ax.legend(h, [f"clock buffers ({nbuf})", f"flip-flops ({nff})", "other cells", "trunk (near the clk pin)", "leaf (buffer to flip-flops)"],
          loc="upper center", bbox_to_anchor=(0.5, -0.07), ncol=3, fontsize=8, frameon=False)
ax.set_title(f"Clock tree after CTS: {len(cts['clock_nets'])} clock nets, {maxlv + 1} levels\n(lines are logical connections, drawn straight; real wires are routed later)", fontsize=10)
fig.tight_layout(); fig.savefig(f"{out}/cts_tree.png"); plt.close(fig)
print("cts: buffers", nbuf, "flops", nff, "levels", maxlv + 1, "nets", len(cts["clock_nets"]))

# ---- 2) final cell composition (count and area)
cd = drivers(fin); cnt = collections.Counter(); area = collections.Counter()
for name, master, typ, x0, y0, x1, y1 in fin["insts"]:
    c = category(master, cd, name); cnt[c] += 1; area[c] += (x1 - x0) * (y1 - y0)
order = [c for c in COL if c in cnt]
print("total insts", sum(cnt.values()), {c: (cnt[c], round(area[c], 1)) for c in order})
fig, axs = plt.subplots(1, 2, figsize=(12, 4.6), dpi=110)
for ax, data, lab in [(axs[0], cnt, "number of instances"), (axs[1], area, "area (µm²)")]:
    vals = [data[c] for c in order]
    ax.barh(order[::-1], vals[::-1], color=[COL[c] for c in order][::-1])
    for y, v in enumerate(vals[::-1]): ax.text(v, y, f" {v:,.0f}", va="center", fontsize=8)
    ax.set_xlabel(lab); ax.spines[["top", "right"]].set_visible(False); ax.set_xlim(0, max(vals) * 1.18)
axs[1].set_yticklabels([])
fig.suptitle(f"What is inside the final layout ({sum(cnt.values()):,} instances, read from the final .odb)", fontsize=11)
fig.tight_layout(); fig.savefig(f"{out}/cell_composition.png"); plt.close(fig)

# ---- 3) final placement coloured by cell category
fig, ax = plt.subplots(figsize=(9, 9.6), dpi=110); frame(ax, fin)
g = draw_cells(ax, fin)
h = [Rectangle((0, 0), 1, 1, fc=COL[c]) for c in order]
ax.legend(h, order, loc="upper center", bbox_to_anchor=(0.5, -0.07), ncol=3, fontsize=8, frameon=False)
ax.set_title("Final placement coloured by cell type", fontsize=11)
fig.tight_layout(); fig.savefig(f"{out}/placement_by_type.png"); plt.close(fig)
