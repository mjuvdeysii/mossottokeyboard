"""Mosto — the keyboard's companion, a derivative of Moss and Otto (Mos(s) + (Ot)to), modelled and lit exactly like
them (ip3d.py: the same matte soft-vinyl materials, eyes, mint leaves, golden bead and product-photo light).

What Mosto takes from each:
  body    a soft keycap — between Moss's low pebble and Otto's tall dome — in a deep teal that sits between Moss's moss
          green and Otto's night blue; slightly narrower at the top, as a keycap is
  head    Moss's real mint (a stem with an opposite pair of serrated leaves) grown into Otto's arching antenna,
          with Otto's golden lamp bead at the tip
  eyes    one of each: a round, wide-open Moss eye (curiosity) and a heavy-lidded Otto eye with a soft bag beneath
          (tiredness) — the deadpan face both share; no blush, no grin
  feet    the same two ink feet
  manner  types as fast as Moss, looks as unimpressed as Otto; at night both eyes settle half-closed and the bead glows

Usage (Blender as a Python module, bpy 5.x):
  python Tools/ip/mosto3d.py sheet  out_dir      family line-up, Mosto states, day and night
  python Tools/ip/mosto3d.py sprites out_dir     transparent keyboard sprites (day, blink, night)
  python Tools/ip/mosto3d.py icon   out.png      1024 px app icon
Options: --samples N  --color #RRGGBB
"""
import math, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy
from mathutils import Euler
import ip3d as B

ARGS = sys.argv[1:]
COLOR = B.arg("--color", "#2E6268")
DEEP = "#234B50"

MOSTO = dict(rx=0.5, ry=0.43, rz=0.43, cz=0.4, n=2.75, taper=0.1)

def _norm(a, b, c):
    n = MOSTO["n"]
    s = (abs(a) ** n + abs(b) ** n + abs(c) ** n) ** (1 / n)
    return a / s, b / s, c / s

def body_point(a, b, c):
    m = MOSTO
    a, b, c = _norm(a, b, c)
    t = 1 - m["taper"] * c                       # a keycap: a touch narrower at the top
    z = c * m["rz"] if c > 0 else c * m["rz"] * 0.82
    return (a * m["rx"] * t, b * m["ry"] * t, m["cz"] + z)

def surface_y(x, z):
    """The front surface (negative y) of the body at (x, z)."""
    m = MOSTO
    c = (z - m["cz"]) / (m["rz"] if z >= m["cz"] else m["rz"] * 0.82)
    t = 1 - m["taper"] * c
    a = x / (m["rx"] * t)
    k = 1 - abs(a) ** m["n"] - abs(c) ** m["n"]
    return -m["ry"] * t * max(0.0, k) ** (1 / m["n"])

def mosto_materials():
    B.M["mosto"] = B.rubber("mosto", COLOR)
    B.M["mostoDeep"] = B.rubber("mostoDeep", DEEP)

def build_mosto(x=0.0, moss_eye=None, otto_eye=None, shut=None, glow=0.6, lean=0.0, perk=0.5, droop=0.0, hop=0.0):
    """moss_eye / otto_eye: dicts for B.eye (look, lid, pupil); shut: 'day' (blink) or 'night' (both eyes settled)."""
    M = B.M
    root = bpy.data.objects.new("Mosto", None); bpy.context.collection.objects.link(root)
    body = B.shaped_sphere("mosto_body", body_point, M["mosto"], seg=72)
    feet = [B.sphere(f"mosto_foot{i}", (s * 0.2, -0.1, 0.045), (0.078, 0.098, 0.055), M["foot"]) for i, s in enumerate((-1, 1))]
    parts = [body, *feet]
    m = MOSTO
    top = m["cz"] + m["rz"] - 0.01
    ez = m["cz"] + 0.15
    me = dict(look=(0.25, 0.35), lid=0.04, pupil=0.56); me.update(moss_eye or {})
    oe = dict(look=(-0.05, -0.15), lid=0.56, pupil=0.57); oe.update(otto_eye or {})
    # left (viewer's left): the Moss eye; right: the Otto eye, a little larger, with a bag
    for s, er in ((-1, 0.104), (1, 0.12)):
        ex = s * 0.165
        sy = surface_y(ex, ez)
        if shut:
            # night: a settled lid line on both; day blink: Moss's quick flat line, Otto's slow curve
            dz = -0.02 if shut == "night" else (-0.006 if s < 0 else -0.03)
            parts.append(B.tube(f"mosto_shut{s}", [(ex - 0.07, sy, ez - 0.005), (ex, sy - 0.02, ez + dz), (ex + 0.07, sy, ez - 0.005)], 0.015, M["pupil"]))
        else:
            kw = me if s < 0 else oe
            parts += B.eye(f"mosto_eye{s}", (ex, sy + 0.024, ez), er, kw["look"], scale=(0.9, 0.5, 1.0), lid=kw["lid"], skin=M["mosto"], pupil=kw["pupil"])
        if s > 0:
            parts.append(B.sphere("mosto_bag", (ex, surface_y(ex, ez - 0.128) + 0.012, ez - 0.128), (0.08, 0.012, 0.016), M["mostoDeep"]))
    # Moss's mint grown into Otto's antenna: a stem from the crown arching forward-left, the opposite pair of mint
    # leaves low on it, the golden lamp bead hanging at its tip
    d = droop
    bx, by, bz = -0.29 - 0.05 * d, -0.17 - 0.06 * d, top + 0.13 - 0.16 * d
    parts.append(B.tube("mosto_stem", [(0.0, -0.01, top - 0.03), (0.0, -0.02, top + 0.15 - 0.03 * d),
                                       (-0.15 - 0.03 * d, -0.09 - 0.04 * d, top + 0.25 - 0.08 * d), (bx, by, bz + 0.065)], 0.017, M["mintDeep"]))
    node = (0.0, -0.02, top + 0.06)
    up = math.radians(30 + 16 * perk); roll = 1.05
    parts.append(B.leaf("mosto_leafL", node, Euler((-roll, -up, math.radians(185))), 0.25, M["mint"], width=0.62))
    parts.append(B.leaf("mosto_leafR", node, Euler((roll, -up, math.radians(-5))), 0.26, M["mintPale"], width=0.62))
    parts.append(B.sphere("mosto_bead", (bx, by, bz), (0.062, 0.062, 0.062), M["bead"]))
    M["bead"].node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 1.6 * glow
    if glow > 0:
        bpy.ops.object.light_add(type="POINT", location=(bx, by - 0.02, bz - 0.04)); lamp = bpy.context.object
        lamp.data.energy = 30 * glow; lamp.data.color = B.hexcol("#FFC66E")[:3]; lamp.data.shadow_soft_size = 0.06
        parts.append(lamp)
    B.parent(parts, root)
    root.location = (x, 0, hop); root.rotation_euler = (0, math.radians(lean), 0)
    if hop > 0: root.scale = (1 - hop * 0.3, 1 - hop * 0.3, 1 + hop * 0.6)
    return root

STATES = {
    "day": dict(),
    "glance": dict(moss_eye=dict(look=(-0.9, 0.2)), otto_eye=dict(look=(-0.7, -0.1)), lean=4, perk=0.8),
    "blink": dict(shut="day"),
    "type": dict(moss_eye=dict(look=(0.1, -0.6), lid=0.1), otto_eye=dict(look=(0.0, -0.6), lid=0.62), lean=-3, perk=0.7),
    "night": dict(shut="night", glow=1.6, droop=0.6, perk=-0.2),
}

def night_world():
    world = bpy.data.worlds.new("wn"); bpy.context.scene.world = world; world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = B.hexcol("#1E2340")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
    def area(loc, rot, energy, size, color):
        bpy.ops.object.light_add(type="AREA", location=loc, rotation=rot); l = bpy.context.object
        l.data.energy = energy; l.data.size = size; l.data.color = B.hexcol(color)[:3]
    # moonlight: a soft cool key and a blue rim, dimmer than the day set but the figure still reads
    area((-2.2, -3.0, 3.0), (math.radians(55), 0, math.radians(-35)), 480, 3.2, "#CCD6FF")
    area((2.8, -2.4, 1.4), (math.radians(75), 0, math.radians(50)), 150, 3.0, "#A9B6E8")
    area((1.5, 2.8, 2.8), (math.radians(-55), 0, math.radians(150)), 260, 1.5, "#9DB2FF")

def night_set():
    """The same studio cyclorama, by night: a deep blue backdrop, moonlight, and the bead as the warm light."""
    B.studio("#262B4A")
    for o in [o for o in bpy.data.objects if o.type == "LIGHT"]:
        bpy.data.objects.remove(o, do_unlink=True)
    night_world()

def bead_position():
    from bpy_extras.object_utils import world_to_camera_view
    s = bpy.context.scene; bpy.context.view_layer.update()
    p = world_to_camera_view(s, s.camera, bpy.data.objects["mosto_bead"].matrix_world.translation)
    return p.x, 1 - p.y

def add_glow(path, at, radius=0.16, strength=0.75):
    """The bead's warm halo, added over the render (as the app does for Otto's bead at night)."""
    from PIL import Image, ImageFilter
    im = Image.open(path).convert("RGBA"); w, h = im.size
    halo = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    from PIL import ImageDraw
    d = ImageDraw.Draw(halo); cx, cy = at[0] * w, at[1] * h; r = radius * w
    for i in range(24, 0, -1):
        k = i / 24
        d.ellipse([cx - r * k, cy - r * k, cx + r * k, cy + r * k], fill=(255, 190, 100, int(255 * strength * (1 - k) ** 1.6)))
    halo = halo.filter(ImageFilter.GaussianBlur(w * 0.01))
    Image.alpha_composite(halo, im).save(path) if im.mode == "RGBA" else None

def ortho_camera(width, cz, tilt_deg=6):
    s = bpy.context.scene
    tilt = math.radians(tilt_deg)
    bpy.ops.object.camera_add(location=(0, -8 * math.cos(tilt), cz + 8 * math.sin(tilt))); c = bpy.context.object
    c.rotation_euler = (math.radians(90) - tilt, 0, 0); c.data.type = "ORTHO"; c.data.ortho_scale = width
    s.camera = c

def sprites(outdir):
    os.makedirs(outdir, exist_ok=True)
    size = B.arg("--size", 360)
    for name, kw in STATES.items():
        s = B.reset(); s.render.film_transparent = True; B.materials(); mosto_materials()
        night_world() if name == "night" else B.sprite_lights()
        s.render.resolution_x = s.render.resolution_y = size
        build_mosto(**kw)
        ortho_camera(1.42, 0.62)
        out = os.path.join(outdir, f"mosto_{name}.png")
        at = bead_position()
        B.render(out, size, size)
        if name == "night": add_glow(out, at)

def sheet(outdir):
    """Family line-up (Moss, Mosto, Otto) in the studio, by day; and Mosto alone at night."""
    os.makedirs(outdir, exist_ok=True)
    w, h = B.arg("--w", 1500), B.arg("--h", 760)
    B.reset(); B.materials(); mosto_materials(); B.studio()
    B.build_moss(x=-1.25, look=(0.85, 0.2), lid=0.06, er=0.12, pupil=0.56, perk=0.7, lean=4)
    build_mosto(x=0.0, moss_eye=dict(look=(-0.5, 0.25)), otto_eye=dict(look=(0.55, -0.05)))
    B.build_otto(x=1.25, look=(-0.85, -0.15), lid=0.6, glow=0.6, slouch=0.8, droop=0.6, bags=True)
    B.camera(target=(0.0, 0, 0.6), dist=7.4, height=1.05, lens=60, fstop=8)
    B.render(os.path.join(outdir, "family.png"), w, h)
    for name in ("day", "glance", "type", "blink"):
        B.reset(); B.materials(); mosto_materials(); B.studio()
        build_mosto(**STATES[name])
        B.camera(target=(0.0, 0, 0.6), dist=4.2, height=0.95, lens=60, fstop=8)
        B.render(os.path.join(outdir, f"state_{name}.png"), 560, 560)
    B.reset(); B.materials(); mosto_materials(); night_set()
    build_mosto(**STATES["night"])
    B.camera(target=(0.0, 0, 0.6), dist=4.2, height=0.95, lens=60, fstop=8)
    at = bead_position()
    B.render(os.path.join(outdir, "state_night.png"), 560, 560)
    add_glow(os.path.join(outdir, "state_night.png"), at, radius=0.12, strength=0.6)

def icon(path):
    from PIL import Image, ImageDraw
    s = B.reset(); s.render.film_transparent = True; B.materials(); mosto_materials(); B.sprite_lights()
    size = 1024
    s.render.resolution_x = s.render.resolution_y = size
    build_mosto(moss_eye=dict(look=(0.2, 0.45)), otto_eye=dict(look=(-0.05, 0.1), lid=0.52))
    ortho_camera(1.68, 0.64)
    tmp = path.replace(".png", "_fg.png")
    B.render(tmp, size, size)
    bg = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(bg)
    for y in range(size):                                   # the same warm paper as the Moss & Otto icon
        t = y / size
        d.line([(0, y), (size, y)], fill=(int(255 - 3 * t), int(248 - 18 * t), int(236 - 32 * t)))
    fg = Image.open(tmp).convert("RGBA")
    bg.paste(fg, (0, 0), fg)
    bg.save(path)
    os.remove(tmp)

if __name__ == "__main__":
    what, out = ARGS[0], ARGS[1]
    {"sheet": sheet, "sprites": sprites, "icon": icon}[what](out)
