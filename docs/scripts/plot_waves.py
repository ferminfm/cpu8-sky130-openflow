"""Render a VCD file to a PNG timing diagram (matplotlib). Usage: plot_waves.py in.vcd out.png title [t_end_ns [t_start_ns]]"""
import sys, re
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt

def parse_vcd(path):
    ids, scope, sigs = {}, [], {}
    ts = 1.0; t = 0
    with open(path) as f:
        defs = True
        for line in f:
            line = line.strip()
            if not line: continue
            if defs:
                if line.startswith("$timescale"):
                    m = re.search(r"(\d+)\s*(ps|ns|fs|us)", line + next(f, ""))
                    if m: ts = int(m.group(1)) * {"fs":1e-6,"ps":1e-3,"ns":1,"us":1e3}[m.group(2)]
                elif line.startswith("$scope"): scope.append(line.split()[2])
                elif line.startswith("$upscope"): scope.pop()
                elif line.startswith("$var"):
                    p = line.split(); w, code, name = int(p[2]), p[3], p[4]
                    full = ".".join(scope + [name])
                    ids.setdefault(code, []).append(full); sigs[full] = (w, [])
                elif line.startswith("$enddefinitions"): defs = False
                continue
            if line[0] == "#": t = int(line[1:]) * ts; continue
            if line[0] in "01xzXZ" and len(line) > 1 and not line.startswith("$"):
                v, code = line[0], line[1:]
            elif line[0] in "bB":
                v, code = line[1:].split()
            else: continue
            for n in ids.get(code, []): sigs[n][1].append((t, v))
    return sigs

def val(v):
    try: return int(v, 2)
    except ValueError: return None

def main():
    vcd, out, title = sys.argv[1], sys.argv[2], sys.argv[3]
    tend = float(sys.argv[4]) if len(sys.argv) > 4 else None
    tmin = float(sys.argv[5]) if len(sys.argv) > 5 else 0.0
    s = parse_vcd(vcd)
    want = [("tb_cpu.clk","clk"),("tb_cpu.rst","rst"),("tb_cpu.cmdin","cmdin"),("tb_cpu.din_1","din_1"),("tb_cpu.din_2","din_2"),
            ("tb_cpu.dut.control_inst.state","FSM state"),("tb_cpu.cpu_rdy","cpu_rdy"),("tb_cpu.dout","dout"),("tb_cpu.zero","zero"),("tb_cpu.error","error")]
    def find(k):
        if k in s: return k
        alt = k.replace("tb_cpu.", "tb_cpu.dut.", 1)
        return alt if alt in s else None
    if "tb_cpu.dout" not in s and find("tb_cpu.dout_high"):
        want = [w for w in want if w[0] != "tb_cpu.dout"]
        want.insert(7, ("tb_cpu.dout_low", "dout_low")); want.insert(7, ("tb_cpu.dout_high", "dout_high"))
    want = [(find(k), l) for k, l in want if find(k)]
    tmax = tend or max(ch[-1][0] for w, ch in s.values() if ch)
    fig, ax = plt.subplots(figsize=(13, 0.55 * len(want) + 1.2), dpi=110)
    names = {0:"RST",1:"FETCH",2:"EXEC",3:"STORE"}
    for i, (k, lab) in enumerate(want):
        y = len(want) - 1 - i
        w, ch = s[k]
        before = [c for c in ch if c[0] <= tmin]
        ch = ([(tmin, before[-1][1])] if before else []) + [c for c in ch if tmin < c[0] <= tmax]
        ch = ch or [(tmin, "x")]
        pts = ch + [(tmax, ch[-1][1])]
        if w == 1:
            xs, ys = [], []
            for (t0, v), (t1, _) in zip(pts, pts[1:]):
                yy = y + (0.7 if v == "1" else 0.1)
                xs += [t0, t1]; ys += [yy, yy]
            ax.plot(xs, ys, color="#1f6fb2", lw=1.2, drawstyle="steps-post")
        else:
            for (t0, v), (t1, _) in zip(pts, pts[1:]):
                if t1 <= t0: continue
                d = min(0.25, (t1 - t0) / 4)
                ax.fill([t0, t0 + d, t1 - d, t1, t1 - d, t0 + d], [y + .4, y + .7, y + .7, y + .4, y + .1, y + .1], color="#e8f4fd", ec="#1f6fb2", lw=0.8)
                n = val(v)
                if n is None: txt = "x"
                elif "state" in lab: txt = names.get(n, str(n))
                elif "dout" in lab: txt = f"0x{n:0{(w+3)//4}x}"
                elif "cmdin" in lab: txt = f"{n:07b}"
                else: txt = str(n)
                if t1 - t0 > ((tmax - tmin) / 70): ax.text((t0 + t1) / 2, y + .4, txt, ha="center", va="center", fontsize=7)
        ax.text(tmin - (tmax - tmin) * 0.01, y + 0.4, lab, ha="right", va="center", fontsize=9, family="monospace")
    ax.set_xlim(tmin, tmax); ax.set_ylim(-0.2, len(want)); ax.set_yticks([])
    ax.set_xlabel("time (ns)"); ax.set_title(title, fontsize=11)
    for sp in ["left", "right", "top"]: ax.spines[sp].set_visible(False)
    ax.grid(axis="x", color="#dddddd", lw=0.5)
    fig.tight_layout(); fig.savefig(out); print("saved", out)
main()
