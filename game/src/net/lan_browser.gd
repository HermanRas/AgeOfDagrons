## THE LISTENING HALF OF LAN DISCOVERY: a UDP socket on `LanBeacon.PORT` and a rolling
## window over what it hears (project owner, 2026-08-31: *"lets wire it up and make it
## live"*).
##
## `LanBeacon` owns the format and the shouting; this owns the table. Split that way
## because a host and a browser are different roles and a device is usually one of them,
## and because the table is the half worth testing without a socket at all.
##
## ── ⚠️ A ROLLING WINDOW, NOT A REFRESH-AND-CLEAR ────────────────────────────
##
## **A BEACON IS A DATAGRAM AND DATAGRAMS ARE LOST.** A list that clears itself and
## repopulates over the following two seconds reads as a flicker, and a row that vanishes
## the one second a packet went missing reads as a host that dropped out -- which is
## exactly the thing a player is watching this page to learn. So a host stays listed for
## `LanBeacon.WINDOW_MSEC` after its last beacon, four beacons' worth of silence, and
## REFRESH means *start the window again* rather than *empty the table*.
##
## `restart()` is what REFRESH calls: it re-opens the socket -- which is the only way back
## from a bind that failed because another copy of the game is already browsing -- and
## pushes every current row's deadline out by a full window, so nothing disappears in the
## second after a press merely because its beacon was in flight.
##
## ── WHAT IT REFUSES ─────────────────────────────────────────────────────────
##
## **ITS OWN PROCESS**, unless asked otherwise. `Net.has_session()` is true for a host the
## moment a slot is opened and the browser is reached from that very screen, so a host
## browsing for other hosts hears its own broadcast come back on every platform that loops
## broadcast to local sockets. `include_self` exists for the one caller that needs the
## opposite -- a single-process test, which cannot have two processes to work with.
##
## Everything else `LanBeacon.decode` refuses on this class's behalf: the wrong version,
## an unparseable packet, an oversized one. The address is the transport's
## `get_packet_ip()` and never the payload's, so a beacon cannot name a machine it is not.
class_name LanBrowser
extends Node

## The set of hosts on screen has changed, or something about one of them has. Emitted at
## most once per poll, and only when the RENDERED content differs -- a beacon that says
## exactly what the last one said is not news, and rebuilding a list of buttons under a
## thumb that is aiming at one of them is worse than not rebuilding it.
signal changed()

## Whether a beacon from this very process counts as a discovered host. False in the game
## (see the class header); true only for a test with one process to work with.
var include_self := false

var _socket: PacketPeerUDP = null
var _error: Error = OK
var _port := LanBeacon.PORT

## origin -> the decoded row, plus `at`, the millisecond its last beacon arrived.
## Keyed on ORIGIN rather than on address, because the origin is the identity: a host with
## two adapters shouts twice and is one host, and an address handed to somebody else by
## DHCP is not the same machine it was ten minutes ago.
var _hosts: Dictionary = {}

## What `hosts()` last handed out, as one string, so `changed` fires on a real difference
## rather than on every arriving packet.
var _signature := ""


## Open the socket. Safe to call on an already-open browser, which is what makes
## `restart()` two lines.
##
## ⚠️ **A FAILED BIND IS THE EXPECTED FAILURE, NOT AN EXOTIC ONE.** Two copies of this
## game browsing on one machine is a developer's normal Tuesday and the second one cannot
## have the port. It is reported rather than swallowed: a browser that finds nothing
## because it never bound looks exactly like a network with no hosts on it, and those two
## want completely different things done about them.
func listen(port: int = LanBeacon.PORT) -> Error:
	_port = port
	if _socket != null:
		return _error
	var socket := PacketPeerUDP.new()
	var err := socket.bind(port)
	_error = err
	if err != OK:
		return err
	_socket = socket
	set_process(true)
	return OK


func stop() -> void:
	set_process(false)
	if _socket != null:
		_socket.close()
		_socket = null


func is_listening() -> bool:
	return _socket != null


## Why the socket is not open, or OK. `ERR_ALREADY_IN_USE` is the one worth a sentence on
## screen -- see `ServerBrowserPanel._note_text`.
func listen_error() -> Error:
	return _error


## REFRESH. Re-opens the socket and starts the window again over what is already listed.
##
## It deliberately does NOT clear: see the class header. Clearing is the version that
## reads as a flicker, and it is also the version that punishes a player for pressing the
## button -- every row they could see is gone for up to a second and some of them come
## back.
func restart() -> void:
	stop()
	listen(_port)
	var now := Time.get_ticks_msec()
	for origin in _hosts:
		(_hosts[origin] as Dictionary)["at"] = now


## Read whatever has arrived and drop whatever has gone quiet.
##
## PUBLIC AND NOT ONLY CALLED FROM `_process`, because the test suite has no frame loop:
## every method here runs to completion when called, so a test sends a packet, calls this,
## and asserts -- rather than proving something about a timer.
func poll() -> void:
	var now := Time.get_ticks_msec()
	if _socket != null:
		while _socket.get_available_packet_count() > 0:
			var bytes := _socket.get_packet()
			var row := LanBeacon.decode(bytes, _socket.get_packet_ip())
			if row.is_empty():
				continue
			if not include_self and String(row["origin"]) == LanBeacon.origin():
				continue
			row["at"] = now
			_hosts[row["origin"]] = row

	for origin in _hosts.keys():
		if now - int((_hosts[origin] as Dictionary)["at"]) > LanBeacon.WINDOW_MSEC:
			_hosts.erase(origin)

	var signature := _signature_of()
	if signature != _signature:
		_signature = signature
		changed.emit()


## Every host still inside the window, oldest field values and all.
##
## SORTED BY NAME AND THEN ADDRESS, which is not a nicety: the rows are pressable and a
## table that reorders itself as beacons arrive is a table where the row under a thumb is
## not the row that gets pressed. Name first because that is what a player is reading.
func hosts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for origin in _hosts:
		out.append((_hosts[origin] as Dictionary).duplicate())
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var an := String(a["name"]).to_lower()
		var bn := String(b["name"]).to_lower()
		if an != bn:
			return an < bn
		return String(a["address"]) < String(b["address"]))
	return out


## One host by origin, or an empty dictionary if it has gone quiet.
##
## A LOOKUP RATHER THAN A WALK OF `hosts()`, because the page asks this once per visible
## row per FRAME to tick its SEEN column -- and `hosts()` duplicates and sorts the lot
## every time it is called, which is the wrong shape to put inside a loop inside
## `_process`. The copy is still a copy: nothing outside this class writes the table.
func host(origin: String) -> Dictionary:
	if not _hosts.has(origin):
		return {}
	return (_hosts[origin] as Dictionary).duplicate()


## How long ago each host was last heard from, in whole seconds. What the SEEN column
## shows, and the honest thing to put where a browser would normally print a ping: this
## is a one-way datagram, so there is no round trip to time, and a made-up latency figure
## on a page whose whole history is about not faking things would be the worst possible
## column to add.
func seconds_since(row: Dictionary) -> int:
	return int(floor(float(Time.get_ticks_msec() - int(row.get("at", 0))) / 1000.0))


func _process(_delta: float) -> void:
	poll()


## The rendered table as one string. Excludes `at`, or every beacon would look like news.
func _signature_of() -> String:
	var parts: Array[String] = []
	for row in hosts():
		parts.append("%s|%s|%s|%d|%d|%d|%d|%d|%d|%d" % [row["origin"], row["address"],
				row["name"], row["map"], (row["size"] as Vector2i).x,
				(row["size"] as Vector2i).y, row["mode"], row["age"], row["slots"],
				row["taken"]])
	return "\n".join(parts)
