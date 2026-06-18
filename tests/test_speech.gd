extends GutTest


## Tests for [C3OpenAIClient.SpeechOptions] defaults.
class TestSpeechOptions extends GutTest:
	func test_default_model() -> void:
		assert_eq(C3OpenAIClient.SpeechOptions.new().model, "")

	func test_default_voice() -> void:
		assert_eq(C3OpenAIClient.SpeechOptions.new().voice, "")

	func test_default_pcm_sample_rate() -> void:
		assert_eq(C3OpenAIClient.SpeechOptions.new().pcm_sample_rate, 24000)

	func test_default_pcm_stereo() -> void:
		assert_false(C3OpenAIClient.SpeechOptions.new().pcm_stereo)

	func test_default_extra_body() -> void:
		assert_eq(C3OpenAIClient.SpeechOptions.new().extra_body, {})


## Tests for [method C3OpenAIClient.create_speech].
class TestCreateSpeech extends GutTest:
	const C3HTTPRequest := preload("res://c3_openai_client/utils/c3_http_request.gd")

	var client: C3TestDoubles.TestableClient

	func before_each() -> void:
		client = C3TestDoubles.TestableClient.new()
		add_child_autofree(client)

	## A preset success response carrying minimal raw PCM bytes.
	func ok_pcm() -> C3HTTPRequest.Response:
		return C3TestDoubles.ok_response(
			PackedByteArray([0x00, 0x01, 0x02, 0x03])
		)

	func test_returns_speech_response() -> void:
		client.preset_response = ok_pcm()
		var result := await client.create_speech("Hello")
		assert_is(result, C3OpenAIClient.SpeechResponse)

	func test_stream_is_audio_stream_wav() -> void:
		client.preset_response = ok_pcm()
		var result := await client.create_speech("Hello")
		assert_is(result.stream, AudioStreamWAV)

	func test_uses_correct_endpoint() -> void:
		client.base_url = "http://example.com/v1"
		client.preset_response = ok_pcm()
		await client.create_speech("Hello")
		assert_eq(
			client.request_log[0]["url"], "http://example.com/v1/audio/speech"
		)

	func test_makes_exactly_one_request() -> void:
		client.preset_response = ok_pcm()
		await client.create_speech("Hello")
		assert_eq(client.request_log.size(), 1)

	func test_sends_input_in_body() -> void:
		client.preset_response = ok_pcm()
		await client.create_speech("Test speech text")
		assert_eq(client.request_log[0]["body"]["input"], "Test speech text")

	func test_extra_body_adds_keys_to_body() -> void:
		client.preset_response = ok_pcm()
		var opts := C3OpenAIClient.SpeechOptions.new()
		opts.extra_body = {"speed": 1.25}
		await client.create_speech("Hello", opts)
		assert_eq(client.request_log[0]["body"]["speed"], 1.25)

	func test_extra_body_overrides_library_keys() -> void:
		client.preset_response = ok_pcm()
		var opts := C3OpenAIClient.SpeechOptions.new()
		opts.extra_body = {"voice": "custom"}
		await client.create_speech("Hello", opts)
		assert_eq(client.request_log[0]["body"]["voice"], "custom")

	func test_sends_model_in_body() -> void:
		client.preset_response = ok_pcm()
		var opts := C3OpenAIClient.SpeechOptions.new()
		opts.model = "kokoro-82m"
		await client.create_speech("Hello", opts)
		assert_eq(client.request_log[0]["body"]["model"], "kokoro-82m")

	func test_sends_voice_in_body() -> void:
		client.preset_response = ok_pcm()
		var opts := C3OpenAIClient.SpeechOptions.new()
		opts.voice = "af_heart"
		await client.create_speech("Hello", opts)
		assert_eq(client.request_log[0]["body"]["voice"], "af_heart")

	func test_sends_response_format_in_body() -> void:
		client.preset_response = ok_pcm()
		await client.create_speech("Hello")
		assert_eq(client.request_log[0]["body"]["response_format"], "pcm")

	func test_pcm_stores_raw_bytes_as_data() -> void:
		var raw := PackedByteArray([0xAA, 0xBB, 0xCC, 0xDD])
		client.preset_response = C3TestDoubles.ok_response(raw)
		var result := await client.create_speech("Hello")
		var wav := result.stream as AudioStreamWAV
		assert_eq(wav.data, raw)

	func test_pcm_uses_configured_sample_rate() -> void:
		client.preset_response = ok_pcm()
		var opts := C3OpenAIClient.SpeechOptions.new()
		opts.pcm_sample_rate = 16000
		var result := await client.create_speech("Hello", opts)
		var wav := result.stream as AudioStreamWAV
		assert_eq(wav.mix_rate, 16000)

	func test_pcm_uses_configured_stereo() -> void:
		client.preset_response = ok_pcm()
		var opts := C3OpenAIClient.SpeechOptions.new()
		opts.pcm_stereo = true
		var result := await client.create_speech("Hello", opts)
		var wav := result.stream as AudioStreamWAV
		assert_true(wav.stereo)

	func test_pcm_defaults_to_24000hz_mono() -> void:
		client.preset_response = ok_pcm()
		var result := await client.create_speech("Hello")
		var wav := result.stream as AudioStreamWAV
		assert_eq(wav.mix_rate, 24000)
		assert_false(wav.stereo)

	func test_returns_failed_response_on_network_error() -> void:
		client.preset_response = C3TestDoubles.transport_error_response(
			"Could not connect."
		)
		var result := await client.create_speech("Hello")
		assert_false(result.ok)

	func test_emits_request_failed_on_network_error() -> void:
		client.preset_response = C3TestDoubles.transport_error_response(
			"Could not connect."
		)
		watch_signals(client)
		await client.create_speech("Hello")
		assert_signal_emitted(client, "request_failed")

	func test_returns_failed_response_on_http_failure() -> void:
		client.preset_response = C3TestDoubles.transport_error_response(
			"Connection error."
		)
		var result := await client.create_speech("Hello")
		assert_false(result.ok)

	func test_emits_request_failed_on_http_failure() -> void:
		client.preset_response = C3TestDoubles.transport_error_response(
			"Connection error."
		)
		watch_signals(client)
		await client.create_speech("Hello")
		assert_signal_emitted(client, "request_failed")
