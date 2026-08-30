"""Convert 0 A.D.'s fauna/dragon COLLADA into a self-contained GLB for an
online auto-rigger, plus a texture-less OBJ fallback and a preview render.

`vis.dragon` is a statue: its source mesh has no armature, no skin, no joints
and no animation, so phase 13 is blocked until something rigs it. This is the
first half of that round trip.

Read-only with respect to the art checkout: it is handed copies.

**WRITE THE OUTPUT TO `art_source/dragon_rig/`, NOT INTO THE REPO.** Owner's
rule, 2026-08-30: 3D models live in the source folder beside `art_source/0ad`,
which is machine-local and uncommitted. They are pipeline INPUT, like the 0 A.D.
checkout -- the repo carries recipes and scripts, and the art that reaches the
game is the baked atlas. A first pass put them under `assets/` and it was wrong.

    blender.exe -b --python tools/dragon_to_glb.py -- \
        <dae> <dds> <out.glb> <out.obj> <preview.png>

Two things that were got wrong once each, both cheap to repeat:

**SCALE.** The COLLADA imports at 1/100 of 0 A.D.'s raw units, so the dragon
arrives 0.18 Blender units long. Auto-riggers size bones and pick thresholds
off the model's own extent, so a sub-unit model invites a bad rig. isobake
measured the real creature at 9.19 x 8.11 x 3.76 m. Getting there means
MULTIPLYING the existing object scale -- assigning it outright discards the
import's own 0.01 and lands at 919 m, which is exactly what happened first
time and what the preview render caught.

**DENSITY.** 339 verts / 454 tris is very little to compute skin weights from;
a wing is about ten vertices. Two levels of SIMPLE subdivision give 5832 verts
with a bit-identical silhouette, because simple subdivision adds vertices
without moving the surface. That is the fallback if a rig deforms badly -- not
the default, since more geometry is more for a rigger to get wrong.

**The return path is the open item.** isobake cannot bake glTF or FBX yet:
`adapters/generic.py` raises NotImplementedError. `isobake inspect` DOES read
both, so judge a rigged file before writing the adapter. See AGENT_ASSET.md.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
dae, dds, out_glb, out_obj, out_png = argv

SCALE = 50.0  # Blender import units -> metres

bpy.ops.wm.read_factory_settings(use_empty=True)

import addon_utils
addon_utils.enable("io_scene_gltf2", default_set=False, persistent=True)

bpy.ops.wm.collada_import(filepath=dae)

objs = list(bpy.context.scene.objects)
print("IMPORTED:", [(o.name, o.type) for o in objs])
meshes = [o for o in objs if o.type == "MESH"]
if not meshes:
    raise SystemExit("no mesh imported")

for m in meshes:
    m.data.calc_loop_triangles()
tris = sum(len(m.data.loop_triangles) for m in meshes)
verts = sum(len(m.data.vertices) for m in meshes)
print(f"STATS verts={verts} tris={tris} "
      f"uv={all(len(m.data.uv_layers) > 0 for m in meshes)}")

# Scale to metres and bake the transform in, so the file carries no pending
# object transform an importer might drop.
# MULTIPLY the existing scale, never assign it. The COLLADA import already
# carries an object scale of 0.01 against mesh data authored at 18.38 raw
# units; assigning 50 outright discards that and lands at 919 m.
for m in meshes:
    m.scale = tuple(s * SCALE for s in m.scale)
bpy.context.view_layer.update()
for m in meshes:
    m.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

for m in meshes:
    d = m.dimensions
    print(f"SCALED {m.name} dims_m=({d.x:.2f}, {d.y:.2f}, {d.z:.2f})")

img = bpy.data.images.load(dds)
print(f"TEXTURE {img.size[0]}x{img.size[1]}")

mat = bpy.data.materials.new("dragon")
mat.use_nodes = True
nt = mat.node_tree
bsdf = nt.nodes["Principled BSDF"]
tex = nt.nodes.new("ShaderNodeTexImage")
tex.image = img
nt.links.new(bsdf.inputs["Base Color"], tex.outputs["Color"])
if "Specular IOR Level" in bsdf.inputs:
    bsdf.inputs["Specular IOR Level"].default_value = 0.0
for m in meshes:
    m.data.materials.clear()
    m.data.materials.append(mat)

bpy.ops.export_scene.gltf(filepath=out_glb, export_format="GLB",
                          export_image_format="AUTO", export_apply=True)
print(f"WROTE {out_glb} {os.path.getsize(out_glb)}")

bpy.ops.wm.obj_export(filepath=out_obj, export_materials=False)
print(f"WROTE {out_obj} {os.path.getsize(out_obj)}")

# --- preview render, so the upload is not taken on trust -------------------
scn = bpy.context.scene
scn.render.engine = "BLENDER_WORKBENCH"
scn.render.resolution_x = 1100
scn.render.resolution_y = 500
scn.render.film_transparent = False
scn.display.shading.light = "STUDIO"
scn.display.shading.color_type = "TEXTURE"

lo = Vector((min(min((m.matrix_world @ Vector(c))[i] for c in m.bound_box)
                 for m in meshes) for i in range(3)))
hi = Vector((max(max((m.matrix_world @ Vector(c))[i] for c in m.bound_box)
                 for m in meshes) for i in range(3)))
centre = (lo + hi) / 2.0
radius = (hi - lo).length / 2.0

cam_data = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cam_data)
scn.collection.objects.link(cam)
scn.camera = cam

for tag, ang in (("side", 0.0), ("front", 90.0), ("three_quarter", 40.0)):
    a = math.radians(ang)
    d = radius * 3.2
    cam.location = centre + Vector((math.cos(a) * d, -math.sin(a) * d, d * 0.35))
    direction = centre - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scn.render.filepath = out_png.replace(".png", f"_{tag}.png")
    bpy.ops.render.render(write_still=True)
    print(f"WROTE {scn.render.filepath}")
