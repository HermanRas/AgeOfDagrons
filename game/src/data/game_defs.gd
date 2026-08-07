## Shared parsing helpers for the *Def classes (PLAN.md 9). Phase 0.4.
##
## JSON gives back floats for every number and untyped Arrays for every list, so
## each Def would otherwise repeat the same int()/StringName() coercion. Kept in
## one place so the coercion rules are stated once.
class_name GameDefs
extends RefCounted

## Resource kinds a cost/carry/gather map may be keyed by (PLAN.md 6.1's
## SimPlayer.stock). Used to validate data rather than to filter it -- an unknown
## key is a typo worth reporting, not something to silently drop.
const RESOURCE_KINDS: Array[StringName] = [&"food", &"wood", &"gold", &"stone"]


## {"food": 50.0} -> {&"food": 50}. JSON has no ints; every number arrives as a
## float, and an unrounded float leaking into the sim would break determinism
## (PLAN.md 7.1), so this is not merely cosmetic.
static func int_map(d: Variant) -> Dictionary:
	var out: Dictionary = {}
	if d is Dictionary:
		for key in d:
			out[StringName(key)] = int(d[key])
	return out


static func name_list(a: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	if a is Array:
		for v in a:
			out.append(StringName(v))
	return out


## [8, 8] -> Vector2i(8, 8).
static func tile_size(a: Variant, fallback := Vector2i.ONE) -> Vector2i:
	if a is Array and (a as Array).size() >= 2:
		return Vector2i(int(a[0]), int(a[1]))
	return fallback


static func int_list(a: Variant) -> Array[int]:
	var out: Array[int] = []
	if a is Array:
		for v in a:
			out.append(int(v))
	return out


## Names of any resource keys in `d` that are not real resource kinds.
static func unknown_kinds(d: Dictionary) -> Array[StringName]:
	var bad: Array[StringName] = []
	for key in d:
		if not RESOURCE_KINDS.has(key):
			bad.append(key)
	return bad
