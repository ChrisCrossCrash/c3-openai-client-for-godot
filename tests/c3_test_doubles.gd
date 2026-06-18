class_name C3TestDoubles
## Shared test doubles for [C3OpenAIClient] tests.

const C3HTTPRequest := preload("res://c3_openai_client/utils/c3_http_request.gd")


## Builds a successful 2xx [C3HTTPRequest.Response] carrying [param body].
static func ok_response(
	body: PackedByteArray = PackedByteArray(), status := 200
) -> C3HTTPRequest.Response:
	var resp := C3HTTPRequest.Response.new()
	resp.status = status
	resp.body = body
	return resp


## Builds a failed non-2xx (HTTP) [C3HTTPRequest.Response]. The upper layer routes
## this through [method C3OpenAIClient.ApiError.from_response], so a JSON error
## [param body] is parsed into a structured API error.
static func http_error_response(
	status: int, body := ""
) -> C3HTTPRequest.Response:
	var resp := C3HTTPRequest.Response.new()
	resp.ok = false
	resp.status = status
	resp.body = body.to_utf8_buffer()
	var e := C3HTTPRequest.RequestError.new()
	e.kind = C3HTTPRequest.RequestError.Kind.HTTP
	e.status = status
	e.message = "Request failed with status %d." % status
	resp.error = e
	return resp


## Builds a failed [C3HTTPRequest.Response] with a transport-level error.
static func transport_error_response(message := "") -> C3HTTPRequest.Response:
	var resp := C3HTTPRequest.Response.new()
	resp.ok = false
	resp.error = C3HTTPRequest.RequestError.transport(message)
	return resp


## Builds a failed [C3HTTPRequest.Response] with a client (bad-argument) error.
static func client_error_response(message := "") -> C3HTTPRequest.Response:
	var resp := C3HTTPRequest.Response.new()
	resp.ok = false
	resp.error = C3HTTPRequest.RequestError.client_error(message)
	return resp


## Test double for [C3OpenAIClient] that bypasses real HTTP requests.
## Set [member preset_response] before calling any method that triggers a request.
## Inspect [member request_log] after the call to assert which endpoints were called
## and with what bodies. Each entry is:[br] [code]{"method": String, "url": String, "body": Variant, "headers": PackedStringArray}[/code]
## [br]where [code]body[/code] is [code]null[/code] for GET requests, a [Dictionary]
## for POST requests, and the raw JSON [String] (possibly empty) for
## [method C3OpenAIClient.custom_request] calls.
@warning_ignore("missing_tool")
class TestableClient extends C3OpenAIClient:
	## Drives the fake streaming seam: emit to resume a parked [method _http_stream]
	## and resolve the [ChatStream] with [member stream_result].
	signal _stream_drive

	## The response returned by the fake HTTP layer. Defaults to an empty success.
	var preset_response: C3HTTPRequest.Response = C3TestDoubles.ok_response()
	## Ordered log of all requests made.
	## Each entry is:[br]
	## [code]{"method": String, "url": String, "body": Variant, "headers": PackedStringArray}[/code].
	var request_log: Array[Dictionary] = []

	## Streaming: the URL/headers/body the last stream was started with.
	var last_stream_url := ""
	var last_stream_headers: PackedStringArray = []
	var last_stream_body := ""
	## The event sink handed to the last stream. Call it to push SSE events:
	## [code]stream_on_event.call(data, "message")[/code].
	var stream_on_event: Callable
	## The cancellation token handed to the last stream.
	var stream_token: C3HTTPRequest.CancellationToken
	## The [C3HTTPRequest.Response] the parked stream returns once driven. Set it,
	## then emit [signal _stream_drive] to finish the stream.
	var stream_result: C3HTTPRequest.Response = C3TestDoubles.ok_response()

	func _http_stream(
		url: String,
		headers: PackedStringArray,
		body: String,
		on_event: Callable,
		token: C3HTTPRequest.CancellationToken
	) -> C3HTTPRequest.Response:
		last_stream_url = url
		last_stream_headers = headers
		last_stream_body = body
		stream_on_event = on_event
		stream_token = token
		# Park until the test drives the stream, returning control so it can connect
		# signals and push events. Emitting the signal an await is parked on resumes
		# this synchronously, so `finished` fires during the driving emit.
		await _stream_drive
		return stream_result

	func _http_get(
		url: String, headers: PackedStringArray
	) -> C3HTTPRequest.Response:
		request_log.append(
			{"method": "GET", "url": url, "body": null, "headers": headers}
		)
		return preset_response

	func _http_post(
		url: String, body: Dictionary, headers: PackedStringArray
	) -> C3HTTPRequest.Response:
		request_log.append(
			{"method": "POST", "url": url, "body": body, "headers": headers}
		)
		return preset_response

	# Catches custom_request(), which calls _http_request() directly rather than
	# going through the _http_get()/_http_post() wrappers stubbed above.
	func _http_request(
		method: C3HTTPRequest.Method,
		url: String,
		headers: PackedStringArray,
		body: String = ""
	) -> C3HTTPRequest.Response:
		request_log.append({
			"method": _HTTP_METHODS.find_key(method),
			"url": url,
			"body": body,
			"headers": headers,
		})
		return preset_response

	func _http_post_multipart(
		url: String,
		form_fields: Dictionary,
		file_field: String,
		file_bytes: PackedByteArray,
		filename: String,
		file_content_type: String,
		headers: PackedStringArray
	) -> C3HTTPRequest.Response:
		request_log.append({
			"method": "POST_MULTIPART",
			"url": url,
			"form_fields": form_fields,
			"file_field": file_field,
			"file_bytes": file_bytes,
			"filename": filename,
			"file_content_type": file_content_type,
			"headers": headers,
		})
		return preset_response
