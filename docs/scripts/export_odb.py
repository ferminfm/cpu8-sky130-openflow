"""Export geometry from an OpenROAD .odb to JSON (run: openroad -python -exit export_odb.py, with ODB and OUT env vars)."""
import os, json, odb
from openroad import Design, Tech
tech = Tech(); d = Design(tech); d.readDb(os.environ["ODB"])
blk = d.getBlock(); dbu = blk.getDbUnitsPerMicron()
die = blk.getDieArea(); core = blk.getCoreArea()
r = lambda b: [b.xMin()/dbu, b.yMin()/dbu, b.xMax()/dbu, b.yMax()/dbu]
insts = []
for i in blk.getInsts():
    m = i.getMaster(); bb = i.getBBox()
    insts.append([i.getName(), m.getName(), m.getType()] + r(bb))
clk = []
for n in blk.getNets():
    if n.getSigType() != "CLOCK": continue
    drv, sinks = None, []
    for it in n.getITerms():
        ok, x, y = it.getAvgXY()
        if not ok: bb = it.getInst().getBBox(); x, y = (bb.xMin()+bb.xMax())/2, (bb.yMin()+bb.yMax())/2
        p = [x/dbu, y/dbu, it.getInst().getName(), it.getInst().getMaster().getName()]
        (drv := p) if it.isOutputSignal() else sinks.append(p)
    for bt in n.getBTerms():
        for pin in bt.getBPins():
            bb = pin.getBBox(); drv = [(bb.xMin()+bb.xMax())/2/dbu, (bb.yMin()+bb.yMax())/2/dbu, bt.getName(), "PORT"]
    clk.append({"net": n.getName(), "driver": drv, "sinks": sinks})
json.dump({"die": r(die), "core": r(core), "insts": insts, "clock_nets": clk}, open(os.environ["OUT"], "w"))
print("insts", len(insts), "clock nets", len(clk))
