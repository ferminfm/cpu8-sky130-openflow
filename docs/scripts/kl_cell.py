# Render one standard cell from the sky130_fd_sc_hd GDS: klayout -zz -r kl_cell.py -rd cell=<name> -rd out=<png> [-rd width=N]
import pya, os
P=os.path.join(os.environ.get("PDK_ROOT", os.path.expanduser("~/.ciel")), "sky130A")
g=globals()
lv=pya.LayoutView(); lv.set_config("background-color","#FFFFFF"); lv.set_config("grid-visible","false"); lv.set_config("text-visible","true")
lv.load_layout(P+"/libs.ref/sky130_fd_sc_hd/gds/sky130_fd_sc_hd.gds")
ly=lv.active_cellview().layout()
c=ly.cell(g["cell"]); lv.active_cellview().cell=c
lv.max_hier(); lv.load_layer_props(P+"/libs.tech/klayout/tech/sky130A.lyp")
bb=c.dbbox().enlarged(0.3,0.3); lv.zoom_box(bb)
w=int(g.get("width","1400")); h=int(w*bb.height()/bb.width())
lv.save_image_with_options(g["out"],w,h,0,0,0,bb,False); print("saved",g["out"],w,h, c.dbbox())
