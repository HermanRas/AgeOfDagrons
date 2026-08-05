## Fixed 10 Hz tick pump (PLAN.md 1, 6.1). Only accumulates and emits
## tick_advanced -- it does not hold or step a SimWorld itself, so whatever
## hosts the match (SimHost, phase 0.6/8) decides what a tick means.
##
## advance() holds the real logic, separated from _process() so it can run
## under the headless test runner without a live scene tree.
##
## No class_name: this script is registered as the "SimClock" autoload
## singleton, and a class_name of the same name collides with that global
## identifier. Tests that need an isolated instance load the script directly.
extends Node

const TICK_HZ := 10
const TICK_MS := 100
const TICK_SECONDS := TICK_MS / 1000.0

var tick: int = 0
signal tick_advanced(tick: int)

var _running: bool = false
var _accum: float = 0.0


func start() -> void:
	_running = true
	_accum = 0.0


func stop() -> void:
	_running = false


func _process(delta: float) -> void:
	advance(delta)


## May emit more than one tick_advanced in a single call if delta is large
## enough to catch up (e.g. after a stall).
func advance(delta: float) -> void:
	if not _running:
		return
	_accum += delta
	while _accum >= TICK_SECONDS:
		_accum -= TICK_SECONDS
		tick += 1
		tick_advanced.emit(tick)
