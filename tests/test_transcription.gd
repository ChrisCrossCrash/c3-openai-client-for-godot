extends GutTest


## Tests for [C3OpenAIClient.TranscriptionOptions] defaults.
class TestTranscriptionOptions extends GutTest:
	func test_default_model() -> void:
		assert_eq(C3OpenAIClient.TranscriptionOptions.new().model, "")

	func test_default_language() -> void:
		assert_eq(C3OpenAIClient.TranscriptionOptions.new().language, "")

	func test_default_extra_body() -> void:
		assert_eq(C3OpenAIClient.TranscriptionOptions.new().extra_body, {})


## Tests for [method C3OpenAIClient.create_transcription].
class TestCreateTranscription extends GutTest:
	var client: C3TestDoubles.TestableClient

	func before_each() -> void:
		client = C3TestDoubles.TestableClient.new()
		add_child_autofree(client)

	## Returns a minimal JSON-encoded transcription response body.
	func make_json_res(text: String) -> PackedByteArray:
		return JSON.stringify({"text": text}).to_utf8_buffer()

	## Loads and returns the test MP3 fixture.
	func make_mp3_stream() -> AudioStreamMP3:
		return load("res://tests/data/demo-speech.mp3") as AudioStreamMP3

	## Creates a minimal in-memory WAV stream for testing.
	func make_wav_stream() -> AudioStreamWAV:
		var stream := AudioStreamWAV.new()
		stream.mix_rate = 44100
		stream.stereo = false
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.data = PackedByteArray([0x00, 0x01, 0x02, 0x03])
		return stream

	func test_returns_transcription_response() -> void:
		client.preset_response = C3TestDoubles.ok_response(
			make_json_res("Hello world")
		)
		var result := await client.create_transcription(make_mp3_stream())
		assert_is(result, C3OpenAIClient.TranscriptionResponse)

	func test_text_is_populated() -> void:
		client.preset_response = C3TestDoubles.ok_response(
			make_json_res("Hello world")
		)
		var result := await client.create_transcription(make_mp3_stream())
		assert_eq(result.text, "Hello world")

	func test_uses_correct_endpoint() -> void:
		client.base_url = "http://example.com/v1"
		client.preset_response = C3TestDoubles.ok_response(make_json_res("Hi"))
		await client.create_transcription(make_mp3_stream())
		assert_eq(
			client.request_log[0]["url"],
			"http://example.com/v1/audio/transcriptions"
		)

	func test_makes_exactly_one_request() -> void:
		client.preset_response = C3TestDoubles.ok_response(make_json_res("Hi"))
		await client.create_transcription(make_mp3_stream())
		assert_eq(client.request_log.size(), 1)

	func test_sends_model_as_form_field() -> void:
		client.preset_response = C3TestDoubles.ok_response(make_json_res("Hi"))
		var opts := C3OpenAIClient.TranscriptionOptions.new()
		opts.model = "whisper-large-v3"
		await client.create_transcription(make_mp3_stream(), opts)
		assert_eq(
			client.request_log[0]["form_fields"]["model"], "whisper-large-v3"
		)

	func test_sends_language_when_set() -> void:
		client.preset_response = C3TestDoubles.ok_response(make_json_res("Hi"))
		var opts := C3OpenAIClient.TranscriptionOptions.new()
		opts.language = "en"
		await client.create_transcription(make_mp3_stream(), opts)
		assert_eq(client.request_log[0]["form_fields"]["language"], "en")

	func test_omits_language_when_empty() -> void:
		client.preset_response = C3TestDoubles.ok_response(make_json_res("Hi"))
		await client.create_transcription(make_mp3_stream())
		assert_false(client.request_log[0]["form_fields"].has("language"))

	func test_extra_body_adds_form_fields() -> void:
		client.preset_response = C3TestDoubles.ok_response(make_json_res("Hi"))
		var opts := C3OpenAIClient.TranscriptionOptions.new()
		opts.extra_body = {"prompt": "proper nouns: Godot"}
		await client.create_transcription(make_mp3_stream(), opts)
		assert_eq(
			client.request_log[0]["form_fields"]["prompt"],
			"proper nouns: Godot"
		)

	func test_extra_body_overrides_library_fields() -> void:
		client.preset_response = C3TestDoubles.ok_response(make_json_res("Hi"))
		var opts := C3OpenAIClient.TranscriptionOptions.new()
		opts.model = "whisper-1"
		opts.extra_body = {"model": "whisper-large-v3"}
		await client.create_transcription(make_mp3_stream(), opts)
		assert_eq(
			client.request_log[0]["form_fields"]["model"], "whisper-large-v3"
		)

	func test_raw_body_contains_full_response() -> void:
		var body := JSON.stringify(
			{"text": "Hi", "language": "english", "duration": 1.5}
		).to_utf8_buffer()
		client.preset_response = C3TestDoubles.ok_response(body)
		var result := await client.create_transcription(make_mp3_stream())
		assert_eq(result.raw_body.get("language"), "english")

	func test_raw_body_empty_on_network_error() -> void:
		client.preset_response = C3TestDoubles.transport_error_response(
			"Could not connect."
		)
		var result := await client.create_transcription(make_mp3_stream())
		assert_eq(result.raw_body, {})

	func test_sends_file_field_named_file() -> void:
		client.preset_response = C3TestDoubles.ok_response(make_json_res("Hi"))
		await client.create_transcription(make_mp3_stream())
		assert_eq(client.request_log[0]["file_field"], "file")

	func test_sends_mp3_bytes_as_file() -> void:
		client.preset_response = C3TestDoubles.ok_response(make_json_res("Hi"))
		var stream := make_mp3_stream()
		await client.create_transcription(stream)
		assert_eq(client.request_log[0]["file_bytes"], stream.data)

	func test_sends_mp3_content_type() -> void:
		client.preset_response = C3TestDoubles.ok_response(make_json_res("Hi"))
		await client.create_transcription(make_mp3_stream())
		assert_eq(client.request_log[0]["file_content_type"], "audio/mpeg")

	func test_sends_wav_bytes_as_file() -> void:
		client.preset_response = C3TestDoubles.ok_response(make_json_res("Hi"))
		var stream := make_wav_stream()
		await client.create_transcription(stream)
		assert_eq(
			client.request_log[0]["file_bytes"],
			client._audio_stream_wav_to_bytes(stream)
		)

	func test_sends_wav_content_type() -> void:
		client.preset_response = C3TestDoubles.ok_response(make_json_res("Hi"))
		await client.create_transcription(make_wav_stream())
		assert_eq(client.request_log[0]["file_content_type"], "audio/wav")

	func test_sends_wav_filename() -> void:
		client.preset_response = C3TestDoubles.ok_response(make_json_res("Hi"))
		await client.create_transcription(make_wav_stream())
		assert_eq(client.request_log[0]["filename"], "audio.wav")

	func test_wav_header_is_canonical_pcm() -> void:
		# Golden 44-byte header for make_wav_stream(): 44100 Hz, mono, 16-bit,
		# 4 bytes of PCM data. Hand-computed so it catches an encoding regression
		# that comparing the helper against itself could not.
		var bytes := client._audio_stream_wav_to_bytes(make_wav_stream())
		var expected := PackedByteArray([
			0x52, 0x49, 0x46, 0x46,  # "RIFF"
			0x28, 0x00, 0x00, 0x00,  # file size - 8 = 40
			0x57, 0x41, 0x56, 0x45,  # "WAVE"
			0x66, 0x6D, 0x74, 0x20,  # "fmt "
			0x10, 0x00, 0x00, 0x00,  # fmt chunk size = 16
			0x01, 0x00,              # PCM format = 1
			0x01, 0x00,              # channels = 1
			0x44, 0xAC, 0x00, 0x00,  # sample rate = 44100
			0x88, 0x58, 0x01, 0x00,  # byte rate = 88200
			0x02, 0x00,              # block align = 2
			0x10, 0x00,              # bits per sample = 16
			0x64, 0x61, 0x74, 0x61,  # "data"
			0x04, 0x00, 0x00, 0x00,  # data size = 4
		])
		assert_eq(bytes.slice(0, 44), expected)

	func test_wav_pcm_follows_header() -> void:
		var stream := make_wav_stream()
		var bytes := client._audio_stream_wav_to_bytes(stream)
		assert_eq(bytes.slice(44), stream.data)

	## Creates a minimal in-memory 8-bit WAV stream for testing.
	func make_wav_stream_8bit(data: PackedByteArray) -> AudioStreamWAV:
		var stream := AudioStreamWAV.new()
		stream.mix_rate = 8000
		stream.stereo = false
		stream.format = AudioStreamWAV.FORMAT_8_BITS
		stream.data = data
		return stream

	func test_wav_8bit_samples_converted_to_unsigned() -> void:
		# Godot stores 8-bit PCM signed; WAV requires unsigned (128 = silence).
		# Each sample's sign bit is flipped: 0x00 -> 0x80, 0x7F -> 0xFF, etc.
		var stream := make_wav_stream_8bit(
			PackedByteArray([0x00, 0x7F, 0x80, 0xFF])
		)
		var bytes := client._audio_stream_wav_to_bytes(stream)
		assert_eq(bytes.slice(44), PackedByteArray([0x80, 0xFF, 0x00, 0x7F]))

	func test_wav_8bit_header_declares_8_bits() -> void:
		var stream := make_wav_stream_8bit(PackedByteArray([0x00, 0x01]))
		var bytes := client._audio_stream_wav_to_bytes(stream)
		# bits_per_sample is the little-endian u16 at byte offset 34.
		assert_eq(bytes.decode_u16(34), 8)

	func test_wav_8bit_conversion_does_not_mutate_source() -> void:
		# Copy-on-write must keep the caller's AudioStreamWAV.data intact.
		var stream := make_wav_stream_8bit(PackedByteArray([0x00, 0x7F]))
		client._audio_stream_wav_to_bytes(stream)
		assert_eq(stream.data, PackedByteArray([0x00, 0x7F]))

	func test_returns_failed_response_on_network_error() -> void:
		client.preset_response = C3TestDoubles.transport_error_response(
			"Could not connect."
		)
		var result := await client.create_transcription(make_mp3_stream())
		assert_false(result.ok)

	func test_emits_request_failed_on_network_error() -> void:
		client.preset_response = C3TestDoubles.transport_error_response(
			"Could not connect."
		)
		watch_signals(client)
		await client.create_transcription(make_mp3_stream())
		assert_signal_emitted(client, "request_failed")

	func test_returns_failed_response_on_http_failure() -> void:
		client.preset_response = C3TestDoubles.transport_error_response(
			"Connection error."
		)
		var result := await client.create_transcription(make_mp3_stream())
		assert_false(result.ok)

	func test_emits_request_failed_on_http_failure() -> void:
		client.preset_response = C3TestDoubles.transport_error_response(
			"Connection error."
		)
		watch_signals(client)
		await client.create_transcription(make_mp3_stream())
		assert_signal_emitted(client, "request_failed")

	func test_returns_failed_response_on_invalid_json() -> void:
		client.preset_response = C3TestDoubles.ok_response(
			"not json".to_utf8_buffer()
		)
		var result := await client.create_transcription(make_mp3_stream())
		assert_false(result.ok)
		assert_eq(result.error.kind, &"parse")

	func test_emits_request_failed_on_invalid_json() -> void:
		client.preset_response = C3TestDoubles.ok_response(
			"not json".to_utf8_buffer()
		)
		watch_signals(client)
		await client.create_transcription(make_mp3_stream())
		assert_signal_emitted(client, "request_failed")

	func test_unsupported_audio_type_is_client_error() -> void:
		var result := await client.create_transcription(
			AudioStreamGenerator.new()
		)
		assert_false(result.ok)
		assert_eq(result.error.kind, &"client")
		assert_eq(client.request_log.size(), 0)
		assert_push_error("Unsupported AudioStream type")

	func test_non_pcm_wav_format_is_client_error() -> void:
		# A compressed WAV (ADPCM/QOA) cannot be wrapped in a PCM header, so it
		# is rejected before any request is made rather than sent as garbage.
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_IMA_ADPCM
		stream.data = PackedByteArray([0x00, 0x01, 0x02, 0x03])
		var result := await client.create_transcription(stream)
		assert_false(result.ok)
		assert_eq(result.error.kind, &"client")
		assert_eq(client.request_log.size(), 0)
		assert_push_error("Unsupported AudioStreamWAV format")
