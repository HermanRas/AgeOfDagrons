## Server-side owner of the authoritative SimWorld (PLAN.md 8: "SimHost --
## server only; owns SimWorld"). Drives it off the shared SimClock autoload
## rather than owning a private clock, since only one match runs per process
## in this architecture.
class_name SimHost
extends Node

var world: SimWorld = null

## Cost of the last world.step() alone, excluding snapshot building/broadcast
## -- what PLAN.md 3.1's "sim tick cost < 5ms per 100ms tick" budget means.
var last_step_usec: int = 0

var _on_tick: Callable = Callable()


## on_tick is called with the Dictionary from SnapshotSystem.build() after
## every world.step(), so the caller (Net) can broadcast it.
func start(cfg: MatchConfig, on_tick: Callable) -> void:
	world = SimWorld.new()
	world.setup(cfg)
	# setup() allocates an empty grid; MapGen puts a world in it (2.3/2.4a/2.6).
	# Split so a test can stand up a bare world without a town centre in the way.
	MapGen.build_debug_map(world)
	_on_tick = on_tick
	SimClock.tick_advanced.connect(_handle_tick)
	SimClock.start()


func stop() -> void:
	SimClock.stop()
	if SimClock.tick_advanced.is_connected(_handle_tick):
		SimClock.tick_advanced.disconnect(_handle_tick)
	world = null
	_on_tick = Callable()


func _handle_tick(_tick: int) -> void:
	var started := Time.get_ticks_usec()
	world.step()
	last_step_usec = Time.get_ticks_usec() - started
	if _on_tick.is_valid():
		for p in world.players:
			_on_tick.call(p.id, SnapshotSystem.build(world, p.id))
