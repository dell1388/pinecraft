
# The traders and their helper, built from code the way the lumberjack is
# (player_build in player.blend): the same pivots (Torso, Head, Arm_*, Elbow_*,
# Hand_*, Finger*, Thumb*, Leg_*, Knee_*, Foot_*) so the game poses them the
# same way, and their props (pickaxe, felling axe, rocking chair) as their own
# objects. Blender: +Y is the front, +Z up.
#
#   lumberman   a big old logger: grey beard, green buffalo plaid, trapper hat
#   miner       helmet and lamp, sooty face, black moustache, overalls
#   granny      small and round: bun, glasses, shawl, long dress, slippers
#   helper      the short fellow who loads your order: hi-vis vest, cap
#
# Run with exec(); then build_all() puts them side by side, or
# build_one('miner') builds one for export.

import bpy, bmesh, math
from mathutils import Vector, Matrix

STYLE = {'sides': 14, 'belly': 16, 'chamfer': 0.016, 'segs': 2, 'soft': 1.25}

def mat(name, rgb, rough=0.8, metal=0.0, glow=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get('Principled BSDF')
    b.inputs['Base Color'].default_value = (*rgb, 1)
    b.inputs['Roughness'].default_value = rough
    b.inputs['Metallic'].default_value = metal
    if glow > 0.0:
        b.inputs['Emission Color'].default_value = (*rgb, 1)
        b.inputs['Emission Strength'].default_value = glow
    return m

M = {}
def materials():
    global M
    M = {
        # shared
        'Skin': mat('N_Skin', (0.8, 0.6, 0.46)), 'SkinOld': mat('N_SkinOld', (0.84, 0.66, 0.56)),
        'Nose': mat('N_Nose', (0.8, 0.34, 0.3)), 'Eye': mat('N_Eye', (0.06, 0.06, 0.07), 0.3),
        'Brass': mat('N_Brass', (0.82, 0.66, 0.26), 0.35, 0.8), 'Sole': mat('N_Sole', (0.09, 0.08, 0.075)),
        'Lace': mat('N_Lace', (0.62, 0.5, 0.34)), 'Steel': mat('N_Steel', (0.6, 0.62, 0.66), 0.35, 0.9),
        'Wood': mat('N_Wood', (0.55, 0.36, 0.2)), 'WoodDark': mat('N_WoodDark', (0.36, 0.22, 0.12)),
        'Cheek': mat('N_Cheek', (0.9, 0.5, 0.48)),
        # lumberman
        'GreenPlaid': mat('N_GreenPlaid', (0.2, 0.44, 0.24)), 'GreenDark': mat('N_GreenDark', (0.06, 0.13, 0.08)),
        'Canvas': mat('N_Canvas', (0.5, 0.38, 0.22)), 'BootBrown': mat('N_BootBrown', (0.24, 0.14, 0.07)),
        'GreyBeard': mat('N_GreyBeard', (0.8, 0.79, 0.76)), 'GreyDark': mat('N_GreyDark', (0.58, 0.57, 0.55)),
        'Leather': mat('N_Leather', (0.44, 0.26, 0.12)), 'Fur': mat('N_Fur', (0.9, 0.84, 0.72)),
        'Tan': mat('N_Tan', (0.64, 0.46, 0.26)), 'AxeRed': mat('N_AxeRed', (0.72, 0.12, 0.1), 0.5),
        # miner
        'Shirt': mat('N_Shirt', (0.74, 0.71, 0.62)), 'Overall': mat('N_Overall', (0.26, 0.33, 0.42)),
        'OverallDark': mat('N_OverallDark', (0.16, 0.2, 0.26)), 'BootBlack': mat('N_BootBlack', (0.1, 0.09, 0.09)),
        'Helmet': mat('N_Helmet', (0.96, 0.74, 0.1), 0.4), 'Lamp': mat('N_Lamp', (1.0, 0.95, 0.7), 0.2, 0.0, 4.0),
        'Soot': mat('N_Soot', (0.36, 0.3, 0.27)), 'Black': mat('N_Black', (0.08, 0.07, 0.07)),
        'Gauntlet': mat('N_Gauntlet', (0.42, 0.3, 0.2)), 'Iron': mat('N_Iron', (0.5, 0.51, 0.55), 0.45, 0.5),
        # granny
        'Dress': mat('N_Dress', (0.56, 0.44, 0.7)), 'DressDark': mat('N_DressDark', (0.4, 0.3, 0.54)),
        'Shawl': mat('N_Shawl', (0.86, 0.5, 0.52)), 'ShawlDark': mat('N_ShawlDark', (0.7, 0.36, 0.4)),
        'Hair': mat('N_Hair', (0.8, 0.8, 0.84)), 'HairDark': mat('N_HairDark', (0.62, 0.62, 0.66)), 'Glasses': mat('N_Glasses', (0.25, 0.2, 0.16), 0.3, 0.6),
        'Slipper': mat('N_Slipper', (0.9, 0.55, 0.62)), 'Apron': mat('N_Apron', (0.94, 0.92, 0.86)),
        'Cushion': mat('N_Cushion', (0.72, 0.2, 0.22)), 'Yarn': mat('N_Yarn', (0.3, 0.55, 0.8)),
        # helper
        'Vis': mat('N_Vis', (1.0, 0.5, 0.08), 0.6), 'Reflect': mat('N_Reflect', (0.92, 0.93, 0.9), 0.3, 0.3),
        'Tee': mat('N_Tee', (0.2, 0.3, 0.55)), 'Work': mat('N_Work', (0.25, 0.25, 0.27)),
        'Cap': mat('N_Cap', (0.18, 0.4, 0.75)), 'Yellow': mat('N_Yellow', (0.95, 0.78, 0.2)),
        'Ginger': mat('N_Ginger', (0.72, 0.34, 0.12)),
    }

coll = None

def empty(name, parent, loc, rot=(0, 0, 0)):
    o = bpy.data.objects.new(name, None)
    o.empty_display_size = 0.05
    coll.objects.link(o)
    o.parent = parent
    o.location = loc
    o.rotation_euler = rot
    return o

def finish(name, bm, m, parent, loc, rot, bevel, segs=None):
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=segs or STYLE['segs'], profile=0.5,
                        affect='EDGES', clamp_overlap=True)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    me.materials.append(M[m])
    o = bpy.data.objects.new(name, me)
    coll.objects.link(o)
    o.parent = parent
    o.location = loc
    o.rotation_euler = rot
    return o

def box(name, size, loc, m, parent, rot=(0, 0, 0), bevel=None, soft=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    b = STYLE['chamfer'] if bevel is None else bevel
    b = b + soft * STYLE['soft']
    return finish(name, bm, m, parent, loc, rot, min(b, min(size) * 0.45))

def rings(name, profile, m, parent, loc=(0, 0, 0), rot=(0, 0, 0), n=None, sx=1.0, sy=1.0, bevel=0.0, dy=0.0):
    n = n or STYLE['sides']
    bm = bmesh.new()
    loops = []
    for entry in profile:
        z, rx, ry = (entry[0], entry[1], entry[1]) if len(entry) == 2 else entry
        loops.append([bm.verts.new((math.cos(t) * rx * sx, math.sin(t) * ry * sy + dy, z))
                      for t in [2 * math.pi * (i + 0.5) / n for i in range(n)]])
    for a, b in zip(loops, loops[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(list(reversed(loops[0])))
    bm.faces.new(loops[-1])
    return finish(name, bm, m, parent, loc, rot, bevel)

def loft(name, sections, m, parent, loc=(0, 0, 0), rot=(0, 0, 0), bevel=0.0):
    bm = bmesh.new()
    loops = [[bm.verts.new(p) for p in sec] for sec in sections]
    n = len(loops[0])
    for a, b in zip(loops, loops[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(list(reversed(loops[0])))
    bm.faces.new(loops[-1])
    return finish(name, bm, m, parent, loc, rot, bevel)

def rrect_xz(y, w, zb, zt, r, k=3, r_top=None):
    h = zt - zb
    rb = min(r, w / 2 - 0.001, h / 2 - 0.001)
    rt = min(r if r_top is None else r_top, w / 2 - 0.001, h - rb - 0.001)
    pts = []
    corners = ((w / 2 - rt, zt - rt, 0.0, rt), (-w / 2 + rt, zt - rt, 0.5 * math.pi, rt),
               (-w / 2 + rb, zb + rb, math.pi, rb), (w / 2 - rb, zb + rb, 1.5 * math.pi, rb))
    for n_c, (cx, cz, a0, rr) in enumerate(corners):
        kk = k + 2 if n_c < 2 else k
        for i in range(kk + 1):
            a = a0 + 0.5 * math.pi * i / kk
            pts.append(Vector((cx + math.cos(a) * rr, y, cz + math.sin(a) * rr)))
    return pts

def rrect_xy(z, wx, wy, r, k=3, dx=0.0):
    r = min(r, wx / 2 - 0.001, wy / 2 - 0.001)
    pts = []
    for cx, cy, a0 in ((wx / 2 - r, wy / 2 - r, 0.0), (-wx / 2 + r, wy / 2 - r, 0.5 * math.pi),
                       (-wx / 2 + r, -wy / 2 + r, math.pi), (wx / 2 - r, -wy / 2 + r, 1.5 * math.pi)):
        for i in range(k + 1):
            a = a0 + 0.5 * math.pi * i / k
            pts.append(Vector((dx + cx + math.cos(a) * r, cy + math.sin(a) * r, z)))
    return pts

def capsule(name, r0, r1, length, m, parent, loc=(0, 0, 0), rot=(0, 0, 0), n=10):
    prof = []
    for a in (80, 55, 25):
        t = math.radians(a)
        prof.append((r0 * 0.6 * math.sin(t), r0 * math.cos(t)))
    prof.append((-length * 0.5, (r0 + r1) / 2))
    for a in (0, 30, 55, 75, 88):
        t = math.radians(a)
        prof.append((-length + r1 * (1 - math.sin(t)), r1 * math.cos(t)))
    return rings(name, list(reversed(prof)), m, parent, loc, rot, n=n)

def torus(name, R, r, m, parent, loc, rot=(0, 0, 0), n=12, k=6):
    bm = bmesh.new()
    loops = []
    for i in range(n):
        a = 2 * math.pi * i / n
        c = Vector((math.cos(a) * R, math.sin(a) * R, 0))
        out = Vector((math.cos(a), math.sin(a), 0))
        loops.append([bm.verts.new(c + out * math.cos(2 * math.pi * j / k) * r + Vector((0, 0, math.sin(2 * math.pi * j / k) * r))) for j in range(k)])
    for i in range(n):
        a, b = loops[i], loops[(i + 1) % n]
        for j in range(k):
            jj = (j + 1) % k
            bm.faces.new((a[j], b[j], b[jj], a[jj]))
    return finish(name, bm, m, parent, loc, rot, 0.0)

# --- The body --------------------------------------------------------------------

def belly_profile(girth, top=0.7):
    base = ((-0.02, 0.33), (0.1, 0.365), (0.24, 0.375), (0.38, 0.358), (0.5, 0.338), (0.58, 0.315),
            (0.64, 0.265), (0.68, 0.19), (0.7, 0.1))
    return [(z * top / 0.7, r * girth, r * girth * 0.97) for z, r in base]

class Body:
    def __init__(self, prof):
        self.prof = prof
    def r(self, z):
        if z > self.prof[-1][0]:
            return (0.0, 0.0)
        for (z0, x0, y0), (z1, x1, y1) in zip(self.prof, self.prof[1:]):
            if z0 <= z <= z1:
                k = (z - z0) / (z1 - z0)
                return (x0 + (x1 - x0) * k, y0 + (y1 - y0) * k)
        return (self.prof[0][1], self.prof[0][2])
    def front(self, x, z):
        rx, ry = self.r(z)
        if rx <= 0.0 or abs(x) >= rx:
            return 0.0
        return ry * math.sqrt(1.0 - (x / rx) ** 2)

def plaid(torso, body, m, dark, bn):
    for i, z in enumerate([0.14, 0.3, 0.45]):
        rx, ry = body.r(z)
        rings('PlaidBand%d' % i, [(z - 0.025, rx + 0.007, ry + 0.007), (z + 0.025, rx + 0.007, ry + 0.007)], dark, torso, n=bn)
    for i in range(0, bn, 2):
        a = 2 * math.pi * (i + 0.5) / bn
        bm = bmesh.new()
        rows = []
        for z in (0.0, 0.1, 0.24, 0.38, 0.5, 0.6):
            rx, ry = body.r(z)
            c = Vector((math.cos(a) * (rx + 0.008), math.sin(a) * (ry + 0.008), z))
            side = Vector((-math.sin(a) * rx, math.cos(a) * ry, 0)).normalized() * 0.024
            rows.append((bm.verts.new(c - side), bm.verts.new(c + side)))
        for (a0, a1), (b0, b1) in zip(rows, rows[1:]):
            bm.faces.new((a0, a1, b1, b0))
        finish('PlaidStripe%d' % i, bm, dark, torso, (0, 0, 0), (0, 0, 0), 0.0)

def straps(torso, body, m, clip):
    for s in (-1, 1):
        x = s * 0.15
        for face, nm in ((1, 'F'), (-1, 'B')):
            bm = bmesh.new()
            cols = []
            for z in (0.07, 0.24, 0.38, 0.5, 0.6, 0.66, 0.69):
                zz = z * body.prof[-1][0] / 0.7
                y = face * (body.front(x, zz) + 0.014)
                c = Vector((x, y, zz))
                side = Vector((0.032, 0, 0))
                out = Vector((0, face * 0.018, 0))
                cols.append([bm.verts.new(c - side), bm.verts.new(c + side), bm.verts.new(c + side + out), bm.verts.new(c - side + out)])
            for a, b in zip(cols, cols[1:]):
                for i in range(4):
                    j = (i + 1) % 4
                    bm.faces.new((a[i], a[j], b[j], b[i]))
            bm.faces.new(list(reversed(cols[0])))
            bm.faces.new(cols[-1])
            finish('Strap_%s%d' % (nm, s), bm, m, torso, (0, 0, 0), (0, 0, 0), 0.0)
            if clip:
                box('StrapClip_%s%d' % (nm, s), (0.08, 0.025, 0.065), (x, face * (body.front(x, 0.1) + 0.03), 0.1), clip, torso)

def boot(side, foot, m, slipper=False):
    if slipper:
        shape = ((-0.12, 0.2, 0.0), (-0.08, 0.22, 0.03), (0.0, 0.23, 0.035), (0.08, 0.23, 0.03),
                 (0.15, 0.22, 0.015), (0.2, 0.2, -0.01), (0.23, 0.16, -0.04), (0.245, 0.1, -0.065))
        loft('Slipper_%s' % side, [rrect_xz(y, w, -0.12, top, 0.03, r_top=w * 0.5) for y, w, top in shape], m, foot)
        rings('SlipperPom_%s' % side, [(-0.03, 0.001), (-0.02, 0.035), (0.02, 0.035), (0.03, 0.001)], 'Hair', foot, (0, 0.14, 0.03), n=8)
        return
    shape = ((-0.14, 0.2, 0.05), (-0.12, 0.25, 0.07), (-0.02, 0.26, 0.075), (0.03, 0.26, 0.064),
             (0.07, 0.258, 0.054), (0.11, 0.256, 0.045), (0.15, 0.252, 0.033), (0.185, 0.246, 0.018),
             (0.215, 0.236, -0.002), (0.24, 0.218, -0.028), (0.258, 0.19, -0.054), (0.27, 0.15, -0.076),
             (0.277, 0.1, -0.091))
    loft('Boot_%s' % side, [rrect_xz(y, w, -0.1, top, 0.03, r_top=w * 0.5) for y, w, top in shape], m, foot)
    sole = [(y, w + 0.022) for y, w, top in shape]
    sole = [(-0.15, 0.2)] + sole[1:-2] + [(0.272, 0.16), (0.283, 0.09)]
    loft('Sole_%s' % side, [rrect_xz(y, w, -0.1425, -0.098, 0.012) for y, w in sole], 'Sole', foot)
    box('Heel_%s' % side, (0.25, 0.1, 0.03), (0, -0.09, -0.155), 'Sole', foot, bevel=0.006)
    rings('BootCollar_%s' % side, [(0.055, 0.132), (0.09, 0.136)], m, foot, (0, -0.06, 0), n=12, sy=0.85, bevel=0.008)

def hand_parts(side, s, hand, m, slim=1.0):
    glove = [(0.03, 0.125, 0.13, 0.05), (-0.02, 0.115, 0.135, 0.048), (-0.055, 0.095, 0.15, 0.04),
             (-0.095, 0.074, 0.18, 0.034), (-0.13, 0.07, 0.19, 0.032), (-0.152, 0.062, 0.185, 0.028),
             (-0.162, 0.048, 0.16, 0.022)]
    loft('Glove_%s' % side, [rrect_xy(z, wx * slim, wy * slim, r * slim) for z, wx, wy, r in glove], m, hand)
    for i, (y, ln) in enumerate(((-0.066, 0.105), (-0.022, 0.125), (0.022, 0.12), (0.066, 0.1))):
        fan = (i - 1.5) * 0.05
        f = empty('Finger_%s%d' % (side, i), hand, (0, y * slim, -0.146), (fan, s * 0.16, 0))
        capsule('FingerBase_%s%d' % (side, i), 0.03 * slim, 0.028 * slim, ln * 0.56, m, f)
        tip = empty('FingerTip_%s%d' % (side, i), f, (0, 0, -ln * 0.5), (0, s * 0.22, 0))
        capsule('FingerEnd_%s%d' % (side, i), 0.028 * slim, 0.025 * slim, ln * 0.54, m, tip)
    th = empty('Thumb_%s' % side, hand, (-s * 0.015, 0.082 * slim, -0.07), (0.6, 0, -s * 0.32))
    capsule('ThumbBase_%s' % side, 0.034 * slim, 0.031 * slim, 0.06, m, th)
    tt = empty('ThumbTip_%s' % side, th, (0, 0, -0.054), (0.32, 0, 0))
    capsule('ThumbEnd_%s' % side, 0.031 * slim, 0.026 * slim, 0.052, m, tt)

def person(name, spec, offset=(0, 0, 0)):
    bn = STYLE['belly']
    g = spec.get('girth', 1.0)
    body = Body(belly_profile(g, spec.get('torso', 0.7)))
    top = body.prof[-1][0]
    leg_len = spec.get('legs', 1.0)
    hip = 0.62 * leg_len
    root = empty(name, None, offset)
    shirt, dark = spec['shirt'], spec.get('shirt_dark', spec['shirt'])
    # Torso
    torso = empty('Torso', root, (0, 0, hip))
    rings('Belly', body.prof, shirt, torso, n=bn)
    if spec.get('plaid'):
        plaid(torso, body, shirt, dark, bn)
    if spec.get('bib'):
        # Overalls: the bib up the front and the straps over the shoulders.
        bm_rows = []
        for z in (0.0, 0.12, 0.24, 0.36, 0.44):
            pts = []
            for k in range(9):
                x = -0.17 + 0.34 * k / 8
                pts.append(Vector((x, body.front(x, z) + 0.012, z)))
            bm_rows.append(pts)
        bm = bmesh.new()
        vv = [[bm.verts.new(p) for p in row] + [bm.verts.new(p + Vector((0, 0.022, 0))) for p in row] for row in bm_rows]
        for ra, rb in zip(vv, vv[1:]):
            for i in range(8):
                bm.faces.new((ra[9 + i], ra[9 + i + 1], rb[9 + i + 1], rb[9 + i]))
        finish('Bib', bm, spec['bib'], torso, (0, 0, 0), (0, 0, 0), 0.0)
        box('BibPocket', (0.14, 0.02, 0.1), (0, body.front(0, 0.3) + 0.04, 0.3), spec.get('bib_dark', spec['bib']), torso)
        straps(torso, body, spec['bib'], 'Brass')
        rings('Waist', [(-0.04, body.r(0)[0] + 0.01), (0.1, body.r(0.1)[0] + 0.012)], spec['bib'], torso, n=bn)
    elif spec.get('vest'):
        # A hi-vis vest: over the shirt, open down the front, two bright bands.
        vr = [(z, body.r(z)[0] + 0.012, body.r(z)[1] + 0.012) for z in (0.02, 0.2, 0.4, 0.56, 0.62)]
        rings('Vest', vr, spec['vest'], torso, n=bn)
        for i, z in enumerate((0.16, 0.34)):
            rx, ry = body.r(z)
            rings('VestBand%d' % i, [(z - 0.022, rx + 0.02, ry + 0.02), (z + 0.022, rx + 0.02, ry + 0.02)], 'Reflect', torso, n=bn)
        rings('Waist', [(-0.04, body.r(0)[0] + 0.004), (0.05, body.r(0.05)[0] + 0.006)], spec['legs_m'], torso, n=bn)
    else:
        rings('Waist', [(-0.04, body.r(0)[0] + 0.004), (0.05, body.r(0.05)[0] + 0.006)], spec['legs_m'], torso, n=bn)
        if spec.get('belt'):
            rings('Belt', [(0.03, body.r(0.03)[0] + 0.012), (0.09, body.r(0.09)[0] + 0.014)], spec['belt'], torso, n=bn)
            box('Buckle', (0.13, 0.03, 0.09), (0, body.front(0, 0.06) + 0.025, 0.06), 'Brass', torso)
    if spec.get('suspenders'):
        straps(torso, body, spec['suspenders'], 'Brass')
    if spec.get('apron'):
        # A pinafore apron over the dress, tied at the waist.
        rows = []
        for z in (-0.02, 0.1, 0.22, 0.34, 0.44):
            rows.append([Vector((x, body.front(x, z) + 0.01, z)) for x in [-0.2 + 0.4 * k / 8 for k in range(9)]])
        bm = bmesh.new()
        vv = [[bm.verts.new(p) for p in row] + [bm.verts.new(p + Vector((0, 0.015, 0))) for p in row] for row in rows]
        for ra, rb in zip(vv, vv[1:]):
            for i in range(8):
                bm.faces.new((ra[9 + i], ra[9 + i + 1], rb[9 + i + 1], rb[9 + i]))
        finish('Apron', bm, spec['apron'], torso, (0, 0, 0), (0, 0, 0), 0.0)
    if spec.get('shawl'):
        # Knitted shawl round the shoulders, a point hanging down the back,
        # tied in a knot at the front.
        # A cape: snug at the neck, falling loose over the shoulders to the
        # upper arms, with a dark edge and a knot at the throat.
        z0 = top * 0.66
        rx0, ry0 = body.r(z0)
        sr = [(z0 - 0.02, rx0 + 0.1, ry0 + 0.06), (z0 + 0.04, rx0 + 0.09, ry0 + 0.055),
              (top * 0.9, body.r(top * 0.9)[0] + 0.09, body.r(top * 0.9)[1] + 0.05), (top + 0.02, 0.15, 0.13)]
        rings('Shawl', sr, spec['shawl'], torso, n=bn)
        rings('ShawlEdge', [(z0 - 0.04, rx0 + 0.105, ry0 + 0.065), (z0 - 0.005, rx0 + 0.105, ry0 + 0.065)], spec.get('shawl_dark', spec['shawl']), torso, n=bn)
        box('ShawlKnot', (0.09, 0.06, 0.07), (0, body.front(0, top * 0.86) + 0.07, top * 0.86), spec.get('shawl_dark', spec['shawl']), torso, soft=0.02)
        for i, x in enumerate((-0.03, 0.03)):
            box('ShawlTail%d' % i, (0.05, 0.03, 0.14), (x, body.front(0, top * 0.8) + 0.07, top * 0.76), spec['shawl'], torso, rot=(0, 0, 0.25 * (1 if i else -1)), soft=0.01)
    if spec.get('buttons'):
        for i, z in enumerate([0.1, 0.22, 0.34]):
            rings('Button%d' % i, [(-0.007, 0.02), (0.007, 0.02)], spec['buttons'], torso, (0, body.front(0, z) + 0.008, z), (math.pi / 2, 0, 0), n=8)
    if spec.get('skirt'):
        # The skirt, from the waist, flaring over the hips and lap.
        rx, ry = body.r(0.0)
        rings('Skirt', [(-0.2, rx * 1.2, ry * 1.2), (-0.08, rx * 1.12, ry * 1.12), (0.04, rx + 0.01, ry + 0.01)], spec['skirt'], torso, n=bn)
        rings('SkirtBand', [(-0.21, rx * 1.21, ry * 1.21), (-0.17, rx * 1.2, ry * 1.2)], spec.get('skirt_dark', spec['skirt']), torso, n=bn)
    # Legs
    skirt = spec.get('skirt')
    for s, side in ((-1, 'L'), (1, 'R')):
        leg = empty('Leg_%s' % side, root, (s * 0.17 * g, 0, hip))
        lm = skirt or spec['legs_m']
        wide = 1.25 if skirt else 1.0
        thigh = 0.28 * leg_len
        rings('Thigh_%s' % side, [(-thigh - 0.02, 0.125 * wide), (-0.1, 0.135 * wide), (0.03, 0.14 * wide)], lm, leg)
        knee = empty('Knee_%s' % side, leg, (0, 0, -thigh))
        rings('KneeJoint_%s' % side, [(-0.06, 0.124 * wide), (0.0, 0.13 * wide), (0.06, 0.124 * wide)], lm, knee)
        shin = 0.2 * leg_len
        if skirt:
            rings('Hem_%s' % side, [(-shin * 0.75, 0.15), (0.03, 0.14)], skirt, knee)
            rings('HemBand_%s' % side, [(-shin * 0.75 - 0.01, 0.155), (-shin * 0.75 + 0.03, 0.155)], spec.get('skirt_dark', skirt), knee)
            rings('Stocking_%s' % side, [(-shin - 0.02, 0.07), (-shin * 0.7, 0.075)], 'Hair', knee)
        else:
            rings('Shin_%s' % side, [(-shin, 0.12), (0.03, 0.125)], lm, knee)
            rings('Cuff_%s' % side, [(-shin * 0.5, 0.148), (-shin * 0.2, 0.148)], lm, knee, bevel=0.008)
        foot = empty('Foot_%s' % side, knee, (0, 0, -shin))
        boot(side, foot, spec['boots'], slipper=spec.get('slippers', False))
    # Arms
    sleeve, sleeve_dark = spec.get('sleeve', shirt), spec.get('sleeve_dark', dark)
    arm_len = spec.get('arms', 1.0)
    for s, side in ((-1, 'L'), (1, 'R')):
        arm = empty('Arm_%s' % side, root, (s * 0.36 * g, 0, hip + top * 0.8), (0, -s * 0.24, 0))
        rings('UpperArm_%s' % side, [(-0.25 * arm_len, 0.108), (-0.04, 0.122), (0.02, 0.12), (0.06, 0.095), (0.085, 0.045)], sleeve, arm)
        if spec.get('plaid'):
            rings('SleeveBand_%s' % side, [(-0.17, 0.126), (-0.12, 0.127)], sleeve_dark, arm)
        elbow = empty('Elbow_%s' % side, arm, (0, 0, -0.24 * arm_len))
        rolled = spec.get('rolled')
        rings('ElbowJoint_%s' % side, [(-0.05, 0.106), (0.0, 0.112), (0.05, 0.108)], sleeve, elbow)
        if rolled:
            rings('RollCuff_%s' % side, [(-0.05, 0.118), (0.0, 0.12)], sleeve, elbow, bevel=0.006)
            rings('Forearm_%s' % side, [(-0.18 * arm_len, 0.09), (0.02, 0.1)], spec.get('skin', 'Skin'), elbow)
        else:
            rings('Forearm_%s' % side, [(-0.18 * arm_len, 0.095), (0.02, 0.108)], sleeve, elbow)
            rings('SleeveCuff_%s' % side, [(-0.17 * arm_len, 0.114), (-0.1 * arm_len, 0.116)], sleeve_dark, elbow, bevel=0.005)
        hand = empty('Hand_%s' % side, elbow, (0, 0, -0.18 * arm_len))
        hand_parts(side, s, hand, spec['hands'], spec.get('hand_slim', 1.0))
    # Head
    head = empty('Head', root, (0, 0, hip + top * 0.886))
    head.scale = (spec.get('head', 1.0),) * 3
    skin = spec.get('skin', 'Skin')
    box('Face', (0.34, 0.32, 0.4), (0, 0.02, 0.2), skin, head, soft=0.04)
    box('Nose', spec.get('nose', (0.14, 0.13, 0.13)), (0, 0.22, 0.19), spec.get('nose_m', 'Nose'), head, soft=0.04)
    for s in (-1, 1):
        box('Eye_%d' % s, (0.042, 0.02, 0.056), (s * 0.075, 0.18, 0.255), 'Eye', head, bevel=0.008)
        box('Brow_%d' % s, (0.12, 0.05, 0.045), (s * 0.08, 0.19, 0.315), spec.get('brow', 'GreyDark'), head,
            rot=(0, s * 0.22 if spec.get('kind') else -s * 0.25, 0), soft=0.008)
        box('Ear_%d' % s, (0.06, 0.08, 0.1), (s * 0.18, 0.0, 0.2), skin, head, soft=0.015)
    beard = spec.get('beard')
    if beard == 'full':
        bm_, bd = spec['beard_m'], spec['beard_dark']
        for s in (-1, 1):
            box('Sideburn_%d' % s, (0.075, 0.17, 0.26), (s * 0.172, 0.07, 0.1), bm_, head, rot=(0.15, 0, 0), soft=0.015)
            box('Moustache_%d' % s, (0.17, 0.08, 0.07), (s * 0.095, 0.27, 0.11), bd, head, rot=(0, s * 0.4, 0), soft=0.02)
        full_beard(head, body, bm_, spec.get('beard_len', 1.0), hip)
    elif beard == 'moustache':
        for s in (-1, 1):
            box('Moustache_%d' % s, (0.19, 0.08, 0.075), (s * 0.1, 0.265, 0.1), spec['beard_m'], head, rot=(0, s * 0.5, 0), soft=0.02)
            box('Stubble_%d' % s, (0.08, 0.16, 0.2), (s * 0.13, 0.12, 0.07), spec['beard_dark'], head, soft=0.02)
        box('Chin', (0.26, 0.12, 0.1), (0, 0.13, -0.01), spec['beard_dark'], head, soft=0.03)
    if spec.get('smile'):
        bm = bmesh.new()
        pts = []
        for k in range(9):
            f = k / 8.0
            x = -0.07 + 0.14 * f
            z = 0.1 + 0.03 * (2 * f - 1) ** 2
            pts.append((x, 0.19 - 0.02 * abs(2 * f - 1), z))
        rows = [[bm.verts.new((x, y, z - 0.008)), bm.verts.new((x, y + 0.012, z - 0.008)),
                 bm.verts.new((x, y + 0.012, z + 0.008)), bm.verts.new((x, y, z + 0.008))] for x, y, z in pts]
        for ra, rb in zip(rows, rows[1:]):
            for i in range(4):
                j = (i + 1) % 4
                bm.faces.new((ra[i], ra[j], rb[j], rb[i]))
        bm.faces.new(list(reversed(rows[0])))
        bm.faces.new(rows[-1])
        finish('Smile', bm, 'Eye', head, (0, 0, 0), (0, 0, 0), 0.0)
    if spec.get('cheeks'):
        for s in (-1, 1):
            box('Cheek_%d' % s, (0.07, 0.03, 0.05), (s * 0.12, 0.185, 0.16), 'Cheek', head, soft=0.012)
    if spec.get('soot'):
        box('Soot_0', (0.1, 0.02, 0.06), (0.1, 0.185, 0.36), 'Soot', head, soft=0.01)
        box('Soot_1', (0.08, 0.02, 0.05), (-0.13, 0.18, 0.13), 'Soot', head, soft=0.01)
    hair = spec.get('hair')
    if hair:
        for s in (-1, 1):
            box('HairSide_%d' % s, (0.05, 0.22, 0.2), (s * 0.172, -0.05, 0.25), hair, head, soft=0.012)
        box('HairBack', (0.35, 0.12, 0.26), (0, -0.13, 0.24), hair, head, soft=0.02)
    if spec.get('bun'):
        # Hair swept up over the top of her head, parted, and a bun at the back.
        rings('HairTop', [(0.0, 0.2), (0.06, 0.2), (0.12, 0.175), (0.17, 0.12), (0.2, 0.04)], hair, head, (0, -0.01, 0.3), n=16, sx=0.98, sy=0.96)
        box('Part', (0.012, 0.2, 0.02), (0, 0.06, 0.5), spec.get('hair_dark', hair), head, rot=(0.35, 0, 0), bevel=0.004)
        rings('Bun', [(-0.05, 0.02), (-0.035, 0.075), (0.02, 0.085), (0.06, 0.055), (0.075, 0.01)], hair, head, (0, -0.17, 0.43), (-1.1, 0, 0), n=12)
        for i, x in enumerate((-0.04, 0.04)):
            rings('Pin%d' % i, [(-0.05, 0.007), (0.05, 0.007)], 'Glasses', head, (x, -0.22, 0.46), (0.3, 1.2 * (1 if i else -1), 0.0), n=5)
    if spec.get('glasses'):
        for s in (-1, 1):
            torus('Lens_%d' % s, 0.048, 0.008, 'Glasses', head, (s * 0.075, 0.2, 0.25), (math.pi / 2, 0, 0))
            box('Arm_G%d' % s, (0.012, 0.2, 0.012), (s * 0.13, 0.1, 0.26), 'Glasses', head, bevel=0.003)
        box('Bridge', (0.05, 0.012, 0.012), (0, 0.205, 0.26), 'Glasses', head, bevel=0.003)
    hat = spec.get('hat')
    if hat == 'trapper':
        rings('TrapperCrown', [(0.0, 0.215), (0.06, 0.212), (0.12, 0.185), (0.17, 0.13), (0.2, 0.05)], spec['hat_m'], head, (0, 0.01, 0.38), n=bn, sx=1.02, sy=0.98)
        rings('TrapperBrim', [(-0.03, 0.228), (0.04, 0.23)], 'Fur', head, (0, 0.02, 0.37), n=bn, sx=1.03, sy=0.98, bevel=0.012)
        for s in (-1, 1):
            box('Flap_%d' % s, (0.07, 0.17, 0.2), (s * 0.2, 0.0, 0.28), 'Fur', head, rot=(0, s * 0.12, 0), soft=0.025)
        box('FlapBack', (0.36, 0.08, 0.14), (0, -0.16, 0.3), 'Fur', head, soft=0.025)
    elif hat == 'helmet':
        rings('HelmetDome', [(0.0, 0.23), (0.07, 0.225), (0.13, 0.195), (0.18, 0.14), (0.21, 0.06)], 'Helmet', head, (0, 0.01, 0.38), n=bn, sx=1.02, sy=1.02)
        rings('HelmetBrim', [(-0.015, 0.27), (0.015, 0.27)], 'Helmet', head, (0, 0.03, 0.37), n=bn, sx=1.0, sy=1.1, bevel=0.008)
        box('HelmetRidge', (0.06, 0.4, 0.05), (0, 0.0, 0.58), 'Helmet', head, soft=0.012)
        rings('LampBody', [(-0.04, 0.055), (0.04, 0.055)], 'Brass', head, (0, 0.23, 0.46), (math.pi / 2, 0, 0), n=12)
        rings('LampGlass', [(-0.01, 0.045), (0.01, 0.045)], 'Lamp', head, (0, 0.275, 0.46), (math.pi / 2, 0, 0), n=12)
    elif hat == 'cap':
        rings('CapCrown', [(0.0, 0.21), (0.06, 0.205), (0.11, 0.17), (0.14, 0.09)], 'Cap', head, (0, 0.02, 0.38), n=bn, sx=1.02, sy=0.98)
        box('CapPeak', (0.3, 0.2, 0.025), (0, 0.24, 0.38), 'Cap', head, rot=(0.12, 0, 0), bevel=0.01)
        rings('CapButton', [(0.0, 0.03), (0.02, 0.02)], 'Cap', head, (0, 0.02, 0.52), n=8)
    return root

def full_beard(head, body, m, length=1.0, hip=0.62):
    rows = [(0.13, 0.42, 0.11), (0.05, 0.45, 0.15), (-0.05, 0.46, 0.17), (-0.15, 0.45, 0.17),
            (-0.25, 0.4, 0.15), (-0.34, 0.31, 0.13), (-0.42, 0.19, 0.1), (-0.48, 0.06, 0.06)]
    rows = [(z * length if z < 0 else z, w, t) for z, w, t in rows]
    head_z = head.location.z - hip
    def under(x, z):
        face = 0.12 if z > 0.0 else 0.12 + 0.35 * (-z)
        return max(min(face, 0.2), body.front(x, z + head_z) + 0.01)
    fine = []
    for (za, wa, ta), (zb, wb, tb) in zip(rows, rows[1:]):
        for k in range(5):
            f = k / 5.0
            fine.append((za + (zb - za) * f, wa + (wb - wa) * f, ta + (tb - ta) * f))
    fine.append(rows[-1])
    def ridge(x, z):
        p = x / 0.052 + 0.35 * math.sin(z * 9.0 + x * 5.0)
        return abs(math.cos(math.pi * p)) ** 0.6
    n = 72
    bm = bmesh.new()
    loops = []
    for z, w, th in fine:
        ring = []
        for i in range(n):
            t = 2 * math.pi * i / n
            x = math.cos(t) * w / 2
            front = 0.5 + 0.5 * math.sin(t)
            y = under(x, z) + th * front + 0.032 * (ridge(x, z) - 0.5) * front ** 1.5
            ring.append(bm.verts.new((x, y, z - 0.02 * math.sin(t * 3.0) * (1.0 if z < 0 else 0.0))))
        loops.append(ring)
    for ra, rb in zip(loops, loops[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((ra[i], ra[j], rb[j], rb[i]))
    bm.faces.new(list(reversed(loops[0])))
    bm.faces.new(loops[-1])
    finish('Beard', bm, m, head, (0, 0, 0), (0, 0, 0), 0.0)

# --- Props -----------------------------------------------------------------------

def pickaxe(name, parent=None, loc=(0, 0, 0), rot=(0, 0, 0)):
    """A pickaxe: its origin is where the hand grips, near the end of the
    handle; the handle runs up +Z to the head, which points out along ±X
    (the game's tools are built the same way: handle up, head along +X)."""
    root = empty(name, parent, loc, rot)
    rings(name + '_Handle', [(-0.12, 0.022), (0.3, 0.02), (0.72, 0.026), (0.8, 0.028)], 'Wood', root, n=8)
    rings(name + '_Grip', [(-0.1, 0.027), (0.12, 0.027)], 'Leather', root, n=8)
    box(name + '_Eye', (0.075, 0.09, 0.1), (0, 0, 0.76), 'Iron', root, bevel=0.01)
    for s in (-1, 1):
        # Each prong: tapering, curving down.
        pts = []
        for k in range(6):
            f = k / 5.0
            pts.append((f, 0.035 * (1 - f) + 0.008, 0.04 * (1 - f) + 0.008))
        bm = bmesh.new()
        loops = []
        for f, hw, hh in pts:
            x = s * (0.04 + 0.3 * f)
            z = 0.76 - 0.1 * f * f
            loops.append([bm.verts.new((x, y, z + dz)) for y, dz in ((-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh))])
        for a, b in zip(loops, loops[1:]):
            for i in range(4):
                j = (i + 1) % 4
                bm.faces.new((a[i], a[j], b[j], b[i]))
        bm.faces.new(list(reversed(loops[0])))
        bm.faces.new(loops[-1])
        finish(name + '_Prong%d' % s, bm, 'Iron', root, (0, 0, 0), (0, 0, 0), 0.0)
    return root

def felling_axe(name, parent=None, loc=(0, 0, 0), rot=(0, 0, 0)):
    """A big felling axe: origin at the grip, the handle up +Z, the blade
    out along +X."""
    root = empty(name, parent, loc, rot)
    rings(name + '_Handle', [(-0.12, 0.024), (0.35, 0.021), (0.78, 0.026), (0.86, 0.028)], 'Wood', root, n=8)
    rings(name + '_Knob', [(-0.15, 0.03), (-0.11, 0.032)], 'WoodDark', root, n=8)
    # The head: a red-painted wedge with a bright steel edge.
    bm = bmesh.new()
    prof = [(-0.05, 0.045), (0.02, 0.05), (0.12, 0.04), (0.2, 0.09)]
    verts = []
    for y, h in prof:
        verts.append([bm.verts.new((y, x, 0.8 + z)) for x, z in ((-0.035 * (1 - y), -h), (0.035 * (1 - y), -h), (0.035 * (1 - y), h), (-0.035 * (1 - y), h))])
    for a, b in zip(verts, verts[1:]):
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(list(reversed(verts[0])))
    bm.faces.new(verts[-1])
    finish(name + '_Head', bm, 'AxeRed', root, (0, 0, 0), (0, 0, 0), 0.0)
    box(name + '_Edge', (0.03, 0.03, 0.19), (0.205, 0, 0.8), 'Steel', root, bevel=0.006)
    box(name + '_Poll', (0.07, 0.075, 0.1), (-0.07, 0, 0.8), 'Iron', root, bevel=0.01)
    return root

def rocking_chair(name, parent=None, loc=(0, 0, 0)):
    """Origin on the floor under the middle of the rockers; the seat faces +Y."""
    root = empty(name, parent, loc)
    for s in (-1, 1):
        # The rocker: an arc of wood.
        bm = bmesh.new()
        loops = []
        for k in range(13):
            a = math.radians(-38 + 76 * k / 12)
            y = math.sin(a) * 1.2
            z = 1.2 - math.cos(a) * 1.2
            loops.append([bm.verts.new((s * 0.26 + dx, y, z + dz)) for dx, dz in ((-0.025, 0), (0.025, 0), (0.025, 0.05), (-0.025, 0.05))])
        for a_, b_ in zip(loops, loops[1:]):
            for i in range(4):
                j = (i + 1) % 4
                bm.faces.new((a_[i], a_[j], b_[j], b_[i]))
        bm.faces.new(list(reversed(loops[0])))
        bm.faces.new(loops[-1])
        finish(name + '_Rocker%d' % s, bm, 'WoodDark', root, (0, 0, 0), (0, 0, 0), 0.0)
        # Legs up from the rockers to the seat, the back posts on up.
        box(name + '_LegF%d' % s, (0.05, 0.05, 0.42), (s * 0.26, 0.2, 0.26), 'Wood', root, bevel=0.01)
        box(name + '_Post%d' % s, (0.055, 0.055, 1.12), (s * 0.26, -0.2, 0.62), 'Wood', root, rot=(-0.14, 0, 0), bevel=0.012)
        rings(name + '_Finial%d' % s, [(0.0, 0.035), (0.04, 0.045), (0.08, 0.02)], 'WoodDark', root, (s * 0.26, -0.28, 1.17), n=8)
        # Arm rests.
        box(name + '_ArmRest%d' % s, (0.08, 0.5, 0.04), (s * 0.28, 0.02, 0.68), 'Wood', root, bevel=0.012)
        box(name + '_ArmPost%d' % s, (0.04, 0.04, 0.22), (s * 0.28, 0.22, 0.57), 'Wood', root, bevel=0.008)
    box(name + '_Seat', (0.58, 0.48, 0.05), (0, 0.0, 0.46), 'Wood', root, bevel=0.012)
    box(name + '_Cushion', (0.5, 0.42, 0.07), (0, 0.01, 0.51), 'Cushion', root, soft=0.02)
    for k in range(5):
        x = -0.18 + 0.09 * k
        box(name + '_Slat%d' % k, (0.045, 0.03, 0.62), (x, -0.25, 0.86), 'Wood', root, rot=(-0.14, 0, 0), bevel=0.008)
    box(name + '_TopRail', (0.58, 0.05, 0.1), (0, -0.3, 1.17), 'WoodDark', root, rot=(-0.14, 0, 0), bevel=0.015)
    box(name + '_MidRail', (0.55, 0.04, 0.05), (0, -0.21, 0.56), 'WoodDark', root, rot=(-0.14, 0, 0), bevel=0.01)
    # A ball of wool and her knitting on the arm.
    rings(name + '_Yarn', [(-0.07, 0.02), (-0.05, 0.065), (0.0, 0.075), (0.05, 0.065), (0.07, 0.02)], 'Yarn', root, (0.29, 0.1, 0.77), n=10)
    return root

# --- The cast --------------------------------------------------------------------

CAST = {
    'lumberman': {'girth': 1.12, 'torso': 0.74, 'legs': 1.05, 'arms': 1.08, 'shirt': 'GreenPlaid', 'shirt_dark': 'GreenDark',
                  'plaid': True, 'legs_m': 'Canvas', 'boots': 'BootBrown', 'hands': 'Tan', 'suspenders': 'Leather',
                  'belt': None, 'beard': 'full', 'beard_m': 'GreyBeard', 'beard_dark': 'GreyDark', 'beard_len': 0.85,
                  'brow': 'GreyDark', 'hat': 'trapper', 'hat_m': 'Leather', 'skin': 'Skin', 'scale': 1.08},
    'miner': {'girth': 1.0, 'shirt': 'Shirt', 'sleeve': 'Shirt', 'rolled': True, 'legs_m': 'Overall', 'bib': 'Overall',
              'bib_dark': 'OverallDark', 'boots': 'BootBlack', 'hands': 'Gauntlet', 'beard': 'moustache',
              'beard_m': 'Black', 'beard_dark': 'Soot', 'brow': 'Black', 'hat': 'helmet', 'soot': True,
              'hair': 'Black', 'scale': 1.0},
    'granny': {'girth': 0.92, 'torso': 0.64, 'legs': 0.86, 'arms': 0.92, 'shirt': 'Dress', 'shirt_dark': 'DressDark',
               'skirt': 'Dress', 'skirt_dark': 'DressDark', 'legs_m': 'Dress', 'boots': 'Slipper', 'slippers': True,
               'hands': 'SkinOld', 'hand_slim': 0.8, 'skin': 'SkinOld', 'hair': 'Hair', 'hair_dark': 'HairDark', 'bun': True, 'glasses': True,
               'shawl': 'Shawl', 'shawl_dark': 'ShawlDark', 'cheeks': True, 'brow': 'HairDark', 'kind': True, 'smile': True,
               'buttons': 'Apron',
               'nose': (0.11, 0.11, 0.11), 'nose_m': 'SkinOld', 'scale': 0.88},
    'helper': {'girth': 1.06, 'torso': 0.62, 'legs': 0.72, 'arms': 0.86, 'head': 1.18, 'shirt': 'Tee', 'sleeve': 'Tee',
               'vest': 'Vis', 'legs_m': 'Work', 'boots': 'BootBlack', 'hands': 'Yellow', 'hat': 'cap',
               'beard': 'moustache', 'beard_m': 'Ginger', 'beard_dark': 'Ginger', 'brow': 'Ginger', 'hair': 'Ginger',
               'cheeks': True, 'kind': True, 'scale': 0.72},
}

def _collection(name):
    global coll
    coll = bpy.data.collections.get(name)
    if coll is None:
        coll = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(coll)
    for o in list(coll.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    return coll

def build_one(who, offset=(0, 0, 0)):
    """One of the cast in its own collection `NPC_<who>`, props and all."""
    materials()
    _collection('NPC_' + who)
    spec = CAST[who]
    root = person('NPC_' + who.capitalize(), spec, offset)
    root.scale = (spec.get('scale', 1.0),) * 3
    if who == 'miner':
        pickaxe('Pickaxe', None, (offset[0] + 0.7, offset[1], offset[2]))
    elif who == 'lumberman':
        felling_axe('Axe', None, (offset[0] + 0.7, offset[1], offset[2]))
    elif who == 'granny':
        rocking_chair('RockingChair', None, (offset[0], offset[1] - 0.05, offset[2]))
    return root

def build_all():
    for i, who in enumerate(('lumberman', 'miner', 'granny', 'helper')):
        build_one(who, (i * 1.8 - 2.7, 0, 0))
