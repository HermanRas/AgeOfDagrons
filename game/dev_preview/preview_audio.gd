## Audio, which no test can judge (PLAN.md 7.5, 7.7's fourth layer).
##
## THE SAME REASON `preview_projectiles` EXISTS, and harder. A projectile at
## least leaves pixels on a screenshot; a sound leaves nothing an automated run
## can look at, so `tests/view/test_audio_seam.gd` can prove the *vocabulary* is
## coherent and can prove nothing whatever about anything being audible. What it
## deliberately does NOT assert is that any bytes are present, because
## `game/assets/audio/` is gitignored build output and a clean checkout has none
## of it — so a green suite is entirely consistent with a silent game.
##
## This closes that gap in the only two ways available:
##
## 1. **It reports what actually resolved.** Per sound id: how many variations are
##    on disk, and whether `AudioManager` could load one. A partial fetch (the
##    0 A.D. LFS endpoint rate-limits, so partial is the normal state for a while)
##    shows up here as a list of names rather than as a quiet absence.
## 2. **It plays a walk through the roster** with a gap between each, naming each
##    one as it goes, so a person can hear whether the mapping is right. Reading
##    that a villager's chop resolved to `lumber_tree_03.ogg` is not the same as
##    hearing that it sounds like an axe.
##
## Run it with sound on and read along:
##
##     & $godot --path game res://dev_preview/preview_audio.tscn
##     & $godot --path game res://dev_preview/preview_audio.tscn -- --report-only
##
## `--report-only` skips the playback and exits as soon as the table is printed,
## which is the form worth running after a re-stage.
extends Node

## Seconds between one sound and the next. Long enough to tell two apart, short
## enough that the whole walk is a couple of minutes.
const GAP := 0.9

## Played in this order, chosen to walk the CATEGORIES rather than to be
## exhaustive: if `ui.click` and `villager.chop` and `attack.sword` and
## `die.female` and one building completion all sound right, the 126 ids not in
## this list are the same five paths through `AudioManager`.
const WALK: Array[StringName] = [
	&"ui.click", &"ui.error", &"ui.age_advance", &"ui.victory", &"ui.defeat",
	&"villager.chop", &"villager.mine_stone", &"villager.forage",
	&"villager.build_stone", &"tree.fall",
	&"attack.sword", &"attack.bow", &"impact.arrow", &"attack.catapult",
	&"die.female", &"die.male", &"die.mounted", &"die.animal",
	&"animal.predator_attack", &"animal.sheep",
	&"complete.town_center", &"complete.house", &"building.destroyed",
	&"gate.open", &"gate.close",
	&"voice.female.select", &"voice.male.attack",
	&"trained.infantry", &"trained.cavalry",
]


func _ready() -> void:
	_report()
	if "--report-only" in OS.get_cmdline_user_args():
		get_tree().quit()
		return
	await _walk()
	get_tree().quit()


## The table. Prints the SILENT ids explicitly rather than only the working ones,
## because "nothing came out of the speakers" is the symptom either way and the
## whole point is to tell a missing fetch from a wrong mapping.
func _report() -> void:
	var ids: Array = GameDataRegistry.sfx_ids()
	var silent: Array = GameDataRegistry.silent_sfx_ids()
	var variations := 0
	for id in ids:
		for path in GameDataRegistry.sfx(id).get("streams", []):
			if ResourceLoader.exists(String(path)):
				variations += 1

	print("\n─── audio seam ───────────────────────────────────────────────")
	print("  %d sfx ids declared, %d with playable streams, %d silent"
			% [ids.size(), ids.size() - silent.size(), silent.size()])
	print("  %d stream files present on disk" % variations)

	var music_silent := 0
	for id in GameDataRegistry.music_ids():
		var playable := false
		for path in GameDataRegistry.music(id).get("streams", []):
			if ResourceLoader.exists(String(path)):
				playable = true
		if not playable:
			music_silent += 1
	print("  music: %d of %d tracks present"
			% [GameDataRegistry.music_ids().size() - music_silent,
				GameDataRegistry.music_ids().size()])

	if not silent.is_empty():
		# NOT a failure. Re-run tools/stage_audio.py; it fetches only what is
		# missing, and the server it fetches from is the slow part.
		print("\n  SILENT (no bytes staged) -- re-run tools/stage_audio.py:")
		var line := "   "
		for id in silent:
			if line.length() + String(id).length() > 74:
				print(line)
				line = "   "
			line += " " + String(id)
		if line.strip_edges() != "":
			print(line)

	print("\n  buses: %s" % [", ".join(_bus_report())])
	print("─────────────────────────────────────────────────────────────\n")


## Each bus with its send target and current level, so a mix routed wrongly is
## visible. A bus whose send is not what `BUS_SENDS` asked for is the failure
## that makes a volume slider do nothing while the sound still plays.
func _bus_report() -> Array:
	var out: Array = []
	for pair in AudioManager.BUS_SENDS:
		var idx := AudioServer.get_bus_index(String(pair[0]))
		if idx == -1:
			out.append("%s=MISSING" % pair[0])
			continue
		out.append("%s->%s @%.2f" % [
			pair[0], AudioServer.get_bus_send(idx),
			AudioManager.bus_volume(pair[0])])
	return out


## Play each id in turn, naming it first so the printout and the speaker stay in
## step. Reports what did NOT play too -- `play_sfx` returns false for a silent id
## and for a starved voice pool, and those are different problems.
func _walk() -> void:
	print("playing %d sounds, %.1fs apart -- listen along:" % [WALK.size(), GAP])
	for id in WALK:
		var streams: Array = GameDataRegistry.sfx(id).get("streams", [])
		var entry: Dictionary = GameDataRegistry.sfx(id)
		var played: bool = AudioManager.play_sfx(id)
		print("  %-26s %-7s %d variation(s)  %+.1f dB  pitch %.2f-%.2f" % [
			id,
			"PLAYED" if played else "silent",
			streams.size(),
			float(entry.get("gain_db", 0.0)),
			float(entry.get("pitch_min", 1.0)),
			float(entry.get("pitch_max", 1.0)),
		])
		await get_tree().create_timer(GAP).timeout

	# The music last, and only briefly: a track is 3-4 minutes and nobody is
	# waiting for it. Long enough to confirm it is the right one and loops.
	if AudioManager.play_music(&"menu.theme"):
		print("\n  menu.theme playing -- 6s")
		await get_tree().create_timer(6.0).timeout
	else:
		print("\n  menu.theme is not staged")
