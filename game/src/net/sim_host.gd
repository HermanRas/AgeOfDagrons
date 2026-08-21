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


## Build the world and start ticking it, in one call. Solo's whole life cycle: there is
## nobody to wait for, so there is nothing to hold the clock for.
##
## on_tick is called with the Dictionary from SnapshotSystem.build() after
## every world.step(), so the caller (Net) can broadcast it.
func start(cfg: MatchConfig, on_tick: Callable) -> void:
	build(cfg, on_tick)
	begin()


## Stand the world up WITHOUT starting the clock (PLAN.md 12.1d).
##
## Split from `begin()` so a hosted match can hold still while its clients build their
## own view of the map and say they are ready. Snapshots that arrive before a client has
## terrain describe a world it cannot draw -- entities on nothing, a camera nowhere --
## and every tick spent waiting is a tick of the match the joiner never sees.
func build(cfg: MatchConfig, on_tick: Callable) -> void:
	world = SimWorld.new()
	world.setup(cfg)
	# setup() allocates an empty grid; MapGen puts a world in it (2.3/2.4a/2.4b/2.6) --
	# the config's own map if it carries one, else the fixed debug map. Split so a test
	# can stand up a bare world without a town centre in the way.
	MapGen.build(world, cfg)
	_on_tick = on_tick
	SimClock.tick_advanced.connect(_handle_tick)


## Let it run. Idempotent, because the handshake can reach "everybody is ready" by two
## routes -- the last ack arriving, or the wait timing out -- and both call this.
func begin() -> void:
	if is_running():
		return
	SimClock.start()


func is_running() -> bool:
	return SimClock.is_running()


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
