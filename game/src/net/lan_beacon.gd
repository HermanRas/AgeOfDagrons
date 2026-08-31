## THE "I AM HOSTING" BEACON, and the wire format both halves of discovery share
## (PLAN.md 12.1's open end; project owner, 2026-08-31: *"lets wire it up and make it
## live"*).
##
## **LAN IS THE WHOLE OF v1 AND THIS MUST NOT QUIETLY BECOME A MASTER SERVER.** A master
## server is a service somebody has to run and pay for and keep online; PLAN.md's
## multiplayer is two devices on a sofa. So a host shouts a small datagram at the
## broadcast address once a second and anybody listening hears it. Nothing is registered
## anywhere, nothing outlives the process, and a host that is switched off stops existing
## as far as every browser is concerned within `WINDOW_MSEC`.
##
## THE FORMAT LIVES WITH THE SENDER, which is why `encode`/`decode` are both here rather
## than one here and one in `LanBrowser`: two files owning two halves of one format is
## two places for a key to be renamed. `LanBrowser` reads these statics.
##
## ── WHAT IS ON THE WIRE, and why each field ─────────────────────────────────
##
## Everything but the name is already in the `MatchConfig` the host broadcasts to its
## lobby, which is the point -- a beacon is a SUBSET of that config and not a second
## description of a match that could disagree with the first. The name is the one new
## field, because today a host is an IP address and a browser listing four of those is a
## browser nobody can choose from.
##
## ⚠️ **IDS TRAVEL, NOT LABELS.** `map`, `mode` and `age` are the integers the config
## holds and the browser resolves them with its own `MapGenerator.type_name`,
## `MatchConfig.mode_name` and `GameDataRegistry.age_label`. Sending the rendered
## strings would have been fewer lines and would let a host on any build put arbitrary
## text in a browser's table -- see `_clean`, which is the other half of that argument.
##
## ⚠️ **THE ADDRESS IS NEVER TAKEN FROM THE PAYLOAD.** `LanBrowser` dials
## `PacketPeerUDP.get_packet_ip()` -- where the datagram actually came from -- so a
## beacon cannot name somebody else's machine and have a browser dial it. Everything in
## the payload is untrusted text from the network and is treated as such: capped in
## length, stripped of control characters, and displayed rather than acted on.
class_name LanBeacon
extends Node

## `Net.PORT + 1`, WRITTEN OUT rather than derived. An autoload is a node, not a class,
## so `Net.PORT` is not a constant expression and cannot be reached from here at parse
## time. The relationship is the thing to keep: one port for the session, the next one up
## for saying the session exists.
const PORT := 27016

## The address a beacon is shouted at. Overridable per call so a test can point one
## socket at another in the same process without depending on the machine having a
## broadcast-capable adapter -- see `tests/net/test_lan_discovery.gd`.
const BROADCAST_ADDRESS := "255.255.255.255"

## One beacon a second. Fast enough that a browser opened just now fills in before the
## player wonders whether it works, slow enough to be nothing at all next to the 18 KB
## snapshots this same network carries ten times a second once a match starts.
const INTERVAL_MSEC := 1000

## How long a host stays listed after its last beacon. **THIS IS WHY THE LIST DOES NOT
## FLICKER.** A datagram is allowed to go missing and one dropped packet must not make a
## row vanish and come back, so a host is kept for four beacons' worth of silence before
## it is dropped. See `LanBrowser`.
const WINDOW_MSEC := 4000

## The format's version. Bumped when a field changes meaning; `decode` refuses anything
## it does not recognise rather than reading a field that has moved.
const VERSION := 1

## Fields that are text from the network, and what they are allowed to be. A beacon is
## the one thing in this game that renders a string a stranger wrote, so the cap is not
## politeness -- an unbounded name is a row that pushes every other column off the page.
const MAX_NAME := 28
const MAX_PACKET := 1024


## This process's beacon, so a host browsing for other hosts does not find ITSELF.
##
## It is reachable: `Net.has_session()` is true for a host the moment a slot is opened
## and this page is reached from that very screen, so the host's own broadcast comes
## straight back to its own listener on every platform that loops broadcast back. A
## browser listing the machine it is running on is a browser that has already lost the
## player's trust.
##
## STATIC, so both halves of one process agree without being introduced to each other:
## whichever `LanBeacon` sent the packet, it is this process's packet. The process id is
## unique on a machine and the microsecond clock separates two runs of the same id, which
## is all this has to do -- it is an identity, not a secret.
static var _origin: String = ""


static func origin() -> String:
	if _origin.is_empty():
		_origin = "%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	return _origin


## What to call this device, when nobody has typed anything.
##
## The environment first because it is what the OWNER of the machine called it, which is
## the whole job here -- "Herman's table" is useful and "GenericDevice" is not. Android
## has neither variable and answers `get_model_name()`, which is a handset model rather
## than a name but is at least the right handset. `GenericDevice` is Godot's own answer
## when it does not know, so it is refused by name.
static func default_host_name() -> String:
	for key in ["COMPUTERNAME", "HOSTNAME"]:
		var named := OS.get_environment(key).strip_edges()
		if not named.is_empty():
			return _clean(named, MAX_NAME)
	var model := OS.get_model_name().strip_edges()
	if not model.is_empty() and model != "GenericDevice":
		return _clean(model, MAX_NAME)
	return "Host"


## The payload a hosting lobby broadcasts, built from the config it is offering.
##
## `taken`/`slots` is chairs out of chairs, not a headcount -- see `ServerBrowserPanel`'s
## SLOTS column. `port` rides along because a host bound somewhere other than `Net.PORT`
## (the suite does exactly that) is still a host worth finding, and a browser that
## assumed the default would dial the wrong one.
static func payload_for(cfg: MatchConfig, host_name: String, taken: int,
		port: int) -> Dictionary:
	var resolved := int(cfg.map_type)
	# THE RESOLVED TYPE, not the requested one, for `_invitation_terms`' reason: a random
	# pick reads as "Random" while the map is plainly a desert, and telling a stranger
	# something different from what they will play on is the one thing this page may not do.
	if cfg.map_data != null:
		resolved = int(cfg.map_data.meta.get("type", cfg.map_type))
	return {
		"aod": VERSION,
		"origin": origin(),
		"name": _clean(host_name, MAX_NAME),
		"map": resolved,
		"w": cfg.map_size.x,
		"h": cfg.map_size.y,
		"mode": int(cfg.mode),
		"age": cfg.starting_age,
		"slots": cfg.player_ids.size(),
		"taken": taken,
		"port": port,
	}


static func encode(payload: Dictionary) -> PackedByteArray:
	return JSON.stringify(payload).to_utf8_buffer()


## One received datagram as a row, or an empty dictionary for anything this does not
## trust. **EVERY REJECTION IS SILENT AND THAT IS DELIBERATE**: this socket is open to
## whatever the network sends it, and a browser that logged a line per malformed packet
## would be a browser somebody could fill a log with.
##
## `from_ip` comes from the transport, never from the payload -- see the class header.
static func decode(bytes: PackedByteArray, from_ip: String) -> Dictionary:
	if bytes.size() > MAX_PACKET or bytes.is_empty() or from_ip.is_empty():
		return {}
	# ⚠️ **`JSON.new().parse()` AND NOT `JSON.parse_string()`.** The static helper pushes an
	# engine ERROR for every packet it cannot read, which makes "silent" above a lie: this
	# socket is open to whatever the network sends it, so one malformed datagram a
	# millisecond is a log somebody can fill from across the room. The instance form
	# returns the error and says nothing. Caught in the suite, where a single deliberately
	# malformed fixture printed "Parse JSON failed" into an otherwise clean run.
	var reader := JSON.new()
	if reader.parse(bytes.get_string_from_utf8()) != OK:
		return {}
	if not (reader.data is Dictionary):
		return {}
	var d: Dictionary = reader.data
	if int(d.get("aod", 0)) != VERSION:
		return {}
	var host_origin := _clean(String(d.get("origin", "")), 64)
	if host_origin.is_empty():
		return {}
	# CLAMPED, NOT VALIDATED. An out-of-range age or map type resolves to a fallback name
	# through the same functions the rest of the game uses, so a nonsense beacon reads as
	# a strange row rather than crashing a page or being silently dropped -- and a silently
	# dropped one is how a genuine version skew becomes "the browser finds nothing".
	return {
		"origin": host_origin,
		"address": from_ip,
		"name": _clean(String(d.get("name", "")), MAX_NAME),
		"map": int(d.get("map", 0)),
		"size": Vector2i(clampi(int(d.get("w", 0)), 0, 4096),
				clampi(int(d.get("h", 0)), 0, 4096)),
		"mode": int(d.get("mode", 0)),
		"age": clampi(int(d.get("age", 1)), 1, 99),
		"slots": clampi(int(d.get("slots", 0)), 0, 99),
		"taken": clampi(int(d.get("taken", 0)), 0, 99),
		"port": clampi(int(d.get("port", 0)), 1, 65535),
	}


## Text from a stranger, made safe to put in a row.
##
## Control characters are stripped rather than escaped: a newline in a host name would
## make one row two rows tall and drag every column with it, and `\n` printed literally
## is noise. What is left is capped, because a `clip_text` label with a 400-character
## name is a label whose minimum width is the whole page.
static func _clean(text: String, limit: int) -> String:
	var out := ""
	for i in range(text.length()):
		var c := text.unicode_at(i)
		if c >= 32 and c != 127:
			out += String.chr(c)
		if out.length() >= limit:
			break
	return out.strip_edges()


# ── the advertising half ────────────────────────────────────────────────────

## Whatever the lobby last said it is offering. Held rather than rebuilt per beacon so
## the socket half knows nothing about `MatchConfig`, and so a lobby that changes nothing
## for a minute costs nothing per second.
var _payload: Dictionary = {}
var _socket: PacketPeerUDP = null
var _dest := BROADCAST_ADDRESS
var _due_at := 0


## Start shouting, or update what is being shouted. Idempotent: the lobby calls this from
## `_refresh_lobby`, which every path that changes anything ends at, so "the settings
## moved" and "start advertising" are one call.
##
## Returns OK, or the error the socket refused with -- which is worth surfacing rather
## than swallowing, because a device that cannot broadcast is a device nobody will find
## and the lobby's dial line is then the only way in.
## `dest`/`port` are settable for the same reason `SkirmishScreen.host_port` is: a real
## socket is the behaviour, faking one would test the fake, and a suite on the game's own
## ports fights the game the owner has open on the same machine. Nothing in the game
## passes either.
func advertise(payload: Dictionary, dest: String = BROADCAST_ADDRESS,
		port: int = PORT) -> Error:
	_payload = payload
	_dest = dest
	if _socket != null:
		return OK
	var socket := PacketPeerUDP.new()
	# THE FLAG IS THE WHOLE FEATURE. Without `set_broadcast_enabled` the OS refuses a
	# datagram addressed to 255.255.255.255 and `put_packet` answers ERR_UNAVAILABLE --
	# which presents as a browser that finds nothing, on both machines, with no error
	# anywhere near the browser.
	socket.set_broadcast_enabled(true)
	var err := socket.set_dest_address(dest, port)
	if err != OK:
		return err
	_socket = socket
	# ⚠️ **NOT SENT HERE.** The first beacon goes out on the first `_process`, which means
	# a screen built by `.new()` in a test never puts a packet on the wire -- and the
	# lobby tests open a REAL socket because "set a slot to Open" and "start listening"
	# are the same act. A suite that broadcast on the office LAN every time it ran would
	# be a suite nobody wants running.
	_due_at = Time.get_ticks_msec()
	set_process(true)
	return OK


func stop() -> void:
	set_process(false)
	if _socket != null:
		_socket.close()
		_socket = null
	_payload.clear()


func is_advertising() -> bool:
	return _socket != null


## One beacon, now, whatever the clock says.
##
## PUBLIC AND NOT ONLY CALLED FROM `_process`, for `LanBrowser.poll`'s reason: the test
## suite has no frame loop, so a test that had to wait for a timer would be a test
## asserting something about `Engine.max_fps`. It is also what a two-process bring-up
## calls to put a packet on the wire on demand.
##
## The result is deliberately not checked. A host that has just lost its adapter fails
## every send until it comes back, and a line per second about it would bury the log the
## bring-up is being read from -- the lobby's own dial line is where "this device has no
## network address" is already said, once.
func send_now() -> void:
	if _socket == null or _payload.is_empty():
		return
	_socket.put_packet(encode(_payload))


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if now < _due_at:
		return
	_due_at = now + INTERVAL_MSEC
	send_now()
