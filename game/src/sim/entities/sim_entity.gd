## Base for everything that exists in the sim: units, buildings, resource
## nodes. Plain GDScript, no Node -- the src/sim/ boundary rule (PLAN.md 4)
## is what makes headless testing and a rendering-free server possible.
class_name SimEntity
extends RefCounted

var id: int = 0
var def_id: StringName = &""
var owner_id: int = 0
var pos: Vector2i = Vector2i.ZERO          # sub-tile units, PLAN.md 1
var hp: int = 0
var max_hp: int = 0
var alive: bool = true
var vision_range: int = 0


func tile() -> Vector2i:
	return pos / SimWorld.SUBTILE


func take_damage(amount: int, _attack_type: int) -> void:
	hp = maxi(0, hp - amount)
	if hp == 0:
		alive = false


func on_tick(_w: SimWorld) -> void:
	pass


## A `Vector2i` FOR `pos`, NOT A PAIRED-INT DICTIONARY (12.1f). `{"x": .., "y": ..}` cost
## 48 bytes to carry two small integers, because `var_to_bytes` re-encodes the key names
## "x" and "y" inside every entry; the Vector2i is 12. Sixty bytes down to twenty-four,
## on every entity, every tick.
##
## Safe here and NOT in `MapData`, which notes the opposite ("Vector2i is not JSON") for a
## good reason: a saved map goes through JSON, and a snapshot never does. Snapshots cross
## by RPC, which encodes Variants in binary; the only thing this project puts through JSON
## is `Replay`, and that carries commands rather than snapshots.
func to_snapshot() -> Dictionary:
	return {
		"id": id,
		"def_id": def_id,
		"owner_id": owner_id,
		"pos": pos,
		"hp": hp,
		"max_hp": max_hp,
		"alive": alive,
	}
