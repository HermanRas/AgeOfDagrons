"""Ground footprint in METRES for a 0 A.D. actor, standing or in a death pose.

    blender.exe -b --factory-startup -P tools/measure_footprint.py

Delivered for asset_request.md [P5], 2026-09-01. Kept because `footprint_m` is
the one figure the game side cannot derive from an atlas -- animals are authored
non-square, so one frame cannot give both ground axes, and the projection
inversion returns a NEGATIVE height for a body lying down. Edit JOBS and re-run
for any new species.

Costs no bake: it reads the source actor. Takes about a minute per subject.

⚠️ EVERY IMPORT IS WRAPPED IN `preserve_sources()`. The Pyrogenesis importer
rewrites every .dae it loads IN PLACE, and that applies to the animation file as
much as to the meshes. Verified after the P5 run: 0 working-tree modifications
across ~20 imports. Remove that context manager and this tool quietly damages the
art checkout (AGENT_ASSET.md 4).

THREE CORRECTIONS TO THE OBVIOUS METHOD, each of which changed a number:

1. `isobake inspect` prints RAW 0 A.D. units labelled "m". The bake scales by
   metres_per_tile / ZEROAD_UNITS_PER_TILE = 2.0 / 4.0 = 0.5, and no fauna recipe
   overrides it with `scale` or `height_m`. isobake's own control: a citizen body
   mesh measures 3.85 raw and should be 1.93 m.

2. A carcass shares its ACTOR with the live animal, so inspect returns the same
   box for both. The carcass is the death clip's final pose, which means posing
   the rig and measuring the DEFORMED mesh off the evaluated depsgraph. Blender
   >=4.4 needs `action_slot` bound or every curve drives nothing and the armature
   sits at rest while reporting success -- isobake's `_assign_action` exists for
   exactly that and is used here rather than reimplemented.

3. AN AXIS-ALIGNED BOX IS THE WRONG FOOTPRINT FOR A BODY THAT DIES TWISTED. The
   wolf's death pose measures 2.51 x 2.48 m axis-aligned, which reads as a
   sprawl; its own body box is far narrower and merely lies at an angle to the
   world axes. A selection ring wants the body, not the world grid, so the
   footprint here is the MINIMUM-AREA ground rectangle. For a standing animal the
   two agree, which is the check that the rotation search is working.

Height is reported for information only -- the game side derives height_m from
the atlas anchor exactly, and their figures reproduce.
"""

import json
import math
import sys
from pathlib import Path

ISOBAKE = r"C:\Users\herman.ras\Downloads\AOD_game\blender_3d_to_2d_isobake"
PYRO = r"C:/Users/herman.ras/Downloads/AOD_game/tools_env/pyrogenesis_importer_src"
ART = Path(r"C:/Users/herman.ras/Downloads/AOD_game/art_source/0ad/binaries/data/mods/public")
sys.path.insert(0, ISOBAKE)

import bpy  # noqa: E402

from isobake.blender import scene as scene_mod  # noqa: E402
from isobake.blender.adapters import subject_armature  # noqa: E402
from isobake.blender.adapters.zeroad import (  # noqa: E402
    _scale_pose_location_curves,
    attach_animation,
)
from isobake.blender.entry import load_pyrogenesis, preserve_sources  # noqa: E402
from isobake.blender.render_impl import _assign_action  # noqa: E402

RAW_TO_M = 0.5

# (id, actor, death clip, location_scale)
# location_scale mirrors the recipe: 1.0 everywhere except the deer, whose clips
# declare INCHES against a mesh in 0 A.D. units. deer_carcass.toml pins 0.0.
JOBS = [
    ("wolf",           "fauna/wolf.xml",       None, 1.0),
    ("bear",           "fauna/bear_brown.xml", None, 1.0),
    ("boar",           "fauna/boar.xml",       None, 1.0),
    ("fish",           "fauna/tuna.xml",       None, 1.0),
    ("sheep",          "fauna/sheep3.xml",     None, 1.0),
    ("cattle",         "fauna/zebu_wild.xml",  None, 1.0),
    ("deer",           "fauna/deer.xml",       None, 1.0),
    ("wolf_carcass",   "fauna/wolf.xml",       "quadraped/wolf_death_01.dae", 1.0),
    ("bear_carcass",   "fauna/bear_brown.xml", "quadraped/bear_death_01.dae", 1.0),
    ("boar_carcass",   "fauna/boar.xml",       "quadraped/animal_boar_death_01.dae", 1.0),
    ("sheep_carcass",  "fauna/sheep3.xml",     "quadraped/sheep_death.dae", 1.0),
    ("cattle_carcass", "fauna/zebu_wild.xml",  "quadraped/bovidae_death_a.dae", 1.0),
    ("deer_carcass",   "fauna/deer.xml",       "quadraped/deer_death_01.dae", 0.0),
]


def ground_points_and_z(objects):
    deps = bpy.context.evaluated_depsgraph_get()
    pts = []
    zlo, zhi = float("inf"), float("-inf")
    for obj in objects:
        if obj.type != "MESH":
            continue
        ev = obj.evaluated_get(deps)
        try:
            mesh = ev.to_mesh()
        except RuntimeError:
            continue
        mw = ev.matrix_world
        for v in mesh.vertices:
            p = mw @ v.co
            pts.append((p.x * RAW_TO_M, p.y * RAW_TO_M))
            z = p.z * RAW_TO_M
            zlo, zhi = min(zlo, z), max(zhi, z)
        ev.to_mesh_clear()
    return pts, zlo, zhi


def min_area_rect(pts):
    """Smallest ground rectangle containing the body, by rotation search.

    Brute force at 0.5 deg over 90 deg rather than rotating calipers: 180 passes
    over a vertex list is nothing next to the import, and a hull implementation
    is one more thing that can be subtly wrong.
    """
    best = None
    for step in range(180):
        a = math.radians(step * 0.5)
        ca, sa = math.cos(a), math.sin(a)
        xs = [x * ca + y * sa for x, y in pts]
        ys = [-x * sa + y * ca for x, y in pts]
        w, h = max(xs) - min(xs), max(ys) - min(ys)
        if best is None or w * h < best[0] * best[1]:
            best = (w, h)
    return sorted(best, reverse=True)


def aabb(pts):
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return sorted([max(xs) - min(xs), max(ys) - min(ys)], reverse=True)


results = {}
for name, actor, clip_rel, loc in JOBS:
    scene_mod.reset()
    load_pyrogenesis(PYRO)
    notes = []
    with preserve_sources():
        before = set(bpy.data.objects)
        bpy.ops.import_pyrogenesis_scene.xml(filepath=str(ART / "art" / "actors" / actor))
        imported = [o for o in bpy.data.objects if o not in before]
        if clip_rel:
            arm = subject_armature(imported, notes)
            clip = attach_animation(ART / "art" / "animation" / clip_rel, arm, "d", notes)
            if loc != 1.0:
                _scale_pose_location_curves(clip.action, loc)
            _assign_action(arm, clip.action)
            bpy.context.scene.frame_set(int(round(clip.frame_end)))
        bpy.context.view_layer.update()
        pts, zlo, zhi = ground_points_and_z(imported)

    results[name] = {
        "footprint_m": [round(v, 2) for v in min_area_rect(pts)],
        "aabb_m": [round(v, 2) for v in aabb(pts)],
        "height_m": round(zhi - zlo, 2),
        "lowest_z_m": round(zlo, 2),
        "clip": clip_rel,
    }
    print(f"done {name}", flush=True)

print("=== FINAL ===")
print(f"{'id':<16}{'footprint_m (body)':<22}{'axis-aligned':<18}{'height_m':<10}lowest_z")
for k, v in results.items():
    print(f"{k:<16}{str(v['footprint_m']):<22}{str(v['aabb_m']):<18}"
          f"{v['height_m']:<10}{v['lowest_z_m']}")
print("\n=== JSON ===")
print(json.dumps(results, separators=(",", ":")))
