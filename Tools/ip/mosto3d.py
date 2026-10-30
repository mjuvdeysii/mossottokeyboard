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
  python Tools/ip/mosto3d.py sheet  out_dir      hero shot and states, day and night, composed into mosto_sheet.png
  python Tools/ip/mosto3d.py sprites out_dir     transparent keyboard sprites (day, glance, blink, type, night, yawn)
  python Tools/ip/mosto3d.py icon   out.png      1024 px app icon (Mosto alone)
  python Tools/ip/mosto3d.py toyicon out.png     1024 px app icon: Mosto on the keyboard's vinyl keys (--night: the dark-mode
                                                 icon, --tinted: the iOS 18 tinted icon, --hero: transparent, for the app)
Options: --samples N  --palette lilac|vermilion|coral  --color #RRGGBB (body only)
         --spread X (how far the wings open)  --measure (print where the wings land and what of them is seen; no render)
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

# A small bat wing, drawn flat (x out from the root, z up): a leading edge that arches up to the top finger, then
# three finger tips with the membrane between them cut in as deep round scallops — three notches that still read at
# 40 px. The root sits behind the shoulder, so the wing grows out of him rather than floating beside him.
WING_TIPS = [(0.30, 0.31), (0.37, 0.15), (0.31, 0.01), (0.06, -0.06)]   # top finger, middle finger, low finger, root

def _qbez(p0, c, p1, n):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t * t * p1[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t * t * p1[1]) for t in (i / n for i in range(n))]

def wing_outline(depth=None):
    """The wing's outline, dense enough that subdivision only softens it: the scallops keep their depth and the
    finger tips stay points. `depth`: how far each scallop is cut in, as a share of its chord."""
    depth = B.arg("--scallop", 0.42) if depth is None else depth
    root_top = (0.0, 0.07)
    pts = _qbez(root_top, (0.06, 0.30), WING_TIPS[0], 16)               # the leading edge, arching up
    centre = (0.12, 0.10)                                                  # the wrist: scallops are cut towards it
    for a, b in zip(WING_TIPS, WING_TIPS[1:]):
        mx, mz = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
        chord = math.hypot(b[0] - a[0], b[1] - a[1])
        dx, dz = centre[0] - mx, centre[1] - mz; dl = math.hypot(dx, dz)
        c = (mx + dx / dl * chord * depth * 2, mz + dz / dl * chord * depth * 2)   # the bezier's control: twice the sag
        pts += _qbez(a, c, b, 14)
    pts.append(WING_TIPS[-1])
    pts += _qbez(WING_TIPS[-1], (0.0, -0.04), (0.0, 0.0), 4)[1:]           # back along the root
    return pts

# How the wing is held. Folded (spread 0): swept back along the body, as on the character sheet. Open (spread 1):
# turned to face front and lifted, so the scalloped edge clears his outline — the icon and the keyboard both want it.
WING_POSE = dict(size=1.08, x=(0.29, 0.33), y=(0.22, 0.14), z=0.53, sweep=(34, -6), lift=(10, 5), tilt=-8, droop=28)

def wing(name, s, material, down=0.0, spread=0.0):
    """A small scalloped bat wing behind the shoulder (s = -1 left, +1 right). `spread` 0..1 opens it out past the
    body's silhouette; `down` 0..1 lets it hang (the yawn) — tipped down, still clear of his outline."""
    verts = [(x, 0, z) for x, z in wing_outline()]
    o = _mesh(name, verts, [tuple(range(len(verts)))], material, sub=0)
    mod = o.modifiers.new("solid", "SOLIDIFY"); mod.thickness = 0.03; mod.offset = 0
    B.smooth(o, 2)
    w = WING_POSE
    k = B.arg("--wings", w["size"])
    o.scale = (s * k, 1, k)
    at = lambda key: w[key][0] + (w[key][1] - w[key][0]) * spread     # folded → open (spread > 1 opens further)
    o.location = (s * B.arg("--wingx", at("x")), B.arg("--wingy", at("y")), B.arg("--wingz", w["z"]) - 0.05 * down)
    sweep = at("sweep")
    lift = at("lift") - w["droop"] * down
    # rotation about y tips the wing in its own plane: -s * lift raises the tip on either side
    o.rotation_euler = (math.radians(w["tilt"]), math.radians(-s * lift), math.radians(s * sweep))
    return o

def wing_report(label=""):
    """Where the wings land in the rendered frame, and how much of their edge is in sight: each wing's outermost and
    highest tip in pixels, and, for the outline's points (the four finger tips and the three scallops' deepest points
    above all), whether the camera sees the wing there or the body hides it. Printed as one JSON line."""
    import json
    from bpy_extras.object_utils import world_to_camera_view
    from mathutils import Vector
    sc = bpy.context.scene; bpy.context.view_layer.update(); dg = bpy.context.evaluated_depsgraph_get()
    cam = sc.camera; W, H = sc.render.resolution_x, sc.render.resolution_y
    outline = wing_outline()
    # the named points: finger tips, and each scallop's deepest point (the outline point nearest the wrist)
    n_lead = 16; named = {"tip0": n_lead}
    for i in range(3):
        seg = range(n_lead + 14 * i, n_lead + 14 * (i + 1))
        named[f"notch{i}"] = min(seg, key=lambda j: math.hypot(outline[j][0] - 0.12, outline[j][1] - 0.10))
        named[f"tip{i + 1}"] = n_lead + 14 * (i + 1)
    rep = {"label": label}
    body = bpy.data.objects["mosto_body"]
    bx = [world_to_camera_view(sc, cam, body.matrix_world @ v.co).x * W for v in body.data.vertices]
    rep["body_x"] = (round(min(bx)), round(max(bx)))
    for side in ("L", "R"):
        o = bpy.data.objects[f"mosto_wing{side}"]
        mw = o.matrix_world
        px = []
        for (x, z) in outline:
            # a hair inside the outline (subdivision rounds the very edge in), on the face towards the camera
            dx, dz = 0.12 - x, 0.10 - z; dl = math.hypot(dx, dz) or 1
            p = mw @ Vector((x + dx / dl * 0.025, -0.016, z + dz / dl * 0.025)); v = world_to_camera_view(sc, cam, p)
            px.append((v.x * W, (1 - v.y) * H, p))
        def seen(p):
            if cam.data.type == "ORTHO":
                d = (cam.matrix_world.to_quaternion() @ Vector((0, 0, -1))).normalized(); org = p - d * 20
            else:
                org = cam.matrix_world.translation; d = (p - org).normalized()
            hit, loc, nrm, idx, ob, _ = sc.ray_cast(dg, org, d)
            return bool(hit) and ob.name.startswith("mosto_wing") and (loc - p).length < 0.06
        vis = [seen(p) for (_, _, p) in px]
        xs = [a for a, _, _ in px]; ys = [b for _, b, _ in px]
        outer = min(range(len(px)), key=lambda i: xs[i]) if side == "L" else max(range(len(px)), key=lambda i: xs[i])
        rep[side] = dict(outer=(round(xs[outer]), round(ys[outer])), top=round(min(ys)),
                         x_range=(round(min(xs)), round(max(xs))), edge_seen=round(sum(vis) / len(vis), 2),
                         points={k: bool(vis[j]) for k, j in named.items()})
    span = rep["R"]["x_range"][1] - rep["L"]["x_range"][0]
    rep["span_over_body"] = round(span / (rep["body_x"][1] - rep["body_x"][0]), 2)
    print("WINGS " + json.dumps(rep), flush=True)
    return rep

def build_mosto(x=0.0, moss_eye=None, otto_eye=None, shut=None, glow=0.0, lean=0.0, perk=0.5, droop=0.0, hop=0.0, evil=0.0, yawn=0.0, spread=None):
    """moss_eye / otto_eye: the left and right eye — dicts of look, lid, pupil. shut: 'day' (blink).
    evil: 0..1, how strongly the gold irises and the tail tip glow (night).
    yawn: 0..1, his one slow yawn (the canon's: the fang shows, the wings droop) — the half of him that wants to rest.
    spread: 0..1, how far the wings open past his outline (default --spread, else folded)."""
    M = B.M
    if spread is None: spread = B.arg("--spread", 0.0)
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
    # a wide cat-mouth grin with a single fang — or, yawning, a mouth opened tall with the fang at its top edge
    my = ez - 0.15
    if yawn > 0:
        oh = 0.04 + 0.05 * yawn
        parts.append(B.sphere("mosto_yawn", (0.0, surface_y(0.0, my - oh * 0.4) - 0.006, my - oh * 0.4), (0.085, 0.035, oh), M["pupil"]))
        fx = 0.03; fz = my + 0.045 + oh * 0.1   # at the top edge of the open mouth, in front of it (see fy)
    else:
        pts = [(-0.085, my + 0.02), (-0.04, my - 0.012), (0.0, my + 0.004), (0.04, my - 0.012), (0.085, my + 0.02)]
        parts.append(B.tube("mosto_grin", [(x_, surface_y(x_, z_) - 0.005, z_) for x_, z_ in pts], B.arg("--grin", 0.011), M["pupil"]))
        fx = 0.035; fz = my - 0.012
    import mathutils
    fy = surface_y(fx, fz) - (0.075 if yawn > 0 else 0.004)
    bpy.ops.mesh.primitive_cone_add(vertices=20, radius1=0.016, radius2=0.002, depth=0.04, location=(fx, fy, fz - 0.016))
    fang = bpy.context.object; fang.name = "mosto_fang"; fang.rotation_euler = (math.radians(180), 0, 0)
    if yawn > 0:
        # against the dark of the open mouth the fang must carry its own light, or it reads as part of the hole
        fm = M["fang"].copy(); fm.name = "fang_lit"
        bsdf = fm.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Emission Color"].default_value = B.hexcol("#FFF6E0")
        bsdf.inputs["Emission Strength"].default_value = 0.6
        fang.data.materials.append(fm)
        fang.scale = (1.8, 1.8, 1.6)   # the open mouth makes the face read smaller: the fang is what says it is him
    else:
        fang.data.materials.append(M["fang"])
    parts.append(fang)
    # curled gold horns: out, then up and in
    for s in (-1, 1):
        hx = s * 0.27
        bz = m["cz"] + 0.32
        p0 = (hx, surface_y(hx, bz) * 0.4, bz)
        p1 = (hx + s * (0.2 + 0.03 * perk), -0.04, bz + 0.08)
        p2 = (hx + s * (0.12 + 0.02 * perk), -0.07, bz + 0.27 + 0.03 * perk)
        parts.append(horn(f"mosto_horn{s}", p0, p1, p2, 0.065, M["gold"]))
    parts += crown(top, material=M["crown"])
    parts += [wing("mosto_wingL", -1, M["mostoDeep"], down=yawn, spread=spread), wing("mosto_wingR", 1, M["mostoDeep"], down=yawn, spread=spread)]
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
    # night, left alone a while: his one slow yawn — eyes nearly shut, the fang showing, the wings drooping
    "yawn": dict(shut="day", evil=0.7, perk=0.0, droop=0.6, yawn=1.0),
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

def toy_finish(s, rim_energy=420):
    """The toy's photo finish, shared by the icon, the app's hero and the sprites: AgX's punchy look (the violet and
    gold stay saturated) and a warm crown-gold rim from behind, left, that lifts his outline off any ground."""
    try: s.view_settings.look = "AgX - Punchy"
    except TypeError: s.view_settings.look = "None"
    bpy.ops.object.light_add(type="AREA", location=(-2.4, 2.6, 2.6), rotation=(math.radians(-60), 0, math.radians(-140)))
    rim = bpy.context.object; rim.data.energy = rim_energy; rim.data.size = 1.6
    rim.data.color = (1.0, 0.82, 0.52)

SPRITE_SPREAD = 1.0
SPRITE_FRAME = (1.70, 0.64, 6, 0.06)   # orthographic width, centre height, tilt, centre x

def sprites(outdir):
    os.makedirs(outdir, exist_ok=True)
    size = B.arg("--size", 360)
    only = B.arg("--only", "")
    for name, kw in STATES.items():
        if only and name not in only.split(","): continue
        s = B.reset(); s.render.film_transparent = True; B.materials(); mosto_materials()
        night_world() if name in ("night", "yawn") else B.sprite_lights()
        toy_finish(s, B.arg("--rim", 300))
        s.render.resolution_x = s.render.resolution_y = size
        # wings open past his outline: at 44 pt the scalloped edge has to show beside the shoulders, not behind them
        build_mosto(**kw, spread=B.arg("--spread", SPRITE_SPREAD))
        ortho_camera(*SPRITE_FRAME)   # wide enough for the horns, the wings and the tail
        out = os.path.join(outdir, f"mosto_{name}.png")
        at = bead_position()
        if "--measure" in ARGS:
            wing_report(name)
            continue
        B.render(out, size, size)
        if name in ("night", "yawn"): add_glow(out, at)

SHEET_LABELS = [("day", "日光 · 平时", "瞪大眼睛看你打字"), ("glance", "张望", "斜眼瞟过去"), ("type", "打字", "低头看键盘"),
                ("blink", "眨眼", "白天每 5–9 秒一次"), ("night", "夜灯", "眯眼坏笑，金光亮起")]

def sheet(outdir):
    """Mosto's hero shot (a three-quarter turn, so the horns and the tail read), then its states; composed into
    mosto_sheet.png (docs/images): the hero above, the five states in a row, each named underneath. The wings are
    held as in the keyboard (SPRITE_SPREAD), so the sheet shows the same scalloped wings people see there."""
    os.makedirs(outdir, exist_ok=True)
    w, h = B.arg("--w", 1500), B.arg("--h", 760)
    sp = B.arg("--spread", SPRITE_SPREAD)
    B.reset(); B.materials(); mosto_materials(); B.studio("#E6DEE8")
    build_mosto(x=0.0, moss_eye=dict(look=(-0.45, 0.2)), otto_eye=dict(look=(-0.4, -0.05)), lean=0, spread=sp)
    bpy.data.objects["Mosto"].rotation_euler = (0, 0, math.radians(-22))
    B.camera(target=(0.0, 0, 0.6), dist=4.6, height=1.05, lens=60, fstop=8)
    B.render(os.path.join(outdir, "family.png"), w, h)
    for name in ("day", "glance", "type", "blink"):
        B.reset(); B.materials(); mosto_materials(); B.studio()
        build_mosto(**STATES[name], spread=sp)
        B.camera(target=(0.0, 0, 0.6), dist=4.2, height=0.95, lens=60, fstop=8)
        B.render(os.path.join(outdir, f"state_{name}.png"), 560, 560)
    B.reset(); B.materials(); mosto_materials(); night_set()
    build_mosto(**STATES["night"], spread=sp)
    B.camera(target=(0.0, 0, 0.6), dist=4.2, height=0.95, lens=60, fstop=8)
    at = bead_position()
    B.render(os.path.join(outdir, "state_night.png"), 560, 560)
    add_glow(os.path.join(outdir, "state_night.png"), at, radius=0.12, strength=0.6)
    compose_sheet(outdir, w, h)

def compose_sheet(outdir, w=1500, h=760):
    from PIL import Image, ImageDraw, ImageFont
    tile, strip = w // len(SHEET_LABELS), 110
    out = Image.new("RGB", (w, h + tile + strip), (244, 240, 246))
    out.paste(Image.open(os.path.join(outdir, "family.png")).convert("RGB"), (0, 0))
    font = "/usr/share/fonts/opentype/noto/NotoSansCJK-%s.ttc"
    big, small = ImageFont.truetype(font % "Bold", 30), ImageFont.truetype(font % "Regular", 20)
    d = ImageDraw.Draw(out)
    for i, (name, title, line) in enumerate(SHEET_LABELS):
        im = Image.open(os.path.join(outdir, f"state_{name}.png")).convert("RGB").resize((tile, tile), Image.LANCZOS)
        out.paste(im, (i * tile, h))
        d.text((i * tile + 20, h + tile + 22), title, font=big, fill=(28, 24, 36))
        d.text((i * tile + 20, h + tile + 66), line, font=small, fill=(92, 86, 104))
    out.save(os.path.join(outdir, "mosto_sheet.png"), optimize=True)

def icon(path):
    from PIL import Image, ImageDraw
    s = B.reset(); s.render.film_transparent = True; B.materials(); mosto_materials(); B.sprite_lights()
    size = 1024
    s.render.resolution_x = s.render.resolution_y = size
    night = "--night" in ARGS
    build_mosto(moss_eye=dict(look=(0.2, 0.3)), otto_eye=dict(look=(-0.05, 0.1), lid=0.52))
    ortho_camera(1.78, 0.58, cx=0.08)
    tmp = path.replace(".png", "_fg.png")
    B.render(tmp, size, size)
    if night:
        at = bead_position()
        add_glow(tmp, at, radius=0.1, strength=0.7)
    bg = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(bg)
    for y in range(size):                                   # warm butter-cream: the complement of Mosto's violet, so it stands out
        t = y / size
        d.line([(0, y), (size, y)], fill=(int(255 - 6 * t), int(244 - 26 * t), int(214 - 62 * t)))
    fg = Image.open(tmp).convert("RGBA")
    bg.paste(fg, (0, 0), fg)
    bg.save(path)
    os.remove(tmp)

def keycap(name, w, d, h, r, material, loc, rot=0.0):
    """A soft vinyl keycap block: a rounded box (bevelled edges, smooth corners)."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc); o = bpy.context.object; o.name = name
    o.scale = (w, d, h); bpy.ops.object.transform_apply(scale=True)
    bev = o.modifiers.new("bevel", "BEVEL"); bev.width = r; bev.segments = 8; bev.limit_method = "NONE"
    for poly in o.data.polygons: poly.use_smooth = True
    o.data.materials.append(material); o.rotation_euler = (0, 0, math.radians(rot))
    return o

def toy_key(name, x, y, rot, face, lip, size=1.0, z=0.0):
    """One toy key, as on the keyboard: a darker lip and the face resting on it."""
    s = size
    keycap(name + "_lip", 1.0 * s, 1.0 * s, 0.40 * s, 0.12 * s, lip, (x, y, z + 0.20 * s), rot)
    keycap(name + "_face", 0.86 * s, 0.86 * s, 0.26 * s, 0.12 * s, face, (x, y - 0.02 * s, z + 0.42 * s), rot)
    return z + 0.55 * s     # the top of the face

def legend(text, x, y, z, rot, size, material, font_path, on=None):
    """A key's legend: raised a hair above the face, centred, turned with the key."""
    bpy.ops.object.text_add(location=(x, y, z + 0.006)); t = bpy.context.object
    t.data.body = text
    try: t.data.font = bpy.data.fonts.load(font_path)
    except Exception: pass
    t.data.align_x = "CENTER"; t.data.align_y = "CENTER"; t.data.size = size; t.data.extrude = 0.012
    t.rotation_euler = (0, 0, math.radians(rot))
    t.data.materials.append(material)
    # fonts differ in how much of the em a glyph fills (a CJK face draws 中 at a third of it): scale to the height
    bpy.context.view_layer.update()
    h = max(t.dimensions.x, t.dimensions.y)
    if h > 0: t.scale = (size / h, size / h, 1.0)
    # a font's "centre" is its line box, not the glyph: move the glyph's own box onto the key face's real centre
    # (keycap() bakes the location into the mesh, so a key turns about the world origin, not about (x, y))
    bpy.context.view_layer.update()
    from mathutils import Vector
    if on is not None:
        o = bpy.data.objects[on]
        vs = [o.matrix_world @ v.co for v in o.data.vertices]
        x = sum(v.x for v in vs) / len(vs); y = sum(v.y for v in vs) / len(vs)
    corners = [t.matrix_world @ Vector(c) for c in t.bound_box]
    cx = sum(c.x for c in corners) / 8; cy = sum(c.y for c in corners) / 8
    t.location.x += x - cx; t.location.y += y - cy
    return t

ICON_SPREAD = 1.4   # seen from above the front, the wings open a little further to clear his head and shoulders

def toy_icon(path):
    """The app icon as a designer toy: Mosto, large, standing on a big cream keycap (the keyboard's own vinyl key, face
    over a lavender lip), with a crown-gold 中 key and a lavender A key in front of him (中/英 at a glance), seen from
    a little above so the legends read, on butter cream. --samples 160 for the shipped 1024 px icon."""
    from PIL import Image, ImageDraw
    night = "--night" in ARGS
    # at home-screen size the grin is what says he is grinning: a bolder line than the keyboard sprites need
    if "--grin" not in B.ARGS: B.ARGS += ["--grin", "0.017"]
    s = B.reset(); s.render.film_transparent = True; B.materials(); mosto_materials()
    night_world() if night else B.sprite_lights()
    toy_finish(s, B.arg("--rim", 420))
    size = B.arg("--size", 1024)
    s.render.resolution_x = s.render.resolution_y = size
    cream = B.rubber("keyCream", "#FFF9EE", rough=0.5, sss=0.06)
    lav = B.rubber("keyLav", "#B3A0EC", rough=0.55)
    lavDeep = B.rubber("keyLavDeep", "#7E68CF", rough=0.55)
    gold = B.mat("keyGold", "#FFB52E", rough=0.36, coat=0.2, sss=0.0)
    goldDeep = B.mat("keyGoldDeep", "#C9851A", rough=0.4, coat=0.15)
    top = toy_key("key_main", 0.0, 0.0, -18, cream, lav, size=1.22)
    gx, gy, gr, gs = B.arg("--gx", 0.92), B.arg("--gy", -0.5), B.arg("--gr", -10), B.arg("--gs", 0.74)
    lx, ly, lr, ls = B.arg("--lx", -0.95), B.arg("--ly", -0.4), B.arg("--lr", 16), B.arg("--ls", 0.66)
    gtop = toy_key("key_gold", gx, gy, gr, gold, goldDeep, size=gs)
    ltop = toy_key("key_lav", lx, ly, lr, lav, lavDeep, size=ls)
    # legends printed on the keys, as on the keyboard: 中 on the crown-gold key, A on the lavender one — the blocks
    # read as keys at a glance, and the icon says "Chinese keyboard" before anyone reads its name
    ink = B.mat("keyInk", "#2B1961", rough=0.5)
    inkLight = B.mat("keyInkLight", "#FFF9EE", rough=0.5)
    legend("中", gx, gy - 0.02 * gs, gtop, gr, 0.56 * gs, ink, "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc", on="key_gold_face")
    legend("A", lx, ly - 0.02 * ls, ltop, lr, 0.56 * ls, ink, "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc", on="key_lav_face")
    # by night (the dark home-screen icon): his scheming squint, gold irises and the spade glowing
    sp = B.arg("--spread", ICON_SPREAD)
    m = build_mosto(**STATES["night"], spread=sp) if night else \
        build_mosto(shut="day", spread=sp) if "--blink" in ARGS else \
        build_mosto(moss_eye=dict(look=(0.1, 0.25)), otto_eye=dict(look=(-0.08, 0.1), lid=0.5), spread=sp)
    m.location = (0.02, -0.05, top - 0.02); m.scale = (B.arg("--ms", 1.55),) * 3
    m.rotation_euler = (0, 0, math.radians(-8))
    # a shadow catcher under the keys: they sit on something
    bpy.ops.mesh.primitive_plane_add(size=12, location=(0, 0, 0)); g = bpy.context.object; g.is_shadow_catcher = True
    B.camera(target=(0.1, 0.15, B.arg("--ty", 0.8)), dist=B.arg("--dist", 4.15), height=B.arg("--ch", 3.25), lens=B.arg("--lens", 52), fstop=22)
    if "--measure" in ARGS:
        wing_report("night" if night else "day"); return
    if "--tinted" in ARGS:
        # the tinted icon (iOS 18+): one grey image the system colours — his figure in greys, lifted so the keys and
        # horns go white and the body sits mid-grey, on the dark icon's night (as a grey) with its soft pool of light
        from PIL import ImageFilter
        tmp = path.replace(".png", "_fg.png")
        B.render(tmp, size, size)
        fg = Image.open(tmp).convert("RGBA"); os.remove(tmp)
        bg = Image.new("RGB", (size, size)); d = ImageDraw.Draw(bg)
        for y in range(size):
            t = y / size
            d.line([(0, y), (size, y)], fill=(int(34 - 20 * t), int(22 - 12 * t), int(70 - 38 * t)))
        glow = Image.new("L", (size, size), 0)
        ImageDraw.Draw(glow).ellipse([size * 0.16, size * 0.06, size * 0.84, size * 0.66], fill=int(B.arg("--halo", 90)))
        glow = glow.filter(ImageFilter.GaussianBlur(size * 0.09))
        bg = Image.composite(Image.new("RGB", (size, size), (78, 52, 140)), bg, glow).convert("L")
        lum = fg.convert("RGB").convert("L").point(lambda v: max(0, min(255, int(1.48 * v - 55))))
        bg.paste(lum, (0, 0), fg.getchannel("A"))
        bg.save(path)
        return
    if "--hero" in ARGS:
        # the app's hero: the same toy scene on a transparent ground (the card behind it is the app's), blinking
        # with --blink
        at = bead_position() if night else None
        B.render(path, size, size)
        if night: add_glow(path, at, radius=0.09, strength=0.65)   # the spade's warm light, as in the keyboard
        return
    tmp = path.replace(".png", "_fg.png")
    B.render(tmp, size, size)
    bg = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(bg)
    for y in range(size):                                   # warm butter-cream: the complement of Mosto's violet
        t = y / size
        if night:                                           # 夜灯: deep violet night, darker toward the bottom
            d.line([(0, y), (size, y)], fill=(int(34 - 20 * t), int(22 - 12 * t), int(70 - 38 * t)))
        else:
            d.line([(0, y), (size, y)], fill=(int(255 - 6 * t), int(244 - 26 * t), int(214 - 62 * t)))
    # a soft pool of light behind his head: the eye goes to the face first
    from PIL import ImageFilter
    glow = Image.new("L", (size, size), 0)
    ImageDraw.Draw(glow).ellipse([size * 0.16, size * 0.06, size * 0.84, size * 0.66], fill=int(B.arg("--halo", 90)))
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.09))
    bg = Image.composite(Image.new("RGB", (size, size), (78, 52, 140) if night else (255, 251, 238)), bg, glow)
    fg = Image.open(tmp).convert("RGBA")
    bg.paste(fg, (0, 0), fg)
    bg.save(path)
    os.remove(tmp)

if __name__ == "__main__":
    what, out = ARGS[0], ARGS[1]
    {"sheet": sheet, "sprites": sprites, "icon": icon, "toyicon": toy_icon}[what](out)
