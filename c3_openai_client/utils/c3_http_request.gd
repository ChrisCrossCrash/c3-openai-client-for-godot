# C3 HTTP Request
# v0.4.0
# Modified from:
# https://github.com/ChrisCrossCrash/c3-http-request/blob/99baab0bc40e7ad9c33244a768cf72d763b0fd21/c3_http_request/c3_http_request.gd

# MODIFIED: Removed global class_name to prevent conflicts.
# class_name C3Http
## General-purpose async HTTP client that requires no scene tree.
##
## Call the static [method request] from anywhere — no [Node] to add or
## configure. Every call [code]await[/code]s a [Response] carrying
## [member Response.ok] as a single failure check that covers transport
## errors, timeouts, and non-2xx statuses alike.

## The installed version of this addon, e.g. for logging or feature gating.
const VERSION := "v0.4.0"

static var _impl: _Impl = _Impl.new()


func _init() -> void:
	push_warning(
		"C3Http is not meant to be instantiated like Godot's native "
		+ "HTTPRequest. Call C3Http.request() directly."
	)


## Sends an HTTP request to [param url] and returns the response. [br]
## [param custom_headers] are sent alongside any headers injected by
## [member Options.accept_gzip]. [br]
## [param method] is an [enum HTTPClient.Method] value; defaults to
## [code]METHOD_GET[/code]. [br]
## [param request_data] is the raw request body string. [br]
## [param options] controls timeout, redirects, and other per-request
## settings; [code]null[/code] uses all defaults.
static func request(
	url: String,
	custom_headers: PackedStringArray = PackedStringArray(),
	method: HTTPClient.Method = HTTPClient.METHOD_GET,
	request_data: String = "",
	options: Options = null
) -> Response:
	var opts: Options = options if options != null else Options.new()
	return await _impl.request(
		url, custom_headers, method, request_data, opts
	)


## Sends an HTTP request with a raw byte-array body, like [method request] but
## the body is sent as-is without UTF-8 encoding. Use for binary payloads
## (encoded files, serialized data, custom binary protocols). [br]
## [param request_data_raw] is the raw request body bytes. [br]
## [param method] defaults to [code]METHOD_POST[/code]; a raw body is ignored
## on [code]METHOD_GET[/code]. [br]
## See [method request] for the remaining parameters.
static func request_raw(
	url: String,
	custom_headers: PackedStringArray = PackedStringArray(),
	method: HTTPClient.Method = HTTPClient.METHOD_POST,
	request_data_raw: PackedByteArray = PackedByteArray(),
	options: Options = null
) -> Response:
	var opts: Options = options if options != null else Options.new()
	return await _impl.request(
		url, custom_headers, method, request_data_raw, opts
	)


## Per-request configuration. Defaults match [HTTPRequest] node defaults.
class Options:
	## Maximum seconds to wait for a response. [code]0.0[/code] disables the timeout.
	var timeout: float = 0.0
	## Maximum response body size in bytes. [code]-1[/code] is unlimited.
	var body_size_limit: int = -1
	## Size in bytes of the buffer used to read the response body off the socket
	## (via [method HTTPClient.set_read_chunk_size]). These are raw, as-received
	## bytes — [i]before[/i] decompression — so for a compressed response this
	## bounds the compressed read, not the decoded output. Lower values reduce
	## peak memory use during large downloads.
	var download_chunk_size: int = 65536
	## When [code]true[/code], sends [code]Accept-Encoding: gzip[/code]
	## and decompresses the response body automatically. Applies to
	## [member download_file] downloads too: compressed bytes are streamed through
	## the decompressor straight to disk, so the file holds the decoded content.
	## [br][br]
	## When [code]false[/code], no [code]Accept-Encoding[/code] header is sent and
	## no decompression is performed (matching [HTTPRequest]). Note this is
	## [i]not[/i] the same as refusing compression: sending no
	## [code]Accept-Encoding[/code] tells the server any encoding is acceptable, so
	## it may still return a [code]Content-Encoding: gzip[/code] body. You then
	## receive it exactly as sent — the raw, still-compressed bytes, for you to
	## decode. To actually forbid compression, set your own
	## [code]Accept-Encoding: identity[/code] in [code]custom_headers[/code]. A
	## caller-supplied [code]Accept-Encoding[/code] always takes precedence and
	## suppresses the automatic one.
	## [br][br]
	## Only [code]gzip[/code] is requested and decoded — never [code]deflate[/code],
	## which is where this differs from [HTTPRequest] ([HTTPRequest] advertises both).
	## HTTP [code]deflate[/code] is ambiguous: the spec says it is zlib-wrapped
	## (RFC 1950), but many servers send raw deflate (RFC 1951) instead, and the two
	## cannot be told apart reliably. Native [HTTPRequest] assumes zlib-wrapped and
	## fails to decode raw-deflate responses — a rare bug that is hard to trace
	## because it only surfaces against the uncommon servers that send raw deflate.
	## C3Http sidesteps it by never requesting deflate at all; gzip is
	## near-universal and brotli covers the rest, so deflate is effectively a rounding
	## error on the modern web. If you genuinely need it, request it via
	## [code]custom_headers[/code] and decode the bytes yourself.
	var accept_gzip: bool = true
	## Maximum number of redirects to follow. [code]0[/code] disables following.
	var max_redirects: int = 8
	## When [code]true[/code], the polling loop runs on a dedicated background
	## thread that polls at OS speed rather than once per rendered frame, lowering
	## latency for fast endpoints and large or streaming downloads. The public
	## [code]await[/code] API is unchanged, and this falls back to the cooperative
	## loop on export templates without thread support.
	## [br][br]
	## The [member on_sse_event], [member on_progress], and
	## [member on_status_changed] callbacks are automatically marshaled back to the
	## main thread, so they stay safe to touch the scene tree. Marshaling uses
	## [code]call_deferred[/code], which would normally let a callback run on a
	## [i]later[/i] frame — but this client drains all pending callbacks before the
	## [code]await[/code] resolves. So any state a callback mutates is fully settled
	## by the time the response comes back, and the result is identical whether or
	## not threading is on:
	## [codeblock]
	## # Count the connection-status changes via a callback.
	## var status_changes: Array[int] = []
	## var opts := C3Http.Options.new()
	## opts.use_threads = true
	## opts.on_status_changed = func(status: HTTPClient.Status) -> void:
	##     status_changes.append(status)
	##
	## await C3Http.request("https://example.com",
	##     PackedStringArray(), HTTPClient.METHOD_GET, "", opts)
	##
	## # Every status change has already fired — none is still queued for a later
	## # frame — so this prints the same count with use_threads true or false.
	## print(status_changes.size())
	## [/codeblock]
	var use_threads: bool = false
	## Path to write the response body to on disk. When non-empty,
	## [member Response.body] is empty and the data is in the file. The file is
	## created only once the response body starts arriving, so a request that fails
	## while resolving, connecting, or sending leaves the path untouched — never
	## truncating an existing file it will not fill. If the transfer fails after
	## writing has begun (timeout, cancellation, a decode error, or exceeding
	## [member body_size_limit]), the partial file is removed.
	var download_file: String = ""
	## TLS options for HTTPS connections. [code]null[/code] uses
	## [method TLSOptions.client] (validates the server certificate). Override
	## with [method TLSOptions.client_unsafe] for self-signed certificates. [br][br]
	## If you set a [member session], leaving this [code]null[/code] (the default)
	## needs no extra thought — pooling just works. But if you [i]do[/i] set a
	## custom [TLSOptions], you must reuse the same instance for every call that
	## shares the session: connections are pooled by this object's identity, so a
	## newly constructed [TLSOptions] per request produces a different pool key
	## each time and silently defeats connection reuse.
	var tls_options: TLSOptions = null
	## Host of an HTTP proxy to route plain [code]http://[/code] requests through.
	## Empty means a direct connection for HTTP. Has no effect on [code]https://[/code]
	## requests — set [member https_proxy_host] for those.
	var http_proxy_host: String = ""
	## Port of the proxy named by [member http_proxy_host]. Ignored when
	## [member http_proxy_host] is empty.
	var http_proxy_port: int = -1
	## Host of an HTTPS proxy to tunnel [code]https://[/code] requests through.
	## Empty means a direct connection for HTTPS. Has no effect on [code]http://[/code]
	## requests — set [member http_proxy_host] for those.
	var https_proxy_host: String = ""
	## Port of the proxy named by [member https_proxy_host]. Ignored when
	## [member https_proxy_host] is empty.
	var https_proxy_port: int = -1
	## Token for cancelling this request from another coroutine or signal
	## handler. [code]null[/code] means no cancellation support.
	var cancellation_token: CancellationToken = null
	## Optional [Callable] invoked once per Server-Sent Event as the response
	## streams in, as [code]on_sse_event.call(data: String, event_type: String,
	## last_event_id: String)[/code]. [code]last_event_id[/code] is the stream's
	## current [code]id:[/code] cursor: it persists across events per the SSE spec,
	## so an event with no [code]id:[/code] line still reports the most recent one
	## (echo it as a [code]Last-Event-ID[/code] header to resume after a drop; see
	## also [member Response.sse_retry_ms] for the suggested backoff). When set,
	## a 2xx response body is parsed as an SSE stream rather than collected:
	## [member Response.body] stays empty and [method C3Http.request]
	## resolves only when the stream closes (use [member cancellation_token] to
	## stop it early). While streaming, [member accept_gzip] and
	## [member download_file] are ignored, and [member timeout] becomes an idle
	## timeout (maximum seconds between events) rather than a total deadline. A
	## non-2xx response is collected normally, so [member Response.ok],
	## [member Response.error], and the error body still work as usual. Both LF
	## ([code]\n\n[/code]) and CRLF ([code]\r\n\r\n[/code]) event delimiters are
	## supported.
	var on_sse_event: Callable = Callable()
	## Optional [Callable] invoked as the response body downloads, as
	## [code]on_progress.call(bytes_received: int, total_bytes: int)[/code].
	## [code]bytes_received[/code] is the cumulative byte count;
	## [code]total_bytes[/code] is the [code]Content-Length[/code], or
	## [code]-1[/code] when unknown (e.g. a chunked response). Fires once per
	## non-empty chunk for both in-memory and [member download_file] downloads.
	## Has no effect in SSE mode (see [member on_sse_event]), where
	## [member on_sse_event] is the incremental signal instead.
	var on_progress: Callable = Callable()
	## Optional [Callable] invoked as the underlying connection advances, as
	## [code]on_status_changed.call(status: HTTPClient.Status)[/code] — one of
	## [code]STATUS_RESOLVING[/code], [code]STATUS_CONNECTING[/code],
	## [code]STATUS_CONNECTED[/code], [code]STATUS_REQUESTING[/code],
	## [code]STATUS_BODY[/code], etc. Fires once per change, in every mode
	## (including SSE), and repeats the cycle for each hop when redirects are
	## followed. Purely observational: the request's outcome is still reported via
	## the returned [Response]. Very brief intermediate states may be coalesced.
	var on_status_changed: Callable = Callable()
	## Optional [Session] for HTTP keep-alive connection reuse. When set, idle
	## connections to the same host are pooled and reused across calls, reducing
	## latency for repeated requests to the same endpoint. [br][br]
	## [code]null[/code] (the default) disables pooling: each call opens a fresh
	## connection. Create a [Session] once and share it across calls that target
	## the same set of hosts. [br][br]
	## If you also set a custom [member tls_options], share that one [TLSOptions]
	## instance across the pooled calls too, or connection reuse is defeated. The
	## default [code]null[/code] [member tls_options] needs no such care. See
	## [member tls_options].
	var session: Session = null


## The response returned by [method C3Http.request].
class Response:
	## [code]true[/code] when a response was received with a 2xx status code.
	var ok := true
	## Error details when [member ok] is [code]false[/code]; [code]null[/code] otherwise.
	var error: RequestError = null
	## HTTP status code, e.g. [code]200[/code] or [code]404[/code].
	## [code]0[/code] when no HTTP response was received (transport failure).
	var status: int = 0
	## Response headers as [code]"Name: Value"[/code] strings.
	## Empty when no HTTP response was received.
	var headers: PackedStringArray = PackedStringArray()
	## Raw response body bytes. Empty when [member Options.download_file] is set
	## or when no body was received. Use [member text] for a decoded string view.
	var body: PackedByteArray = PackedByteArray()
	## The server's last SSE [code]retry:[/code] value, in milliseconds — the
	## backoff it suggests before reconnecting. [code]-1[/code] when the stream
	## sent no [code]retry:[/code] line or the response was not an SSE stream. Pair
	## it with the [code]last_event_id[/code] from [member Options.on_sse_event] to
	## reconnect: wait this long, then re-request with a [code]Last-Event-ID[/code]
	## header set to the last id seen.
	var sse_retry_ms: int = -1
	## The response body decoded as UTF-8. Computed lazily on first access and
	## cached, so binary responses never pay the decode cost. Returns
	## [code]""[/code] for an empty or non-UTF-8 body.
	var text: String:
		get:
			if _text_cache == null:
				_text_cache = body.get_string_from_utf8()
				if _text_cache == "" and not body.is_empty():
					push_error("C3Http: response body is not valid UTF-8.")
			return _text_cache

	var _text_cache: Variant = null

	## The response body parsed as JSON. Parsed lazily on first access and cached,
	## reusing the [member text] decode. On a parse failure this pushes an error
	## (once, at parse time) and returns [code]null[/code]. Note that a successful
	## parse of a literal JSON [code]null[/code] body also returns [code]null[/code].
	var json: Variant:
		get:
			if not _json_parsed:
				_json_parsed = true
				var parser := JSON.new()
				var err := parser.parse(text)
				if err == OK:
					_json_cache = parser.data
				else:
					push_error(
						"C3Http: response body is not valid JSON: "
						+ parser.get_error_message()
					)
					_json_cache = null
			return _json_cache

	var _json_parsed := false
	var _json_cache: Variant = null


## Structured error placed on [member Response.error] when
## [member Response.ok] is [code]false[/code].
class RequestError:
	## Broad category of failure.
	enum Kind {
		## No usable HTTP response (DNS, TLS, connection, or request-start failure).
		TRANSPORT,
		## A non-2xx status was received.
		HTTP,
		## The request was rejected before being sent (e.g. an invalid argument).
		CLIENT,
		## The caller aborted the request.
		CANCELLED,
		## No response was received before the timeout elapsed.
		TIMEOUT,
		## The response body exceeded [member Options.body_size_limit].
		BODY_SIZE_LIMIT_EXCEEDED,
	}
	## Broad category of failure. One of the [enum Kind] values.
	var kind: Kind = Kind.TRANSPORT
	## Human-readable description. Never empty.
	var message := ""
	## HTTP status code, or [code]0[/code] when not applicable.
	var status := 0

	## Builds an error for a transport-level failure with no usable HTTP response.
	static func transport(p_message: String) -> RequestError:
		var e := RequestError.new()
		e.kind = Kind.TRANSPORT
		e.message = p_message
		return e

	## Builds an error for a request that received no response before the timeout.
	static func timed_out(p_message: String) -> RequestError:
		var e := RequestError.new()
		e.kind = Kind.TIMEOUT
		e.message = p_message
		return e

	## Builds an error for a request rejected before being sent.
	static func client_error(p_message: String) -> RequestError:
		var e := RequestError.new()
		e.kind = Kind.CLIENT
		e.message = p_message
		return e

	## Builds an error for a caller-initiated cancellation.
	static func cancelled(p_message: String) -> RequestError:
		var e := RequestError.new()
		e.kind = Kind.CANCELLED
		e.message = p_message
		return e

	## Builds an error for a response body that exceeded [member Options.body_size_limit].
	static func body_size_limit_exceeded(p_message: String) -> RequestError:
		var e := RequestError.new()
		e.kind = Kind.BODY_SIZE_LIMIT_EXCEEDED
		e.message = p_message
		return e

	func _to_string() -> String:
		var kind_name: String = Kind.find_key(kind)
		var parts := PackedStringArray(["[%s]" % kind_name.to_lower()])
		if status != 0:
			parts.append("status=%d" % status)
		parts.append(message)
		return " ".join(parts)


## Token passed to [member Options.cancellation_token] to cancel an in-flight
## request from another coroutine or signal handler.
class CancellationToken:
	var _cancelled := false

	## Cancels any in-flight request holding this token. Subsequent calls have
	## no effect.
	func cancel() -> void:
		_cancelled = true

	## Returns [code]true[/code] if [method cancel] has been called.
	func is_cancelled() -> bool:
		return _cancelled


## Holds a pool of idle HTTP connections for reuse across calls, reducing the
## TCP and TLS handshake cost for repeated requests to the same host.
##
## Create one [Session] per logical group of requests and set it on
## [member Options.session]. A [Session] is a [RefCounted] and is freed
## automatically when no [Options] objects reference it. [br][br]
## One-off callers that leave [member Options.session] as [code]null[/code]
## pay zero cost — a fresh connection is opened each time, as in previous versions.
class Session:
	## Maximum number of idle connections kept per unique
	## [code](host, port, scheme, TLS, proxy)[/code] key. Extra connections
	## beyond this limit are closed immediately on checkin.
	var max_connections_per_host: int = 6
	## Seconds an idle connection may sit in the pool before being discarded on
	## the next checkout attempt. Keep this shorter than the server's keep-alive
	## timeout (nginx defaults to 75 s, so 60 s is a safe choice). Set to
	## [code]0.0[/code] to disable time-based eviction.
	var idle_timeout: float = 60.0

	var _pool: Dictionary = {}
	var _mutex: Mutex = Mutex.new()

	class _PoolEntry:
		var client: HTTPClient
		var checked_in_at_msec: int

	## Closes all pooled connections and empties the pool. Optional — connections
	## are also freed when the [Session] goes out of scope.
	func close() -> void:
		_mutex.lock()
		for key: String in _pool:
			for entry: _PoolEntry in _pool[key]:
				entry.client.close()
		_pool.clear()
		_mutex.unlock()

	## Evicts all idle connections whose age exceeds [member idle_timeout].
	## Useful after a network change to force fresh connections on the next call.
	func prune() -> void:
		if idle_timeout <= 0.0:
			return
		var now := Time.get_ticks_msec()
		_mutex.lock()
		for key: String in _pool.keys():
			var entries: Array = _pool[key]
			var i := entries.size() - 1
			while i >= 0:
				var entry: _PoolEntry = entries[i]
				if (now - entry.checked_in_at_msec) / 1000.0 >= idle_timeout:
					entry.client.close()
					entries.remove_at(i)
				i -= 1
			if entries.is_empty():
				_pool.erase(key)
		_mutex.unlock()

	func _make_key(
		host: String,
		port: int,
		tls: bool,
		tls_options: TLSOptions,
		options: Options
	) -> String:
		var tls_id := 0 if (not tls or tls_options == null) else tls_options.get_instance_id()
		var proxy := (
			"%s:%d" % [options.https_proxy_host, options.https_proxy_port]
			if tls
			else "%s:%d" % [options.http_proxy_host, options.http_proxy_port]
		)
		return "%s:%d:%s:%d:%s" % [host, port, str(tls), tls_id, proxy]

	## Returns a connected, non-expired client for [param key], or
	## [code]null[/code] if none is available. Stale or disconnected entries
	## encountered during the search are discarded.
	func checkout(key: String) -> HTTPClient:
		_mutex.lock()
		if not _pool.has(key):
			_mutex.unlock()
			return null
		var entries: Array = _pool[key]
		var now := Time.get_ticks_msec()
		var result: HTTPClient = null
		while not entries.is_empty() and result == null:
			var entry: _PoolEntry = entries.pop_back()
			if entry.client.get_status() != HTTPClient.STATUS_CONNECTED:
				continue
			if idle_timeout > 0.0 and (now - entry.checked_in_at_msec) / 1000.0 >= idle_timeout:
				entry.client.close()
				continue
			result = entry.client
		if entries.is_empty():
			_pool.erase(key)
		_mutex.unlock()
		return result

	## Returns [param client] to the pool under [param key].
	## If the pool is at [member max_connections_per_host] capacity,
	## the oldest idle entry is closed and evicted.
	func checkin(key: String, client: HTTPClient) -> void:
		_mutex.lock()
		if max_connections_per_host <= 0:
			client.close()
			_mutex.unlock()
			return
		if not _pool.has(key):
			_pool[key] = []
		var entries: Array = _pool[key]
		if entries.size() >= max_connections_per_host:
			var oldest: _PoolEntry = entries.pop_front()
			oldest.client.close()
		var entry := _PoolEntry.new()
		entry.client = client
		entry.checked_in_at_msec = Time.get_ticks_msec()
		entries.push_back(entry)
		_mutex.unlock()


## Test helper that intercepts [method C3Http.request] calls.
## Install with [method install], configure canned responses with [method stub],
## and inspect recorded calls via [member calls]. Always pair [method install]
## with [method uninstall] in [code]after_each()[/code]. [br][br]
## [codeblock]
## const C3Http := preload("res://addons/c3_openai_client/utils/c3_http_request.gd")
## var mock: C3Http.Mock
##
## func before_each() -> void:
##     mock = C3Http.Mock.new()
##     mock.install(C3Http)
##
## func after_each() -> void:
##     mock.uninstall(C3Http)
##
## func test_example() -> void:
##     mock.stub().ok({"id": 1})
##     var res := await C3Http.request("https://api.example.com/users")
##     assert_true(res.ok)
##     assert_eq(mock.last_call["url"], "https://api.example.com/users")
## [/codeblock]
class Mock extends _Impl:
	## Recorded calls in order, newest last. Each entry is a [Dictionary] with
	## keys [code]url[/code] ([String]), [code]method[/code] ([int],
	## [code]HTTPClient.METHOD_*[/code]), [code]headers[/code]
	## ([PackedStringArray]), [code]body[/code] ([Variant]),
	## and [code]options[/code] ([Options]).
	var calls: Array[Dictionary] = []

	## Total number of calls received since construction or the last [method reset].
	var call_count: int:
		get:
			return calls.size()

	## The most recent call dictionary, or an empty [Dictionary] if no calls
	## have been made yet.
	var last_call: Dictionary:
		get:
			return calls.back() if not calls.is_empty() else {}

	var _stubs: Array = []

	## Installs this mock as [code]C3Http._impl[/code]. Pass the preloaded
	## script as [param c3_http] — the same reference used to call
	## [code]C3Http.Mock.new()[/code].
	# MODIFIED: install/uninstall take an explicit GDScript reference instead of
	# using `C3Http._impl` directly, because class_name C3Http is commented out
	# to prevent addon conflicts, leaving no identifier to reference the outer script.
	func install(c3_http: GDScript) -> void:
		c3_http._impl = self

	## Uninstalls this mock and restores normal request behavior.
	func uninstall(c3_http: GDScript) -> void:
		c3_http._impl = _Impl.new()

	## Returns a stub builder for [param url]. Omit [param url] to create
	## the catch-all default stub, matched when no URL-specific stub exists.
	## [br][br]Stubs are evaluated in registration order; the first exact URL
	## match wins, then the first default stub, then an empty [Response].
	func stub(url: String = "") -> _Stub:
		var s := _Stub.new(url)
		_stubs.append(s)
		return s

	## Clears all recorded calls and registered stubs.
	func reset() -> void:
		calls.clear()
		_stubs.clear()

	func request(
		url: String,
		custom_headers: PackedStringArray,
		method: int,
		request_data: Variant,
		options: Options,
		_redirects_left: int = -1,
		_on_worker: bool = false,
		_start_ms: int = -1,
		_force_fresh: bool = false
	) -> Response:
		calls.append({
			"url": url,
			"method": method,
			"headers": custom_headers,
			"body": request_data,
			"options": options,
		})
		return _find_stub(url)._response()

	func _find_stub(url: String) -> _Stub:
		var fallback: _Stub = null
		for s: _Stub in _stubs:
			if s._url == url:
				return s
			if s._url == "" and fallback == null:
				fallback = s
		return fallback if fallback != null else _Stub.new("")


## Canned-response builder returned by [method Mock.stub]. Configure with
## [method ok], [method fail], or [method returns], then discard — the [Mock]
## retains the stub internally.
class _Stub:
	var _url: String
	var _preset: Response = null

	func _init(url: String) -> void:
		_url = url

	## Configures a successful response. [param json] is JSON-encoded into
	## [member Response.body].
	func ok(json: Dictionary = {}, status: int = 200) -> void:
		var res := Response.new()
		res.ok = true
		res.status = status
		res.body = JSON.stringify(json).to_utf8_buffer()
		_preset = res

	## Configures a failure response. Build [param error] with the
	## [RequestError] factory methods ([method RequestError.transport],
	## [method RequestError.timed_out], etc.) or construct one manually.
	func fail(error: RequestError) -> void:
		var res := Response.new()
		res.ok = false
		res.error = error
		res.status = error.status
		_preset = res

	## Sets a [Response] directly, bypassing [method ok] and [method fail].
	func returns(response: Response) -> void:
		_preset = response

	func _response() -> Response:
		return _preset if _preset != null else Response.new()


class _Impl:
	class _ParsedURL:
		var host: String
		var port: int
		var path: String
		var tls: bool

		func _init(h: String, po: int, pa: String, t: bool) -> void:
			host = h
			port = po
			path = pa
			tls = t

	# Worker-thread poll pacing in microseconds, mirroring the cadence of
	# HTTPRequest's threaded mode. Only used when running on a worker thread.
	# Note: on Windows, using OS.delay_usec with any value less than 2000
	# is effectively the same as 2000 due to the scheduler's granularity.
	const _PUMP_DELAY_USEC := 1000

	func request(
		url: String,
		custom_headers: PackedStringArray,
		method: int,
		request_data: Variant,
		options: Options,
		_redirects_left: int = -1,
		_on_worker: bool = false,
		_start_ms: int = -1,
		_force_fresh: bool = false
	) -> Response:
		# options.use_threads is read exactly once — here — to decide whether to
		# spawn a worker. Every downstream poll and dispatch decision uses _on_worker
		# instead, so the fallback path (threads requested but unavailable) behaves
		# identically to the cooperative path.
		if options.use_threads and not _on_worker and _threads_available():
			return await _run_threaded(
				url,
				custom_headers,
				method,
				request_data,
				options,
				_redirects_left
			)

		if not options.download_file.is_empty() and not options.on_sse_event.is_null():
			return _fail(RequestError.client_error(
				"download_file and on_sse_event cannot be used together."
			))

		if _cancelled(options):
			return _fail(RequestError.cancelled("Request was cancelled."))
		var redirects_left := (
			options.max_redirects if _redirects_left < 0 else _redirects_left
		)
		# A valid on_sse_event sink switches a 2xx body to incremental SSE parsing.
		var streaming := options.on_sse_event.is_valid()

		var parsed := _parse_url(url)
		if parsed == null:
			return _fail(RequestError.client_error('Invalid URL: "%s".' % url))

		var all_headers := _build_request_headers(
			custom_headers, options.accept_gzip, streaming
		)

		var tree := Engine.get_main_loop() as SceneTree
		var start_ms := Time.get_ticks_msec() if _start_ms < 0 else _start_ms
		var last_status := HTTPClient.STATUS_DISCONNECTED

		var pool_key := ""
		var reusing := false
		var client: HTTPClient
		if options.session != null:
			pool_key = options.session._make_key(
				parsed.host, parsed.port, parsed.tls, options.tls_options, options
			)
			# A retry after a silent reuse failure forces a fresh connection: skip
			# checkout (so we never hand back another pooled socket) but keep pool_key
			# so the new connection is still checked in on success.
			var pooled: HTTPClient = (
				null if _force_fresh else options.session.checkout(pool_key)
			)
			if pooled != null:
				client = pooled
				reusing = true
			else:
				client = HTTPClient.new()
		else:
			client = HTTPClient.new()
		client.set_read_chunk_size(options.download_chunk_size)

		if not reusing:
			var conn_err: Variant = await _connect_client(
				client, parsed, options, start_ms, tree, _on_worker
			)
			if conn_err != null:
				return conn_err
			if OS.has_feature("web"):
				# HTTPClientWeb only advances once per frame. _connect_client's
				# loop just polled to observe STATUS_CONNECTED and returned
				# without a pump, so without this the loop below would poll again
				# in the same frame and trigger a "polled multiple times" warning.
				await _pump(tree, _on_worker)
		last_status = HTTPClient.STATUS_CONNECTED

		var err := _send_request(client, method, parsed, all_headers, request_data)
		if err != OK:
			# A send failure on a pooled connection means the socket was dead before
			# any bytes left the client, so the request was never transmitted: replay
			# it on a fresh connection regardless of method. _force_fresh makes the
			# child skip the pool, so it cannot loop; start_ms preserves the deadline.
			if reusing:
				client.close()
				return await request(
					url, custom_headers, method, request_data, options,
					redirects_left, _on_worker, start_ms, true
				)
			return _fail(RequestError.transport(
				"Failed to send request (error %d)." % err
			))

		while true:
			client.poll()
			last_status = _emit_status_change(
				client, last_status, options, _on_worker
			)
			if client.get_status() != HTTPClient.STATUS_REQUESTING:
				break
			if _timed_out(start_ms, options.timeout):
				return _fail(
					RequestError.timed_out("Timed out waiting for response.")
				)
			if _cancelled(options):
				return _fail(RequestError.cancelled("Request was cancelled."))
			await _pump(tree, _on_worker)

		if not client.has_response():
			# A pooled connection the server closed silently between checkout and use
			# surfaces here: request() buffered locally, then the socket was already
			# dead. Retry once on a fresh connection for methods safe to replay — once
			# the request was sent, a body-bearing method may have been processed, so
			# only bodyless-idempotent methods qualify (matches Go net/http).
			# _force_fresh makes the child skip the pool, so it cannot loop. start_ms
			# carries through to preserve the original deadline.
			if reusing and _is_safe_to_retry(method):
				client.close()
				return await request(
					url, custom_headers, method, request_data, options,
					redirects_left, _on_worker, start_ms, true
				)
			return _fail(RequestError.transport("No response received."))

		var status := client.get_response_code()
		var resp_headers: PackedStringArray = client.get_response_headers()

		# A 2xx body with a sink set is parsed as an SSE stream; everything else
		# (non-2xx error bodies, redirect bodies) is collected normally.
		var sse_mode := streaming and status >= 200 and status < 300
		# On a worker thread, marshal SSE events back to the main thread so the
		# caller's sink never runs off-thread; otherwise it would dispatch directly.
		var sse_sink := options.on_sse_event
		if _on_worker and sse_sink.is_valid():
			sse_sink = func(data: String, event_type: String, last_event_id: String) -> void:
				options.on_sse_event.call_deferred(data, event_type, last_event_id)
		var body_bytes := PackedByteArray()
		var sse_buffer := PackedByteArray()
		# Persistent SSE cursors, threaded through the parser for the whole stream:
		# the last-event-id (surfaced per event) and the server's retry backoff in
		# ms (surfaced on the final Response). Boxed so the parser can write back.
		var sse_id := [""]
		var sse_retry := [-1]
		var last_recv_ms := start_ms
		# Content-Length if the server sent one, else -1 (e.g. chunked responses).
		var total_bytes := client.get_response_body_length()
		var bytes_received := 0
		# Bytes actually written to the download file (decompressed, when decoding).
		var bytes_written := 0
		var file: FileAccess = null
		if not options.download_file.is_empty() and not streaming:
			file = FileAccess.open(options.download_file, FileAccess.WRITE)
			if file == null:
				return _fail(RequestError.client_error(
					"Cannot open download file: \"%s\"." % options.download_file
				))
		# When downloading to a file, decompress the body on the fly so the file
		# holds decoded content rather than raw compressed bytes. SSE streams are
		# never decompressed.
		var download_decoder: StreamPeerGZIP = null
		if file != null and not sse_mode:
			download_decoder = _make_download_decoder(
				resp_headers, options.accept_gzip
			)
		while client.get_status() == HTTPClient.STATUS_BODY:
			# While streaming, timeout is idle time since the last bytes, not total
			# stream duration — a healthy long-lived stream must not be cut off.
			if _timed_out(last_recv_ms if sse_mode else start_ms, options.timeout):
				if file != null:
					file.close()
					DirAccess.remove_absolute(options.download_file)
				return _fail(RequestError.timed_out(
					"Stream idle for too long." if sse_mode
					else "Timed out while reading body."
				), sse_retry[0])
			if _cancelled(options):
				if file != null:
					file.close()
					DirAccess.remove_absolute(options.download_file)
				return _fail(RequestError.cancelled("Request was cancelled."), sse_retry[0])
			client.poll()
			last_status = _emit_status_change(
				client, last_status, options, _on_worker
			)
			# poll() may set STATUS_CONNECTION_ERROR if the connection drops;
			# calling read_response_body_chunk() outside STATUS_BODY triggers
			# an engine error.
			if last_status != HTTPClient.STATUS_BODY:
				break
			var chunk: PackedByteArray = client.read_response_body_chunk()
			if chunk.is_empty():
				await _pump(tree, _on_worker)
				continue
			last_recv_ms = Time.get_ticks_msec()
			if sse_mode:
				# Accumulate raw bytes and slice on the ASCII event delimiter so a
				# multi-byte UTF-8 character split across reads is never mangled.
				if (
					options.body_size_limit >= 0
					and sse_buffer.size() + chunk.size() > options.body_size_limit
				):
					return _fail(RequestError.body_size_limit_exceeded(
						"SSE event exceeded limit of %d bytes."
						% options.body_size_limit
					), sse_retry[0])
				sse_buffer.append_array(chunk)
				sse_buffer = _drain_sse_buffer(sse_buffer, sse_sink, sse_id, sse_retry)
				continue
			if file != null:
				# The limit is applied to bytes written to disk (decompressed),
				# matching native — this is what actually bounds a decompression
				# bomb, which a compressed-byte limit would not. The decoder is
				# given the remaining allowance so it stops before ballooning
				# memory rather than decoding a whole bomb chunk first.
				var to_write := chunk
				if download_decoder != null:
					var budget := (
						options.body_size_limit - bytes_written
						if options.body_size_limit >= 0
						else -1
					)
					var decoded := _decode_chunk(
						download_decoder,
						chunk,
						options.download_chunk_size,
						budget
					)
					if not decoded["ok"]:
						file.close()
						DirAccess.remove_absolute(options.download_file)
						return _fail(RequestError.transport(
							"Failed to decompress download stream."
						))
					to_write = decoded["data"]
				if (
					options.body_size_limit >= 0
					and bytes_written + to_write.size() > options.body_size_limit
				):
					file.close()
					DirAccess.remove_absolute(options.download_file)
					return _fail(RequestError.body_size_limit_exceeded(
						"Response body exceeded limit of %d bytes."
						% options.body_size_limit
					))
				file.store_buffer(to_write)
				bytes_written += to_write.size()
			else:
				# In-memory limit here is on received (compressed) bytes. The
				# decompressed output is bounded separately by _maybe_decompress_body
				# below, which caps decompression at body_size_limit so a zip bomb
				# under this check can't inflate to unbounded memory.
				if (
					options.body_size_limit >= 0
					and body_bytes.size() + chunk.size() > options.body_size_limit
				):
					return _fail(RequestError.body_size_limit_exceeded(
						"Response body exceeded limit of %d bytes."
						% options.body_size_limit
					))
				body_bytes.append_array(chunk)
			bytes_received += chunk.size()
			_emit(options.on_progress, _on_worker, [bytes_received, total_bytes])

		# A server may end the final event without a trailing blank line; flush
		# what remains. Every byte has arrived, so decode the tail in one pass.
		if sse_mode:
			var tail := _decode_sse_lines(sse_buffer)
			if not tail.strip_edges().is_empty():
				_emit_sse_event(
					tail, sse_sink, sse_id, sse_retry, _id_field_has_nul(sse_buffer)
				)

		if file != null:
			file.close()
		else:
			var decoded: Variant = _maybe_decompress_body(
				body_bytes,
				resp_headers,
				options.accept_gzip,
				options.body_size_limit,
				options.download_chunk_size
			)
			if decoded is RequestError:
				return _fail(decoded)
			body_bytes = decoded

		if status >= 300 and status < 400 and redirects_left > 0:
			var location := _header_value(resp_headers, "Location")
			if not location.is_empty():
				var redirect_url := _resolve_redirect_url(
					location,
					parsed.host,
					parsed.port,
					parsed.tls,
					parsed.path
				)
				var redirect_headers := _strip_auth_if_cross_origin(
					custom_headers, parsed, _parse_url(redirect_url)
				)
				# Release this hop's connection before following the redirect.
				# Without this, the coroutine frame keeps client alive — and the
				# server-side slot occupied — for the entire remaining chain.
				client.close()
				var redirect_res: Response = await request(
					redirect_url,
					redirect_headers,
					_redirect_method(method, status),
					_redirect_body(method, status, request_data),
					options,
					redirects_left - 1,
					_on_worker,
					start_ms
				)
				if not redirect_res.ok and not options.download_file.is_empty():
					if FileAccess.file_exists(options.download_file):
						DirAccess.remove_absolute(options.download_file)
				return redirect_res

		# Pool the connection for reuse only when the transport is still connected
		# AND the server has not asked us to close it. Honoring a "Connection: close"
		# response header is essential: servers cap keep-alive connections by age or
		# request count and announce the final response with "close" while the socket
		# is still momentarily readable (STATUS_CONNECTED). Pooling it anyway hands the
		# next request a connection the server is tearing down — a "No response
		# received" failure on reuse.
		if options.session != null and not pool_key.is_empty():
			var keep_alive := (
				client.get_status() == HTTPClient.STATUS_CONNECTED
				and not _connection_close_requested(resp_headers)
			)
			if keep_alive:
				options.session.checkin(pool_key, client)
			else:
				client.close()

		var res := Response.new()
		res.status = status
		res.headers = resp_headers
		res.body = body_bytes if file == null else PackedByteArray()
		res.sse_retry_ms = sse_retry[0]
		if status < 200 or status >= 300:
			res.ok = false
			var e := RequestError.new()
			e.kind = RequestError.Kind.HTTP
			e.status = status
			# A 3xx carrying a Location that we stopped following only because the
			# redirect budget is spent. Say so, otherwise the bare status reads
			# like an unexpected failure. (redirects_left is never negative, so
			# == 0 is the exhausted/disabled case.)
			var is_redirect := status >= 300 and status < 400
			var has_location := not _header_value(resp_headers, "Location").is_empty()
			if is_redirect and has_location and redirects_left == 0:
				e.message = (
					"Redirect limit (%d) reached at status %d; not following further."
					% [options.max_redirects, status]
				)
			else:
				e.message = "Request failed with status %d." % status
			res.error = e
		return res

	# Sends the request on [param client], dispatching to request_raw for a
	# PackedByteArray body and request otherwise. Returns the HTTPClient error code
	# (OK on success).
	func _send_request(
		client: HTTPClient,
		method: int,
		parsed: _ParsedURL,
		all_headers: PackedStringArray,
		request_data: Variant
	) -> int:
		if request_data is PackedByteArray:
			return client.request_raw(method, parsed.path, all_headers, request_data)
		return client.request(method, parsed.path, all_headers, request_data)

	# Connects [param client] to the host described by [param parsed], applying
	# proxies and TLS from [param options], then polls until STATUS_CONNECTED or
	# a timeout or cancellation occurs. Returns null on success; returns an error
	# Response on failure.
	func _connect_client(
		client: HTTPClient,
		parsed: _ParsedURL,
		options: Options,
		start_ms: int,
		tree: SceneTree,
		on_worker: bool
	) -> Variant:
		var proxies := _resolve_proxies(options)
		if proxies.has("http"):
			client.set_http_proxy(proxies["http"][0], proxies["http"][1])
		if proxies.has("https"):
			client.set_https_proxy(proxies["https"][0], proxies["https"][1])
		var err: int
		if parsed.tls:
			var tls: TLSOptions = (
				options.tls_options
				if options.tls_options != null
				else TLSOptions.client()
			)
			err = client.connect_to_host(parsed.host, parsed.port, tls)
		else:
			err = client.connect_to_host(parsed.host, parsed.port)
		if err != OK:
			return _fail(RequestError.transport(
				"Failed to start connection (error %d)." % err
			))
		var last_status := HTTPClient.STATUS_DISCONNECTED
		while true:
			client.poll()
			last_status = _emit_status_change(client, last_status, options, on_worker)
			if client.get_status() not in [
				HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING
			]:
				break
			if _timed_out(start_ms, options.timeout):
				return _fail(RequestError.timed_out("Timed out while connecting."))
			if _cancelled(options):
				return _fail(RequestError.cancelled("Request was cancelled."))
			await _pump(tree, on_worker)
		if client.get_status() != HTTPClient.STATUS_CONNECTED:
			return _fail(RequestError.transport(
				"Could not connect (status %d)." % client.get_status()
			))
		return null

	# Yields between polls. On a worker thread it sleeps briefly and returns
	# synchronously — the await never suspends, so request() runs straight through
	# on the worker. On the main thread it yields to the next frame, keeping it
	# responsive.
	func _pump(tree: SceneTree, on_worker: bool) -> void:
		if on_worker:
			OS.delay_usec(_PUMP_DELAY_USEC)
		else:
			await tree.process_frame

	# Runs request() on a dedicated background thread (polling at OS speed) and
	# awaits its completion on the main thread, leaving the public await API
	# unchanged. The worker re-enters request() with _on_worker = true.
	func _run_threaded(
		url: String,
		custom_headers: PackedStringArray,
		method: int,
		request_data: Variant,
		options: Options,
		redirects_left: int
	) -> Response:
		var tree := Engine.get_main_loop() as SceneTree
		# Marshaled callbacks are dispatched with call_deferred from the worker, so
		# they run on the main thread at the next message-queue flush. We must drain
		# that queue before resolving so every callback fires before the Response —
		# but only when a callback is actually configured.
		var has_observers := (
			options.on_sse_event.is_valid()
			or options.on_progress.is_valid()
			or options.on_status_changed.is_valid()
		)
		var thread := Thread.new()
		thread.start(
			func() -> Response:
				return await request(
					url,
					custom_headers,
					method,
					request_data,
					options,
					redirects_left,
					true
				)
		)
		while thread.is_alive():
			await tree.process_frame
		var result: Variant = thread.wait_to_finish()
		# Enforce the worker-never-suspends invariant: on the worker path _pump
		# sleeps synchronously and never yields, so request() must run straight
		# through and the thread function must return a Response. If a future change
		# adds an await that actually suspends, the function returns a coroutine
		# state instead — fail loudly here rather than corrupting the result.
		assert(
			result is Response,
			"C3Http: threaded worker suspended; the worker path must run "
			+ "synchronously (see _pump). Did a new await get added to request()?"
		)
		var res: Response = result
		if has_observers:
			# One more frame guarantees a message-queue flush after the worker has
			# returned, so all deferred callbacks fire before this Response resolves.
			await tree.process_frame
		return res

	# Whether the current platform supports spawning worker threads. Single-threaded
	# export templates (e.g. web without thread support) fall back to the
	# cooperative loop.
	func _threads_available() -> bool:
		return OS.has_feature("threads")

	# Invokes an observer callback, marshaling to the main thread via call_deferred
	# when running on a worker so the caller's callback never touches the scene tree
	# off-thread; otherwise dispatches it directly.
	func _emit(cb: Callable, threaded: bool, args: Array) -> void:
		if not cb.is_valid():
			return
		if threaded:
			cb.bindv(args).call_deferred()
		else:
			cb.callv(args)

	func _parse_url(url: String) -> _ParsedURL:
		var sep := url.find("://")
		if sep == -1:
			return null
		var scheme := url.substr(0, sep).to_lower()
		if scheme != "http" and scheme != "https":
			return null
		var rest := url.substr(sep + 3)
		var slash := rest.find("/")
		var host_part: String
		var path: String
		if slash == -1:
			host_part = rest
			path = "/"
		else:
			host_part = rest.substr(0, slash)
			path = rest.substr(slash)
		if host_part.is_empty():
			return null
		var fragment := path.find("#")
		if fragment != -1:
			path = path.substr(0, fragment)
		var port := 443 if scheme == "https" else 80
		var host := host_part
		if host_part.begins_with("["):
			var bracket_close := host_part.find("]")
			if bracket_close == -1:
				return null
			host = host_part.substr(1, bracket_close - 1)
			var after_bracket := host_part.substr(bracket_close + 1)
			if after_bracket.begins_with(":"):
				var port_str := after_bracket.substr(1)
				if port_str.is_valid_int():
					port = port_str.to_int()
		else:
			var colon := host_part.find(":")
			if colon != -1:
				var port_str := host_part.substr(colon + 1)
				if port_str.is_valid_int():
					port = port_str.to_int()
				host = host_part.substr(0, colon)
		return _ParsedURL.new(host, port, path, scheme == "https")

	# Resolves which proxy applies to each scheme. A key ("http"/"https") is present
	# only when that scheme has a non-empty host; its value is [host, port]. Kept pure
	# (no HTTPClient) so the per-scheme routing can be unit-tested without a network.
	func _resolve_proxies(options: Options) -> Dictionary:
		var proxies := {}
		if not options.http_proxy_host.is_empty():
			proxies["http"] = [options.http_proxy_host, options.http_proxy_port]
		if not options.https_proxy_host.is_empty():
			proxies["https"] = [options.https_proxy_host, options.https_proxy_port]
		return proxies

	func _timed_out(start_ms: int, timeout: float) -> bool:
		if timeout <= 0.0:
			return false
		return (Time.get_ticks_msec() - start_ms) / 1000.0 >= timeout

	func _cancelled(options: Options) -> bool:
		return (
			options.cancellation_token != null
			and options.cancellation_token.is_cancelled()
		)

	# Emits on_status_changed when the client's status differs from last_status,
	# returning the current status to carry forward to the next poll.
	func _emit_status_change(
		client: HTTPClient,
		last_status: HTTPClient.Status,
		options: Options,
		on_worker: bool
	) -> HTTPClient.Status:
		var current := client.get_status()
		if current != last_status:
			_emit(options.on_status_changed, on_worker, [current])
		return current

	func _header_value(headers: PackedStringArray, name: String) -> String:
		var prefix := name.to_lower() + ":"
		for header: String in headers:
			if header.to_lower().begins_with(prefix):
				return header.substr(prefix.length()).strip_edges()
		return ""

	# True when the response's Connection header carries the "close" token, meaning
	# the server will drop the socket after this response and it must not be pooled.
	# The header is a comma-separated token list, so match tokenwise rather than by
	# substring (a value like "close-something" must not count).
	func _connection_close_requested(headers: PackedStringArray) -> bool:
		var value := _header_value(headers, "Connection")
		if value.is_empty():
			return false
		for token: String in value.split(","):
			if token.strip_edges().to_lower() == "close":
				return true
		return false

	# Methods safe to replay on a fresh connection after a reused connection died
	# before any response. Restricted to the bodyless-idempotent methods (matching
	# Go's net/http): once the request was sent, a body-bearing method may already
	# have been processed by the server, so it must not be auto-retried. The method
	# here is an HTTPClient.METHOD_* value.
	func _is_safe_to_retry(method: int) -> bool:
		return method in [
			HTTPClient.METHOD_GET,
			HTTPClient.METHOD_HEAD,
			HTTPClient.METHOD_OPTIONS,
		]

	# Merges the caller's headers with the gzip opt-in. Our Accept-Encoding is added
	# only when accept_gzip is on, the request isn't an SSE stream, and the caller
	# hasn't already set their own Accept-Encoding — a caller-supplied value wins,
	# matching HTTPRequest. We advertise gzip only, never deflate; see the
	# Options.accept_gzip doc comment for why.
	func _build_request_headers(
		custom_headers: PackedStringArray, accept_gzip: bool, streaming: bool
	) -> PackedStringArray:
		var headers := PackedStringArray()
		if (
			accept_gzip
			and not streaming
			and _header_value(custom_headers, "Accept-Encoding").is_empty()
		):
			headers.append("Accept-Encoding: gzip")
		headers.append_array(custom_headers)
		return headers

	# Builds the on-the-fly decompressor for a download, or null when none applies.
	# Decompression is gated on accept_gzip (accept_gzip == false means the caller
	# opted out, so raw bytes pass through unchanged, like HTTPRequest). Only
	# gzip is decoded; see the Options.accept_gzip doc for why deflate isn't supported.
	func _make_download_decoder(
		resp_headers: PackedStringArray, accept_gzip: bool
	) -> StreamPeerGZIP:
		if not accept_gzip:
			return null
		if _header_value(resp_headers, "Content-Encoding").to_lower() != "gzip":
			return null
		var decoder := StreamPeerGZIP.new()
		decoder.start_decompression(false)
		return decoder

	# Decompresses an in-memory gzip body, or returns it unchanged. Gated on
	# accept_gzip (false means the caller opted out, so raw bytes pass through, like
	# HTTPRequest). Only gzip is decoded; see the Options.accept_gzip doc for why
	# deflate isn't supported.
	#
	# Decodes through the same StreamPeerGZIP feed-and-drain path as the download
	# branch (_decode_chunk), feeding the whole body as one chunk — so both paths and
	# HTTPRequest behave identically. This deliberately avoids
	# PackedByteArray.decompress_dynamic, whose binding collapses three distinct
	# outcomes — a valid empty body, an over-limit body, and a corrupt body — into the
	# same empty return, which made an empty gzipped body look over-limit.
	#
	# Returns the decoded PackedByteArray on success (empty in, empty out — no false
	# limit error), a BODY_SIZE_LIMIT_EXCEEDED RequestError when the decoded output
	# would exceed body_size_limit (-1 disables the cap; the budget stops a zip bomb
	# before it balloons), or a TRANSPORT RequestError when the stream is corrupt.
	func _maybe_decompress_body(
		body_bytes: PackedByteArray,
		resp_headers: PackedStringArray,
		accept_gzip: bool,
		body_size_limit: int,
		read_size: int = 65536
	) -> Variant:
		if not accept_gzip or body_bytes.is_empty():
			return body_bytes
		if _header_value(resp_headers, "Content-Encoding").to_lower() != "gzip":
			return body_bytes
		var decoder := StreamPeerGZIP.new()
		decoder.start_decompression(false)
		var decoded := _decode_chunk(
			decoder, body_bytes, read_size, body_size_limit
		)
		if not decoded["ok"]:
			return RequestError.transport("Failed to decompress response body.")
		var out: PackedByteArray = decoded["data"]
		if body_size_limit >= 0 and out.size() > body_size_limit:
			return RequestError.body_size_limit_exceeded(
				"Decompressed response body exceeded limit of %d bytes."
				% body_size_limit
			)
		return out

	# Feeds one compressed chunk into the decompressor and returns everything it
	# decodes. Returns {"ok": bool, "data": PackedByteArray}; "ok" is false on a
	# decode error (e.g. corrupt stream), with whatever decoded first.
	#
	# The decoder inflates input into a fixed-size internal buffer and refuses to
	# accept more once it fills (StreamPeerGZIP.put_data returns ERR_OUT_OF_MEMORY).
	# A highly compressible chunk can expand past that buffer many times over, so
	# we feed incrementally with put_partial_data and drain between feeds to make
	# room — never assuming the whole chunk's output fits at once.
	#
	# [param budget] caps decoded output: once more than [param budget] bytes have
	# been produced, decoding stops early so a zip bomb can't balloon memory before
	# the caller's size-limit check rejects it. A negative budget means unlimited.
	func _decode_chunk(
		decoder: StreamPeerGZIP,
		chunk: PackedByteArray,
		read_size: int,
		budget: int = -1
	) -> Dictionary:
		var out := PackedByteArray()
		var pos := 0
		while pos < chunk.size():
			var fed: Array = decoder.put_partial_data(chunk.slice(pos))
			var feed_error: Error = fed[0]
			var sent: int = fed[1]
			if feed_error != OK:
				return {"ok": false, "data": out}
			pos += sent
			var drained := _drain_decoder(decoder, read_size)
			out.append_array(drained["data"])
			if not drained["ok"]:
				return {"ok": false, "data": out}
			if budget >= 0 and out.size() > budget:
				# Past the allowance — stop; the caller will reject this as over-limit.
				break
			if sent == 0 and (drained["data"] as PackedByteArray).is_empty():
				# No input consumed and nothing decoded means no further progress is
				# possible — the gzip stream has hit Z_STREAM_END — so stop spinning.
				# Any bytes left in this chunk past the end marker are dropped. For a
				# normal single-member response that's correct (trailing bytes aren't
				# content). The gap: concatenated multi-member gzip (valid per RFC
				# 1952) is truncated at the first member, since StreamPeerGZIP doesn't
				# inflateReset for the next one. Fixing it would mean spinning up a
				# fresh decoder from the leftover offset; rare enough over HTTP to
				# defer. Without this guard the loop could spin forever on such input.
				break
		return {"ok": true, "data": out}

	# Drains all decoded bytes currently available from the decompressor, reading
	# in [param read_size] slices until it yields nothing more.
	func _drain_decoder(decoder: StreamPeerGZIP, read_size: int) -> Dictionary:
		var out := PackedByteArray()
		while true:
			var result: Array = decoder.get_partial_data(read_size)
			var drain_error: Error = result[0]
			var part: PackedByteArray = result[1]
			if drain_error != OK:
				return {"ok": false, "data": out}
			if part.is_empty():
				break
			out.append_array(part)
		return {"ok": true, "data": out}

	# Resolves a Location header value against the original request per RFC 3986 §5.2.
	func _resolve_redirect_url(
		location: String, host: String, port: int, tls: bool, base_path: String
	) -> String:
		if location.begins_with("http://") or location.begins_with("https://"):
			return location
		var scheme := "https" if tls else "http"
		var default_port := 443 if tls else 80
		var authority := host if port == default_port else "%s:%d" % [host, port]
		if location.begins_with("//"):
			return scheme + ":" + location
		if location.begins_with("/"):
			return scheme + "://" + authority + _normalize_path(location)
		var slash := base_path.rfind("/")
		return (
			scheme
			+ "://"
			+ authority
			+ _normalize_path(base_path.substr(0, slash + 1) + location)
		)

	# Removes . and .. segments from an absolute path per RFC 3986 §5.2.4.
	func _normalize_path(path: String) -> String:
		var out: Array[String] = []
		for seg: String in path.split("/"):
			if seg == "..":
				if out.size() > 1:
					out.pop_back()
			elif seg != ".":
				out.append(seg)
		return "/".join(out)

	# RFC 9110 §15.4: 303 always redirects as GET (any original method); 301/302
	# historically switch POST to GET but preserve other methods (§15.4.2–15.4.3).
	# 307/308 explicitly require preserving the original method and body (§15.4.8–15.4.9).
	func _redirect_method(method: int, status: int) -> int:
		if (
			status == 303
			or (status in [301, 302] and method == HTTPClient.METHOD_POST)
		):
			return HTTPClient.METHOD_GET
		return method

	func _redirect_body(
		method: int, status: int, request_data: Variant
	) -> Variant:
		if (
			status == 303
			or (status in [301, 302] and method == HTTPClient.METHOD_POST)
		):
			return ""
		return request_data

	# Returns headers with Authorization, Cookie, Cookie2, and Proxy-Authorization
	# stripped when the redirect crosses origins (different host, port, or scheme).
	# Same-origin redirects keep all headers intact so authenticated API chains work.
	func _strip_auth_if_cross_origin(
		headers: PackedStringArray,
		origin: _ParsedURL,
		redirect: _ParsedURL
	) -> PackedStringArray:
		if redirect == null:
			return headers
		if (
			origin.host == redirect.host
			and origin.port == redirect.port
			and origin.tls == redirect.tls
		):
			return headers
		var sensitive := ["authorization", "cookie", "cookie2", "proxy-authorization"]
		var out := PackedStringArray()
		for header: String in headers:
			var colon := header.find(":")
			if colon == -1 or header.substr(0, colon).strip_edges().to_lower() not in sensitive:
				out.append(header)
		return out

	# Carves every complete event out of [param buffer], dispatching each to
	# [param on_event], and returns the trailing partial bytes (an incomplete
	# event, possibly mid-character) to keep for the next read.
	func _drain_sse_buffer(
		buffer: PackedByteArray, on_event: Callable, id_box: Array, retry_box: Array
	) -> PackedByteArray:
		var bound := _find_sse_boundary(buffer)
		while bound.x != -1:
			var event_bytes := buffer.slice(0, bound.x)
			# Decide the id-NUL case on the raw bytes (see _id_field_has_nul) before
			# decoding, since get_string_from_utf8() truncates the value at the NUL.
			_emit_sse_event(
				_decode_sse_lines(event_bytes),
				on_event, id_box, retry_box, _id_field_has_nul(event_bytes)
			)
			buffer = buffer.slice(bound.y)
			bound = _find_sse_boundary(buffer)
		return buffer

	# Locates the first SSE event boundary (a blank line) in [param buffer],
	# handling both LF (\n\n) and CRLF (\r\n\r\n) terminators. Returns a Vector2i
	# of (content_end, next_start) byte offsets, or (-1, -1) if no complete event
	# has arrived. The delimiter is pure ASCII, so it is found at the byte level
	# without decoding — a multi-byte UTF-8 character can never straddle it.
	func _find_sse_boundary(buffer: PackedByteArray) -> Vector2i:
		var size := buffer.size()
		var i := 0
		while i < size:
			if buffer[i] == 0x0A:
				var j := i + 1
				if j < size and buffer[j] == 0x0D:
					j += 1
				if j < size and buffer[j] == 0x0A:
					return Vector2i(i, j + 1)
			i += 1
		return Vector2i(-1, -1)

	# Parses one raw SSE event block and, if it carries data, invokes
	# [param on_event] with (data, event_type, last_event_id). Multiple data: lines
	# are joined with newlines; event_type defaults to "message" per the SSE spec.
	# Comment lines (":") and events with no data: lines (bare keep-alives, id-only
	# blocks) are dropped. The id: and retry: fields update the persistent
	# [param id_box] / [param retry_box] cursors even on dropped blocks, so they
	# carry forward across the stream: id_box[0] is surfaced as last_event_id (for
	# the caller to echo as Last-Event-ID on reconnect) and retry_box[0] is the
	# server's suggested backoff in ms (surfaced on the final Response). This
	# client does not reconnect itself; it only exposes the cursors.
	func _emit_sse_event(
		raw_event: String,
		on_event: Callable,
		id_box: Array,
		retry_box: Array,
		id_has_nul: bool = false
	) -> void:
		var data_lines := PackedStringArray()
		var event_type := "message"
		for line: String in raw_event.split("\n"):
			line = line.trim_suffix("\r")
			if line.begins_with(":"):
				continue
			if line.begins_with("data:"):
				var value := line.substr(5)
				if value.begins_with(" "):
					value = value.substr(1)
				data_lines.append(value)
			elif line.begins_with("event:"):
				var value := line.substr(6)
				if value.begins_with(" "):
					value = value.substr(1)
				event_type = value
			elif line.begins_with("id:"):
				var value := line.substr(3)
				if value.begins_with(" "):
					value = value.substr(1)
				# Per spec, an id whose value contains a NUL is ignored entirely; the
				# previous cursor stands. The NUL is detected upstream on the raw bytes
				# (see _id_field_has_nul) because the decoded value can no longer reveal
				# it — get_string_from_utf8() truncates at the NUL.
				if not id_has_nul:
					id_box[0] = value
			elif line.begins_with("retry:"):
				var value := line.substr(6)
				if value.begins_with(" "):
					value = value.substr(1)
				# retry must be digits only; is_valid_int() also
				# accepts a leading sign, so exclude it.
				if value.is_valid_int() and not (
					value.begins_with("-") or value.begins_with("+")
				):
					retry_box[0] = value.to_int()
		if data_lines.is_empty():
			return
		on_event.call("\n".join(data_lines), event_type, id_box[0])

	# Decodes a raw event block to a String one line at a time, splitting on LF
	# (0x0A) at the byte level. Decoding per line rather than in one pass confines
	# get_string_from_utf8()'s truncate-at-NUL behavior to the offending line, so a
	# NUL in (say) an id: field can't swallow the data: lines that follow it. The CR
	# of a CRLF terminator rides along as a trailing character and is stripped later
	# by _emit_sse_event, exactly as before.
	func _decode_sse_lines(event_bytes: PackedByteArray) -> String:
		var lines := PackedStringArray()
		var start := 0
		while start <= event_bytes.size():
			var nl := event_bytes.find(0x0A, start)
			var stop := nl if nl != -1 else event_bytes.size()
			lines.append(event_bytes.slice(start, stop).get_string_from_utf8())
			if nl == -1:
				break
			start = nl + 1
		return "\n".join(lines)

	# True when [param event_bytes] contains an "id:" field whose value holds a NUL
	# (0x00). The check runs on the raw bytes, before UTF-8 decoding, for two
	# reasons: get_string_from_utf8() truncates a value at its first NUL (hiding the
	# rest of the field), and a Godot String cannot carry a NUL at all (it decodes
	# to U+FFFD). Working at the byte level keeps the spec's "ignore a NUL id"
	# guarantee — which stops a NUL being echoed back as a Last-Event-ID header —
	# independent of how the engine decodes strings. The "\n" split and the "id:"
	# prefix (0x69 0x64 0x3A) are pure ASCII, so they are safe to match byte-wise.
	func _id_field_has_nul(event_bytes: PackedByteArray) -> bool:
		var start := 0
		while start <= event_bytes.size():
			var nl := event_bytes.find(0x0A, start)
			var end := nl if nl != -1 else event_bytes.size()
			var line := event_bytes.slice(start, end)
			if (
				line.size() >= 3
				and line[0] == 0x69 and line[1] == 0x64 and line[2] == 0x3A
				and line.find(0x00) != -1
			):
				return true
			if nl == -1:
				break
			start = nl + 1
		return false

	func _fail(error: RequestError, sse_retry_ms: int = -1) -> Response:
		var res := Response.new()
		res.ok = false
		res.error = error
		# Preserve a retry: hint parsed before a stream failed (e.g. idle timeout),
		# so a reconnecting caller still honors the server's backoff. -1 (the
		# default) on every non-SSE path leaves the field unset as before.
		res.sse_retry_ms = sse_retry_ms
		return res
