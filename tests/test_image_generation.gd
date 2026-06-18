extends GutTest


## Tests for [C3OpenAIClient.ImageOptions] defaults.
class TestImageOptions extends GutTest:
	func test_default_model() -> void:
		assert_eq(C3OpenAIClient.ImageOptions.new().model, "")

	func test_default_size() -> void:
		assert_eq(C3OpenAIClient.ImageOptions.new().size, "")

	func test_default_quality() -> void:
		assert_eq(C3OpenAIClient.ImageOptions.new().quality, "")

	func test_default_background() -> void:
		assert_eq(C3OpenAIClient.ImageOptions.new().background, "")

	func test_default_extra_body() -> void:
		assert_eq(C3OpenAIClient.ImageOptions.new().extra_body, {})

	func test_default_response_format() -> void:
		assert_eq(C3OpenAIClient.ImageOptions.new().response_format, "auto")


## Tests for [method C3OpenAIClient.create_image].
class TestCreateImage extends GutTest:
	const C3HTTPRequest := preload("res://c3_openai_client/utils/c3_http_request.gd")

	var client: C3TestDoubles.TestableClient
	var png_b64: String

	func before_each() -> void:
		client = C3TestDoubles.TestableClient.new()
		add_child_autofree(client)
		var img := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color.RED)
		png_b64 = Marshalls.raw_to_base64(img.save_png_to_buffer())

	## A preset success response carrying a real PNG as a b64_json data entry in
	## the OpenAI image response shape. Pass a revised prompt to include one.
	func ok_image(revised_prompt: Variant = null) -> C3HTTPRequest.Response:
		var entry := {"b64_json": png_b64}
		if revised_prompt != null:
			entry["revised_prompt"] = revised_prompt
		var json := JSON.stringify({"created": 1234567890, "data": [entry]})
		return C3TestDoubles.ok_response(json.to_utf8_buffer())

	func test_returns_image_generation_response() -> void:
		client.preset_response = ok_image()
		var result := await client.create_image("A red square")
		assert_is(result, C3OpenAIClient.ImageGenerationResponse)

	func test_image_is_decoded() -> void:
		client.preset_response = ok_image()
		var result := await client.create_image("A red square")
		assert_is(result.image, Image)
		assert_eq(result.image.get_width(), 4)
		assert_eq(result.image.get_height(), 4)

	func test_data_carries_b64_json_entry() -> void:
		client.preset_response = ok_image()
		var result := await client.create_image("A red square")
		assert_eq(result.data.get("b64_json"), png_b64)

	func test_data_carries_revised_prompt() -> void:
		client.preset_response = ok_image("A photorealistic red square")
		var result := await client.create_image("A red square")
		assert_eq(
			result.data.get("revised_prompt"), "A photorealistic red square"
		)

	func test_url_response_leaves_image_null() -> void:
		# A url entry is a legitimate success — image is null, data carries the url.
		var json := JSON.stringify(
			{"data": [{"url": "https://example.com/img.png"}]}
		)
		client.preset_response = C3TestDoubles.ok_response(json.to_utf8_buffer())
		var result := await client.create_image("A red square")
		assert_true(result.ok)
		assert_null(result.image)
		assert_eq(result.data.get("url"), "https://example.com/img.png")

	func test_uses_correct_endpoint() -> void:
		client.base_url = "http://example.com/v1"
		client.preset_response = ok_image()
		await client.create_image("A red square")
		assert_eq(
			client.request_log[0]["url"],
			"http://example.com/v1/images/generations"
		)

	func test_makes_exactly_one_request() -> void:
		client.preset_response = ok_image()
		await client.create_image("A red square")
		assert_eq(client.request_log.size(), 1)

	func test_sends_prompt_in_body() -> void:
		client.preset_response = ok_image()
		await client.create_image("A serene mountain lake")
		assert_eq(
			client.request_log[0]["body"]["prompt"], "A serene mountain lake"
		)

	func test_sends_model_in_body() -> void:
		client.preset_response = ok_image()
		var opts := C3OpenAIClient.ImageOptions.new()
		opts.model = "gpt-image-1-mini"
		await client.create_image("A red square", opts)
		assert_eq(client.request_log[0]["body"]["model"], "gpt-image-1-mini")

	func test_sends_n_as_one() -> void:
		client.preset_response = ok_image()
		await client.create_image("A red square")
		assert_eq(client.request_log[0]["body"]["n"], 1)

	func test_size_omitted_when_empty() -> void:
		client.preset_response = ok_image()
		await client.create_image("A red square")
		assert_false(client.request_log[0]["body"].has("size"))

	func test_size_sent_when_set() -> void:
		client.preset_response = ok_image()
		var opts := C3OpenAIClient.ImageOptions.new()
		opts.size = "1024x1024"
		await client.create_image("A red square", opts)
		assert_eq(client.request_log[0]["body"]["size"], "1024x1024")

	func test_quality_omitted_when_empty() -> void:
		client.preset_response = ok_image()
		await client.create_image("A red square")
		assert_false(client.request_log[0]["body"].has("quality"))

	func test_quality_sent_when_set() -> void:
		client.preset_response = ok_image()
		var opts := C3OpenAIClient.ImageOptions.new()
		opts.quality = "low"
		await client.create_image("A red square", opts)
		assert_eq(client.request_log[0]["body"]["quality"], "low")

	func test_background_omitted_when_empty() -> void:
		client.preset_response = ok_image()
		await client.create_image("A red square")
		assert_false(client.request_log[0]["body"].has("background"))

	func test_background_sent_when_set() -> void:
		client.preset_response = ok_image()
		var opts := C3OpenAIClient.ImageOptions.new()
		opts.background = "transparent"
		await client.create_image("A red square", opts)
		assert_eq(client.request_log[0]["body"]["background"], "transparent")

	func test_extra_body_adds_keys_to_body() -> void:
		client.preset_response = ok_image()
		var opts := C3OpenAIClient.ImageOptions.new()
		opts.extra_body = {"negative_prompt": "blurry"}
		await client.create_image("A red square", opts)
		assert_eq(client.request_log[0]["body"]["negative_prompt"], "blurry")

	func test_extra_body_overrides_library_keys() -> void:
		client.preset_response = ok_image()
		var opts := C3OpenAIClient.ImageOptions.new()
		opts.extra_body = {"n": 4}
		await client.create_image("A red square", opts)
		assert_eq(client.request_log[0]["body"]["n"], 4)

	func test_raw_body_contains_full_response() -> void:
		client.preset_response = ok_image()
		var result := await client.create_image("A red square")
		assert_eq(result.raw_body.get("created"), 1234567890)

	func test_raw_body_empty_on_network_error() -> void:
		client.preset_response = C3TestDoubles.transport_error_response(
			"Could not connect."
		)
		var result := await client.create_image("A red square")
		assert_eq(result.raw_body, {})

	# --- response_format "auto" resolution ---

	func test_auto_omits_response_format_for_non_dalle() -> void:
		client.preset_response = ok_image()
		var opts := C3OpenAIClient.ImageOptions.new()
		opts.model = "gpt-image-1-mini"
		await client.create_image("A red square", opts)
		assert_false(client.request_log[0]["body"].has("response_format"))

	func test_auto_sends_b64_json_for_dalle() -> void:
		client.preset_response = ok_image()
		var opts := C3OpenAIClient.ImageOptions.new()
		opts.model = "dall-e-3"
		await client.create_image("A red square", opts)
		assert_eq(client.request_log[0]["body"]["response_format"], "b64_json")

	func test_auto_is_case_insensitive_for_dalle() -> void:
		client.preset_response = ok_image()
		var opts := C3OpenAIClient.ImageOptions.new()
		opts.model = "DALL-E-3"
		await client.create_image("A red square", opts)
		assert_eq(client.request_log[0]["body"]["response_format"], "b64_json")

	func test_empty_response_format_omits_even_for_dalle() -> void:
		client.preset_response = ok_image()
		var opts := C3OpenAIClient.ImageOptions.new()
		opts.model = "dall-e-3"
		opts.response_format = ""
		await client.create_image("A red square", opts)
		assert_false(client.request_log[0]["body"].has("response_format"))

	func test_explicit_response_format_passed_through() -> void:
		client.preset_response = ok_image()
		var opts := C3OpenAIClient.ImageOptions.new()
		opts.response_format = "url"
		await client.create_image("A red square", opts)
		assert_eq(client.request_log[0]["body"]["response_format"], "url")

	# --- failure paths ---

	func test_returns_failed_response_on_network_error() -> void:
		client.preset_response = C3TestDoubles.transport_error_response(
			"Could not connect."
		)
		var result := await client.create_image("A red square")
		assert_false(result.ok)

	func test_emits_request_failed_on_network_error() -> void:
		client.preset_response = C3TestDoubles.transport_error_response(
			"Could not connect."
		)
		watch_signals(client)
		await client.create_image("A red square")
		assert_signal_emitted(client, "request_failed")

	func test_returns_failed_response_on_invalid_json() -> void:
		client.preset_response = C3TestDoubles.ok_response(
			"not json".to_utf8_buffer()
		)
		var result := await client.create_image("A red square")
		assert_false(result.ok)
		assert_eq(result.error.kind, &"parse")

	func test_returns_failed_response_on_missing_data() -> void:
		client.preset_response = C3TestDoubles.ok_response("{}".to_utf8_buffer())
		var result := await client.create_image("A red square")
		assert_false(result.ok)
		assert_eq(result.error.kind, &"parse")

	func test_returns_failed_response_on_empty_data() -> void:
		client.preset_response = C3TestDoubles.ok_response(
			'{"data": []}'.to_utf8_buffer()
		)
		var result := await client.create_image("A red square")
		assert_false(result.ok)
		assert_eq(result.error.kind, &"parse")

	func test_returns_failed_response_on_malformed_entry() -> void:
		# data[0] is not an object — cannot be exposed as the data dictionary.
		client.preset_response = C3TestDoubles.ok_response(
			'{"data": [42]}'.to_utf8_buffer()
		)
		var result := await client.create_image("A red square")
		assert_false(result.ok)
		assert_eq(result.error.kind, &"parse")

	func test_undecodable_b64_fails_response() -> void:
		# b64_json present but not a recognized image: hard failure, but the raw
		# bytes are preserved on data.
		var bad := Marshalls.raw_to_base64(
			PackedByteArray([0x00, 0x01, 0x02, 0x03])
		)
		var json := JSON.stringify({"data": [{"b64_json": bad}]})
		client.preset_response = C3TestDoubles.ok_response(json.to_utf8_buffer())
		var result := await client.create_image("A red square")
		assert_false(result.ok)
		assert_eq(result.error.kind, &"parse")
		assert_null(result.image)
		assert_eq(result.data.get("b64_json"), bad)
		# image_from_base64 pushes an error for the unrecognized format; expected.
		assert_push_error("could not detect")

	func test_emits_request_failed_on_parse_failure() -> void:
		client.preset_response = C3TestDoubles.ok_response(
			"not json".to_utf8_buffer()
		)
		watch_signals(client)
		await client.create_image("A red square")
		assert_signal_emitted(client, "request_failed")


## Tests for [method C3OpenAIClient.image_from_base64].
class TestImageFromBase64 extends GutTest:
	func test_decodes_png() -> void:
		var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color.RED)
		var b64 := Marshalls.raw_to_base64(img.save_png_to_buffer())
		var decoded := C3OpenAIClient.image_from_base64(b64)
		assert_is(decoded, Image)
		assert_eq(decoded.get_width(), 16)
		assert_eq(decoded.get_height(), 16)

	func test_decodes_jpeg() -> void:
		var img := Image.create_empty(16, 16, false, Image.FORMAT_RGB8)
		img.fill(Color.BLUE)
		var b64 := Marshalls.raw_to_base64(img.save_jpg_to_buffer())
		var decoded := C3OpenAIClient.image_from_base64(b64)
		assert_is(decoded, Image)
		assert_eq(decoded.get_width(), 16)

	func test_decodes_webp() -> void:
		var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color.GREEN)
		var b64 := Marshalls.raw_to_base64(img.save_webp_to_buffer())
		var decoded := C3OpenAIClient.image_from_base64(b64)
		assert_is(decoded, Image)
		assert_eq(decoded.get_width(), 16)

	func test_empty_returns_null() -> void:
		assert_null(C3OpenAIClient.image_from_base64(""))
		assert_push_error("empty string")

	func test_unknown_format_returns_null() -> void:
		var b64 := Marshalls.raw_to_base64(
			PackedByteArray([0x00, 0x01, 0x02, 0x03])
		)
		assert_null(C3OpenAIClient.image_from_base64(b64))
		assert_push_error("could not detect")

	func test_corrupt_png_returns_null() -> void:
		# Valid PNG signature followed by garbage: detected as PNG, fails to decode.
		var b64 := Marshalls.raw_to_base64(PackedByteArray(
			[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01]
		))
		assert_null(C3OpenAIClient.image_from_base64(b64))
		# Decoding corrupt PNG bytes makes Godot's image loader emit engine-level
		# errors (plus our own push_error). They are expected here, so mark them
		# handled to keep GUT from failing the test on them.
		for e in get_errors():
			e.handled = true


## Tests for [method C3OpenAIClient.download_image].
class TestDownloadImage extends GutTest:
	var client: C3TestDoubles.TestableClient

	func before_each() -> void:
		client = C3TestDoubles.TestableClient.new()
		add_child_autofree(client)

	func test_downloads_and_decodes_png() -> void:
		var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color.RED)
		client.preset_response = C3TestDoubles.ok_response(img.save_png_to_buffer())
		var decoded := await client.download_image("https://example.com/img.png")
		assert_is(decoded, Image)
		assert_eq(decoded.get_width(), 16)
		assert_eq(decoded.get_height(), 16)

	func test_requests_the_given_url() -> void:
		var img := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
		client.preset_response = C3TestDoubles.ok_response(img.save_png_to_buffer())
		await client.download_image("https://cdn.example.com/abc.png")
		assert_eq(client.request_log[0]["method"], "GET")
		assert_eq(
			client.request_log[0]["url"], "https://cdn.example.com/abc.png"
		)

	func test_returns_null_on_network_error() -> void:
		client.preset_response = C3TestDoubles.transport_error_response(
			"Could not connect."
		)
		var decoded := await client.download_image("https://example.com/img.png")
		assert_null(decoded)
		assert_push_error("download_image")

	func test_returns_null_on_undecodable_data() -> void:
		client.preset_response = C3TestDoubles.ok_response(
			PackedByteArray([0x00, 0x01, 0x02, 0x03])
		)
		var decoded := await client.download_image("https://example.com/img.png")
		assert_null(decoded)
		assert_push_error("could not detect")
