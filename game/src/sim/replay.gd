## A MatchConfig plus an ordered command log -- a few KB that reproduces any
## bug exactly (PLAN.md 7.7 layer 4). Also the manual-testing tool: record a
## session on the phone, replay it headless on the desktop to debug.
##
## Purely data plus playback logic against a SimWorld -- no Node, consistent
## with the src/sim/ boundary, so replays are recordable/playable in the same
## headless tests as everything else here.
class_name Replay
extends RefCounted

var cfg: MatchConfig = null
var commands: Array[Dictionary] = []          # [{tick: int, cmd: Dictionary}, ...]


## tick is the world tick the command was queued at (queue_command() then
## marks it for tick+1 as usual) -- record alongside the live queue_command()
## call, not instead of it.
func record(tick: int, cmd: Command) -> void:
	commands.append({"tick": tick, "cmd": cmd.to_dict()})


## Steps w for total_ticks, re-queuing each recorded command at the tick it
## was originally issued on. Assumes w has already been setup() with this
## replay's cfg and has taken no steps yet.
func play(w: SimWorld, total_ticks: int) -> void:
	var by_tick: Dictionary = {}                # int tick -> Array[Dictionary]
	for entry in commands:
		var t: int = int(entry.tick)
		if not by_tick.has(t):
			by_tick[t] = []
		by_tick[t].append(entry.cmd)

	for i in total_ticks:
		if by_tick.has(w.tick):
			for cmd_dict in by_tick[w.tick]:
				var cmd := Command.from_dict(cmd_dict)
				if cmd != null:
					w.queue_command(cmd)
		w.step()


func to_dict() -> Dictionary:
	return {"player_ids": cfg.player_ids, "commands": commands}


static func from_dict(d: Dictionary) -> Replay:
	var r := Replay.new()
	var cfg := MatchConfig.new()
	var ids: Array[int] = []
	for v in d.get("player_ids", []):
		ids.append(int(v))
	cfg.player_ids = ids
	r.cfg = cfg

	var cmds: Array[Dictionary] = []
	for entry in d.get("commands", []):
		cmds.append({"tick": int(entry.get("tick", 0)), "cmd": entry.get("cmd", {})})
	r.commands = cmds
	return r


func save(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict()))
	return OK


static func load_from_file(path: String) -> Replay:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return null
	return Replay.from_dict(parsed)
