extends GutTest


## Tests for [method C3OpenAIClient.custom_request].
class TestCustomRequest extends GutTest:
	var client: C3TestDoubles.TestableClient

	func before_each() -> void:
		client = C3TestDoubles.TestableClient.new()
		add_child_autofree(client)
		client.preset_response = {
			"ok": true, "body": '{"object": "list"}'.to_utf8_buffer()
		}

	func test_returns_custom_request_response() -> void:
		var result := await client.custom_request("/embeddings", "POST")
		assert_is(result, C3OpenAIClient.CustomRequestResponse)

	func test_uses_the_given_path() -> void:
		client.base_url = "http://example.com/v1"
		await client.custom_request("/embeddings", "POST")
		assert_eq(
			client.request_log[0]["url"], "http://example.com/v1/embeddings"
		)

	func test_adds_missing_leading_slash() -> void:
		client.base_url = "http://example.com/v1"
		await client.custom_request("embeddings", "POST")
		assert_eq(
			client.request_log[0]["url"], "http://example.com/v1/embeddings"
		)

	func test_makes_exactly_one_request() -> void:
		await client.custom_request("/embeddings", "POST")
		assert_eq(client.request_log.size(), 1)

	func test_sends_method() -> void:
		await client.custom_request("/embeddings", "POST")
		assert_eq(client.request_log[0]["method"], "POST")

	func test_method_is_case_insensitive() -> void:
		await client.custom_request("/files/abc", "delete")
		assert_eq(client.request_log[0]["method"], "DELETE")

	func test_sends_body_as_json() -> void:
		await client.custom_request(
			"/embeddings", "POST", {"model": "m", "input": "hi"}
		)
		var sent: Dictionary = JSON.parse_string(client.request_log[0]["body"])
		assert_eq(sent, {"model": "m", "input": "hi"})

	func test_empty_body_sends_nothing() -> void:
		await client.custom_request("/models/gpt-x", "GET")
		assert_eq(client.request_log[0]["body"], "")

	func test_appends_query_string() -> void:
		await client.custom_request("/files", "GET", {}, {"limit": 5})
		assert_eq(
			client.request_log[0]["url"], client.base_url + "/files?limit=5"
		)

	func test_query_values_are_url_encoded() -> void:
		await client.custom_request("/files", "GET", {}, {"q": "a b"})
		var url: String = client.request_log[0]["url"]
		assert_true(url.ends_with("?q=a%20b"))

	func test_no_query_string_when_query_empty() -> void:
		await client.custom_request("/files", "GET")
		var url: String = client.request_log[0]["url"]
		assert_false(url.contains("?"))

	func test_sends_auth_header() -> void:
		client.api_key = "secret"
		await client.custom_request("/embeddings", "POST")
		var headers: PackedStringArray = client.request_log[0]["headers"]
		assert_true(headers.has("Authorization: Bearer secret"))

	func test_raw_body_contains_parsed_response() -> void:
		client.preset_response = {
			"ok": true,
			"body": '{"object": "embedding.list", "model": "m"}'.to_utf8_buffer()
		}
		var result := await client.custom_request("/embeddings", "POST")
		assert_true(result.ok)
		assert_eq(result.raw_body, {"object": "embedding.list", "model": "m"})

	func test_empty_body_response_is_success() -> void:
		client.preset_response = {"ok": true, "body": PackedByteArray()}
		var result := await client.custom_request("/files/abc", "DELETE")
		assert_true(result.ok)
		assert_null(result.error)
		assert_eq(result.raw_body, {})

	# --- failure paths ---

	func test_invalid_method_fails_without_sending() -> void:
		var result := await client.custom_request("/embeddings", "FETCH")
		assert_false(result.ok)
		assert_eq(result.error.kind, &"client")
		assert_eq(client.request_log.size(), 0)
		assert_push_error("Unsupported HTTP method")

	func test_returns_failed_response_on_network_error() -> void:
		client.preset_response = {
			"ok": false,
			"error": C3OpenAIClient.ApiError.transport("Could not connect.")
		}
		var result := await client.custom_request("/embeddings", "POST")
		assert_false(result.ok)
		assert_eq(result.error.kind, &"transport")

	func test_emits_request_failed_on_network_error() -> void:
		client.preset_response = {
			"ok": false,
			"error": C3OpenAIClient.ApiError.transport("Could not connect.")
		}
		watch_signals(client)
		await client.custom_request("/embeddings", "POST")
		assert_signal_emitted(client, "request_failed")

	func test_returns_failed_response_on_invalid_json() -> void:
		client.preset_response = {
			"ok": true, "body": "not json".to_utf8_buffer()
		}
		var result := await client.custom_request("/embeddings", "POST")
		assert_false(result.ok)
		assert_eq(result.error.kind, &"parse")

	func test_returns_failed_response_on_non_object_json() -> void:
		client.preset_response = {"ok": true, "body": "[1, 2]".to_utf8_buffer()}
		var result := await client.custom_request("/embeddings", "POST")
		assert_false(result.ok)
		assert_eq(result.error.kind, &"parse")
		assert_eq(result.error.raw, "[1, 2]")

	func test_emits_request_failed_on_parse_failure() -> void:
		client.preset_response = {
			"ok": true, "body": "not json".to_utf8_buffer()
		}
		watch_signals(client)
		await client.custom_request("/embeddings", "POST")
		assert_signal_emitted(client, "request_failed")


## Tests for [C3OpenAIClient.CustomRequestResponse] defaults.
class TestCustomRequestResponse extends GutTest:
	func test_default_ok() -> void:
		assert_true(C3OpenAIClient.CustomRequestResponse.new().ok)

	func test_default_error() -> void:
		assert_null(C3OpenAIClient.CustomRequestResponse.new().error)

	func test_default_raw_body() -> void:
		assert_eq(C3OpenAIClient.CustomRequestResponse.new().raw_body, {})
