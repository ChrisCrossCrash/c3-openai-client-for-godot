extends GutTest


## Tests for [method C3OpenAIClient.get_models].
class TestGetModels extends GutTest:
	var client: C3TestDoubles.TestableClient

	func before_each() -> void:
		client = C3TestDoubles.TestableClient.new()
		add_child_autofree(client)

	func test_returns_models_response() -> void:
		client.preset_response = C3TestDoubles.ok_response(
			'{"data": [{"id": "model-a"}, {"id": "model-b"}]}'.to_utf8_buffer()
		)

		var result := await client.get_models()

		assert_is(result, C3OpenAIClient.ModelsResponse)

	func test_returns_model_ids() -> void:
		client.preset_response = C3TestDoubles.ok_response(
			'{"data": [{"id": "model-a"}, {"id": "model-b"}]}'.to_utf8_buffer()
		)

		var result := await client.get_models()

		assert_eq(result.ids, PackedStringArray(["model-a", "model-b"]))

	func test_raw_body_contains_full_response() -> void:
		client.preset_response = C3TestDoubles.ok_response(
			'{"object": "list", "data": [{"id": "model-a", "owned_by": "acme"}]}'
			. to_utf8_buffer()
		)

		var result := await client.get_models()

		assert_eq(result.raw_body.get("object"), "list")

	func test_raw_body_empty_on_network_error() -> void:
		client.preset_response = C3TestDoubles.transport_error_response(
			"Could not connect."
		)

		var result := await client.get_models()

		assert_eq(result.raw_body, {})

	func test_returns_empty_ids_for_empty_data() -> void:
		client.preset_response = C3TestDoubles.ok_response(
			'{"data": []}'.to_utf8_buffer()
		)

		var result := await client.get_models()

		assert_eq(result.ids, PackedStringArray())

	func test_missing_data_key_is_parse_failure() -> void:
		client.preset_response = C3TestDoubles.ok_response("{}".to_utf8_buffer())

		var result := await client.get_models()

		assert_false(result.ok)
		assert_eq(result.error.kind, &"parse")

	func test_non_array_data_is_parse_failure() -> void:
		client.preset_response = C3TestDoubles.ok_response(
			'{"data": "nope"}'.to_utf8_buffer()
		)

		var result := await client.get_models()

		assert_false(result.ok)
		assert_eq(result.error.kind, &"parse")

	func test_invalid_json_is_parse_failure() -> void:
		client.preset_response = C3TestDoubles.ok_response(
			"not json".to_utf8_buffer()
		)
		watch_signals(client)

		var result := await client.get_models()

		assert_false(result.ok)
		assert_eq(result.error.kind, &"parse")
		assert_signal_emitted(client, "request_failed")

	func test_skips_malformed_entries() -> void:
		client.preset_response = C3TestDoubles.ok_response(
			'{"data": [{"id": "model-a"}, {"no_id": true}, "junk"]}'
			. to_utf8_buffer()
		)

		var result := await client.get_models()

		assert_eq(result.ids, PackedStringArray(["model-a"]))

	func test_uses_correct_endpoint() -> void:
		client.base_url = "http://example.com/v1"
		client.preset_response = C3TestDoubles.ok_response(
			'{"data": []}'.to_utf8_buffer()
		)

		await client.get_models()

		assert_eq(client.request_log[0]["url"], "http://example.com/v1/models")

	func test_makes_exactly_one_request() -> void:
		client.preset_response = C3TestDoubles.ok_response(
			'{"data": []}'.to_utf8_buffer()
		)

		await client.get_models()

		assert_eq(client.request_log.size(), 1)

	func test_emits_request_failed_on_network_error() -> void:
		client.preset_response = C3TestDoubles.transport_error_response(
			"Could not connect."
		)
		watch_signals(client)

		await client.get_models()

		assert_signal_emitted(client, "request_failed")

	func test_returns_failed_response_on_network_error() -> void:
		client.preset_response = C3TestDoubles.transport_error_response(
			"Could not connect."
		)

		var result := await client.get_models()

		assert_false(result.ok)

	func test_emits_request_failed_on_http_failure() -> void:
		client.preset_response = C3TestDoubles.transport_error_response(
			"Connection error."
		)
		watch_signals(client)

		await client.get_models()

		assert_signal_emitted(client, "request_failed")

	func test_returns_failed_response_on_http_failure() -> void:
		client.preset_response = C3TestDoubles.transport_error_response(
			"Connection error."
		)

		var result := await client.get_models()

		assert_false(result.ok)
