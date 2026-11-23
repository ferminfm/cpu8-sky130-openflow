"""Charts from text reports: setup-slack histogram (OpenSTA), power breakdown (OpenSTA + VCD), IR-drop map (OpenROAD PSM).
Usage: plot_reports.py endpoints_max.txt power_vcd.rpt net-VPWR.csv outdir"""
import sys, re, csv
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
ep, pw, ir, out = sys.argv[1:5]

# 1) setup slack per endpoint, clock group only
grp, sl = None, []
for line in open(ep):
    m = re.match(r"max_delay/setup group (\S+)", line)
    if m: grp = m.group(1); continue
    m = re.search(r"\s(-?\d+\.\d+) \((MET|VIOLATED)\)", line)
    if m and grp == "clk": sl.append(float(m.group(1)))
neg = sum(1 for s in sl if s < 0)
fig, ax = plt.subplots(figsize=(9, 4), dpi=110)
bins = [x / 4 for x in range(int(min(sl) * 4) - 1, int(max(sl) * 4) + 2)]
n, b, patches = ax.hist(sl, bins=bins, edgecolor="white")
for p, left in zip(patches, b): p.set_facecolor("#e45756" if left < 0 else "#4c78a8")
ax.axvline(0, color="black", lw=1)
ax.set_xlabel("setup slack (ns)  —  negative = too slow for a 5 ns clock"); ax.set_ylabel("number of endpoints")
ax.set_title(f"Setup slack of every timing endpoint (OpenSTA, after routing, 5 ns clock): {len(sl)} endpoints, {neg} violating, worst {min(sl):.3f} ns", fontsize=10)
ax.spines[["top", "right"]].set_visible(False)
fig.tight_layout(); fig.savefig(f"{out}/timing_slack_histogram.png"); plt.close(fig)
print("endpoints", len(sl), "violating", neg, "worst", min(sl))

# 2) power breakdown
rows = {}
for line in open(pw):
    p = line.split()
    if p and p[0] in ("Sequential", "Combinational", "Clock"): rows[p[0]] = [float(v) * 1e3 for v in p[1:4]]
    if p and p[0] == "Total" and len(p) > 4: total = float(p[4]) * 1e3
fig, ax = plt.subplots(figsize=(8, 3.6), dpi=110)
names = list(rows); left = [0] * len(names)
for k, (lab, col) in enumerate([("internal", "#4c78a8"), ("switching", "#f2a541"), ("leakage", "#54a24b")]):
    vals = [rows[nm][k] for nm in names]
    ax.barh(names, vals, left=left, color=col, label=lab)
    left = [a + v for a, v in zip(left, vals)]
for y, v in enumerate(left): ax.text(v, y, f" {v:.2f} mW ({100 * v / total:.1f} %)", va="center", fontsize=9)
ax.set_xlim(0, max(left) * 1.45); ax.invert_yaxis(); ax.legend(frameon=False, fontsize=8, loc="lower right")
ax.set_xlabel("power (mW)"); ax.spines[["top", "right"]].set_visible(False)
ax.set_title(f"Power with real switching activity (VCD from tb_light gate-level sim): total {total:.2f} mW at 5 ns", fontsize=10)
fig.tight_layout(); fig.savefig(f"{out}/power_breakdown.png"); plt.close(fig)
print("power", rows, total)

# 3) IR drop map (VPWR), default activity
xs, ys, vs = [], [], []
for r in csv.DictReader(open(ir)):
    xs.append(float(r["X location"])); ys.append(float(r["Y location"])); vs.append((1.8 - float(r["Voltage"])) * 1e3)
fig, ax = plt.subplots(figsize=(7.5, 7.2), dpi=110)
sc = ax.scatter(xs, ys, c=vs, s=4, cmap="inferno_r", marker="s")
cb = fig.colorbar(sc, ax=ax, shrink=0.8); cb.set_label("IR drop on VPWR (mV)")
ax.set_aspect("equal"); ax.set_xlabel("x (µm)"); ax.set_ylabel("y (µm)")
ax.set_title(f"Static IR drop on the power net (OpenROAD PSM, default activity)\nworst {max(vs):.2f} mV of 1.8 V", fontsize=10)
fig.tight_layout(); fig.savefig(f"{out}/ir_drop_vpwr.png"); plt.close(fig)
print("ir worst mV", max(vs))
