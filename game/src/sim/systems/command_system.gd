## Drains SimWorld's pending commands, validating each against current state
## before applying it. The reject-silently behaviour is deliberate: a stale
## command (its unit died, changed owner) is not an error, just a no-op.
class_name CommandSystem
extends SimSystem

func process_tick(w: SimWorld) -> void:
	for cmd in w.drain_pending_commands():
		if cmd != null and cmd.validate(w):
			cmd.apply(w)
