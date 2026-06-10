class_name C3TestDoubles
## Shared test doubles for [C3OpenAIClient] tests.


## Fake SSE transport that records the request and never touches the network.
## Tests drive the stream by emitting the inherited [C3SSERequest] signals
## (stream_started, event_received, finished, request_failed) by hand.
class FakeSSERequest extends C3SSERequest:
	var requested := false
	var request_return: Error = OK
	var last_url := ""
	var last_headers: PackedStringArray = []
	var last_method: HTTPClient.Method = HTTPClient.METHOD_GET
	var last_body := ""

	func request(
		url: String,
		custom_headers: PackedStringArray = [],
		method: HTTPClient.Method = HTTPClient.METHOD_GET,
		request_body: String = "",
	) -> Error:
		requested = true
		last_url = url
		last_headers = custom_headers
		last_method = method
		last_body = request_body
		return request_return


## Test double for [C3OpenAIClient] that bypasses real HTTP requests.
## Set [member preset_response] before calling any method that triggers a request.
## Inspect [member request_log] after the call to assert which endpoints were called
## and with what bodies. Each entry is:[br] [code]{"method": String, "url": String, "body": Variant, "headers": PackedStringArray}[/code]
## [br]where [code]body[/code] is [code]null[/code] for GET requests, a [Dictionary]
## for POST requests, and the raw JSON [String] (possibly empty) for
## [method C3OpenAIClient.custom_request] calls.
@warning_ignore("missing_tool")
class TestableClient extends C3OpenAIClient:
	## The response returned by the fake HTTP layer. Defaults to an empty success.
	var preset_response := {"ok": true, "body": PackedByteArray()}
	## Ordered log of all requests made.
	## Each entry is:[br]
	## [code]{"method": String, "url": String, "body": Variant, "headers": PackedStringArray}[/code].
	var request_log: Array[Dictionary] = []
	## The most recent fake SSE transport handed to a [ChatStream]. Drive its
	## signals to simulate a stream. Set before the call via [member sse_request_return].
	var last_sse: FakeSSERequest
	## The [Error] the next fake SSE [method FakeSSERequest.request] should return.
	var sse_request_return: Error = OK

	func _make_sse_request() -> C3SSERequest:
		last_sse = FakeSSERequest.new()
		last_sse.request_return = sse_request_return
		return last_sse

	func _http_get(url: String, headers: PackedStringArray) -> Dictionary:
		request_log.append(
			{"method": "GET", "url": url, "body": null, "headers": headers}
		)
		return preset_response

	func _http_post(
		url: String, body: Dictionary, headers: PackedStringArray
	) -> Dictionary:
		request_log.append(
			{"method": "POST", "url": url, "body": body, "headers": headers}
		)
		return preset_response

	# Catches custom_request(), which calls _http_request() directly rather than
	# going through the _http_get()/_http_post() wrappers stubbed above.
	func _http_request(
		method: int, url: String, headers: PackedStringArray, body: String = ""
	) -> Dictionary:
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
	) -> Dictionary:
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
