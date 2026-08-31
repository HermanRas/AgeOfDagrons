## Two Godot processes, one real broadcast, one real discovery (2026-08-31).
##
## **THIS IS THE ONLY HONEST TEST OF THE ONE LINE THAT MATTERS MOST.**
## `tests/net/test_lan_discovery.gd` runs a beacon and a browser in one process and they
## really do talk -- two `PacketPeerUDP`s are two sockets, unlike two ENet peers -- but it
## sends to 127.0.0.1, so `set_broadcast_enabled(true)` is the single line no assertion in
## the suite reaches. Without that flag the OS refuses a datagram addressed to
## 255.255.255.255 outright, `put_packet` answers `ERR_UNAVAILABLE`, and the symptom on
## both machines is a server browser that finds nothing with no error anywhere near it.
## The same goes for anything a firewall or an adapter does, which is most of what breaks
## discovery in practice.
##
## It is also the two-machine bring-up: run `beacon` on one device and `browse` on the
## other and the answer is a printed row or a non-zero exit.
##
## Usage -- start the beacon first, it waits:
##   Godot --headless --path game res://dev_preview/preview_lan_discovery.tscn -- --role beacon
##   Godot --headless --path game res://dev_preview/preview_lan_discovery.tscn -- --role browse
##
## ⚠️ **ON ONE MACHINE, ONLY THE BROWSER MAY BIND.** The beacon does not bind at all --
## it only sends -- so the pair runs side by side on one desktop; but two BROWSERS cannot,
## and the second reports `ERR_ALREADY_IN_USE` rather than silently finding nothing, which
## is the distinction `LanBrowser.listen_error` exists for.
##
## Exits 0 when the browse side saw the beacon (or the beacon side finished its run), 1
## otherwise, so a script can chain the two and read the answer.
extends Node

## Long enough to start the second process by hand, short enough that a failed run ends
## rather than hanging a terminal.
const WAIT_SECONDS := 25.0

## How long the beacon keeps shouting. Comfortably longer than a browser needs at one
## beacon a second.
const BEACON_SECONDS := 20.0

var _role := "beacon"
var _done := false
var _waited := 0.0

var _beacon: LanBeacon = null
var _browser: LanBrowser = null


func _ready() -> void:
	_role = _string_arg("--role", "beacon")
	print("lan discovery preview -- role %s, beacon port %d" % [_role, LanBeacon.PORT])

	if _role == "beacon":
		# A REAL LOBBY'S CONFIG, not a hand-made dictionary: the payload is a subset of
		# `MatchConfig` by design and building it any other way here would be testing a
		# second description of a match.
		var cfg := MatchConfig.debug_generated(4242, MapGenerator.Type.FOREST, 4)
		cfg.host_name = LanBeacon.default_host_name()
		_beacon = LanBeacon.new()
		add_child(_beacon)
		var err := _beacon.advertise(
				LanBeacon.payload_for(cfg, cfg.host_name, 2, Net.PORT))
		if err != OK:
			_finish(false, "could not open the broadcast socket: %s" % error_string(err))
			return
		print("  broadcasting \"%s\" to %s:%d every %.1f s -- %s"
				% [cfg.host_name, LanBeacon.BROADCAST_ADDRESS, LanBeacon.PORT,
				LanBeacon.INTERVAL_MSEC / 1000.0, ", ".join(_own_addresses())])
		print("  now run the browse side, here or on another device")
	else:
		_browser = LanBrowser.new()
		# LEFT AT ITS DEFAULT (false), unlike the suite's. A browser that finds its own
		# process is the bug, not the fixture -- and on one desktop the beacon side is a
		# DIFFERENT process, so its packets are a stranger's and are meant to be seen.
		add_child(_browser)
		var err := _browser.listen()
		if err != OK:
			_finish(false, "could not bind port %d: %s -- another copy of the game or "
					% [LanBeacon.PORT, error_string(err)]
					+ "another browse process probably has it")
			return
		print("  listening on %d; waiting up to %.0f s for a beacon" % [LanBeacon.PORT,
				WAIT_SECONDS])


func _process(delta: float) -> void:
	if _done:
		return
	_waited += delta

	if _role == "beacon":
		if _waited >= BEACON_SECONDS:
			_finish(true, "shouted for %.0f s; whether anybody heard is the other side's "
					% _waited + "answer to give")
		return

	var found := _browser.hosts()
	if not found.is_empty():
		for row in found:
			print("  FOUND %s at %s:%d -- %s %dx%d, %s, %d/%d chairs, age %d"
					% [row["name"], row["address"], row["port"],
					MapGenerator.type_name(int(row["map"]) as MapGenerator.Type),
					(row["size"] as Vector2i).x, (row["size"] as Vector2i).y,
					MatchConfig.mode_name(int(row["mode"]) as MatchConfig.Mode),
					row["taken"], row["slots"], row["age"]])
		_finish(true, "%d host(s) discovered in %.1f s" % [found.size(), _waited])
		return

	if _waited >= WAIT_SECONDS:
		# THE THREE THINGS THIS IS USUALLY NOT, listed because the failure says nothing on
		# its own and the wrong guess costs an afternoon. It bound (that was checked at
		# start-up), so what is left is the wire.
		_finish(false, "nothing heard in %.0f s. Check, in order: the beacon side is "
				% WAIT_SECONDS
				+ "running; both devices are on the SAME subnet (a phone on mobile data "
				+ "is not); the host's firewall allows outbound UDP %d. Wi-Fi access "
				% LanBeacon.PORT
				+ "points that isolate clients block this by design.")


func _finish(ok: bool, why: String) -> void:
	_done = true
	print("%s -- %s" % ["OK" if ok else "FAILED", why])
	if _beacon != null:
		_beacon.stop()
	if _browser != null:
		_browser.stop()
	# Quitting at all because a headless main loop with nothing to do spins a core
	# forever, which is how the AI preview left processes running.
	get_tree().quit(0 if ok else 1)


## This device's routable addresses, so the log says where the beacon is coming FROM --
## the first thing to compare against the browsing device's own subnet.
func _own_addresses() -> Array[String]:
	var out: Array[String] = []
	for a in IP.get_local_addresses():
		var s := String(a)
		if s.begins_with("127.") or s.begins_with("169.254.") or s.contains(":"):
			continue
		out.append(s)
	if out.is_empty():
		out.append("no network address")
	return out


func _string_arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == name:
			return String(args[i + 1])
	return fallback
