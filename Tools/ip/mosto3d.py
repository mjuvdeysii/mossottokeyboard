"""Mosto — the keyboard's companion. The name sounds like 魔头 (mótóu, "the demon"), so Mosto is a little demon king
(小魔王): bright, cute, a bit wicked. It shares only the studio's way of making figures with Moss and Otto
(ip3d.py: matte soft vinyl, painted glossy eyes, product-photo light), coloured like a designer toy.

  body    a chubby gumdrop, plumper at the bottom, in deep violet #633EBF (one clear body colour; the rest stays quiet)
  crown   a small matte-gold crown worn at a rakish angle, three points
  horns   two curled cream horns: out, then up and in
  wings   two small scalloped bat wings behind the shoulders, deep violet
  eyes    big and round, amber irises, big glossy pupils — under two brows that slant down to the middle (cute eyes,
          wicked intent); pink blush
  mouth   a wide cat-mouth grin with a single fang
  tail    a lavender tail curling up on the right, ending in a cream spade (it glows gold at night)
  manner  mischievous, never menacing; at night a scheming squint, the eyes and the spade glowing gold

Usage (Blender as a Python module, bpy 5.x):
  python Tools/ip/mosto3d.py sheet  out_dir      hero shot and states, day and night
  python Tools/ip/mosto3d.py sprites out_dir     transparent keyboard sprites (day, blink, night)
  python Tools/ip/mosto3d.py icon   out.png      1024 px app icon
Options: --samples N  --palette lilac|vermilion|coral  --color #RRGGBB (body only)
"""
import math, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy
from mathutils import Euler
import ip3d as B

_reset = B.reset
def _bright_reset():
    sc = _reset(); sc.view_settings.look = "None"; return sc   # AgX without the punchy look: clear colour, soft highlights
B.reset = _bright_reset

ARGS = sys.argv[1:]
# 小魔王: a lavender little demon king — matte-gold crown, curled cream horns, bat wings, big glossy eyes with
# amber irises under two scheming brows, one fang. Palettes: --palette lilac (default) | vermilion | coral
PALETTES = {
    # designer-toy colour: one clear body colour, everything else quiet (cream horns, a deeper shade for wings and feet)
    "vermilion": dict(body="#E0503F", deep="#6A2228", horn="#F2DDB2", iris="#C98A2E", blush="#F2A08E", feet="#3E1518", glow="#FFB54A"),
    "coral":     dict(body="#FF8A6B", deep="#8A3440", horn="#FFE6B8", iris="#5A3226", blush="#FFB7A4", feet="#4A2228", glow="#FFB54A"),
    "lilac":     dict(body="#633EBF", deep="#2B1961", horn="#FFE4A8", iris="#D69A34", blush="#F2A9D2", feet="#221650", glow="#FFC45A"),
}
P = PALETTES[B.arg("--palette", "lilac")]
COLOR = B.arg("--color", P["body"])

# a gumdrop: round and soft, plumper at the bottom, a softer top
MOSTO = dict(rx=0.52, ry=0.45, rz=0.45, cz=0.42, n=2.3, taper=0.17)

def _norm(a, b, c):
    n = MOSTO["n"]
    s = (abs(a) ** n + abs(b) ** n + abs(c) ** n) ** (1 / n)
    return a / s, b / s, c / s

def body_point(a, b, c):
    m = MOSTO
    a, b, c = _norm(a, b, c)
    t = 1 - m["taper"] * c                       # wider at the bottom: a sitting, chubby figure
    z = c * m["rz"] if c > 0 else c * m["rz"] * 0.86
    return (a * m["rx"] * t, b * m["ry"] * t, m["cz"] + z)

def surface_y(x, z):
    """The front surface (negative y) of the body at (x, z)."""
    m = MOSTO
    c = (z - m["cz"]) / (m["rz"] if z >= m["cz"] else m["rz"] * 0.86)
    t = 1 - m["taper"] * max(-1, min(1, c))
    a = x / (m["rx"] * t)
    k = 1 - abs(a) ** m["n"] - abs(c) ** m["n"]
    return -m["ry"] * t * max(0.0, k) ** (1 / m["n"])

def mosto_materials():
    B.M["mosto"] = B.rubber("mosto", COLOR, rough=0.5, sss=0.08)
    B.M["mostoDeep"] = B.rubber("mostoDeep", P["deep"], rough=0.5)
    B.M["gold"] = B.mat("horn", P["horn"], rough=0.42, coat=0.2, sss=0.12, sss_rad=(0.5, 0.35, 0.1))
    B.M["crown"] = B.mat("crown", P.get("crown", "#E3B24A"), rough=0.32, coat=0.35, sss=0.05)   # matte gold
    B.M["tip"] = B.mat("tip", P["horn"], rough=0.4, coat=0.2, emit=P["glow"], emit_strength=0.0)
    B.M["iris"] = B.mat("iris", P["iris"], rough=0.15, coat=1.0, emit=P["glow"], emit_strength=0.0)
    B.M["blush"] = B.mat("blush", P["blush"], rough=0.6, sss=0.3)
    B.M["fang"] = B.mat("fang", "#FFFBF2", rough=0.3, coat=0.5)
    B.M["foot"] = B.rubber("mostoFoot", P["feet"])

def _mesh(name, verts, faces, material, sub=2):
    me = bpy.data.meshes.new(name); me.from_pydata(verts, [], faces); me.update()
    o = bpy.data.objects.new(name, me); bpy.context.collection.objects.link(o)
    for poly in o.data.polygons: poly.use_smooth = True
    if sub: B.smooth(o, sub)
    o.data.materials.append(material); return o

def horn(name, p0, p1, p2, r0, material, rings=22, seg=20):
    """A curled horn: a tapered tube along a quadratic bezier p0 → p1 → p2, closed at the tip."""
    from mathutils import Vector
    p0, p1, p2 = Vector(p0), Vector(p1), Vector(p2)
    verts, faces = [], []
    up = Vector((0, -1, 0))
    for i in range(rings):
        t = i / (rings - 1) * 0.97
        pt = (1 - t) ** 2 * p0 + 2 * (1 - t) * t * p1 + t * t * p2
        tg = (2 * (1 - t) * (p1 - p0) + 2 * t * (p2 - p1)).normalized()
        nx = tg.cross(up).normalized(); ny = tg.cross(nx).normalized()
        r = r0 * (1 - t) ** 0.85 + 0.004
        for j in range(seg):
            a = 2 * math.pi * j / seg
            verts.append(tuple(pt + (nx * math.cos(a) + ny * math.sin(a)) * r))
    verts.append(tuple(p2)); tip = len(verts) - 1
    verts.append(tuple(p0 - (p1 - p0).normalized() * 0.01)); base = len(verts) - 1
    for i in range(rings - 1):
        for j in range(seg):
            a, b = i * seg + j, i * seg + (j + 1) % seg
            faces.append((a, b, b + seg, a + seg))
    last = (rings - 1) * seg
    for j in range(seg):
        faces.append((last + j, last + (j + 1) % seg, tip))
        faces.append(((j + 1) % seg, j, base))
    return _mesh(name, verts, faces, material)

def crown(top, tilt=-14, material=None):
    """A small crown worn at a rakish angle between the horns: a band and three points."""
    parts = []
    R, H = 0.11, 0.05
    cx, cz = 0.02, top - 0.012
    verts, faces = [], []
    seg = 40
    for k, (r, z) in enumerate(((R, 0), (R * 1.04, H))):
        for j in range(seg):
            a = 2 * math.pi * j / seg
            verts.append((r * math.cos(a), r * 0.92 * math.sin(a), z))
    for j in range(seg):
        faces.append((j, (j + 1) % seg, seg + (j + 1) % seg, seg + j))
    band = _mesh("mosto_crown", verts, faces, material, sub=0)
    mod = band.modifiers.new("solid", "SOLIDIFY"); mod.thickness = 0.018; B.smooth(band, 2)
    parts.append(band)
    import mathutils
    for j in range(3):
        a = 2 * math.pi * j / 3 - math.pi / 2
        bx, by = R * 1.02 * math.cos(a), R * 0.94 * math.sin(a)
        bpy.ops.mesh.primitive_cone_add(vertices=24, radius1=0.046, radius2=0.006, depth=0.085, location=(bx, by, H + 0.036))
        c = bpy.context.object; c.name = f"mosto_crown_pt{j}"; c.data.materials.append(material)
        for poly in c.data.polygons: poly.use_smooth = True
        parts.append(c)
    root = bpy.data.objects.new("mosto_crown_root", None); bpy.context.collection.objects.link(root)
    B.parent(parts, root)
    root.location = (cx, 0.02, cz); root.rotation_euler = (math.radians(-6), math.radians(tilt), 0)
    return [root, *parts]

def wing(name, s, material):
    """A small bat wing behind the shoulder: a scalloped outline, given thickness and rounded."""
    outline = [(0, 0), (0.08, 0.1), (0.2, 0.17), (0.3, 0.16), (0.27, 0.09), (0.21, 0.1), (0.17, 0.03), (0.11, 0.05), (0.06, -0.02)]
    verts = [(x, 0, z) for x, z in outline]
    o = _mesh(name, verts, [tuple(range(len(verts)))], material, sub=0)
    mod = o.modifiers.new("solid", "SOLIDIFY"); mod.thickness = 0.025; mod.offset = 0
    B.smooth(o, 2)
    o.scale = (s * 1.4, 1, 1.4)
    o.location = (s * 0.38, 0.22, 0.5)
    o.rotation_euler = (math.radians(-10), math.radians(-s * 12), math.radians(s * 28))
    return o

def build_mosto(x=0.0, moss_eye=None, otto_eye=None, shut=None, glow=0.0, lean=0.0, perk=0.5, droop=0.0, hop=0.0, evil=0.0):
    """moss_eye / otto_eye: the left and right eye — dicts of look, lid, pupil. shut: 'day' (blink).
    evil: 0..1, how strongly the gold irises and the tail tip glow (night)."""
    M = B.M
    root = bpy.data.objects.new("Mosto", None); bpy.context.collection.objects.link(root)
    body = B.shaped_sphere("mosto_body", body_point, M["mosto"], seg=80)
    feet = [B.sphere(f"mosto_foot{i}", (s * 0.21, -0.12, 0.045), (0.085, 0.1, 0.055), M["foot"]) for i, s in enumerate((-1, 1))]
    parts = [body, *feet]
    m = MOSTO
    top = m["cz"] + m["rz"]
    ez = m["cz"] + 0.11
    le = dict(look=(0.15, 0.1), lid=0.0, pupil=0.6); le.update(moss_eye or {})
    re_ = dict(look=(0.15, 0.1), lid=0.18, pupil=0.6); re_.update(otto_eye or {})
    for k in ("iris", "tip"):
        M[k].node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 5.0 * evil
    for s, er in ((-1, 0.128), (1, 0.128)):
        ex = s * 0.175
        sy = surface_y(ex, ez)
        # scheming brows: both slant down towards the middle — cute eyes, wicked intent
        bx = ex
        parts.append(B.tube(f"mosto_brow{s}", [(bx + s * 0.085, surface_y(bx + s * 0.085, ez + 0.17) - 0.006, ez + 0.19 + 0.02 * perk),
                                               (bx + s * 0.01, surface_y(bx + s * 0.01, ez + 0.16) - 0.008, ez + 0.165),
                                               (bx - s * 0.07, surface_y(bx - s * 0.07, ez + 0.13) - 0.006, ez + 0.125)], 0.016, M["mostoDeep"]))
        parts.append(B.sphere(f"mosto_blush{s}", (s * 0.3, surface_y(s * 0.3, ez - 0.1) + 0.012, ez - 0.1), (0.06, 0.02, 0.035), M["blush"]))
        if shut:
            parts.append(B.tube(f"mosto_shut{s}", [(ex - 0.075, sy - 0.004, ez + 0.0), (ex, sy - 0.02, ez - 0.035), (ex + 0.075, sy - 0.004, ez + 0.0)], 0.016, M["pupil"]))
            continue
        kw = le if s < 0 else re_
        at = (ex, sy + 0.03, ez); sc = (0.92, 0.5, 1.05)
        parts += B.eye(f"mosto_eye{s}", at, er, kw["look"], scale=sc, lid=kw["lid"], skin=M["mosto"], pupil=kw["pupil"])
        lx, lz = kw["look"]; pr = er * kw["pupil"]
        px, py, pz = at[0] + lx * er * 0.42, at[1] - er * sc[1] * 0.78, at[2] + lz * er * 0.42
        parts.append(B.sphere(f"mosto_iris{s}", (px, py + 0.0015, pz), (pr * 1.32, pr * 0.4, pr * 1.32), M["iris"]))
    # a wide cat-mouth grin with a single fang
    my = ez - 0.15
    pts = [(-0.085, my + 0.02), (-0.04, my - 0.012), (0.0, my + 0.004), (0.04, my - 0.012), (0.085, my + 0.02)]
    parts.append(B.tube("mosto_grin", [(x_, surface_y(x_, z_) - 0.005, z_) for x_, z_ in pts], 0.011, M["pupil"]))
    fx = 0.035; fz = my - 0.012
    import mathutils
    bpy.ops.mesh.primitive_cone_add(vertices=20, radius1=0.016, radius2=0.002, depth=0.04, location=(fx, surface_y(fx, fz) - 0.004, fz - 0.016))
    fang = bpy.context.object; fang.name = "mosto_fang"; fang.rotation_euler = (math.radians(180), 0, 0)
    fang.data.materials.append(M["fang"]); parts.append(fang)
    # curled gold horns: out, then up and in
    for s in (-1, 1):
        hx = s * 0.27
        bz = m["cz"] + 0.32
        p0 = (hx, surface_y(hx, bz) * 0.4, bz)
        p1 = (hx + s * (0.2 + 0.03 * perk), -0.04, bz + 0.08)
        p2 = (hx + s * (0.12 + 0.02 * perk), -0.07, bz + 0.27 + 0.03 * perk)
        parts.append(horn(f"mosto_horn{s}", p0, p1, p2, 0.065, M["gold"]))
    parts += crown(top, material=M["crown"])
    parts += [wing("mosto_wingL", -1, M["mostoDeep"]), wing("mosto_wingR", 1, M["mostoDeep"])]
    # the tail: from behind the right flank, a lively S, ending in a gold spade (named bead: the glow follows it)
    d = droop
    tx, ty, tz = 0.7 - 0.03 * d, 0.08, 0.6 - 0.12 * d
    parts.append(B.tube("mosto_tail", [(0.32, 0.3, 0.2), (0.62, 0.32, 0.18), (0.76, 0.2, 0.36), (tx, ty - 0.01, tz - 0.005)], 0.022, M["mosto"]))
    bpy.ops.object.empty_add(location=(tx, ty, tz + 0.02)); bead = bpy.context.object; bead.name = "mosto_bead"; parts.append(bead)
    # a spade: a point on top, two round lobes below, a notch where the tail joins
    spade = [(0, 0.11), (0.035, 0.07), (0.068, 0.03), (0.075, -0.005), (0.055, -0.03), (0.025, -0.032), (0.0, -0.015),
             (-0.025, -0.032), (-0.055, -0.03), (-0.075, -0.005), (-0.068, 0.03), (-0.035, 0.07)]
    v = [(x_, 0, z_) for x_, z_ in spade]
    sp = _mesh("mosto_spade", v, [tuple(range(len(v)))], M["tip"], sub=0)
    mod = sp.modifiers.new("solid", "SOLIDIFY"); mod.thickness = 0.035; mod.offset = 0; B.smooth(sp, 2)
    sp.location = (tx, ty - 0.01, tz + 0.01); sp.rotation_euler = (math.radians(4), 0, math.radians(-12)); sp.scale = (1.1, 1, 1.1)
    parts.append(sp)
    if evil > 0:
        bpy.ops.object.light_add(type="POINT", location=(tx, ty - 0.1, tz)); lamp = bpy.context.object
        lamp.data.energy = 16 * evil; lamp.data.color = B.hexcol(P["glow"])[:3]; lamp.data.shadow_soft_size = 0.06
        parts.append(lamp)
    for o in parts:
        if o.parent is None: o.parent = root
    root.location = (x, 0, hop); root.rotation_euler = (0, math.radians(lean), 0)
    if hop > 0: root.scale = (1 - hop * 0.3, 1 - hop * 0.3, 1 + hop * 0.6)
    return root

STATES = {
    "day": dict(),
    "glance": dict(moss_eye=dict(look=(-0.9, 0.15)), otto_eye=dict(look=(-0.7, -0.1)), lean=4, perk=0.8),
    "blink": dict(shut="day"),
    "type": dict(moss_eye=dict(look=(0.1, -0.6), lid=0.15), otto_eye=dict(look=(0.0, -0.6), lid=0.3), lean=-3, perk=0.7),
    # night: awake, eyes narrowed to a scheming squint, gold irises and the spade glowing
    "night": dict(moss_eye=dict(look=(0.2, 0.0), lid=0.42, pupil=0.5), otto_eye=dict(look=(0.0, 0.0), lid=0.48, pupil=0.5), evil=1.0, perk=1.0),
}

def night_world():
    world = bpy.data.worlds.new("wn"); bpy.context.scene.world = world; world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = B.hexcol("#1E1428")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
    def area(loc, rot, energy, size, color):
        bpy.ops.object.light_add(type="AREA", location=loc, rotation=rot); l = bpy.context.object
        l.data.energy = energy; l.data.size = size; l.data.color = B.hexcol(color)[:3]
    # moonlight: a soft cool key and a blue rim, dimmer than the day set but the figure still reads
    # night: a dim violet key and a magenta rim; the gold glow of the eyes and the spade carries the mood
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
        d.ellipse([cx - r * k, cy - r * k, cx + r * k, cy + r * k], fill=(*[int(P['glow'][i:i+2],16) for i in (1,3,5)], int(255 * strength * (1 - k) ** 1.6)))
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
    ortho_camera(1.78, 0.58, cx=0.08)
    tmp = path.replace(".png", "_fg.png")
    B.render(tmp, size, size)
    bg = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(bg)
    for y in range(size):                                   # warm butter-cream: the complement of Mosto's violet, so it stands out
        t = y / size
        d.line([(0, y), (size, y)], fill=(int(255 - 6 * t), int(244 - 26 * t), int(214 - 62 * t)))
    fg = Image.open(tmp).convert("RGBA")
    bg.paste(fg, (0, 0), fg)
    bg.save(path)
    os.remove(tmp)

if __name__ == "__main__":
    what, out = ARGS[0], ARGS[1]
    {"sheet": sheet, "sprites": sprites, "icon": icon}[what](out)
