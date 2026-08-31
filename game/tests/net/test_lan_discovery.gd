## LAN discovery: the beacon format, the rolling window, and one real datagram
## (2026-08-31, PLAN.md 12.1's open end).
##
## ⚠️ **WHAT CANNOT BE TESTED HERE, AND WHY IT DOES NOT MATTER AS MUCH AS IT SOUNDS.**
## `test_net_remote`'s header records that two ENet peers cannot exist in one process,
## because a `multiplayer_peer` belongs to a SceneTree and this suite has one. UDP is not
## like that -- a `PacketPeerUDP` is its own socket and two of them in one process are two
## real sockets -- so the beacon and the browser genuinely do talk to each other below.
## What is faked is only the DESTINATION: the round trip goes over 127.0.0.1 rather than
## 255.255.255.255, so `set_broadcast_enabled` is the one line no assertion here reaches.
## That is what `dev_preview/preview_lan_discovery.gd` is for, and it is not a formality:
## without the flag the OS refuses the datagram outright and both machines see a browser
## that finds nothing, with no error anywhere near the browser.
##
## PORTS ARE THE SUITE'S OWN, never the game's. Both halves bind for real, so a suite on
## `LanBeacon.PORT` would fight a game the owner has open -- and would be FOUND by it,
## which is worse: a row in somebody's live server browser for a host that existed for a
## hundredth of a second.
extends TestCase

const _PORT := 47016

## Long enough for loopback and short enough that a failure is a failure rather than a
## hung terminal. A datagram to 127.0.0.1 is delivered by the kernel with no wire
## involved, so this is generous by two orders of magnitude.
const _DELIVERY_MSEC := 500

var beacon: LanBeacon
var browser: LanBrowser


func before_each() -> void:
	beacon = LanBeacon.new()
	browser = LanBrowser.new()
	# THE ONE CALLER THAT WANTS THIS. In the game a browser refuses its own process's
	# beacons -- a host browsing for hosts must not find itself -- and here there is only
	# one process to have.
	browser.include_self = true


func after_each() -> void:
	# Both hold real sockets and the next test wants the same port. A test that fails part
	# way through would otherwise take every later one with it, which is the shape
	# `test_skirmish_screen.after_each` already guards.
	beacon.stop()
	browser.stop()
	beacon.free()
	browser.free()


# ── the format ──────────────────────────────────────────────────────────────

func test_a_payload_survives_the_wire_and_comes_back_the_same() -> void:
	var cfg := MatchConfig.debug_generated(7, MapGenerator.Type.FOREST, 3)
	cfg.starting_age = 2
	var sent := LanBeacon.payload_for(cfg, "Kitchen phone", 2, 27015)
	var got := LanBeacon.decode(LanBeacon.encode(sent), "192.0.2.11")

	assert_eq(String(got["name"]), "Kitchen phone")
	assert_eq(int(got["slots"]), 3, "three players in the config, three chairs")
	assert_eq(int(got["taken"]), 2)
	assert_eq(int(got["age"]), 2)
	assert_eq(int(got["port"]), 27015)
	assert_eq(got["size"] as Vector2i, cfg.map_size)
	assert_eq(int(got["mode"]), int(MatchConfig.Mode.LAST_MAN_STANDING))


func test_the_map_type_on_the_wire_is_the_resolved_one() -> void:
	# `_invitation_terms`' rule, and it matters more here than there: `map_type` records
	# what was ASKED FOR, so a Random pick would advertise itself as "Random" while the
	# map is plainly a desert. Telling a stranger something different from what they will
	# play on is the one thing a browser may not do.
	var cfg := MatchConfig.debug_generated(11, MapGenerator.Type.RANDOM, 2)
	var got := LanBeacon.decode(
			LanBeacon.encode(LanBeacon.payload_for(cfg, "x", 1, 27015)), "192.0.2.1")
	assert_ne(int(got["map"]), int(MapGenerator.Type.RANDOM),
			"a generated map always has a real type: %s"
			% MapGenerator.type_name(int(got["map"]) as MapGenerator.Type))
	assert_eq(int(got["map"]), int(cfg.map_data.meta["type"]))


func test_ids_travel_and_labels_do_not() -> void:
	# The browser resolves `map`, `mode` and `age` with its OWN tables, so a host cannot
	# put arbitrary text in somebody's column. If any of these ever became a string, this
	# is the test that says so.
	var cfg := MatchConfig.debug_generated(1, MapGenerator.Type.ISLAND, 2)
	var wire := LanBeacon.payload_for(cfg, "n", 1, 1)
	for key in ["map", "mode", "age", "slots", "taken", "port", "w", "h"]:
		assert_true(wire[key] is int, "%s is an id, not a label" % key)


# ── what it refuses ─────────────────────────────────────────────────────────

func test_it_refuses_anything_it_does_not_recognise() -> void:
	# EVERY REJECTION IS SILENT AND RETURNS THE SAME EMPTY DICTIONARY. This socket is open
	# to whatever the network sends it.
	assert_true(LanBeacon.decode("not json at all".to_utf8_buffer(), "192.0.2.1").is_empty())
	assert_true(LanBeacon.decode("[1, 2, 3]".to_utf8_buffer(), "192.0.2.1").is_empty(),
			"valid JSON that is not an object")
	assert_true(LanBeacon.decode(PackedByteArray(), "192.0.2.1").is_empty())
	assert_true(LanBeacon.decode('{"aod": 99, "origin": "x"}'.to_utf8_buffer(),
			"192.0.2.1").is_empty(), "a version this build cannot read")
	assert_true(LanBeacon.decode('{"aod": 1}'.to_utf8_buffer(), "192.0.2.1").is_empty(),
			"no origin, so nothing to key a row on")

	# AN OVERSIZED PACKET IS DROPPED WITHOUT BEING PARSED, which is the point of checking
	# the size first: `JSON.parse_string` on a megabyte somebody sent us is the work.
	var fat := '{"aod": 1, "origin": "x", "name": "%s"}' \
			% "a".repeat(LanBeacon.MAX_PACKET * 2)
	assert_true(LanBeacon.decode(fat.to_utf8_buffer(), "192.0.2.1").is_empty())


func test_a_hostile_name_cannot_break_the_table() -> void:
	# The one place this game renders a string a stranger wrote. A newline would make one
	# row two rows tall and drag every column with it; an unbounded name is a `clip_text`
	# label whose minimum width is the whole page.
	var nasty := '{"aod": 1, "origin": "x", "name": "%s"}' % ("A\\nB" + "z".repeat(200))
	var got := LanBeacon.decode(nasty.to_utf8_buffer(), "192.0.2.1")
	assert_false(got.is_empty(), "it is rendered safely, not dropped")
	var shown := String(got["name"])
	assert_false(shown.contains("\n"), "no control characters survive")
	assert_true(shown.length() <= LanBeacon.MAX_NAME,
			"capped at %d, got %d" % [LanBeacon.MAX_NAME, shown.length()])


func test_the_address_comes_from_the_transport_and_never_from_the_payload() -> void:
	# ⚠️ THE SECURITY PROPERTY, and it is one line in `decode`. A beacon that could name
	# an address would be a beacon that makes somebody else's browser dial a machine of
	# its choosing -- the same shape as `Net._recv_colour_request` resolving the asker's
	# slot from the peer id rather than from what the packet claims.
	var lying := '{"aod": 1, "origin": "x", "address": "203.0.113.9"}'
	var got := LanBeacon.decode(lying.to_utf8_buffer(), "192.0.2.44")
	assert_eq(String(got["address"]), "192.0.2.44", "where it actually came from")


# ── the rolling window ──────────────────────────────────────────────────────
#
# Driven by poking `at` rather than by sleeping, for the reason `test_tick_cost`'s note
# gives about this workstation: a test that waited out `WINDOW_MSEC` would be a test
# asserting something about the scheduler.

func test_a_host_survives_a_lost_packet_and_not_a_lost_host() -> void:
	# **A BEACON IS A DATAGRAM AND DATAGRAMS ARE LOST.** A list that dropped a row the
	# first second a packet went missing would report a host as gone once a minute or so,
	# which is precisely the thing a player is watching this page to learn.
	_note("Study desktop", "192.0.2.7")
	assert_eq(browser.hosts().size(), 1)

	_age_everything(LanBeacon.WINDOW_MSEC / 2)
	browser.poll()
	assert_eq(browser.hosts().size(), 1, "one missed beacon is not a host going away")

	_age_everything(LanBeacon.WINDOW_MSEC)
	browser.poll()
	assert_eq(browser.hosts().size(), 0, "silence past the window is")


func test_refresh_starts_the_window_again_rather_than_clearing_the_list() -> void:
	# Clearing is the version that reads as a flicker, and it is the version that punishes
	# a player for pressing the button: every row goes and some of them come back.
	_note("Kitchen phone", "192.0.2.24")
	_age_everything(LanBeacon.WINDOW_MSEC - 200)

	browser.restart()
	browser.poll()
	assert_eq(browser.hosts().size(), 1, "still listed, and now with a full window")

	_age_everything(LanBeacon.WINDOW_MSEC - 200)
	browser.poll()
	assert_eq(browser.hosts().size(), 1,
			"which is what 'start the window again' has to mean to be worth a button")


func test_two_beacons_from_one_host_are_one_row() -> void:
	# Keyed on ORIGIN, not on address: a machine with two adapters shouts twice and is one
	# machine, and the row should name the address the packet we can hear came from.
	_note("Twin", "192.0.2.7", "same-origin")
	_note("Twin", "10.0.0.7", "same-origin")
	assert_eq(browser.hosts().size(), 1)
	assert_eq(String(browser.hosts()[0]["address"]), "10.0.0.7",
			"the most recent route to it is the one that reached us")


func test_hosts_are_ordered_so_a_row_does_not_move_under_a_thumb() -> void:
	# The rows are pressable and beacons arrive in whatever order the network feels like.
	# A table that reordered itself as they landed is a table where the row under a thumb
	# is not the row that gets pressed.
	_note("zeta", "192.0.2.3", "c")
	_note("alpha", "192.0.2.1", "a")
	_note("Mid", "192.0.2.2", "b")
	var names: Array[String] = []
	for row in browser.hosts():
		names.append(String(row["name"]))
	assert_eq(names, ["alpha", "Mid", "zeta"] as Array[String],
			"by name, case-insensitively")


# ── one real datagram ───────────────────────────────────────────────────────

func test_a_beacon_reaches_a_browser_through_a_real_socket() -> void:
	# Two `PacketPeerUDP`s in one process are two real sockets, unlike two ENet peers --
	# see the file header. Over 127.0.0.1, so the only untested line is the broadcast flag.
	assert_eq(browser.listen(_PORT), OK, "the suite's own port, not the game's")

	var cfg := MatchConfig.debug_generated(4, MapGenerator.Type.RIVER, 2)
	assert_eq(beacon.advertise(LanBeacon.payload_for(cfg, "Loopback", 1, 47015),
			"127.0.0.1", _PORT), OK)
	beacon.send_now()

	var waited := 0
	while browser.hosts().is_empty() and waited < _DELIVERY_MSEC:
		OS.delay_msec(10)
		waited += 10
		browser.poll()

	assert_eq(browser.hosts().size(), 1, "nothing arrived in %d ms" % waited)
	var row := browser.hosts()[0]
	assert_eq(String(row["name"]), "Loopback")
	assert_eq(String(row["address"]), "127.0.0.1", "from the transport, as ever")
	assert_eq(int(row["port"]), 47015, "the ENet port to dial, not the beacon's")


func test_a_browser_does_not_find_its_own_process() -> void:
	# ⚠️ `Net.has_session()` is true for a host the moment a slot is opened and the browser
	# is reached FROM that screen, so a host's own broadcast comes back to its own listener
	# on every platform that loops broadcast to local sockets. A browser listing the
	# machine it is running on has already lost the player's trust.
	browser.include_self = false
	assert_eq(browser.listen(_PORT), OK)

	var cfg := MatchConfig.debug_generated(4, MapGenerator.Type.RIVER, 2)
	beacon.advertise(LanBeacon.payload_for(cfg, "Myself", 1, 47015), "127.0.0.1", _PORT)
	beacon.send_now()

	var waited := 0
	while waited < 200:
		OS.delay_msec(10)
		waited += 10
		browser.poll()
	assert_eq(browser.hosts().size(), 0, "it heard itself and said nothing")


# ── helpers ─────────────────────────────────────────────────────────────────

## Put a host in the table the way an arriving packet would, without a socket.
func _note(host: String, address: String, origin: String = "") -> void:
	var payload := {
		"aod": LanBeacon.VERSION,
		"origin": origin if not origin.is_empty() else address,
		"name": host, "map": 1, "w": 96, "h": 96, "mode": 0, "age": 1,
		"slots": 2, "taken": 1, "port": 27015,
	}
	var row := LanBeacon.decode(LanBeacon.encode(payload), address)
	row["at"] = Time.get_ticks_msec()
	browser._hosts[row["origin"]] = row


## Pretend `msec` have gone by since every host's last beacon. White-box on purpose: the
## alternative is a test that sleeps for four seconds and still cannot say what it proved.
func _age_everything(msec: int) -> void:
	for origin in browser._hosts:
		var row: Dictionary = browser._hosts[origin]
		row["at"] = int(row["at"]) - msec
