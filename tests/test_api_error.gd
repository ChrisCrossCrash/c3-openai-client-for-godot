extends GutTest


## Unit tests for the [C3OpenAIClient.ApiError] value type and its factories.
class TestApiError extends GutTest:
	const ApiError := C3OpenAIClient.ApiError

	## A JSON-encoded OpenAI-style error body.
	func error_body(
		message := "Incorrect API key provided: ABC123.",
		code := "invalid_api_key",
		type := "invalid_request_error"
	) -> PackedByteArray:
		return JSON.stringify(
			{"error": {"message": message, "code": code, "type": type}}
		).to_utf8_buffer()

	func test_transport_factory() -> void:
		var e := ApiError.transport("Could not connect.")
		assert_eq(e.kind, &"transport")
		assert_eq(e.message, "Could not connect.")
		assert_eq(e.status, 0)

	func test_parse_failure_factory_keeps_raw() -> void:
		var e := ApiError.parse_failure("Bad JSON.", "not json")
		assert_eq(e.kind, &"parse")
		assert_eq(e.message, "Bad JSON.")
		assert_eq(e.raw, "not json")

	func test_cancelled_factory() -> void:
		var e := ApiError.cancelled("Stream cancelled.")
		assert_eq(e.kind, &"cancelled")
		assert_eq(e.message, "Stream cancelled.")

	func test_client_error_factory() -> void:
		var e := ApiError.client_error("Unsupported AudioStream type.")
		assert_eq(e.kind, &"client")
		assert_eq(e.message, "Unsupported AudioStream type.")

	func test_from_response_parses_api_error_body() -> void:
		var e := ApiError.from_response(401, error_body())
		assert_eq(e.kind, &"api")
		assert_eq(e.status, 401)
		assert_eq(e.code, "invalid_api_key")
		assert_eq(e.type, "invalid_request_error")
		assert_eq(e.message, "Incorrect API key provided: ABC123.")

	func test_from_response_keeps_raw_body() -> void:
		var body := error_body()
		var e := ApiError.from_response(401, body)
		assert_eq(e.raw, body.get_string_from_utf8())

	func test_from_response_missing_fields_default_to_empty() -> void:
		var body := (
			JSON.stringify({"error": {"message": "Oops."}}).to_utf8_buffer()
		)
		var e := ApiError.from_response(400, body)
		assert_eq(e.kind, &"api")
		assert_eq(e.message, "Oops.")
		assert_eq(e.code, "")
		assert_eq(e.type, "")

	func test_from_response_non_json_body_falls_back_to_http() -> void:
		var e := ApiError.from_response(
			500, "Internal Server Error".to_utf8_buffer()
		)
		assert_eq(e.kind, &"http")
		assert_eq(e.status, 500)
		assert_eq(e.message, "Request failed with status 500.")

	func test_from_response_json_without_error_key_falls_back_to_http() -> void:
		var e := ApiError.from_response(
			404, '{"detail": "nope"}'.to_utf8_buffer()
		)
		assert_eq(e.kind, &"http")
		assert_eq(e.message, "Request failed with status 404.")

	func test_to_string_includes_status_code_and_message() -> void:
		var s := str(ApiError.from_response(401, error_body()))
		assert_string_contains(s, "[api]")
		assert_string_contains(s, "status=401")
		assert_string_contains(s, "code=invalid_api_key")
		assert_string_contains(s, "Incorrect API key provided: ABC123.")

	func test_to_string_omits_zero_status_and_empty_code() -> void:
		assert_eq(str(ApiError.transport("Down.")), "[transport] Down.")


## Tests for _to_api_error(), which maps a failed C3HTTPRequest.Response into the
## addon's typed ApiError. Used by every endpoint on a failure.
class TestToApiError extends GutTest:
	var client: C3OpenAIClient

	func before_each() -> void:
		client = C3OpenAIClient.new()
		add_child_autofree(client)

	func test_transport_failure_is_transport_error() -> void:
		var err := client._to_api_error(
			C3TestDoubles.transport_error_response("Could not connect.")
		)
		assert_eq(err.kind, &"transport")
		assert_eq(err.message, "Could not connect.")

	func test_client_failure_is_client_error() -> void:
		var err := client._to_api_error(
			C3TestDoubles.client_error_response("Invalid URL.")
		)
		assert_eq(err.kind, &"client")
		assert_eq(err.message, "Invalid URL.")

	func test_non_2xx_with_error_body_is_api_error() -> void:
		var body := JSON.stringify(
			{"error": {"message": "Bad key.", "code": "invalid_api_key"}}
		)
		var err := client._to_api_error(
			C3TestDoubles.http_error_response(401, body)
		)
		assert_eq(err.kind, &"api")
		assert_eq(err.status, 401)
		assert_eq(err.code, "invalid_api_key")

	func test_non_2xx_without_error_body_is_http_error() -> void:
		var err := client._to_api_error(
			C3TestDoubles.http_error_response(500, "boom")
		)
		assert_eq(err.kind, &"http")
		assert_eq(err.status, 500)
