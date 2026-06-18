# C3 Godot Utils
# v4.2.2
# File revision: 2026-06-05

extends Node

## An HTTPRequest-style node for consuming Server-Sent Event (SSE) streams.
##
## Where [code]HTTPRequest[/code] fires [code]request_completed[/code] once with
## the whole body, [code]SSERequest[/code] emits [code]event_received[/code]
## repeatedly as each event arrives, then [code]finished[/code] when the stream
## closes.[br][br]
##
## [signal event_received] surfaces the [code]data:[/code] and
## [code]event:[/code] fields. [code]event_type[/code] defaults to
## [code]"message"[/code] when no [code]event:[/code] line is present, per the
## SSE spec. Events with no [code]data:[/code] lines (e.g. bare keep-alives or
## [code]id:[/code]-only blocks) are dropped silently. The [code]id:[/code] and
## [code]retry:[/code] fields are ignored because this class does not
## auto-reconnect.

## Headers parsed; the response code and headers are now known.
signal stream_started(response_code: int, headers: PackedStringArray)
## One SSE event arrived. `data` is the concatenated `data:` field(s).
## `event_type` is the `event:` field value, or `"message"` if absent.
signal event_received(data: String, event_type: String)
## The stream closed cleanly (socket end or server hang-up).
signal finished
## The server responded with a non-2xx status. Carries the full (non-SSE)
## response body — typically a JSON error payload — once it has been read.
## Emitted instead of [signal finished]; [signal stream_started] still fires
## first so the response code is available either way.
signal response_error(code: int, body: String)
## Something went wrong before or during the stream.
signal request_failed(reason: String)

enum _State { IDLE, CONNECTING, REQUESTING, STREAMING, ERROR_BODY }

var _client := HTTPClient.new()
var _state := _State.IDLE
# Raw, undecoded bytes off the socket. Kept as bytes (not a String) so a
# multi-byte UTF-8 character split across two reads is reassembled before
# decoding — decoding per-chunk would mangle the straddling character.
var _buffer := PackedByteArray()
var _response_code := 0

# Request parameters, captured at request() time and used once CONNECTED.
var _host := ""
var _port := -1
var _use_ssl := false
var _path := ""
var _headers: PackedStringArray = []
var _method := HTTPClient.METHOD_GET
var _body := ""


func _ready() -> void:
	# Idle until a request is in flight; no point polling a closed client.
	set_process(false)


func _exit_tree() -> void:
	_client.close()


## Mirrors [code]HTTPRequest.request()[/code]: give it a full URL and it streams
## the response. Returns [code]OK[/code] on a successful start, or an error code
## if busy / malformed.
func request(
	url: String,
	custom_headers: PackedStringArray = [],
	method: HTTPClient.Method = HTTPClient.METHOD_GET,
	request_body: String = "",
) -> Error:
	if _state != _State.IDLE:
		return ERR_BUSY

	if not _parse_url(url):
		return ERR_INVALID_PARAMETER

	_headers = custom_headers
	_method = method
	_body = request_body
	_buffer = PackedByteArray()

	var tls := TLSOptions.client() if _use_ssl else null
	var err := _client.connect_to_host(_host, _port, tls)
	if err != OK:
		return err

	_state = _State.CONNECTING
	set_process(true)
	return OK


# Minimal scheme://host[:port][/path?query] parse. Userinfo (user:password@host)
# is not supported.
func _parse_url(url: String) -> bool:
	_use_ssl = url.begins_with("https://")
	if not _use_ssl and not url.begins_with("http://"):
		return false

	var rest := url.trim_prefix("https://").trim_prefix("http://")
	var slash := rest.find("/")
	var authority := rest if slash == -1 else rest.substr(0, slash)
	_path = "/" if slash == -1 else rest.substr(slash)

	_port = 443 if _use_ssl else 80
	var colon := authority.find(":")
	if colon == -1:
		_host = authority
	else:
		_host = authority.substr(0, colon)
		_port = authority.substr(colon + 1).to_int()

	if _host == "localhost":
		push_warning(
			(
				'C3SSERequest: "localhost" may resolve to ::1 (IPv6) on '
				+ "Windows, causing connection failures if the server listens "
				+ 'only on IPv4. Use "127.0.0.1" instead.'
			)
		)

	return not _host.is_empty()


func _process(_delta: float) -> void:
	const CONNECT_ERRORS := [
		HTTPClient.STATUS_CANT_CONNECT,
		HTTPClient.STATUS_CANT_RESOLVE,
		HTTPClient.STATUS_CONNECTION_ERROR,
		HTTPClient.STATUS_TLS_HANDSHAKE_ERROR,
	]
	_client.poll()
	var client_status := _client.get_status()

	match _state:
		_State.CONNECTING:
			if client_status == HTTPClient.STATUS_CONNECTED:
				_send_request()
			elif client_status in CONNECT_ERRORS:
				_fail("Could not connect to %s:%d." % [_host, _port])
			# STATUS_RESOLVING / STATUS_CONNECTING: still working; wait a frame.

		_State.REQUESTING:
			match client_status:
				HTTPClient.STATUS_BODY:
					_response_code = _client.get_response_code()
					stream_started.emit(
						_response_code, _client.get_response_headers()
					)
					# A non-2xx body is a regular (non-SSE) payload — usually a
					# JSON error. Collect it raw rather than parsing SSE events.
					_state = (
						_State.STREAMING
						if _is_ok(_response_code)
						else _State.ERROR_BODY
					)
				HTTPClient.STATUS_CONNECTED:
					# Response carried no body (e.g. 204). Started and done.
					_response_code = _client.get_response_code()
					stream_started.emit(
						_response_code, _client.get_response_headers()
					)
					if _is_ok(_response_code):
						_finish()
					else:
						_reset()
						response_error.emit(_response_code, "")
				HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_DISCONNECTED:
					_fail("Connection lost while awaiting response.")

		_State.STREAMING:
			_stream_step()

		_State.ERROR_BODY:
			_error_body_step()


func _send_request() -> void:
	var err := _client.request(_method, _path, _headers, _body)
	if err != OK:
		_fail("Failed to send request (error %d)." % err)
		return
	_state = _State.REQUESTING


func _is_ok(code: int) -> bool:
	return code >= 200 and code < 300


func _stream_step() -> void:
	# Drain everything the OS has buffered this frame, not just one chunk, so a
	# fast burst doesn't trickle out one event per frame. Chunks land on
	# arbitrary byte boundaries, so accumulate raw bytes and defer decoding to
	# _drain_buffer(), which slices on the ASCII event delimiter.
	while true:
		var chunk := _client.read_response_body_chunk()
		if chunk.size() == 0:
			break
		_buffer.append_array(chunk)

	_drain_buffer()

	# Body status drops once the server closes its end: stream is over.
	if _client.get_status() != HTTPClient.STATUS_BODY:
		_finish()


# Accumulate a non-2xx response body (a plain payload, not SSE) and hand it off
# once the server closes its end.
func _error_body_step() -> void:
	while true:
		var chunk := _client.read_response_body_chunk()
		if chunk.size() == 0:
			break
		_buffer.append_array(chunk)

	if _client.get_status() != HTTPClient.STATUS_BODY:
		_finish_error_body()


func _finish_error_body() -> void:
	# The whole body is in hand now, so decode it in one pass — no chunk
	# boundary can split a character once every byte has arrived.
	var body := _buffer.get_string_from_utf8()
	_reset()
	response_error.emit(_response_code, body)


# Carve complete `\n\n`-delimited events out of the byte buffer and dispatch
# each. The delimiter is pure ASCII (0x0A 0x0A), so it's located at the byte
# level without decoding; only a fully sliced-out event is decoded, and that
# event never splits a UTF-8 character because its boundary is an ASCII newline.
# Trailing partial bytes (an incomplete event, possibly mid-character) stay in
# the buffer for the next read. Reassigning a member var here (unlike a by-value
# local) actually sticks.
func _drain_buffer() -> void:
	var sep := _find_event_boundary()
	while sep != -1:
		var raw_event := _buffer.slice(0, sep).get_string_from_utf8()
		_buffer = _buffer.slice(sep + 2)
		_emit_event(raw_event)
		sep = _find_event_boundary()


# Byte offset of the first `\n\n` (0x0A 0x0A) in the buffer, or -1 if absent.
func _find_event_boundary() -> int:
	var nl := _buffer.find(0x0A)
	while nl != -1 and nl + 1 < _buffer.size():
		if _buffer[nl + 1] == 0x0A:
			return nl
		nl = _buffer.find(0x0A, nl + 1)
	return -1


func _emit_event(raw_event: String) -> void:
	# data: lines are collected; id: and retry: are ignored.
	# Lines beginning with ":" are comments (servers use them as keep-alives).
	var data_lines: PackedStringArray = []
	var event_type := "message"
	for line in raw_event.split("\n"):
		if line.begins_with(":"):
			continue
		if line.begins_with("data:"):
			var value := line.substr(5)
			# Spec: a single leading space after the colon is stripped.
			if value.begins_with(" "):
				value = value.substr(1)
			data_lines.append(value)
		elif line.begins_with("event:"):
			var value := line.substr(6)
			if value.begins_with(" "):
				value = value.substr(1)
			event_type = value

	if data_lines.is_empty():
		return
	event_received.emit("\n".join(data_lines), event_type)


func _finish() -> void:
	# A server may end the last event without a trailing blank line; flush it.
	# The stream is over, so every byte is here — decode the tail in one pass.
	var tail := _buffer.get_string_from_utf8()
	if not tail.strip_edges().is_empty():
		_emit_event(tail)
	_reset()
	finished.emit()


func _fail(reason: String) -> void:
	_reset()
	request_failed.emit(reason)


func _reset() -> void:
	_client.close()
	_buffer = PackedByteArray()
	_state = _State.IDLE
	set_process(false)
