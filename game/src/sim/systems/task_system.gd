## Per-unit task state machine. For 0.5's MOVE-only scope this just retires a
## finished move to IDLE once MovementSystem has landed the unit exactly on
## its target tile; GATHER/BUILD/ATTACK transitions join this as their
## systems land.
class_name TaskSystem
extends SimSystem

func process_tick(w: SimWorld) -> void:
	for e in w.entities.values():
		if e is SimUnit and e.task == SimUnit.Task.MOVE:
			if e.pos == e.move_target_subpos():
				e.task = SimUnit.Task.IDLE
