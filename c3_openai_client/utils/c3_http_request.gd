# C3 HTTP Request
# v0.2.0
# Modified from:
# https://github.com/ChrisCrossCrash/c3-http-request/blob/3c636292eb12cd507531a1f73347ce2af28d04af/c3_http_request/c3_http_request.gd
# Modifications are noted with a MODIFIED comment.

# MODIFIED: Removed global class_name to prevent conflicts.
# class_name C3HTTPRequest
## General-purpose async HTTP client that requires no scene tree.
##
## Call the static [method request] from anywhere — no [Node] to add or
## configure. Every call [code]await[/code]s a [Response] carrying
## [member Response.ok] as a single failure check that covers transport
## errors, timeouts, and non-2xx statuses alike.

## HTTP method for [method request].
enum Method { GET = 0, HEAD, POST, PUT, DELETE, OPTIONS, PATCH }

## The installed version of this addon, e.g. for logging or feature gating.
const VERSION := "v0.2.0"

const _METHOD_MAP: Dictionary = {
	Method.GET: HTTPClient.METHOD_GET,
	Method.HEAD: HTTPClient.METHOD_HEAD,
	Method.POST: HTTPClient.METHOD_POST,
	Method.PUT: HTTPClient.METHOD_PUT,
	Method.DELETE: HTTPClient.METHOD_DELETE,
	Method.OPTIONS: HTTPClient.METHOD_OPTIONS,
	Method.PATCH: HTTPClient.METHOD_PATCH,
}

static var _impl: _Impl = _Impl.new()


## Sends an HTTP request to [param url] and returns the response. [br]
## [param custom_headers] are sent alongside any headers injected by
## [member Options.accept_gzip]. [br]
## [param method] is a [enum Method] value; defaults to [code]GET[/code]. [br]
## [param request_data] is the raw request body string. [br]
## [param options] controls timeout, redirects, and other per-request
## settings; [code]null[/code] uses all defaults.
static func request(
	url: String,
	custom_headers: PackedStringArray = PackedStringArray(),
	method: Method = Method.GET,
	request_data: String = "",
	options: Options = null
) -> Response:
	var opts: Options = options if options != null else Options.new()
	return await _impl.execute(
		url, custom_headers, _METHOD_MAP[method], request_data, opts
	)


## Sends an HTTP request with a raw byte-array body, like [method request] but
## the body is sent as-is without UTF-8 encoding. Use for binary payloads
## (encoded files, serialized data, custom binary protocols). [br]
## [param request_data_raw] is the raw request body bytes. [br]
## [param method] defaults to [code]POST[/code]; a raw body is ignored on
## [code]GET[/code]. [br]
## See [method request] for the remaining parameters.
static func request_raw(
	url: String,
	custom_headers: PackedStringArray = PackedStringArray(),
	method: Method = Method.POST,
	request_data_raw: PackedByteArray = PackedByteArray(),
	options: Options = null
) -> Response:
	var opts: Options = options if options != null else Options.new()
	return await _impl.execute(
		url, custom_headers, _METHOD_MAP[method], request_data_raw, opts
	)


## Per-request configuration. Defaults match [HTTPRequest] node defaults.
class Options:
	## Maximum seconds to wait for a response. [code]0.0[/code] disables the timeout.
	var timeout: float = 0.0
	## Maximum response body size in bytes. [code]-1[/code] is unlimited.
	var body_size_limit: int = -1
	## Size of each read buffer in bytes. Lower values reduce peak memory use
	## during large downloads.
	var download_chunk_size: int = 65536
	## When [code]true[/code], sends [code]Accept-Encoding: gzip, deflate[/code]
	## and decompresses the response body automatically. Has no effect when
	## [member download_file] is set.
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
	## var opts := C3HTTPRequest.Options.new()
	## opts.use_threads = true
	## opts.on_status_changed = func(status: HTTPClient.Status) -> void:
	##     status_changes.append(status)
	##
	## await C3HTTPRequest.request("https://example.com",
	##     PackedStringArray(), C3HTTPRequest.Method.GET, "", opts)
	##
	## # Every status change has already fired — none is still queued for a later
	## # frame — so this prints the same count with use_threads true or false.
	## print(status_changes.size())
	## [/codeblock]
	var use_threads: bool = false
	## Path to write the response body to on disk. When non-empty,
	## [member Response.body] is empty and the data is in the file. A partial
	## file may be left on disk if the request fails after the connection opens.
	var download_file: String = ""
	## TLS options for HTTPS connections. [code]null[/code] uses
	## [method TLSOptions.client] (validates the server certificate). Override
	## with [method TLSOptions.client_unsafe] for self-signed certificates.
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
	## streams in, as
	## [code]on_sse_event.call(data: String, event_type: String)[/code]. When set,
	## a 2xx response body is parsed as an SSE stream rather than collected:
	## [member Response.body] stays empty and [method C3HTTPRequest.request]
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


## The response returned by [method C3HTTPRequest.request].
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
	## The response body decoded as UTF-8. Computed lazily on first access and
	## cached, so binary responses never pay the decode cost. Returns
	## [code]""[/code] for an empty or non-UTF-8 body.
	var text: String:
		get:
			if _text_cache == null:
				_text_cache = body.get_string_from_utf8()
				if _text_cache == "" and not body.is_empty():
					push_error("C3HTTPRequest: response body is not valid UTF-8.")
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
						"C3HTTPRequest: response body is not valid JSON: "
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


class _Impl:
	# Worker-thread poll pacing in microseconds (1 ms), mirroring the cadence of
	# HTTPRequest's threaded mode. Only used when running on a worker thread.
	# Note: on Windows, using OS.delay_usec with any value less than 2000
	# is effectively the same as 2000 due to the scheduler's granularity.
	const _PUMP_DELAY_USEC := 1000

	func execute(
		url: String,
		custom_headers: PackedStringArray,
		method: int,
		request_data: Variant,
		options: Options, # MODIFIED
		_redirects_left: int = -1,
		_on_worker: bool = false
	) -> Response: # MODIFIED
		# options.use_threads is read exactly once — here — to decide whether to
		# spawn a worker. Every downstream poll and dispatch decision uses _on_worker
		# instead, so the fallback path (threads requested but unavailable) behaves
		# identically to the cooperative path.
		if options.use_threads and not _on_worker and _threads_available():
			return await _run_threaded(
				url, custom_headers, method, request_data, options, _redirects_left
			)

		if _cancelled(options):
			return _fail(RequestError.cancelled("Request was cancelled.")) # MODIFIED
		var redirects_left := (
			options.max_redirects if _redirects_left < 0 else _redirects_left
		)
		# A valid on_sse_event sink switches a 2xx body to incremental SSE parsing.
		var streaming := options.on_sse_event.is_valid()

		var parsed := _parse_url(url)
		if parsed.is_empty():
			return _fail(RequestError.client_error( # MODIFIED
					'Invalid URL: "%s".' % url
			))

		var file: FileAccess = null
		if not options.download_file.is_empty() and not streaming:
			file = FileAccess.open(options.download_file, FileAccess.WRITE)
			if file == null:
				return _fail(RequestError.client_error( # MODIFIED
					"Cannot open download file: \"%s\"." % options.download_file
				))

		var all_headers := PackedStringArray()
		if options.accept_gzip and options.download_file.is_empty() and not streaming:
			all_headers.append("Accept-Encoding: gzip, deflate")
		all_headers.append_array(custom_headers)

		var client := HTTPClient.new()
		client.set_read_chunk_size(options.download_chunk_size)
		var proxies := _resolve_proxies(options)
		if proxies.has("http"):
			client.set_http_proxy(proxies["http"][0], proxies["http"][1])
		if proxies.has("https"):
			client.set_https_proxy(proxies["https"][0], proxies["https"][1])

		var err: int
		if parsed["tls"]:
			var tls: TLSOptions = (
				options.tls_options
				if options.tls_options != null
				else TLSOptions.client()
			)
			err = client.connect_to_host(parsed["host"], parsed["port"], tls)
		else:
			err = client.connect_to_host(parsed["host"], parsed["port"])
		if err != OK:
			return _fail(RequestError.transport( # MODIFIED
				"Failed to start connection (error %d)." % err
			))

		var tree := Engine.get_main_loop() as SceneTree
		var start_ms := Time.get_ticks_msec()
		var last_status := HTTPClient.STATUS_DISCONNECTED

		while true:
			client.poll()
			last_status = _emit_status_change(client, last_status, options, _on_worker)
			if client.get_status() not in [
				HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING
			]:
				break
			if _timed_out(start_ms, options.timeout):
				return _fail(RequestError.timed_out( # MODIFIED
					"Timed out while connecting."
				))
			if _cancelled(options):
				return _fail(RequestError.cancelled( # MODIFIED
						"Request was cancelled."
				))
			await _pump(tree, _on_worker)

		if client.get_status() != HTTPClient.STATUS_CONNECTED:
			return _fail(RequestError.transport( # MODIFIED
				"Could not connect (status %d)." % client.get_status()
			))

		if request_data is PackedByteArray:
			err = client.request_raw(
				method, parsed["path"], all_headers, request_data
			)
		else:
			err = client.request(
				method, parsed["path"], all_headers, request_data
			)
		if err != OK:
			return _fail(RequestError.transport( # MODIFIED
				"Failed to send request (error %d)." % err
			))

		while true:
			client.poll()
			last_status = _emit_status_change(client, last_status, options, _on_worker)
			if client.get_status() != HTTPClient.STATUS_REQUESTING:
				break
			if _timed_out(start_ms, options.timeout):
				return _fail(RequestError.timed_out( # MODIFIED
					"Timed out waiting for response."
				))
			if _cancelled(options):
				return _fail(RequestError.cancelled( # MODIFIED
					"Request was cancelled."
				))
			await _pump(tree, _on_worker)

		if not client.has_response():
			return _fail(RequestError.transport( # MODIFIED
				"No response received."
			))

		var status := client.get_response_code()
		var resp_headers: PackedStringArray = client.get_response_headers()

		# A 2xx body with a sink set is parsed as an SSE stream; everything else
		# (non-2xx error bodies, redirect bodies) is collected normally.
		var sse_mode := streaming and status >= 200 and status < 300
		# On a worker thread, marshal SSE events back to the main thread so the
		# caller's sink never runs off-thread; otherwise dispatch directly.
		var sse_sink := options.on_sse_event
		if _on_worker and sse_sink.is_valid():
			sse_sink = func(data: String, event_type: String) -> void:
				options.on_sse_event.call_deferred(data, event_type)
		var body_bytes := PackedByteArray()
		var sse_buffer := PackedByteArray()
		var last_recv_ms := start_ms
		# Content-Length if the server sent one, else -1 (e.g. chunked responses).
		var total_bytes := client.get_response_body_length()
		var bytes_received := 0
		while client.get_status() == HTTPClient.STATUS_BODY:
			# While streaming, timeout is idle time since the last bytes, not total
			# stream duration — a healthy long-lived stream must not be cut off.
			if _timed_out(last_recv_ms if sse_mode else start_ms, options.timeout):
				if file != null:
					file.close()
				return _fail(RequestError.timed_out( # MODIFIED
					"Stream idle for too long." if sse_mode
					else "Timed out while reading body."
				))
			if _cancelled(options):
				if file != null:
					file.close()
				return _fail(RequestError.cancelled( # MODIFIED
					"Request was cancelled."
				))
			client.poll()
			last_status = _emit_status_change(client, last_status, options, _on_worker)
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
					return _fail(RequestError.body_size_limit_exceeded( # MODIFIED
						"SSE event exceeded limit of %d bytes."
						% options.body_size_limit
					))
				sse_buffer.append_array(chunk)
				sse_buffer = _drain_sse_buffer(sse_buffer, sse_sink)
				continue
			if (
				options.body_size_limit >= 0
				and body_bytes.size() + chunk.size() > options.body_size_limit
			):
				if file != null:
					file.close()
				return _fail(RequestError.body_size_limit_exceeded( # MODIFIED
					"Response body exceeded limit of %d bytes."
					% options.body_size_limit
				))
			if file != null:
				file.store_buffer(chunk)
			else:
				body_bytes.append_array(chunk)
			bytes_received += chunk.size()
			_emit(options.on_progress, _on_worker, [bytes_received, total_bytes])

		if file != null:
			file.close()

		# A server may end the final event without a trailing blank line; flush
		# what remains. Every byte has arrived, so decode the tail in one pass.
		if sse_mode:
			var tail := sse_buffer.get_string_from_utf8()
			if not tail.strip_edges().is_empty():
				_emit_sse_event(tail, sse_sink)

		if options.accept_gzip and file == null and not body_bytes.is_empty():
			var encoding := _header_value(resp_headers, "Content-Encoding").to_lower()
			var mode := -1
			if encoding == "gzip":
				mode = FileAccess.COMPRESSION_GZIP
			elif encoding == "deflate":
				mode = FileAccess.COMPRESSION_DEFLATE
			if mode != -1:
				var decompressed := body_bytes.decompress_dynamic(-1, mode)
				if not decompressed.is_empty():
					body_bytes = decompressed

		if status >= 300 and status < 400 and redirects_left > 0:
			var location := _header_value(resp_headers, "Location")
			if not location.is_empty():
				return await execute(
					_resolve_redirect_url(
						location,
						parsed["host"],
						parsed["port"],
						parsed["tls"],
						parsed["path"]
					),
					custom_headers,
					_redirect_method(method, status),
					_redirect_body(method, status, request_data),
					options,
					redirects_left - 1,
					_on_worker
				)

		var res := Response.new() # MODIFIED
		res.status = status
		res.headers = resp_headers
		res.body = body_bytes if file == null else PackedByteArray()
		if status < 200 or status >= 300:
			res.ok = false
			var e := RequestError.new() # MODIFIED
			e.kind = RequestError.Kind.HTTP # MODIFIED
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

	# Yields between polls. On a worker thread it sleeps briefly and returns
	# synchronously — the await never suspends, so execute() runs straight through
	# on the worker. On the main thread it yields to the next frame, keeping it
	# responsive.
	func _pump(tree: SceneTree, on_worker: bool) -> void:
		if on_worker:
			OS.delay_usec(_PUMP_DELAY_USEC)
		else:
			await tree.process_frame

	# Runs execute() on a dedicated background thread (polling at OS speed) and
	# awaits its completion on the main thread, leaving the public await API
	# unchanged. The worker re-enters execute() with _on_worker = true.
	func _run_threaded(
		url: String,
		custom_headers: PackedStringArray,
		method: int,
		request_data: Variant,
		options: Options, # MODIFIED
		redirects_left: int
	) -> Response: # MODIFIED
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
			func() -> Response: # MODIFIED
				return await execute(
					url, custom_headers, method, request_data, options,
					redirects_left, true
				)
		)
		while thread.is_alive():
			await tree.process_frame
		var result: Variant = thread.wait_to_finish()
		# Enforce the worker-never-suspends invariant: on the worker path _pump
		# sleeps synchronously and never yields, so execute() must run straight
		# through and the thread function must return a Response. If a future change
		# adds an await that actually suspends, the function returns a coroutine
		# state instead — fail loudly here rather than corrupting the result.
		assert(
			result is Response, # MODIFIED
			"C3HTTPRequest: threaded worker suspended; the worker path must run "
			+ "synchronously (see _pump). Did a new await get added to execute()?"
		)
		var res: Response = result # MODIFIED
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

	func _parse_url(url: String) -> Dictionary:
		var sep := url.find("://")
		if sep == -1:
			return {}
		var scheme := url.substr(0, sep).to_lower()
		if scheme != "http" and scheme != "https":
			return {}
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
			return {}
		var fragment := path.find("#")
		if fragment != -1:
			path = path.substr(0, fragment)
		var port := 443 if scheme == "https" else 80
		var host := host_part
		if host_part.begins_with("["):
			var bracket_close := host_part.find("]")
			if bracket_close == -1:
				return {}
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
		return {
			"host": host,
			"port": port,
			"path": path,
			"tls": scheme == "https"
		}

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

	func _cancelled(options: Options) -> bool: # MODIFIED
		return (
			options.cancellation_token != null
			and options.cancellation_token.is_cancelled()
		)

	# Emits on_status_changed when the client's status differs from last_status,
	# returning the current status to carry forward to the next poll.
	func _emit_status_change(
		client: HTTPClient,
		last_status: HTTPClient.Status,
		options: Options, # MODIFIED
		on_worker: bool
	) -> HTTPClient.Status:
		var current := client.get_status()
		if current != last_status:
			_emit(options.on_status_changed, on_worker, [current])
		return current

	func _header_value(headers: PackedStringArray, name: String) -> String:
		var prefix := name.to_lower() + ": "
		for header: String in headers:
			if header.to_lower().begins_with(prefix):
				return header.substr(prefix.length()).strip_edges()
		return ""

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

	# Carves every complete event out of [param buffer], dispatching each to
	# [param on_event], and returns the trailing partial bytes (an incomplete
	# event, possibly mid-character) to keep for the next read.
	func _drain_sse_buffer(
		buffer: PackedByteArray, on_event: Callable
	) -> PackedByteArray:
		var bound := _find_sse_boundary(buffer)
		while bound.x != -1:
			_emit_sse_event(buffer.slice(0, bound.x).get_string_from_utf8(), on_event)
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
	# [param on_event] with (data, event_type). Multiple data: lines are joined
	# with newlines; event_type defaults to "message" per the SSE spec. Comment
	# lines (":") and events with no data: lines (bare keep-alives, id-only
	# blocks) are dropped. The id: and retry: fields are ignored — this client
	# does not reconnect.
	func _emit_sse_event(raw_event: String, on_event: Callable) -> void:
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
		if data_lines.is_empty():
			return
		on_event.call("\n".join(data_lines), event_type)

	func _fail(error: RequestError) -> Response: # MODIFIED
		var res := Response.new() # MODIFIED
		res.ok = false
		res.error = error
		return res
