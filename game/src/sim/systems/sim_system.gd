## Base for one stage of SimWorld.step(). Systems run in a fixed order
## (PLAN.md 5.1, 6.2) so tick behaviour stays deterministic regardless of
## instantiation order.
class_name SimSystem
extends RefCounted

func process_tick(_w: SimWorld) -> void:
	pass
