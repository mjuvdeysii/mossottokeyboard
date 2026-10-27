"""Mosto — the keyboard's companion. The name sounds like 魔头 (mótóu, "the demon"), so Mosto is a small, sly devil
of its own: no longer a mix of Moss and Otto, and sharing only the studio's way of making figures (ip3d.py: matte
soft vinyl, painted glossy eyes, product-photo light).

  body    a soft keycap — it lives in a keyboard — in deep plum-violet, a touch narrower at the top
  horns   two short ivory horns, angled outwards
  tail    a thin plum tail curling up behind the right side, ending in a crimson spade (it glows at night)
  eyes    mismatched on purpose: one round and wide, one heavy-lidded; crimson irises; a one-sided smirk
  feet    two ink feet
  manner  mischievous rather than menacing: never shouts, never grins wide; at night the eyes narrow and glow red

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
COLOR = B.arg("--color", "#3B2152")
DEEP = "#24122F"
CRIMSON = "#C8243C"
IVORY = "#EFE5D3"

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
    B.M["horn"] = B.mat("horn", IVORY, rough=0.38, sss=0.15, sss_rad=(0.4, 0.3, 0.2), coat=0.25)
    B.M["crimson"] = B.mat("crimson", CRIMSON, rough=0.3, coat=0.5, emit=CRIMSON, emit_strength=0.0)
    B.M["iris"] = B.mat("irisRed", CRIMSON, rough=0.15, coat=1.0, emit=CRIMSON, emit_strength=0.0)

def cone(name, base, tip, r0, r1, material):
    """A horn: a cone from base to tip, smoothed."""
    import mathutils
    v = mathutils.Vector(tip) - mathutils.Vector(base)
    bpy.ops.mesh.primitive_cone_add(vertices=40, radius1=r0, radius2=r1, depth=v.length,
                                    location=(mathutils.Vector(base) + v / 2))
    o = bpy.context.object; o.name = name
    o.rotation_euler = v.to_track_quat("Z", "Y").to_euler()
    for poly in o.data.polygons: poly.use_smooth = True
    B.smooth(o, 2)
    o.data.materials.append(material); return o

def build_mosto(x=0.0, moss_eye=None, otto_eye=None, shut=None, glow=0.0, lean=0.0, perk=0.5, droop=0.0, hop=0.0, evil=0.0):
    """moss_eye / otto_eye: the left (wide) and right (heavy-lidded) eye — dicts of look, lid, pupil.
    shut: 'day' (blink). evil: 0..1, how strongly the irises and the tail tip glow (night)."""
    M = B.M
    root = bpy.data.objects.new("Mosto", None); bpy.context.collection.objects.link(root)
    body = B.shaped_sphere("mosto_body", body_point, M["mosto"], seg=72)
    feet = [B.sphere(f"mosto_foot{i}", (s * 0.2, -0.1, 0.045), (0.078, 0.098, 0.055), M["foot"]) for i, s in enumerate((-1, 1))]
    parts = [body, *feet]
    m = MOSTO
    top = m["cz"] + m["rz"] - 0.01
    ez = m["cz"] + 0.15
    le = dict(look=(0.25, 0.2), lid=0.12, pupil=0.5); le.update(moss_eye or {})
    re_ = dict(look=(-0.05, -0.1), lid=0.52, pupil=0.5); re_.update(otto_eye or {})
    for k in ("iris", "crimson"):
        M[k].node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 6.0 * evil
    for s, er in ((-1, 0.105), (1, 0.115)):
        ex = s * 0.165
        sy = surface_y(ex, ez)
        if shut:
            dz = -0.006 if s < 0 else -0.03
            parts.append(B.tube(f"mosto_shut{s}", [(ex - 0.07, sy, ez - 0.005), (ex, sy - 0.02, ez + dz), (ex + 0.07, sy, ez - 0.005)], 0.015, M["pupil"]))
            continue
        kw = le if s < 0 else re_
        at = (ex, sy + 0.024, ez); sc = (0.9, 0.5, 1.0)
        parts += B.eye(f"mosto_eye{s}", at, er, kw["look"], scale=sc, lid=kw["lid"], skin=M["mosto"], pupil=kw["pupil"])
        # a crimson iris ring behind the pupil
        lx, lz = kw["look"]; pr = er * kw["pupil"]
        px, py, pz = at[0] + lx * er * 0.42, at[1] - er * sc[1] * 0.78, at[2] + lz * er * 0.42
        parts.append(B.sphere(f"mosto_iris{s}", (px, py + 0.0015, pz), (pr * 1.3, pr * 0.4, pr * 1.3), M["iris"]))
        # a slanted brow line over the wide eye: the sly half of the face
        if s < 0:
            parts.append(B.tube("mosto_brow", [(ex - 0.08, surface_y(ex - 0.08, ez + 0.13) - 0.004, ez + 0.11),
                                               (ex + 0.0, surface_y(ex, ez + 0.15) - 0.006, ez + 0.145),
                                               (ex + 0.08, surface_y(ex + 0.08, ez + 0.13) - 0.004, ez + 0.125)], 0.012, M["mostoDeep"]))
    # the smirk: one corner up
    my = ez - 0.165
    parts.append(B.tube("mosto_smirk", [(-0.09, surface_y(-0.09, my) - 0.003, my + 0.005), (0.02, surface_y(0.02, my) - 0.006, my - 0.008),
                                        (0.1, surface_y(0.1, my + 0.03) - 0.004, my + 0.035)], 0.012, M["pupil"]))
    # horns, angled outwards
    for s in (-1, 1):
        hx = s * 0.24
        base = (hx, -0.02, top - 0.05)
        tip = (hx + s * (0.11 + 0.03 * perk), -0.05, top + 0.2 + 0.03 * perk)
        parts.append(cone(f"mosto_horn{s}", base, tip, 0.068, 0.012, M["horn"]))
    # the tail: from behind the right flank, curling up, a crimson spade at the end (named bead: the glow follows it)
    d = droop
    tx, ty, tz = 0.66 - 0.03 * d, 0.06, 0.66 - 0.12 * d
    parts.append(B.tube("mosto_tail", [(0.3, 0.32, 0.22), (0.58, 0.3, 0.26), (0.7, 0.18, 0.42), (tx, ty, tz - 0.06)], 0.02, M["mostoDeep"]))
    parts.append(cone("mosto_bead", (tx, ty, tz - 0.07), (tx + 0.005, ty - 0.01, tz + 0.08), 0.06, 0.004, M["crimson"]))
    if evil > 0:
        bpy.ops.object.light_add(type="POINT", location=(tx, ty - 0.08, tz)); lamp = bpy.context.object
        lamp.data.energy = 18 * evil; lamp.data.color = B.hexcol("#FF4D5E")[:3]; lamp.data.shadow_soft_size = 0.06
        parts.append(lamp)
    B.parent(parts, root)
    root.location = (x, 0, hop); root.rotation_euler = (0, math.radians(lean), 0)
    if hop > 0: root.scale = (1 - hop * 0.3, 1 - hop * 0.3, 1 + hop * 0.6)
    return root

STATES = {
    "day": dict(),
    "glance": dict(moss_eye=dict(look=(-0.9, 0.15)), otto_eye=dict(look=(-0.7, -0.1)), lean=4, perk=0.8),
    "blink": dict(shut="day"),
    "type": dict(moss_eye=dict(look=(0.1, -0.6), lid=0.18), otto_eye=dict(look=(0.0, -0.6), lid=0.6), lean=-3, perk=0.7),
    # night: awake, eyes narrowed, irises and tail tip glowing red
    "night": dict(moss_eye=dict(look=(0.2, 0.0), lid=0.5, pupil=0.42), otto_eye=dict(look=(0.0, 0.0), lid=0.6, pupil=0.42), evil=1.0, perk=1.0),
}

def night_world():
    world = bpy.data.worlds.new("wn"); bpy.context.scene.world = world; world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = B.hexcol("#1E1428")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
    def area(loc, rot, energy, size, color):
        bpy.ops.object.light_add(type="AREA", location=loc, rotation=rot); l = bpy.context.object
        l.data.energy = energy; l.data.size = size; l.data.color = B.hexcol(color)[:3]
    # moonlight: a soft cool key and a blue rim, dimmer than the day set but the figure still reads
    # night: a dim violet key and a magenta rim, so the plum body stays plum and the red glow carries the mood
    area((-2.2, -3.0, 3.0), (math.radians(55), 0, math.radians(-35)), 420, 3.2, "#E2D4FF")
    area((2.8, -2.4, 1.4), (math.radians(75), 0, math.radians(50)), 140, 3.0, "#C9B6F0")
    area((1.5, 2.8, 2.8), (math.radians(-55), 0, math.radians(150)), 300, 1.5, "#FF8FB0")

def night_set():
    """The same studio cyclorama, by night: a deep blue backdrop, moonlight, and the bead as the warm light."""
    B.studio("#241A30")
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
        d.ellipse([cx - r * k, cy - r * k, cx + r * k, cy + r * k], fill=(255, 77, 94, int(255 * strength * (1 - k) ** 1.6)))
    halo = halo.filter(ImageFilter.GaussianBlur(w * 0.01))
    Image.alpha_composite(halo, im).save(path) if im.mode == "RGBA" else None

def ortho_camera(width, cz, tilt_deg=6, cx=0.0):
    s = bpy.context.scene
    tilt = math.radians(tilt_deg)
    bpy.ops.object.camera_add(location=(cx, -8 * math.cos(tilt), cz + 8 * math.sin(tilt))); c = bpy.context.object
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
        ortho_camera(1.62, 0.64, cx=0.08)   # wide enough for the horns and the tail
        out = os.path.join(outdir, f"mosto_{name}.png")
        at = bead_position()
        B.render(out, size, size)
        if name == "night": add_glow(out, at)

def sheet(outdir):
    """Mosto's hero shot (a three-quarter turn, so the horns and the tail read), then its states."""
    os.makedirs(outdir, exist_ok=True)
    w, h = B.arg("--w", 1500), B.arg("--h", 760)
    B.reset(); B.materials(); mosto_materials(); B.studio("#E6DEE8")
    build_mosto(x=0.0, moss_eye=dict(look=(-0.45, 0.2)), otto_eye=dict(look=(-0.4, -0.05)), lean=0)
    bpy.data.objects["Mosto"].rotation_euler = (0, 0, math.radians(-22))
    B.camera(target=(0.0, 0, 0.6), dist=4.6, height=1.05, lens=60, fstop=8)
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
    build_mosto(moss_eye=dict(look=(0.2, 0.3)), otto_eye=dict(look=(-0.05, 0.1), lid=0.52))
    ortho_camera(1.78, 0.68, cx=0.08)
    tmp = path.replace(".png", "_fg.png")
    B.render(tmp, size, size)
    bg = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(bg)
    for y in range(size):                                   # a pale lilac that turns ember-pink at the bottom
        t = y / size
        d.line([(0, y), (size, y)], fill=(int(244 - 2 * t), int(236 - 40 * t), int(246 - 36 * t)))
    fg = Image.open(tmp).convert("RGBA")
    bg.paste(fg, (0, 0), fg)
    bg.save(path)
    os.remove(tmp)

if __name__ == "__main__":
    what, out = ARGS[0], ARGS[1]
    {"sheet": sheet, "sprites": sprites, "icon": icon}[what](out)
