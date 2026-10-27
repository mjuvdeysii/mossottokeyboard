"""Moss and Otto as 3D characters, rendered with Blender Cycles (bpy), for the app's IP art.

Why: the companions drawn as flat 2D paths cannot reach the soft, tactile look of an animated feature. Here they are
modelled once — Moss a velvety moss pebble with a mint sprout, Otto a matte clay capsule with one big eye and a lamp on
a curved antenna (docs/IP.md §4) — lit like a film set (warm key, cool rim, soft fill, the lamp's own light) and
rendered with subsurface scattering, sheen, soft shadows and depth of field. Poses and expressions are parameters, so
every picture of them comes from the same model.

Usage:
  python3 tools/ip3d.py hero out.png [--w 1600 --h 1000 --samples 96]
  python3 tools/ip3d.py sheet out.png                 a sheet of expressions
"""
import math, sys, os
import bpy
from mathutils import Vector, Euler

ARGS = sys.argv[1:]
def arg(name, default):
    return type(default)(ARGS[ARGS.index(name) + 1]) if name in ARGS else default

def hexcol(h, a=1.0):
    h = h.lstrip("#"); r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    lin = lambda c: c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (lin(r), lin(g), lin(b), a)

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    s = bpy.context.scene
    s.render.engine = "CYCLES"
    s.cycles.device = "CPU"
    s.cycles.samples = arg("--samples", 96)
    s.cycles.use_denoising = True
    s.view_settings.view_transform = "AgX"
    s.view_settings.look = "AgX - Punchy"
    s.render.film_transparent = "--transparent" in ARGS
    return s

# ---------- materials ----------
def mat(name, base, rough=0.5, sss=0.0, sss_rad=(0.2, 0.1, 0.05), sheen=0.0, sheen_tint=None, coat=0.0, emit=None, emit_strength=0.0, bump=None):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; p = nt.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = hexcol(base)
    p.inputs["Roughness"].default_value = rough
    if sss:
        p.inputs["Subsurface Weight"].default_value = sss
        p.inputs["Subsurface Radius"].default_value = sss_rad
        p.inputs["Subsurface Scale"].default_value = 0.05
    if sheen:
        p.inputs["Sheen Weight"].default_value = sheen
        p.inputs["Sheen Roughness"].default_value = 0.4
        if sheen_tint: p.inputs["Sheen Tint"].default_value = hexcol(sheen_tint)
    if coat:
        p.inputs["Coat Weight"].default_value = coat
        p.inputs["Coat Roughness"].default_value = 0.03
    if emit:
        p.inputs["Emission Color"].default_value = hexcol(emit)
        p.inputs["Emission Strength"].default_value = emit_strength
    if bump:
        # a fine noise: moss fuzz or clay texture
        tex = nt.nodes.new("ShaderNodeTexNoise"); tex.inputs["Scale"].default_value = bump[0]; tex.inputs["Detail"].default_value = 8
        bm = nt.nodes.new("ShaderNodeBump"); bm.inputs["Strength"].default_value = bump[1]; bm.inputs["Distance"].default_value = 0.02
        nt.links.new(tex.outputs["Fac"], bm.inputs["Height"]); nt.links.new(bm.outputs["Normal"], p.inputs["Normal"])
    return m

def rubber(name, base, rough=0.6, sss=0.04, ior_level=0.35):
    """Soft matte vinyl, as designer toys are cast: an even colour, a soft broad sheen, a hint of light through the
    edges, and a fine orange-peel surface. No fur, no gloss, no painted texture."""
    m = mat(name, base, rough=rough, sss=sss, sss_rad=(0.4, 0.3, 0.25), bump=(700, 0.025))
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Specular IOR Level"].default_value = ior_level
    return m

def moss_material():
    """Velvety moss: a green that varies in lighter tufts (noise through a colour ramp), sheen for the fuzz, a little
    subsurface so the light glows through the edges, and fine bump."""
    m = mat("moss", "#55704A", rough=0.8, sss=0.1, sss_rad=(0.3, 0.5, 0.15), sheen=0.55, sheen_tint="#BFD9A0", bump=(260, 0.3))
    nt = m.node_tree; p = nt.nodes["Principled BSDF"]
    n = nt.nodes.new("ShaderNodeTexNoise"); n.inputs["Scale"].default_value = 14; n.inputs["Detail"].default_value = 6; n.inputs["Roughness"].default_value = 0.65
    r = nt.nodes.new("ShaderNodeValToRGB")
    r.color_ramp.elements[0].position = 0.42; r.color_ramp.elements[0].color = hexcol("#4C6A41")
    r.color_ramp.elements[1].position = 0.72; r.color_ramp.elements[1].color = hexcol("#6B8A55")
    nt.links.new(n.outputs["Fac"], r.inputs["Fac"]); nt.links.new(r.outputs["Color"], p.inputs["Base Color"])
    return m

# ---------- shapes ----------
def smooth(o, levels=3):
    mod = o.modifiers.new("sub", "SUBSURF"); mod.levels = levels; mod.render_levels = levels
    for poly in o.data.polygons: poly.use_smooth = True
    return o

def sphere(name, loc, scale, material, seg=48):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=seg // 2, location=loc)
    o = bpy.context.object; o.name = name; o.scale = scale
    for poly in o.data.polygons: poly.use_smooth = True
    o.data.materials.append(material); return o

def parent(children, root):
    for c in children: c.parent = root

def leaf(name, at, rot, length, material, width=0.55):
    """A real mint leaf (Mentha): ovate with a pointed tip and a short stalk, a serrated edge (about seven teeth a side),
    a sunken midrib with lateral veins standing out between them, the blade cupped and crinkled, the tip curling up.
    Built along +x from its stalk, then solidified and smoothed."""
    nu, nv = 14, 48
    L, W = length, length * width / 2
    verts, faces = [], []
    for j in range(nv + 1):
        t = j / nv
        w = W * math.sin(math.pi * min(1.0, t ** 0.78)) * (1 - 0.22 * t)
        if t < 0.07: w *= t / 0.07 * 0.35 + 0.05          # the stalk
        saw = ((t * 7.5) % 1.0)
        w *= 1 + 0.13 * (saw if t > 0.1 else 0) - 0.06
        for i in range(nu + 1):
            u = i / nu * 2 - 1
            x, y = t * L, u * w
            z = -0.022 * L * math.exp(-(u / 0.13) ** 2)                                   # midrib groove
            z += 0.007 * L * max(0.0, math.cos(2 * math.pi * (t * 5.5 - abs(u) * 0.55))) ** 6 * (1 - abs(u) ** 3)  # veins
            z += 0.006 * L * math.sin(u * 8 + t * 15)                                      # crinkle
            z += 0.07 * L * u * u + 0.2 * L * t * t                                        # cupped, tip curling up
            verts.append((x, y, z))
    for j in range(nv):
        for i in range(nu):
            a0 = j * (nu + 1) + i
            faces.append((a0, a0 + 1, a0 + nu + 2, a0 + nu + 1))
    me = bpy.data.meshes.new(name); me.from_pydata(verts, [], faces)
    o = bpy.data.objects.new(name, me); bpy.context.collection.objects.link(o)
    sol = o.modifiers.new("thick", "SOLIDIFY"); sol.thickness = 0.006 * L / 0.3
    smooth(o, 1)
    o.location = at; o.rotation_euler = rot
    o.data.materials.append(material); return o

def sprig(top, material_big, material_small, perk=0.0):
    """Moss's mint sprig, as on the icon: a stem, two big leaves at a node (left and right), and at the tip two small
    young leaves turned a quarter (mint leaves grow in opposite pairs, each pair crossing the one below)."""
    up_big = math.radians(28 + 18 * perk); up_small = math.radians(55 + 15 * perk)
    stem = tube("moss_stem", [(0, -0.02, top - 0.04), (0.008, -0.025, top + 0.08), (0.0, -0.02, top + 0.17)], 0.013, M["mintDeep"])
    n1 = (0.0, -0.022, top + 0.075); n2 = (0.0, -0.02, top + 0.165)
    # each blade turned to face the viewer (mint holds its leaves out flat to the light), so the outline, the teeth and
    # the veins read from the front; the young pair at the tip rises in a V, as on the icon
    roll = 1.05
    return [stem,
            leaf("moss_leafL", n1, Euler((-roll, -up_big, math.radians(185))), 0.33, material_big, width=0.62),
            leaf("moss_leafR", n1, Euler((roll, -up_big, math.radians(-5))), 0.35, material_big, width=0.62),
            leaf("moss_leafF", n2, Euler((-roll, -up_small, math.radians(160))), 0.14, material_small, width=0.6),
            leaf("moss_leafB", n2, Euler((roll, -up_small, math.radians(20))), 0.13, material_small, width=0.6)]

def tube(name, points, radius, material):
    cd = bpy.data.curves.new(name, "CURVE"); cd.dimensions = "3D"; cd.bevel_depth = radius; cd.bevel_resolution = 6
    sp = cd.splines.new("BEZIER"); sp.bezier_points.add(len(points) - 1)
    for bp, p in zip(sp.bezier_points, points):
        bp.co = p; bp.handle_left_type = bp.handle_right_type = "AUTO"
    o = bpy.data.objects.new(name, cd); bpy.context.collection.objects.link(o)
    o.data.materials.append(material); return o

M = {}
def materials():
    M["moss"] = rubber("moss", "#55704A")
    M["mint"] = rubber("mint", "#4E9A6C", rough=0.5, sss=0.08)
    M["mintPale"] = rubber("mintPale", "#8CCBA5", rough=0.5, sss=0.08)
    M["mintDeep"] = mat("mintDeep", "#3D6B44", rough=0.6)
    M["otto"] = rubber("otto", "#203872")
    M["ottoDeep"] = rubber("ottoDeep", "#1F3566")
    # painted eyes: a satin white and a glossy black, as on a vinyl figure
    M["eye"] = mat("eye", "#F6F3EA", rough=0.35, coat=0.35)
    M["pupil"] = mat("pupil", "#0E0E0D", rough=0.05, coat=1.0)
    M["iris"] = mat("iris", "#3A2A20", rough=0.2, coat=1.0)
    M["catch"] = mat("catch", "#FFFFFF", rough=0.1, emit="#FFFFFF", emit_strength=4.0)
    halo = bpy.data.materials.new("halo"); halo.use_nodes = True; nt = halo.node_tree
    for n in list(nt.nodes): nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial"); em = nt.nodes.new("ShaderNodeEmission"); tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader"); fres = nt.nodes.new("ShaderNodeLayerWeight"); fres.inputs["Blend"].default_value = 0.25
    em.inputs["Color"].default_value = hexcol("#FFC66E"); em.inputs["Strength"].default_value = 2.5
    nt.links.new(fres.outputs["Facing"], mix.inputs["Fac"]); nt.links.new(em.outputs[0], mix.inputs[1]); nt.links.new(tr.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"]); M["halo"] = halo
    M["cheek"] = mat("cheek", "#F49AB0", rough=0.6, sss=0.3)
    M["foot"] = rubber("foot", "#22231F")
    M["bead"] = mat("bead", "#D49A12", rough=0.35, emit="#FFA81E", emit_strength=0.0, coat=0.3, sss=0.3, sss_rad=(1.0, 0.6, 0.2))

def eye(name, at, r, look, scale=(1, 0.75, 1.1), lid=0.0, skin=None, pupil=0.55):
    """An eye: a glossy white, a pupil that looks where asked, a lid of the body's material when half closed."""
    w = sphere(name, at, (r * scale[0], r * scale[1], r * scale[2]), M["eye"])
    lx, lz = look
    pr = r * pupil
    px, py, pz = at[0] + lx * r * 0.42, at[1] - r * scale[1] * 0.78, at[2] + lz * r * 0.42
    p = sphere(name + "_p", (px, py - 0.002, pz), (pr, pr * 0.42, pr), M["pupil"])
    # the catchlight that makes an eye alive: a small bright spot up and to the left of the pupil
    c = sphere(name + "_c", (px - pr * 0.42, py - pr * 0.2, pz + pr * 0.42), (pr * 0.26, pr * 0.1, pr * 0.26), M["catch"])
    parts = [w, p, c]
    if lid > 0 and skin:
        # the lid: the body's skin covering the top of the eye
        l = sphere(name + "_lid", at, (r * scale[0] * 1.06, r * scale[1] * 1.1, r * scale[2] * 1.06), skin)
        bpy.ops.object.select_all(action="DESELECT"); l.select_set(True); bpy.context.view_layer.objects.active = l
        bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="DESELECT"); bpy.ops.object.mode_set(mode="OBJECT")
        cut = (1 - 2 * lid)
        for v in l.data.vertices: v.select = v.co.z < cut
        bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.delete(type="VERT"); bpy.ops.object.mode_set(mode="OBJECT")
        parts.append(l)
    return parts

def shaped_sphere(name, f, material, seg=64):
    """A sphere whose vertices are moved by f(x, y, z) -> (x, y, z) from unit coordinates."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=seg // 2, location=(0, 0, 0))
    o = bpy.context.object; o.name = name
    for v in o.data.vertices: v.co = Vector(f(*v.co))
    for poly in o.data.polygons: poly.use_smooth = True
    o.data.materials.append(material); return o

# Moss: a pebble 1.24 wide, 1.0 deep, its top at 0.74; the bottom flattened where it rests
MOSS = dict(rx=0.57, ry=0.5, rz=0.5, cz=0.4)
def moss_surface_y(x, z):
    m = MOSS; k = 1 - (x / m["rx"]) ** 2 - ((z - m["cz"]) / m["rz"]) ** 2
    return -m["ry"] * math.sqrt(max(0.0, k))

def build_moss(x=0.0, look=(0.45, 0.7), happy=False, lean=0.0, lid=0.0, er=0.105, pupil=0.62, hop=0.0, perk=0.0, shut=None):
    """Moss, the child: energy. `hop` lifts and stretches the body mid-jump; `perk` stands the leaves up."""
    m = MOSS
    root = bpy.data.objects.new("Moss", None); bpy.context.collection.objects.link(root)
    # the icon's pebble: higher on the right, the left shoulder lower and rounder, the base flattened where it rests
    def f(a, b, c):
        # a round, full pebble: no peak, no wedge — only a breath higher on the right (the icon's DNA), so the body
        # never reads as an arrow pointing somewhere
        z = (c if c > 0 else c * 0.72) * m["rz"]
        if c > 0: z *= 1 + 0.05 * a
        return (a * m["rx"], b * m["ry"], m["cz"] + z)
    body = shaped_sphere("moss_body", f, M["moss"])
    feet = [sphere(f"moss_foot{i}", (s * 0.22, -0.12, 0.045), (0.08, 0.1, 0.055), M["foot"]) for i, s in enumerate((-1, 1))]
    top = m["cz"] + m["rz"]
    # the mint sprig: always real mint leaves (serrated, veined), never a generic sprout
    sprig_parts = sprig(top, M["mint"], M["mintPale"], perk)
    parts = [body, *feet, *sprig_parts]
    ez, ex = m["cz"] + 0.2, 0.135
    for s in (-1, 1):
        sy = moss_surface_y(s * ex, ez)
        if happy or shut:
            dz = {"down": -0.03, "flat": -0.006}.get(shut, 0.045)
            parts.append(tube(f"moss_shut{s}", [(s * ex - 0.075, sy - 0.0, ez - 0.01), (s * ex, sy - 0.022, ez + dz * 1.2), (s * ex + 0.075, sy - 0.0, ez - 0.01)], 0.016, M["pupil"]))
        else:
            parts += eye(f"moss_eye{s}", (s * ex, sy + 0.025, ez), er, look, scale=(0.87, 0.5, 1.0), lid=lid, skin=M["moss"], pupil=pupil)
    if "--cheeks" in ARGS:
        for s in (-1, 1):
            cz = m["cz"] + 0.04; cx = s * 0.3
            parts.append(sphere(f"moss_cheek{s}", (cx, moss_surface_y(cx, cz) + 0.012, cz), (0.075, 0.015, 0.045), M["cheek"]))
    parent(parts, root)
    root.location = (x, 0, hop); root.rotation_euler = (0, math.radians(lean), 0)
    if hop > 0: root.scale = (1 - hop * 0.35, 1 - hop * 0.35, 1 + hop * 0.7)   # stretched in the air
    return root

# Otto: a tall dome 0.84 wide, its top at 1.26, the bottom rounded onto the table
OTTO = dict(rx=0.45, ry=0.41, cz=0.48, top=0.64, bottom=0.44)
OTTO_PROFILE = [(0.03, 0.0), (0.09, 0.41), (0.22, 0.455), (0.45, 0.45), (0.7, 0.425), (0.9, 0.37), (1.04, 0.27), (1.12, 0.14), (1.14, 0.0)]
def otto_radius(z):
    for (z0, r0), (z1, r1) in zip(OTTO_PROFILE, OTTO_PROFILE[1:]):
        if z0 <= z <= z1: return r0 + (r1 - r0) * (z - z0) / (z1 - z0)
    return 0.0
def otto_surface_y(x, z):
    r = otto_radius(z) * 0.97   # the subdivided surface sits a little inside the profile
    return -0.9 * math.sqrt(max(0.0, r * r - x * x))

def build_otto(x=0.0, look=(-0.3, 0.0), lid=0.3, glow=1.0, lean=0.0, happy=False, slouch=0.0, droop=0.0, bags=False, yawn=False, shut=None, smirk=False):
    """Otto, the adult: a tired, unhurried calm. `slouch` lets the body settle forward and sag a little; `droop` lowers the
    lamp on its rod; `bags` adds the soft shadow under the eye; `yawn` opens a small mouth."""
    o = OTTO
    root = bpy.data.objects.new("Otto", None); bpy.context.collection.objects.link(root)
    # turned like a wooden toy: a profile spun round its axis — a broad soft base, nearly straight sides that lean in a
    # little, and a round dome (the icon's silhouette), then smoothed
    prof = [(0.0, 0.03), (0.28, 0.035), (0.41, 0.09), (0.455, 0.22), (0.45, 0.45), (0.425, 0.7), (0.37, 0.9), (0.27, 1.04), (0.14, 1.12), (0.0, 1.14)]
    me = bpy.data.meshes.new("otto_profile"); me.from_pydata([(x, 0, z) for x, z in prof], [(i, i + 1) for i in range(len(prof) - 1)], [])
    body = bpy.data.objects.new("otto_body", me); bpy.context.collection.objects.link(body)
    sc = body.modifiers.new("spin", "SCREW"); sc.steps = 64; sc.render_steps = 64; sc.use_merge_vertices = True; sc.use_smooth_shade = True
    smooth(body, 2)
    body.scale = (1.0, 0.9, 1.0)
    body.data.materials.append(M["otto"])
    feet = [sphere(f"otto_foot{i}", (s * 0.17, -0.1, 0.045), (0.075, 0.095, 0.055), M["foot"]) for i, s in enumerate((-1, 1))]
    parts = [body, *feet]
    ez = 0.8
    if shut:
        sy = otto_surface_y(0, ez)
        dz = -0.012 if shut == "flat" else -0.05
        parts.append(tube("otto_shut", [(-0.13, sy - 0.0, ez), (0.0, sy - 0.03, ez + dz), (0.13, sy - 0.0, ez)], 0.017, M["pupil"]))
        if bags: parts.append(sphere("otto_bag", (0.0, otto_surface_y(0, ez - 0.2) + 0.035, ez - 0.2), (0.17, 0.03, 0.035), M["ottoDeep"]))
    elif happy:
        sy = otto_surface_y(0, ez)
        parts.append(tube("otto_smile", [(-0.12, sy + 0.01, ez - 0.02), (0.0, sy - 0.015, ez + 0.06), (0.12, sy + 0.01, ez - 0.02)], 0.016, M["pupil"]))
        parts.append(sphere("otto_cheek", (0.24, otto_surface_y(0.24, ez - 0.14) + 0.01, ez - 0.14), (0.065, 0.015, 0.04), M["cheek"]))
    else:
        parts += eye("otto_eye", (0.0, otto_surface_y(0, ez) + 0.06, ez), 0.21, look, scale=(1.05, 0.5, 0.95), lid=lid, skin=M["otto"], pupil=0.57)
        if bags:
            # tiredness: a soft, slightly darker fold under the eye
            parts.append(sphere("otto_bag", (0.0, otto_surface_y(0, ez - 0.2) + 0.035, ez - 0.2), (0.17, 0.03, 0.035), M["ottoDeep"]))
    if smirk:
        # the most Otto ever smiles: one corner, lifted
        sy = otto_surface_y(0.05, 0.5)
        parts.append(tube("otto_smirk", [(-0.07, sy + 0.005, 0.5), (0.04, sy - 0.005, 0.495), (0.1, sy + 0.0, 0.525)], 0.012, M["pupil"]))
    if yawn:
        # a long, slow yawn: a dark oval mouth set into the front, low on the face
        parts.append(sphere("otto_yawn", (0.0, otto_surface_y(0, 0.5) - 0.005, 0.5), (0.085, 0.03, 0.11), M["foot"]))
    # the antenna: from the top of the head, arching forward, the lamp bead at its end
    top = (0.0, 0.0, 1.13)
    # the icon's rod: up from the crown, arching forward and to the left, the bead hanging at its end
    bx, by, bz = -0.36 - 0.06 * droop, -0.22 - 0.08 * droop, top[2] + 0.12 - 0.22 * droop
    parts.append(tube("otto_antenna", [top, (-0.02, -0.03, top[2] + 0.2 - 0.05 * droop), (-0.2 - 0.04 * droop, -0.12 - 0.05 * droop, top[2] + 0.28 - 0.1 * droop), (bx, by, bz + 0.07)], 0.015, M["ottoDeep"]))
    parts.append(sphere("otto_bead", (bx, by, bz), (0.07, 0.07, 0.07), M["bead"]))
    # (the glow round the bead is added in 2D, over the render)
    M["bead"].node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 1.6 * glow
    if glow > 0:
        bpy.ops.object.light_add(type="POINT", location=(bx, by - 0.02, bz - 0.04)); lamp = bpy.context.object
        lamp.data.energy = 25 * glow; lamp.data.color = hexcol("#FFC66E")[:3]; lamp.data.shadow_soft_size = 0.07
        parts.append(lamp)
    parent(parts, root)
    root.location = (x, 0.2, 0); root.rotation_euler = (math.radians(4 * slouch), math.radians(lean), 0)
    if slouch: root.scale = (1 + 0.025 * slouch, 1 + 0.025 * slouch, 1 - 0.04 * slouch)
    return root

# ---------- set ----------
def table_and_lights(night=False):
    # a wooden table top and a soft wall behind
    bpy.ops.mesh.primitive_plane_add(size=12, location=(0, 0, 0)); t = bpy.context.object
    wood = mat("wood", "#C99A62", rough=0.55, bump=(14, 0.12))
    nt = wood.node_tree; p = nt.nodes["Principled BSDF"]
    w = nt.nodes.new("ShaderNodeTexWave"); w.inputs["Scale"].default_value = 1.6; w.inputs["Distortion"].default_value = 6; w.inputs["Detail"].default_value = 3
    r = nt.nodes.new("ShaderNodeValToRGB"); r.color_ramp.elements[0].color = hexcol("#B98450"); r.color_ramp.elements[1].color = hexcol("#D9AE77")
    nt.links.new(w.outputs["Fac"], r.inputs["Fac"]); nt.links.new(r.outputs["Color"], p.inputs["Base Color"])
    t.data.materials.append(wood)
    bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 5.5, 3), rotation=(math.radians(90), 0, 0)); wall = bpy.context.object
    wall.data.materials.append(mat("wall", "#3A3350" if night else "#F3E6D3", rough=0.9))
    world = bpy.data.worlds.new("w"); bpy.context.scene.world = world; world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = hexcol("#2A2540" if night else "#FFF4E6")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.12 if night else 0.3
    def area(loc, rot, energy, size, color):
        bpy.ops.object.light_add(type="AREA", location=loc, rotation=rot); l = bpy.context.object
        l.data.energy = energy; l.data.size = size; l.data.color = hexcol(color)[:3]; return l
    # key: warm, high left; rim: cool, behind right; fill: soft from the front
    area((-2.4, -2.2, 3.4), (math.radians(45), 0, math.radians(-45)), 520 if not night else 60, 1.4, "#FFE1BE")
    area((2.4, 2.2, 2.4), (math.radians(-60), 0, math.radians(140)), 260 if not night else 90, 1.2, "#BFD8FF")
    area((0.4, -3.4, 1.0), (math.radians(80), 0, 0), 90 if not night else 10, 3.0, "#FFF6EA")

def studio(color="#E8E1D5"):
    """A product-photography set, as figures are shot for a catalogue: a seamless curved backdrop in one warm grey, one
    big soft key from the front left, a fill, a rim from behind, and a soft contact shadow under each figure."""
    import math as m
    prof = [(-6.0, 0.0)] + [(2.0 + 1.5 * m.sin(t * m.pi / 2), 1.5 - 1.5 * m.cos(t * m.pi / 2)) for t in [i / 12 for i in range(13)]] + [(3.5, 6.0)]
    verts, faces = [], []
    for x in (-8.0, 8.0):
        for (y, z) in prof: verts.append((x, y, z))
    n = len(prof)
    for i in range(n - 1): faces.append((i, i + 1, n + i + 1, n + i))
    me = bpy.data.meshes.new("cyc"); me.from_pydata(verts, [], faces)
    o = bpy.data.objects.new("cyc", me); bpy.context.collection.objects.link(o)
    for poly in me.polygons: poly.use_smooth = True
    o.data.materials.append(mat("cyc", color, rough=0.95))
    world = bpy.data.worlds.new("w"); bpy.context.scene.world = world; world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = hexcol("#FFF6EC")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.25
    def area(loc, rot, energy, size, color):
        bpy.ops.object.light_add(type="AREA", location=loc, rotation=rot); l = bpy.context.object
        l.data.energy = energy; l.data.size = size; l.data.color = hexcol(color)[:3]; return l
    area((-2.2, -3.0, 3.0), (math.radians(55), 0, math.radians(-35)), 520, 3.2, "#FFF1E0")   # key: a big softbox
    area((2.8, -2.4, 1.4), (math.radians(75), 0, math.radians(50)), 160, 3.0, "#F4F6FF")      # fill
    area((1.5, 2.8, 2.8), (math.radians(-55), 0, math.radians(150)), 380, 1.5, "#FFFFFF")     # rim

def board3d(out):
    """Gate 1, round 3: Otto tired and unhurried (an adult at the end of a long day), Moss full of a child's energy."""
    from PIL import Image
    # cold humour for both: whatever the body does, the face stays deadpan — half-lidded, level, unimpressed
    pairs = [
        ("p1", dict(look=(0.0, 0.05), lid=0.45, pupil=0.5, hop=0.12, perk=1.0), dict(look=(-0.8, -0.3), lid=0.6, slouch=1.0, droop=0.7, bags=True)),
        ("p2", dict(look=(0.9, 0.1), lid=0.45, pupil=0.5, lean=8, perk=0.8), dict(look=(0.0, -0.1), lid=0.8, slouch=1.2, droop=1.0, bags=True, yawn=True)),
        ("p3", dict(look=(0.0, 0.0), lid=0.5, pupil=0.48, perk=0.6), dict(look=(0.0, -0.05), lid=0.62, slouch=0.9, droop=0.6, bags=True)),
    ]
    tiles = []
    only = ARGS[ARGS.index("--only") + 1].split(",") if "--only" in ARGS else None
    for name, mk, ok in pairs:
        if only and name not in only: continue
        reset(); materials(); studio()
        build_moss(x=-0.58, **mk)
        build_otto(x=0.62, glow=0.6, lean=-2, **ok)
        camera(target=(0.05, 0, 0.62), dist=5.9, height=1.0, lens=70, fstop=5.6)
        path = out.replace(".png", f"_{name}.png")
        render(path, arg("--w", 900), arg("--h", 560)); tiles.append(path)

def ring_stacker(loc, k=1.0):
    """The Montessori ring stacker, in wood and lacquer: a base, a rod and three rings."""
    wood = mat("toywood", "#E3C08C", rough=0.45, coat=0.3)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.2 * k, depth=0.06 * k, location=(loc[0], loc[1], 0.03 * k)); b = bpy.context.object; b.data.materials.append(wood); smooth(b, 2)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.025 * k, depth=0.55 * k, location=(loc[0], loc[1], 0.3 * k)); r = bpy.context.object; r.data.materials.append(wood)
    z = 0.1 * k
    for rr, c in [(0.19, "#4FA3A0"), (0.155, "#F2C14E"), (0.12, "#E0644B")]:
        bpy.ops.mesh.primitive_torus_add(major_radius=rr * k * 0.62, minor_radius=rr * k * 0.38, location=(loc[0], loc[1], z)); t = bpy.context.object
        t.scale.z = 0.8; t.data.materials.append(mat("ring" + c, c, rough=0.3, coat=0.7)); smooth(t, 1)
        z += rr * k * 0.62
    sphere("toyknob", (loc[0], loc[1], 0.6 * k), (0.045 * k, 0.045 * k, 0.045 * k), wood)

def bloom():
    s = bpy.context.scene; s.use_nodes = True
    tree = s.compositing_node_group if hasattr(s, "compositing_node_group") and s.compositing_node_group else None
    try:
        nt = s.node_tree
        rl = nt.nodes.get("Render Layers") or nt.nodes.new("CompositorNodeRLayers")
        comp = nt.nodes.get("Composite") or nt.nodes.new("CompositorNodeComposite")
        g = nt.nodes.new("CompositorNodeGlare"); g.glare_type = "FOG_GLOW"; g.threshold = 0.9; g.size = 7
        nt.links.new(rl.outputs["Image"], g.inputs["Image"]); nt.links.new(g.outputs["Image"], comp.inputs["Image"])
    except Exception as e:
        print("no bloom:", e)

def camera(target=(0.05, 0, 0.58), dist=4.4, height=0.82, lens=50, fstop=2.4):
    bpy.ops.object.camera_add(location=(0.15, -dist, height)); c = bpy.context.object
    d = Vector(target) - c.location; c.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    c.data.lens = lens; c.data.dof.use_dof = True; c.data.dof.focus_distance = d.length; c.data.dof.aperture_fstop = fstop
    bpy.context.scene.camera = c

def render(path, w, h):
    s = bpy.context.scene; s.render.resolution_x = w; s.render.resolution_y = h; s.render.filepath = os.path.abspath(path)
    bpy.ops.render.render(write_still=True)

# ---------- the app's sprites ----------
# Every state the app shows, each character alone, transparent, under one product-photo light, the same slightly
# raised orthographic camera; the bead's position is written alongside, for the app's glow at night.
OTTO_TIRED = dict(slouch=0.8, droop=0.6, bags=True)
STATES = {
    # Moss is a small child: wide awake, big pupils, leaves up, always half a move into something
    "moss": {
        "idle": dict(lid=0.08, look=(0.15, 0.1), er=0.12, pupil=0.56, perk=0.6, lean=-3),
        "left": dict(lid=0.05, look=(-0.95, 0.15), er=0.12, pupil=0.56, perk=0.8, lean=8),
        "right": dict(lid=0.05, look=(0.95, 0.15), er=0.12, pupil=0.56, perk=0.8, lean=-8),
        "up": dict(lid=0.0, look=(0.1, 0.95), er=0.12, pupil=0.52, perk=1.0),
        "down": dict(lid=0.15, look=(0, -0.5), er=0.12, pupil=0.56, perk=0.4, lean=-4),
        "blink": dict(shut="flat", perk=0.6, lean=-3),
        "wide": dict(lid=0.0, look=(0, 0.2), er=0.135, pupil=0.44, perk=1.0),
        "glee": dict(shut="up", perk=1.0, lean=-5),
        "sleep": dict(shut="down", perk=-0.3),
        "hop": dict(lid=0.0, look=(0.1, 0.4), er=0.12, pupil=0.5, perk=1.0, lean=-6),
    },
    "otto": {
        "idle": dict(lid=0.6, look=(0, -0.1), **OTTO_TIRED), "left": dict(lid=0.6, look=(-0.85, -0.15), **OTTO_TIRED),
        "right": dict(lid=0.6, look=(0.85, -0.15), **OTTO_TIRED), "up": dict(lid=0.5, look=(0, 0.7), **OTTO_TIRED),
        "down": dict(lid=0.62, look=(0, -0.42), **OTTO_TIRED), "blink": dict(shut="flat", **OTTO_TIRED),
        "wide": dict(lid=0.3, look=(0, 0.1), slouch=0.3, droop=0.2, bags=True), "glee": dict(lid=0.5, look=(0, 0), smirk=True, **OTTO_TIRED),
        "sleep": dict(shut="down", slouch=1.2, droop=1.0, bags=True), "yawn": dict(shut="flat", yawn=True, slouch=1.0, droop=0.9, bags=True),
    },
}
FRAME = {"moss": (1.62, 0.6), "otto": (1.9, 0.74)}   # orthographic width, centre height (the ground sits ~8% up)

def sprite_lights():
    world = bpy.data.worlds.new("w"); bpy.context.scene.world = world; world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = hexcol("#FFF6EC")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.45
    def area(loc, rot, energy, size, color):
        bpy.ops.object.light_add(type="AREA", location=loc, rotation=rot); l = bpy.context.object
        l.data.energy = energy; l.data.size = size; l.data.color = hexcol(color)[:3]
    area((-2.2, -3.0, 3.0), (math.radians(55), 0, math.radians(-35)), 520, 3.2, "#FFF1E0")
    area((2.8, -2.4, 1.4), (math.radians(75), 0, math.radians(50)), 170, 3.0, "#F4F6FF")
    area((1.5, 2.8, 2.8), (math.radians(-55), 0, math.radians(150)), 380, 1.5, "#FFFFFF")

def sprites(outdir):
    import json
    os.makedirs(outdir, exist_ok=True)
    only = ARGS[ARGS.index("--only") + 1].split(",") if "--only" in ARGS else None
    size = arg("--size", 512)
    meta = {"frame": FRAME}
    for kind, states in STATES.items():
        for st, kw in states.items():
            name = f"{kind}_{st}"
            if only and name not in only: continue
            s = reset(); s.render.film_transparent = True; materials(); sprite_lights()
            s.render.resolution_x = s.render.resolution_y = size
            if kind == "moss": build_moss(**kw)
            else: build_otto(glow=0.6, **kw)
            ortho, cz = FRAME[kind]
            tilt = math.radians(6)
            bpy.ops.object.camera_add(location=(0, -8 * math.cos(tilt), cz + 8 * math.sin(tilt))); c = bpy.context.object
            c.rotation_euler = (math.radians(90) - tilt, 0, 0); c.data.type = "ORTHO"; c.data.ortho_scale = ortho
            s.camera = c
            if kind == "otto":
                from bpy_extras.object_utils import world_to_camera_view
                bpy.context.view_layer.update()
                p = world_to_camera_view(s, c, bpy.data.objects["otto_bead"].matrix_world.translation)
                meta[f"bead_{st}"] = [round(p.x, 4), round(1 - p.y, 4)]
            render(os.path.join(outdir, name + ".png"), size, size)
    old = json.load(open(os.path.join(outdir, "sprites.json"))) if os.path.exists(os.path.join(outdir, "sprites.json")) else {}
    old.update(meta); json.dump(old, open(os.path.join(outdir, "sprites.json"), "w"), indent=1)

def hero(path):
    reset(); materials(); table_and_lights(night="--night" in ARGS)
    build_moss(x=-0.62, look=(0.7, 0.1), lean=4)
    build_otto(x=0.62, look=(-0.7, -0.2), lid=0.32, glow=1.0, lean=-2)
    ring_stacker((0.05, 0.9, 0), 0.9)
    bloom()
    camera()
    render(path, arg("--w", 1600), arg("--h", 1000))

if __name__ == "__main__":
    what, out = ARGS[0], ARGS[1]
    {"hero": hero, "board": board3d, "sprites": sprites}[what](out)
