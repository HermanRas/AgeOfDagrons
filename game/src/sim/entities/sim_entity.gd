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


func to_snapshot() -> Dictionary:
	return {
		"id": id,
		"def_id": def_id,
		"owner_id": owner_id,
		"pos": {"x": pos.x, "y": pos.y},
		"hp": hp,
		"max_hp": max_hp,
		"alive": alive,
	}
