## What a snapshot actually costs on the wire (PLAN.md 12.1f).
##
## THE MEASUREMENT THAT WAS MISSING. ENet says this out loud during an ordinary match --
##
##     WARNING: Sending 18532 bytes unreliably which is above the MTU (1392),
##              this will result in higher packet loss
##
## -- and 18,532 bytes is about fourteen fragments, of which losing ANY ONE loses the
## whole snapshot, because `_recv_snapshot` is `unreliable_ordered`. Invisible on
## loopback, which is exactly why it wanted measuring rather than assuming: the
## two-process PC run it came from looked perfect.
##
## Reports the breakdown, because the total on its own does not say what to fix. The
## interesting split is FOG versus ENTITIES: `vision` is one byte per tile of the whole
## map, sent every tick to every player, so it is a function of the MAP and grows with
## nothing that happens in the match -- while `updated` is every entity a player may see,
## sent in full every tick, and grows with the army.
##
## `var_to_bytes` is the yardstick because it is what the transport does: Godot encodes
## RPC arguments as binary Variants, which is also why a `PackedByteArray` survives the
## wire while JSON mangles it (see `MapData._terrain_from`).
##
## Usage:
##   Godot --headless --path game res://dev_preview/preview_wire_size.tscn
##       [-- --ticks 3000] [--seed 3]
extends Node

## Where to take readings.
##
## STARTS AT 1, NOT 0, and the difference is instructive. `SimHost` steps the world and
## then broadcasts, so no snapshot is ever built from an unstepped world -- and an
## unstepped world has no vision computed yet, which sends `_entry_for` down its
## "no fog in this world" branch and puts EVERY entity on the map into the packet. Read at
## tick 0 the 8-player board reports 344,500 bytes and 248 fragments, which is not a
## packet anybody sends; it is this harness measuring a state the host skips. Left
## documented rather than deleted because it is also what a fog-less world costs, and
## `SimPlayer.vision` allows one.
const MARKS := [1, 600, 1800, 3600]

## What the transport will fragment across. ENet's own figure from the warning above.
const MTU := 1392


func _ready() -> void:
	var p_seed := _int_arg("--seed", 3)
	var ticks := _int_arg("--ticks", MARKS[MARKS.size() - 1])

	# `-- --fields` instead of the sweep: one entry of each kind, broken down field by
	# field. A scene rather than a `--script`, because a custom MainLoop skips the boot
	# that parents the autoloads and `GameDataRegistry` would be missing.
	if OS.get_cmdline_user_args().has("--fields"):
		_report_fields(p_seed)
		get_tree().quit()
		return

	print("SNAPSHOT WIRE SIZE — one row per reading, bytes as the transport encodes them")
	print("MTU is %d bytes; anything above it fragments, and an unreliable_ordered" % MTU)
	print("packet loses the WHOLE snapshot if any one fragment is dropped.")
	print("")

	# Every slot count the lobby now offers a board for. 8 players is not a hypothetical:
	# the count picker went live today, and the map it sizes is 192x192.
	for slots in [2, 4, 8]:
		_measure(p_seed, slots, ticks)


func _measure(p_seed: int, slots: int, ticks: int) -> void:
	# TWO players on a board sized for `slots`, which is the lobby's own "close the rest"
	# case -- and the honest worst case for fog, since vision is per player per tile and
	# the board is what sets the tile count.
	var cfg := MatchConfig.new()
	cfg.player_ids = [1, 2] as Array[int]
	cfg.colours = [2, 1] as Array[int]
	cfg.ai_players = [true, true] as Array[bool]
	cfg.map_data = MapGenerator.generate(p_seed, MapGenerator.Type.FOREST, 2, slots)
	cfg.map_size = cfg.map_data.size

	var w := SimWorld.new()
	w.setup(cfg)
	MapGen.build(w, cfg)

	print("── room for %d: %dx%d, %d tiles ──" % [slots, w.map.size.x, w.map.size.y,
			w.map.size.x * w.map.size.y])
	print("  tick  entities   total     vision  entities   state   frags  over MTU")

	for i in range(ticks + 1):
		if MARKS.has(i):
			_report(w, i)
		if i < ticks:
			w.step()
			if w.match_over:
				_report(w, w.tick)
				print("  (match over on tick %d)" % w.tick)
				break
	print("")


func _report(w: SimWorld, tick: int) -> void:
	var snap := SnapshotSystem.build(w, 1)
	var total := var_to_bytes(snap).size()

	# Each component measured on its own, so the total is attributable rather than just
	# alarming. Measured as the transport would encode that value, not as a share of the
	# whole -- the pieces do not sum exactly to the total because the enclosing dictionary
	# has its own keys and headers, and that residue is small and uninteresting.
	# Kept as a column even though 12.1f stopped sending it, because this is the number
	# the change was made for and a row that no longer shows it cannot show that. Reads 8
	# when the key is absent -- what an empty PackedByteArray encodes to -- so anything
	# above that means the grid has come back.
	var vision := var_to_bytes(snap.get("vision", PackedByteArray())).size()
	var entities := var_to_bytes(snap.get("updated", [])).size()
	var state := var_to_bytes(snap.get("player_state", {})).size()

	var frags := int(ceil(float(total) / float(MTU)))
	print("  %4d  %8d  %6d  %9d  %8d  %6d  %6d  %s"
			% [tick, w.entities.size(), total, vision, entities, state, frags,
			"YES" if total > MTU else "no"])
	_report_entities(w, snap)


## WHAT THE ENTITY PAYLOAD IS MADE OF, which is the question that decides what to do about
## it. `updated` sends every entity a player may see, in full, every tick -- so the split
## that matters is between things that CHANGE tick to tick and things that do not. A tree
## re-sent 600 times in a minute is 600 identical copies of a fact that was true the first
## time.
##
## Split by what the client is told, not by class name: a REMEMBERED entry is a static
## somebody explored and cannot currently see, and it is the most obviously wasteful of
## all -- it is a fact that by definition cannot have changed since they last looked.
func _report_entities(w: SimWorld, snap: Dictionary) -> void:
	var counts := {"unit": 0, "building": 0, "resource": 0, "remembered": 0}
	var bytes := {"unit": 0, "building": 0, "resource": 0, "remembered": 0}
	for entry in snap.get("updated", []):
		var key := "resource"
		if bool(entry.get("remembered", false)):
			key = "remembered"
		elif GameDataRegistry.unit(StringName(entry.get("def_id", &""))) != null:
			key = "unit"
		elif GameDataRegistry.building(StringName(entry.get("def_id", &""))) != null:
			key = "building"
		counts[key] += 1
		bytes[key] += var_to_bytes(entry).size()

	var parts: Array[String] = []
	for key in ["unit", "building", "resource", "remembered"]:
		parts.append("%s %d/%dB" % [key, counts[key], bytes[key]])
	print("        of which: %s" % ", ".join(parts))


## WHERE THE BYTES IN ONE ENTRY GO. Only 36 entities are visible on the 8-player board and
## they cost 16,024 bytes, which is ~445 bytes each -- so the question is not how many
## entities are sent but why one costs that much. This answers it per field, splitting the
## KEY NAME from the value, because `var_to_bytes` encodes a dictionary key as a full
## length-prefixed string on every entry that has it.
func _report_fields(p_seed: int) -> void:
	var cfg := MatchConfig.debug_generated(p_seed, MapGenerator.Type.FOREST, 2)
	var w := SimWorld.new()
	w.setup(cfg)
	MapGen.build(w, cfg)
	w.step()

	var shown: Dictionary = {}
	for entry in SnapshotSystem.build(w, 1).get("updated", []):
		var def_id := StringName(entry.get("def_id", &""))
		var kind := "resource"
		if GameDataRegistry.unit(def_id) != null:
			kind = "unit"
		elif GameDataRegistry.building(def_id) != null:
			kind = "building"
		if shown.has(kind):
			continue
		shown[kind] = true

		print("── %s (%s): %d bytes across %d fields ──"
				% [kind, def_id, var_to_bytes(entry).size(), entry.size()])
		var rows: Array = []
		for k in entry:
			var kb := var_to_bytes(k).size()
			var vb := var_to_bytes(entry[k]).size()
			rows.append([kb + vb, String(k), kb, vb, str(entry[k]).substr(0, 36)])
		rows.sort_custom(func(a, b): return a[0] > b[0])
		var keys_total := 0
		for r in rows:
			keys_total += int(r[2])
			print("   %5d B  %-16s  key %3d + value %5d   %s" % [r[0], r[1], r[2], r[3], r[4]])
		print("   key names alone: %d B of %d" % [keys_total, var_to_bytes(entry).size()])
		print("")


func _int_arg(name: String, fallback: int) -> int:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == name:
			return int(args[i + 1])
	return fallback
