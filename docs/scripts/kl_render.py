# KLayout batch renderer: klayout -zz -r kl_render.py -rd inp=... -rd out=... [-rd box=x1,y1,x2,y2] [-rd width=1600] [-rd hide=layerpattern,...]
import pya, os
P = os.path.join(os.environ.get("PDK_ROOT", os.path.expanduser("~/.ciel")), "sky130A")
lyt = P + "/libs.tech/klayout/tech/sky130A.lyt"
lyp = P + "/libs.tech/klayout/tech/sky130A.lyp"
lym = P + "/libs.tech/klayout/tech/sky130A.map"
lefs = [P + "/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__nom.tlef",
        P + "/libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef",
        P + "/libs.ref/sky130_fd_sc_hd/lef/sky130_ef_sc_hd.lef"]
g = globals()
inp = g["inp"]; out = g["out"]
width = int(g.get("width", "1600"))
tech = pya.Technology(); tech.load(lyt)
lv = pya.LayoutView()
lv.set_config("grid-visible", "false")
lv.set_config("text-visible", g.get("text", "false"))
lv.set_config("background-color", g.get("bg", "#FFFFFF"))
if inp.endswith(".gds"):
    lv.load_layout(inp)
else:
    o = tech.load_layout_options
    o.lefdef_config.map_file = lym
    o.lefdef_config.macro_resolution_mode = int(g.get("mrm", "1"))
    o.lefdef_config.read_lef_with_def = False
    o.lefdef_config.lef_files = lefs
    lv.load_layout(inp, o, lyt)
lv.max_hier()
lv.load_layer_props(lyp)
hide = [h for h in g.get("hide", "").split(",") if h]
show_only = [h for h in g.get("only", "").split(",") if h]
it = lv.begin_layers()
while not it.at_end():
    lp = it.current()
    name = lp.name or lp.source
    if show_only:
        lp.visible = any(s in name or s in lp.source for s in show_only)
    elif any(h in name or h in lp.source for h in hide):
        lp.visible = False
    it.next()
top = lv.active_cellview().layout().top_cell()
bb = top.dbbox()
if "box" in g:
    x1, y1, x2, y2 = [float(v) for v in g["box"].split(",")]
    bb = pya.DBox(x1, y1, x2, y2)
lv.zoom_box(bb)
h = int(width * bb.height() / bb.width())
lv.save_image_with_options(out, width, h, 0, 0, 0, bb, False)
print("saved", out, width, h)
