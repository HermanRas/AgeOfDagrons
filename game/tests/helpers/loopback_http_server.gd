## A real HTTP server on 127.0.0.1, so a DOWNLOAD can be exercised without the internet.
##
## ## WHY THIS EXISTS (0.3a)
##
## `tests/net/test_pack_installer.gd` opens by saying the download is not tested and cannot
## be -- *"a test that needs the internet fails on a train"* -- so everything below the fetch
## is driven through `install_from_file()`. That was the right call and it leaves one hole
## that 0.3a lives in: **a resume is a property of the fetch itself**, and no amount of
## `install_from_file` reaches it.
##
## The way out is not the internet. It is a socket on loopback that speaks enough HTTP to be
## a server, and -- the part that matters -- **can be told to fail in the exact way the real
## one failed**: drop the connection part way through the body, unprovoked, the way
## `art_base_v1.zip` died at about 3 MB on a good wired connection on 2026-09-12.
##
## ## WHAT IT SPEAKS, AND WHAT IT DELIBERATELY DOES NOT
##
## `GET`, `Content-Length`, and `Range: bytes=N-` answered with `206` and a `Content-Range`.
## That is the whole of the contract 0.3a depends on. It is not a web server: no keep-alive
## (one request per connection, then close), no chunked encoding, no HEAD, no TLS.
##
## ⚠️ **TLS IS THE ONE OMISSION WORTH SAYING OUT LOUD.** The real packs are fetched over
## https and `PackDef` refuses any url that is not -- deliberately, so a rewritten manifest
## cannot downgrade the transport. This server is `http://127.0.0.1:<port>/`, so anything
## driving it is testing `PackInstaller._download()` and NOT `PackDef`'s url rules. Those are
## checked in the suite, where they belong, and the two must not be confused for each other.
##
## ## USE
##
##     var server := LoopbackHttpServer.new()
##     add_child(server)
##     server.body = some_bytes
##     server.cut_after_bytes = 4096        # die part way through, like the real one did
##     var err := server.start()
##     ... await a download of server.url_for("pack.zip") ...
##     print(server.requests)               # what was actually asked for, Range included
##
## Every request is recorded in `requests` **before** it is answered, so a run that dies
## still says what it was asked. The whole point of several of these checks is the SECOND
## request's `Range` header, and a log written on the way out would not have it.
class_name LoopbackHttpServer
extends Node

## Emitted once per request, after it has been answered (or cut). The dictionary is the same
## shape as a `requests` row.
signal served(request: Dictionary)

const HOST := "127.0.0.1"

## Longest request head accepted, headers and all. A client that sends more than this
## without a blank line is not one of ours, and the guard stops a runaway loop from eating
## memory in a test process.
const MAX_HEAD_BYTES := 8192

## The bytes this server is serving. Set before `start()`.
var body: PackedByteArray = PackedByteArray()

## Answer `Range` with `206`, or ignore it and answer `200` with the whole body.
##
## ⚠️ **`false` IS A REAL SERVER'S BEHAVIOUR AND NOT A SILLY CASE.** A cache or a proxy that
## does not do ranges answers `200` with the entire file, and a client that appended that to
## what it already had would produce a file of the right length made of the wrong bytes --
## which the checksum catches, but only after the whole download has been paid for twice.
## The client has to notice the `200` and start again, and this flag is what proves it does.
var honour_range := true

## Cut the connection after this many bytes of THIS RESPONSE's payload. 0 serves it whole.
##
## Counted per response, not per file: a cut at 4096 on a request that already carries
## `Range: bytes=8192-` closes after serving bytes 8192..12287.
var cut_after_bytes := 0

## WHICH requests to cut, 1-based, when `cut_after_bytes` is set. Empty cuts every response.
##
## ⚠️ **THIS IS WHAT MAKES A RESUME PROVABLE AT ALL**, and it is not a convenience. To show
## that a client resumed, at least one chunk must LAND before one dies -- a client whose very
## first request is cut has nothing banked and correctly asks for byte 0 again, which is
## indistinguishable from not resuming. `[2]` means "let the first chunk through, then break
## the second", which is the smallest arrangement that can tell the two apart.
var cut_on_requests: Array[int] = []

## Force a status code instead of deciding one. 0 decides normally (200, or 206 for a range).
var status_override := 0

## Answer the first N requests with a `302` pointing at this same server, so the client has
## to follow a redirect before it gets any bytes.
##
## ⚠️ **THIS IS NOT AN EXOTIC CASE -- IT IS WHAT A CDN DOES**, and the question it answers
## cannot be answered by reading: **does `HTTPRequest` still send our `Range` header after
## following a redirect?** If it does not, every resume quietly turns back into a download
## from byte zero that still ends with the right file and the right checksum -- correct, and
## costing exactly what 0.3a exists to stop costing. A redirected request that arrives with
## `range_start == -1` is that bug, and it is why -1 and 0 are kept apart.
var redirect_first := 0

## Every request seen, oldest first. Keys: `method`, `path`, `range_start` (-1 when the
## request carried no `Range`), `status`, `sent` (payload bytes actually written), `cut`.
var requests: Array[Dictionary] = []

var _server: TCPServer = null
var _clients: Array[Dictionary] = []


## Bind an ephemeral port on loopback. Returns `OK`, or the error `TCPServer.listen` gave.
##
## PORT 0 ON PURPOSE: the OS picks a free one and `port()` reports it. A hardcoded port is
## the classic way for two checks on one machine -- or a rerun after a crash -- to collide
## with `ERR_ALREADY_IN_USE` and read as the feature being broken.
func start() -> Error:
	_server = TCPServer.new()
	var err := _server.listen(0, HOST)
	if err != OK:
		_server = null
		return err
	set_process(true)
	return OK


func stop() -> void:
	for client in _clients:
		var peer: StreamPeerTCP = client["peer"]
		peer.disconnect_from_host()
	_clients.clear()
	if _server != null:
		_server.stop()
		_server = null
	set_process(false)


func port() -> int:
	if _server == null:
		return 0
	return _server.get_local_port()


## The url a client should fetch. `name` is decoration -- every path serves `body` -- but it
## is logged, so a check driving two packs can tell the requests apart.
func url_for(name: String = "pack.bin") -> String:
	return "http://%s:%d/%s" % [HOST, port(), name]


func _process(_delta: float) -> void:
	poll()


## Accept and answer whatever is pending. Called every frame by `_process`, and exposed
## because the suite's runner calls test methods with no `await` -- a synchronous test that
## ever needs this can drive it by hand the way `test_lan_discovery` drives `LanBrowser`.
func poll() -> void:
	if _server == null:
		return
	while _server.is_connection_available():
		_clients.append({"peer": _server.take_connection(), "head": PackedByteArray()})

	var still_open: Array[Dictionary] = []
	for client in _clients:
		if _serve(client):
			continue          # answered and closed
		still_open.append(client)
	_clients = still_open


## One client. Returns true once it has been answered and disconnected.
func _serve(client: Dictionary) -> bool:
	var peer: StreamPeerTCP = client["peer"]
	peer.poll()
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return true

	var available := peer.get_available_bytes()
	if available > 0:
		var chunk: Array = peer.get_data(available)
		if int(chunk[0]) == OK:
			var head: PackedByteArray = client["head"]
			head.append_array(chunk[1])
			client["head"] = head

	var head_bytes: PackedByteArray = client["head"]
	var text := head_bytes.get_string_from_utf8()
	if not text.contains("\r\n\r\n"):
		if head_bytes.size() > MAX_HEAD_BYTES:
			peer.disconnect_from_host()
			return true
		return false          # still arriving

	_answer(peer, text)
	return true


func _answer(peer: StreamPeerTCP, head: String) -> void:
	var lines := head.split("\r\n")
	var first := lines[0].split(" ")
	var asked := _range_of(lines)
	var record := {
		"method": first[0] if first.size() > 0 else "",
		"path": first[1] if first.size() > 1 else "",
		"range_start": asked.x,
		"range_end": asked.y,
		"status": 0,
		"sent": 0,
		"cut": false,
	}
	requests.append(record)

	# A redirect, before any thought is given to ranges or bodies. Recorded like any other
	# request, so a caller can see the Range it did (or did not) carry.
	if requests.size() <= redirect_first:
		var moved := "HTTP/1.1 302 Found\r\n"
		moved += "Location: %s\r\n" % url_for("redirected.bin")
		moved += "Content-Length: 0\r\n"
		moved += "Connection: close\r\n\r\n"
		peer.put_data(moved.to_utf8_buffer())
		record["status"] = 302
		peer.poll()
		peer.disconnect_from_host()
		served.emit(record)
		return

	var total := body.size()
	var start := 0
	var status := 200
	if asked.x >= 0 and honour_range:
		start = asked.x
		status = 206
	if status_override > 0:
		status = status_override

	# A range that starts at or past the end. 416 is the honest answer and the client has to
	# cope with it, because a `.part` the same size as the pack is exactly what an
	# interruption after the last byte but before the rename leaves behind.
	if start >= total and status == 206:
		status = 416
		start = 0

	var payload := PackedByteArray()
	if status == 200:
		payload = body
	elif status == 206:
		# ⚠️ **THE END OF THE RANGE IS HONOURED, AND THE FIRST VERSION OF THIS FILE IGNORED
		# IT.** `bytes=0-29999` was answered with everything from byte 0, so a client asking
		# for twenty chunks got the whole file in one response -- and the check built on top
		# reported "1 request" and no resume, which reads exactly like the installer failing
		# to chunk. A fixture that quietly serves more than it was asked for cannot test a
		# client that asks for less.
		var last: int = total - 1 if asked.y < 0 else mini(asked.y, total - 1)
		payload = body.slice(start, last + 1)

	var header := "HTTP/1.1 %d %s\r\n" % [status, _reason(status)]
	header += "Content-Length: %d\r\n" % payload.size()
	header += "Accept-Ranges: bytes\r\n"
	if status == 206:
		header += "Content-Range: bytes %d-%d/%d\r\n" % [start, start + payload.size() - 1, total]
	if status == 416:
		header += "Content-Range: bytes */%d\r\n" % total
	header += "Connection: close\r\n\r\n"
	peer.put_data(header.to_utf8_buffer())

	# `requests` already holds this request, so its size is this request's 1-based number.
	var chosen := cut_on_requests.is_empty() or cut_on_requests.has(requests.size())
	var to_send := payload
	if cut_after_bytes > 0 and chosen and cut_after_bytes < payload.size():
		to_send = payload.slice(0, cut_after_bytes)
		record["cut"] = true
	if to_send.size() > 0:
		peer.put_data(to_send)

	record["status"] = status
	record["sent"] = to_send.size()

	# ⚠️ FLUSH BEFORE CLOSING, or the cut swallows bytes the test believes were sent.
	# `disconnect_from_host()` on a peer with data still queued discards it, so a check
	# measuring "the client kept the first 4096 bytes" would be measuring this instead.
	peer.poll()
	peer.disconnect_from_host()
	served.emit(record)


## `bytes=N-M` -> (N, M). `bytes=N-` -> (N, -1), meaning "to the end".
##
## `x` is -1 when there is no `Range` header at all, which is a different answer from 0 and
## the two must not be collapsed: 0 is a client asking for the whole file by range, and -1 is
## a first attempt with no range on it.
static func _range_of(lines: PackedStringArray) -> Vector2i:
	for line in lines:
		var lower := line.to_lower()
		if not lower.begins_with("range:"):
			continue
		var value := lower.split(":", true, 1)[1].strip_edges()
		if not value.begins_with("bytes="):
			return Vector2i(-1, -1)
		var spec := value.substr("bytes=".length()).split("-")
		if spec.size() < 1 or not spec[0].is_valid_int():
			return Vector2i(-1, -1)
		var last := -1
		if spec.size() > 1 and spec[1].is_valid_int():
			last = int(spec[1])
		return Vector2i(int(spec[0]), last)
	return Vector2i(-1, -1)


static func _reason(status: int) -> String:
	match status:
		200: return "OK"
		206: return "Partial Content"
		404: return "Not Found"
		416: return "Range Not Satisfiable"
		500: return "Internal Server Error"
		_: return "Unknown"
