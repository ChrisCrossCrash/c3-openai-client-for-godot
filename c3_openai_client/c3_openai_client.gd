@tool
class_name C3OpenAIClient
extends Node
## General-purpose client for OpenAI-compatible HTTP APIs.


## Emitted when a request fails. The [member ok] field of the returned response
## object is the primary way to detect failure; this signal is a secondary
## broadcast for optional cross-cutting concerns such as global error logging.
signal request_failed(error: ApiError)

# HTTP method names accepted by custom_request(), mapped to the HTTPClient
# constants taken by _http_request().
const _HTTP_METHODS: Dictionary = {
	"GET": HTTPClient.METHOD_GET,
	"HEAD": HTTPClient.METHOD_HEAD,
	"POST": HTTPClient.METHOD_POST,
	"PUT": HTTPClient.METHOD_PUT,
	"DELETE": HTTPClient.METHOD_DELETE,
	"OPTIONS": HTTPClient.METHOD_OPTIONS,
	"PATCH": HTTPClient.METHOD_PATCH,
}

## The base URL of the OpenAI-compatible API, including the version path.
## For example, [code]"https://api.openai.com/v1"[/code] for OpenAI or
## [code]"http://127.0.0.1:1234/v1"[/code] for a local server.
@export var base_url: String = "http://127.0.0.1:1234/v1"
## The API key sent as a Bearer token in the [code]Authorization[/code] header.
## Set to any non-empty value for servers that don't require authentication.
var api_key := "no-key"


## Returns the list of model IDs available on the server.
## Returns a [ModelsResponse] with [member ModelsResponse.ok] set to
## [code]false[/code] and emits [signal request_failed] on failure.
func get_models() -> ModelsResponse:
	var response := await _http_get(base_url + "/models", _headers())
	var res := ModelsResponse.new()
	if not response["ok"]:
		res.ok = false
		res.error = response["error"]
		request_failed.emit(res.error)
		return res
	var body_str := (response["body"] as PackedByteArray).get_string_from_utf8()
	var parser := JSON.new()
	if parser.parse(body_str) != OK:
		res.ok = false
		res.error = ApiError.parse_failure(
			"Failed to parse models response as JSON.", body_str
		)
		request_failed.emit(res.error)
		return res
	var json: Variant = parser.get_data()
	if json is Dictionary:
		res.raw_body = json
	var data: Variant = json.get("data") if json is Dictionary else null
	if not data is Array:
		res.ok = false
		res.error = ApiError.parse_failure(
			'Models response JSON missing "data" array.', body_str
		)
		request_failed.emit(res.error)
		return res
	# Skip malformed entries rather than failing the whole list.
	for m in (data as Array):
		if m is Dictionary and (m as Dictionary).get("id") is String:
			res.ids.append((m as Dictionary)["id"])
	return res


## Sends a chat completion request and returns the model's response.
## Returns a [ChatCompletionResponse] with [member ChatCompletionResponse.ok]
## set to [code]false[/code] and emits [signal request_failed] on failure.
func chat_completion(
	messages: Array, opts: ChatOptions = null
) -> ChatCompletionResponse:
	if opts == null:
		opts = ChatOptions.new()
	var body := _build_chat_body(messages, opts)
	body.merge(opts.extra_body, true)
	var response := await _http_post(
		base_url + "/chat/completions", body, _headers()
	)
	var res := ChatCompletionResponse.new()
	if not response["ok"]:
		res.ok = false
		res.error = response["error"]
		request_failed.emit(res.error)
		return res
	var body_str := (response["body"] as PackedByteArray).get_string_from_utf8()
	var parser := JSON.new()
	if parser.parse(body_str) != OK:
		res.ok = false
		res.error = ApiError.parse_failure(
			"Failed to parse response body as JSON.", body_str
		)
		request_failed.emit(res.error)
		return res
	var json: Variant = parser.get_data()
	if json is Dictionary:
		res.raw_body = json
	var choices: Variant = json.get("choices") if json is Dictionary else null
	if not choices is Array or (choices as Array).is_empty():
		res.ok = false
		res.error = ApiError.parse_failure(
			"Response JSON missing choices.", body_str
		)
		request_failed.emit(res.error)
		return res
	var json_dict: Dictionary = json
	var choice_val: Variant = (choices as Array)[0]
	if not choice_val is Dictionary:
		res.ok = false
		res.error = ApiError.parse_failure(
			"Response JSON choice is malformed.", body_str
		)
		request_failed.emit(res.error)
		return res
	var choice: Dictionary = choice_val
	var message_val: Variant = choice.get("message")
	if not message_val is Dictionary:
		res.ok = false
		res.error = ApiError.parse_failure(
			"Response JSON choice missing message.", body_str
		)
		request_failed.emit(res.error)
		return res
	var message: Dictionary = message_val
	var content: Variant = message.get("content")
	res.content = content if content is String else ""
	var refusal: Variant = message.get("refusal")
	res.refusal = refusal if refusal is String else ""
	var finish_reason: Variant = choice.get("finish_reason")
	res.finish_reason = finish_reason if finish_reason is String else ""
	var model_val: Variant = json_dict.get("model")
	res.model = model_val if model_val is String else ""
	var raw_usage: Dictionary = json_dict.get("usage", {})
	res.usage = {
		"prompt_tokens": int(raw_usage.get("prompt_tokens", 0)),
		"completion_tokens": int(raw_usage.get("completion_tokens", 0)),
		"total_tokens": int(raw_usage.get("total_tokens", 0)),
	}
	return res


## Sends a streaming chat completion request and returns a [ChatStream] handle.
## Connect to [signal ChatStream.delta] for incremental text and
## [code]await[/code] [signal ChatStream.finished] for the final
## [ChatCompletionResponse]. On a non-200 response or transport error the
## result's [member ChatCompletionResponse.ok] is [code]false[/code] and
## [signal request_failed] is emitted, mirroring [method chat_completion].
func chat_completion_stream(
	messages: Array, opts: ChatOptions = null
) -> ChatStream:
	if opts == null:
		opts = ChatOptions.new()
	var body := _build_chat_body(messages, opts)
	body["stream"] = true
	if opts.include_usage:
		body["stream_options"] = {"include_usage": true}
	body.merge(opts.extra_body, true)
	var stream := ChatStream.new()
	add_child(stream)
	stream._start(
		_make_sse_request(),
		base_url + "/chat/completions",
		_headers(),
		JSON.stringify(body),
		self
	)
	return stream


## Helper function for constructing a user message
## dictionary for the OpenAI chat API. [br]
## Returns:[br]
## [code]{"role": "user", "content": content}[/code]
static func make_user_msg(content: String) -> Dictionary:
	return {"role": "user", "content": content}


## Helper function for constructing an assistant message
## dictionary for the OpenAI chat API. [br]
## Returns:[br]
## [code]{"role": "assistant", "content": content}[/code]
static func make_assistant_msg(content: String) -> Dictionary:
	return {"role": "assistant", "content": content}


## Helper function for constructing a system message
## dictionary for the OpenAI chat API. [br]
## Returns:[br]
## [code]{"role": "system", "content": content}[/code]
static func make_system_msg(content: String) -> Dictionary:
	return {"role": "system", "content": content}


## Constructs a text content part for use with [method make_user_msg_with_parts]. [br]
## Returns:[br]
## [code]{"type": "text", "text": text}[/code]
static func make_part_text(text: String) -> Dictionary:
	return {"type": "text", "text": text}


## Constructs an image URL content part for use with [method make_user_msg_with_parts]. [br]
## [param url] may be an [code]https://[/code] URL or a [code]data:[/code] URI
## (e.g. [code]"data:image/png;base64,..."[/code]). [br]
## [param detail] controls resolution sampling: [code]"auto"[/code] (default),
## [code]"low"[/code], or [code]"high"[/code]. [br]
## Returns:[br]
## [code]{"type": "image_url", "image_url": {"url": url, "detail": detail}}[/code]
static func make_part_image_url(
	url: String, detail: String = "auto"
) -> Dictionary:
	return {"type": "image_url", "image_url": {"url": url, "detail": detail}}


## Constructs a user message whose content is an array of content parts
## built with [method make_part_text] and [method make_part_image_url]. [br]
## Returns:[br]
## [code]{"role": "user", "content": parts}[/code]
static func make_user_msg_with_parts(parts: Array) -> Dictionary:
	return {"role": "user", "content": parts}


## Sends a text-to-speech request and returns a [SpeechResponse].
## The server must return raw 16-bit signed little-endian PCM (request format
## [code]"pcm"[/code]). Use [member SpeechOptions.pcm_sample_rate] and
## [member SpeechOptions.pcm_stereo] to match the server's output. [br]
## Returns a [SpeechResponse] with [member SpeechResponse.ok] set to
## [code]false[/code] and emits [signal request_failed] on failure.
func create_speech(input: String, opts: SpeechOptions = null) -> SpeechResponse:
	if opts == null:
		opts = SpeechOptions.new()
	var body := {
		"model": opts.model,
		"input": input,
		"voice": opts.voice,
		"response_format": "pcm",
	}
	body.merge(opts.extra_body, true)
	var response := await _http_post(
		base_url + "/audio/speech", body, _headers()
	)
	var res := SpeechResponse.new()
	if not response["ok"]:
		res.ok = false
		res.error = response["error"]
		request_failed.emit(res.error)
		return res
	var wav := AudioStreamWAV.new()
	wav.data = response["body"]
	wav.stereo = opts.pcm_stereo
	wav.mix_rate = opts.pcm_sample_rate
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	res.stream = wav
	return res


## Transcribes an [AudioStream] and returns a [TranscriptionResponse].
## Supports [AudioStreamMP3] and [AudioStreamWAV] as input.
## Returns a [TranscriptionResponse] with [member TranscriptionResponse.ok] set to
## [code]false[/code] and emits [signal request_failed] on failure.
func create_transcription(
	audio: AudioStream, opts: TranscriptionOptions = null
) -> TranscriptionResponse:
	if opts == null:
		opts = TranscriptionOptions.new()
	var res := TranscriptionResponse.new()
	var audio_bytes: PackedByteArray
	var filename: String
	var file_content_type: String
	if audio is AudioStreamMP3:
		audio_bytes = (audio as AudioStreamMP3).data
		filename = "audio.mp3"
		file_content_type = "audio/mpeg"
	elif audio is AudioStreamWAV:
		var wav := audio as AudioStreamWAV
		# Only uncompressed PCM can be wrapped in the PCM WAV header we write.
		# ADPCM and QOA store compressed samples, so their bytes would not match
		# the header and the server would receive corrupt audio.
		if (
			wav.format != AudioStreamWAV.FORMAT_8_BITS
			and wav.format != AudioStreamWAV.FORMAT_16_BITS
		):
			push_error(
				"C3OpenAIClient: Unsupported AudioStreamWAV format. Only 8-bit and 16-bit PCM are supported."
			)
			res.ok = false
			res.error = ApiError.client_error(
				"Unsupported AudioStreamWAV format."
			)
			return res
		audio_bytes = _audio_stream_wav_to_bytes(wav)
		filename = "audio.wav"
		file_content_type = "audio/wav"
	else:
		push_error(
			"C3OpenAIClient: Unsupported AudioStream type. Only AudioStreamMP3 and AudioStreamWAV are supported."
		)
		res.ok = false
		res.error = ApiError.client_error("Unsupported AudioStream type.")
		return res
	var form_fields := {"model": opts.model}
	if not opts.language.is_empty():
		form_fields["language"] = opts.language
	form_fields.merge(opts.extra_body, true)
	var response := await _http_post_multipart(
		base_url + "/audio/transcriptions",
		form_fields,
		"file",
		audio_bytes,
		filename,
		file_content_type,
		_headers()
	)
	if not response["ok"]:
		res.ok = false
		res.error = response["error"]
		request_failed.emit(res.error)
		return res
	var parser := JSON.new()
	var body_str := (response["body"] as PackedByteArray).get_string_from_utf8()
	if parser.parse(body_str) != OK:
		res.ok = false
		res.error = ApiError.parse_failure(
			"Failed to parse transcription response as JSON.", body_str
		)
		request_failed.emit(res.error)
		return res
	var json: Variant = parser.get_data()
	if json is Dictionary:
		res.raw_body = json
	var text: Variant = (
		(json as Dictionary).get("text") if json is Dictionary else null
	)
	res.text = text if text is String else ""
	return res


## Generates an image from a text prompt and returns an [ImageGenerationResponse].
## On success, [member ImageGenerationResponse.data] carries the first entry of
## the API's [code]data[/code] array exactly as returned, and — when that entry
## contains base64 image bytes — [member ImageGenerationResponse.image] holds the
## decoded [Image]. When the server returns a [code]"url"[/code] instead,
## [member ImageGenerationResponse.image] is [code]null[/code]; fetch it with
## [method download_image] using [member ImageGenerationResponse.data]. See
## [member ImageOptions.response_format] for how the request format is chosen.
## Returns an [ImageGenerationResponse] with [member ImageGenerationResponse.ok]
## set to [code]false[/code] and emits [signal request_failed] on failure —
## including when base64 bytes are present but cannot be decoded.
func create_image(
	prompt: String, opts: ImageOptions = null
) -> ImageGenerationResponse:
	if opts == null:
		opts = ImageOptions.new()
	var res := ImageGenerationResponse.new()
	var body := {
		"model": opts.model,
		"prompt": prompt,
		"n": 1,
	}
	if not opts.size.is_empty():
		body["size"] = opts.size
	if not opts.quality.is_empty():
		body["quality"] = opts.quality
	if not opts.background.is_empty():
		body["background"] = opts.background
	var response_format := opts.response_format
	if response_format == "auto":
		response_format = "b64_json" if "dall-e" in opts.model.to_lower() else ""
	if not response_format.is_empty():
		body["response_format"] = response_format
	body.merge(opts.extra_body, true)
	var response := await _http_post(
		base_url + "/images/generations", body, _headers()
	)
	if not response["ok"]:
		res.ok = false
		res.error = response["error"]
		request_failed.emit(res.error)
		return res
	var body_str := (response["body"] as PackedByteArray).get_string_from_utf8()
	var parser := JSON.new()
	if parser.parse(body_str) != OK:
		res.ok = false
		res.error = ApiError.parse_failure(
			"Failed to parse image response as JSON.", body_str
		)
		request_failed.emit(res.error)
		return res
	var json: Variant = parser.get_data()
	if json is Dictionary:
		res.raw_body = json
	var data: Variant = json.get("data") if json is Dictionary else null
	if not data is Array or (data as Array).is_empty():
		res.ok = false
		res.error = ApiError.parse_failure(
			'Image response JSON missing "data" array.', body_str
		)
		request_failed.emit(res.error)
		return res
	var first: Variant = (data as Array)[0]
	if not first is Dictionary:
		res.ok = false
		res.error = ApiError.parse_failure(
			"Image response data entry is malformed.", body_str
		)
		request_failed.emit(res.error)
		return res
	var first_dict: Dictionary = first
	res.data = first_dict
	# Decode base64 bytes into an Image when present. A url entry leaves image
	# null (the caller downloads it); base64 that is present but undecodable is a
	# genuine failure, even though the raw bytes remain on data.
	var b64: Variant = first_dict.get("b64_json")
	if b64 is String:
		var image := image_from_base64(b64 as String)
		if image == null:
			res.ok = false
			res.error = ApiError.parse_failure(
				"Image response contained base64 data that could not be decoded.",
				body_str
			)
			request_failed.emit(res.error)
			return res
		res.image = image
	return res


## Decodes a base64-encoded image — such as the [code]"b64_json"[/code] value of
## an [method create_image] response entry — into an [Image]. The codec is
## detected from the decoded bytes, so PNG, JPEG, and WebP are all supported.
## Returns [code]null[/code] (and pushes an error) when [param b64] is empty,
## is not a recognized image format, or cannot be decoded.
static func image_from_base64(b64: String) -> Image:
	if b64.is_empty():
		push_error("C3OpenAIClient: image_from_base64() received an empty string.")
		return null
	return _image_from_bytes(Marshalls.base64_to_raw(b64))


## Downloads an image from a URL — such as the [code]"url"[/code] value of an
## [method create_image] response entry — and decodes it into an [Image]. The
## codec is detected from the downloaded bytes, so PNG, JPEG, and WebP are all
## supported. Returns [code]null[/code] (and pushes an error) on a transport
## failure, a non-2xx response, or data that cannot be decoded. [br]
## Unlike [method image_from_base64], this performs a network request, so it is
## an instance method that must be [code]await[/code]ed rather than a static one.
func download_image(url: String) -> Image:
	var response := await _http_get(url, PackedStringArray())
	if not response["ok"]:
		push_error(
			"C3OpenAIClient: download_image() request failed: "
			+ str(response["error"])
		)
		return null
	return _image_from_bytes(response["body"])


## Escape hatch for endpoints and behaviors this client does not cover. Sends a
## request to [param path] — appended to [member base_url], with a leading
## [code]"/"[/code] added when missing — using the client's usual auth and JSON
## headers, and returns the response body parsed but uninterpreted on
## [member CustomRequestResponse.raw_body]. [br]
## [param method] is an HTTP method name (case-insensitive): [code]"GET"[/code],
## [code]"HEAD"[/code], [code]"POST"[/code], [code]"PUT"[/code],
## [code]"DELETE"[/code], [code]"OPTIONS"[/code], or [code]"PATCH"[/code]. [br]
## [param body] is sent as the JSON request body; leave empty to send no body
## (as a GET usually would). [br]
## [param query] entries are URL-encoded and appended to the URL as a query
## string; leave empty for none. [br]
## Returns a [CustomRequestResponse] with [member CustomRequestResponse.ok] set
## to [code]false[/code] and emits [signal request_failed] on failure —
## including when a non-empty 2xx body is not a JSON object. An empty 2xx body
## (e.g. [code]204 No Content[/code]) succeeds with
## [member CustomRequestResponse.raw_body] set to [code]{}[/code].
func custom_request(
	path: String, method: String, body: Dictionary = {}, query: Dictionary = {}
) -> CustomRequestResponse:
	var res := CustomRequestResponse.new()
	var method_int: int = _HTTP_METHODS.get(method.to_upper(), -1)
	if method_int == -1:
		push_error('C3OpenAIClient: Unsupported HTTP method "%s".' % method)
		res.ok = false
		res.error = ApiError.client_error(
			'Unsupported HTTP method "%s".' % method
		)
		return res
	if not path.begins_with("/"):
		path = "/" + path
	var url := base_url + path
	if not query.is_empty():
		url += "?" + HTTPClient.new().query_string_from_dict(query)
	var request_body := "" if body.is_empty() else JSON.stringify(body)
	var response := await _http_request(
		method_int, url, _headers(), request_body
	)
	if not response["ok"]:
		res.ok = false
		res.error = response["error"]
		request_failed.emit(res.error)
		return res
	var body_str := (response["body"] as PackedByteArray).get_string_from_utf8()
	# A bodyless 2xx (e.g. 204 from a DELETE) is a success with nothing to parse.
	if body_str.strip_edges().is_empty():
		return res
	var parser := JSON.new()
	if parser.parse(body_str) != OK:
		res.ok = false
		res.error = ApiError.parse_failure(
			"Failed to parse custom request response as JSON.", body_str
		)
		request_failed.emit(res.error)
		return res
	var json: Variant = parser.get_data()
	if not json is Dictionary:
		res.ok = false
		res.error = ApiError.parse_failure(
			"Custom request response JSON is not an object.", body_str
		)
		request_failed.emit(res.error)
		return res
	res.raw_body = json
	return res


# Creates the C3SSERequest used by chat_completion_stream().
# Overridable in tests to substitute a fake transport.
func _make_sse_request() -> C3SSERequest:
	return C3SSERequest.new()


# Assembles the JSON request body shared by chat_completion() and
# chat_completion_stream(). Warns when no model is set.
func _build_chat_body(messages: Array, opts: ChatOptions) -> Dictionary:
	if opts.model.is_empty():
		push_warning(
			(
				"C3OpenAIClient: opts.model is empty — using server default. "
				+ "Set opts.model explicitly when targeting OpenAI."
			)
		)
	var body := {
		"model": opts.model,
		"messages": messages,
	}
	if not is_nan(opts.temperature):
		body["temperature"] = opts.temperature
	if opts.max_tokens != -1:
		body["max_tokens"] = opts.max_tokens
	if not opts.stop.is_empty():
		body["stop"] = opts.stop
	if not opts.response_format.is_empty():
		body["response_format"] = opts.response_format
	return body


func _audio_stream_wav_to_bytes(wav: AudioStreamWAV) -> PackedByteArray:
	var pcm := wav.data
	var num_channels := 2 if wav.stereo else 1
	# create_transcription() guarantees 8- or 16-bit PCM, so anything that is
	# not 8-bit is 16-bit.
	var bits_per_sample := 8 if wav.format == AudioStreamWAV.FORMAT_8_BITS else 16
	var bytes_per_sample := bits_per_sample >> 3
	var byte_rate := wav.mix_rate * num_channels * bytes_per_sample
	var block_align := num_channels * bytes_per_sample

	# Godot stores 8-bit PCM as signed (-128..127), but the WAV spec defines
	# 8-bit PCM as unsigned (0..255, 128 = silence). Flip the sign bit of each
	# sample so the file is spec-compliant. 16-bit PCM is signed in both
	# formats, so it passes through unchanged. (Copy-on-write keeps wav.data
	# untouched once we mutate pcm.)
	if bits_per_sample == 8:
		for i in pcm.size():
			pcm[i] ^= 0x80

	var data_size := pcm.size()

	# WAV is little-endian. StreamPeerBuffer appends each field in order, which
	# reads more clearly than hand-encoding every byte at a fixed offset.
	var header := StreamPeerBuffer.new()
	header.big_endian = false
	# RIFF chunk
	header.put_data("RIFF".to_ascii_buffer())
	header.put_u32(36 + data_size)  # file size - 8
	header.put_data("WAVE".to_ascii_buffer())
	# fmt chunk
	header.put_data("fmt ".to_ascii_buffer())
	header.put_u32(16)  # chunk size
	header.put_u16(1)  # PCM format
	header.put_u16(num_channels)
	header.put_u32(wav.mix_rate)
	header.put_u32(byte_rate)
	header.put_u16(block_align)
	header.put_u16(bits_per_sample)
	# data chunk
	header.put_data("data".to_ascii_buffer())
	header.put_u32(data_size)
	return header.data_array + pcm


# Internal HTTP POST method. Can be overridden in tests.
func _http_post(
	url: String, body: Dictionary, headers: PackedStringArray
) -> Dictionary:
	return await _http_request(
		HTTPClient.METHOD_POST, url, headers, JSON.stringify(body)
	)


# Internal multipart/form-data POST. Can be overridden in tests.
func _http_post_multipart(
	url: String,
	form_fields: Dictionary,
	file_field: String,
	file_bytes: PackedByteArray,
	filename: String,
	file_content_type: String,
	headers: PackedStringArray
) -> Dictionary:
	var boundary := "GodotFormBoundary" + str(randi())
	var body := PackedByteArray()
	for key in form_fields:
		var part: String = (
			"--"
			+ boundary
			+ "\r\n"
			+ 'Content-Disposition: form-data; name="'
			+ key
			+ '"\r\n\r\n'
			+ str(form_fields[key])
			+ "\r\n"
		)
		body.append_array(part.to_utf8_buffer())
	var file_header := (
		"--"
		+ boundary
		+ "\r\n"
		+ 'Content-Disposition: form-data; name="'
		+ file_field
		+ '"; filename="'
		+ filename
		+ '"\r\n'
		+ "Content-Type: "
		+ file_content_type
		+ "\r\n\r\n"
	)
	body.append_array(file_header.to_utf8_buffer())
	body.append_array(file_bytes)
	body.append_array(("\r\n--" + boundary + "--\r\n").to_utf8_buffer())
	var multipart_headers := PackedStringArray()
	for h in headers:
		if not h.begins_with("Content-Type:"):
			multipart_headers.append(h)
	multipart_headers.append(
		"Content-Type: multipart/form-data; boundary=" + boundary
	)
	return await _http_request_raw(
		HTTPClient.METHOD_POST, url, multipart_headers, body
	)


# Internal HTTP GET method. Can be overridden in tests.
func _http_get(url: String, headers: PackedStringArray) -> Dictionary:
	return await _http_request(HTTPClient.METHOD_GET, url, headers)


func _http_request(
	method: int, url: String, headers: PackedStringArray, body: String = ""
) -> Dictionary:
	var req := HTTPRequest.new()
	add_child(req)
	var err := req.request(url, headers, method, body)
	if err != OK:
		req.queue_free()
		return {
			"ok": false,
			"error":
			ApiError.transport("Failed to start request (error %d)." % err)
		}
	var args: Array = await req.request_completed
	req.queue_free()
	return _process_http_result(args)


func _http_request_raw(
	method: int, url: String, headers: PackedStringArray, body: PackedByteArray
) -> Dictionary:
	var req := HTTPRequest.new()
	add_child(req)
	var err := req.request_raw(url, headers, method, body)
	if err != OK:
		req.queue_free()
		return {
			"ok": false,
			"error":
			ApiError.transport("Failed to start request (error %d)." % err)
		}
	var args: Array = await req.request_completed
	req.queue_free()
	return _process_http_result(args)


# Maps the HTTPRequest.request_completed arguments to the shared response shape:
# {"ok": true, "body": PackedByteArray} on a 2xx response, or
# {"ok": false, "error": ApiError} on a transport failure or non-2xx status.
func _process_http_result(args: Array) -> Dictionary:
	var result: int = args[0]
	var status: int = args[1]
	var resp_body: PackedByteArray = args[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		return {
			"ok": false,
			"error":
			ApiError.transport("HTTP transport failed (result %d)." % result)
		}
	if status < 200 or status >= 300:
		return {"ok": false, "error": ApiError.from_response(status, resp_body)}
	return {"ok": true, "body": resp_body}


func _headers() -> PackedStringArray:
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not api_key.is_empty():
		headers.append("Authorization: Bearer " + api_key)
	return headers


# Decodes raw image bytes into an Image, detecting the codec by magic bytes.
# Shared by image_from_base64() and download_image(). Returns null (and pushes
# an error) when the bytes are not a recognized format or cannot be decoded.
static func _image_from_bytes(bytes: PackedByteArray) -> Image:
	var image := Image.new()
	var err := OK
	if _is_png(bytes):
		err = image.load_png_from_buffer(bytes)
	elif _is_jpeg(bytes):
		err = image.load_jpg_from_buffer(bytes)
	elif _is_webp(bytes):
		err = image.load_webp_from_buffer(bytes)
	else:
		push_error(
			"C3OpenAIClient: could not detect a PNG, JPEG, or WebP image."
		)
		return null
	if err != OK:
		push_error(
			"C3OpenAIClient: failed to decode the image (error %d)." % err
		)
		return null
	return image


# Image format detection by magic bytes, used by _image_from_bytes().
static func _is_png(bytes: PackedByteArray) -> bool:
	# 0x89 "PNG"
	return (
		bytes.size() >= 8
		and bytes[0] == 0x89 and bytes[1] == 0x50
		and bytes[2] == 0x4E and bytes[3] == 0x47
	)


static func _is_jpeg(bytes: PackedByteArray) -> bool:
	# Start of Image marker 0xFFD8 followed by another marker (0xFF).
	return (
		bytes.size() >= 3
		and bytes[0] == 0xFF and bytes[1] == 0xD8 and bytes[2] == 0xFF
	)


static func _is_webp(bytes: PackedByteArray) -> bool:
	# "RIFF" <4-byte size> "WEBP"
	return (
		bytes.size() >= 12
		and bytes[0] == 0x52 and bytes[1] == 0x49
		and bytes[2] == 0x46 and bytes[3] == 0x46
		and bytes[8] == 0x57 and bytes[9] == 0x45
		and bytes[10] == 0x42 and bytes[11] == 0x50
	)


## Structured error placed on the [code]error[/code] field of every response
## object when [code]ok[/code] is [code]false[/code], and carried by
## [signal request_failed].
class ApiError:
	## Broad category of failure:[br]
	## [code]&"transport"[/code] — no usable HTTP response (DNS, connection, TLS,
	## or the request could not be started).[br]
	## [code]&"http"[/code] — a non-2xx status with no parseable API error body.[br]
	## [code]&"api"[/code] — the server returned a structured error body.[br]
	## [code]&"parse"[/code] — a 2xx body that could not be understood.[br]
	## [code]&"client"[/code] — the request was rejected before being sent (e.g.
	## an invalid argument).[br]
	## [code]&"cancelled"[/code] — the caller aborted the request.
	var kind := &""
	## Human-readable description. Never empty.
	var message := ""
	## HTTP status code, or [code]0[/code] when not applicable.
	var status := 0
	## Machine-readable API error code (e.g. [code]"invalid_api_key"[/code]), or
	## [code]""[/code] if absent.
	var code := ""
	## API error type (e.g. [code]"invalid_request_error"[/code]), or [code]""[/code].
	var type := ""
	## Raw response body, for debugging. May be [code]""[/code].
	var raw := ""

	## Builds an error for a transport-level failure with no usable HTTP response.
	static func transport(p_message: String) -> ApiError:
		var e := ApiError.new()
		e.kind = &"transport"
		e.message = p_message
		return e

	## Builds an error for a 2xx response whose body could not be understood.
	static func parse_failure(
		p_message: String, p_raw: String = ""
	) -> ApiError:
		var e := ApiError.new()
		e.kind = &"parse"
		e.message = p_message
		e.raw = p_raw
		return e

	## Builds an error for a caller-initiated cancellation.
	static func cancelled(p_message: String) -> ApiError:
		var e := ApiError.new()
		e.kind = &"cancelled"
		e.message = p_message
		return e

	## Builds an error for a request rejected before being sent (bad argument).
	static func client_error(p_message: String) -> ApiError:
		var e := ApiError.new()
		e.kind = &"client"
		e.message = p_message
		return e

	## Builds an error from a non-2xx response, pulling the server's own
	## [code]{"error": {...}}[/code] body when present. Falls back to a generic
	## HTTP-status message otherwise.
	static func from_response(p_status: int, body: PackedByteArray) -> ApiError:
		var e := ApiError.new()
		e.kind = &"http"
		e.status = p_status
		e.raw = body.get_string_from_utf8()
		e.message = "Request failed with status %d." % p_status
		var parser := JSON.new()
		if parser.parse(e.raw) == OK and parser.get_data() is Dictionary:
			var api_err: Variant = (parser.get_data() as Dictionary).get("error")
			if api_err is Dictionary:
				var d: Dictionary = api_err
				e.kind = &"api"
				if d.get("message") is String:
					e.message = d["message"]
				if d.get("code") is String:
					e.code = d["code"]
				if d.get("type") is String:
					e.type = d["type"]
		return e

	func _to_string() -> String:
		var parts := PackedStringArray(["[%s]" % kind])
		if status != 0:
			parts.append("status=%d" % status)
		if not code.is_empty():
			parts.append("code=%s" % code)
		parts.append(message)
		return " ".join(parts)


## Optional parameters for a chat completion request.
class ChatOptions:
	var model := ""
	## Leave as [constant @GDScript.NAN] to omit temperature from the request entirely.
	var temperature := NAN
	## Set to -1 to omit max_tokens from the request entirely.
	var max_tokens := -1
	## One or more sequences where generation stops. Leave empty to omit from the request.
	var stop := PackedStringArray()
	## Streaming only: request a final usage chunk so
	## [member ChatCompletionResponse.usage] is populated. Has no effect on
	## [method chat_completion], which always returns usage. Sent as
	## [code]stream_options.include_usage[/code]; leave [code]false[/code] for
	## servers that reject the field.
	var include_usage := false
	## Constrain the model's output format. Set to a [code]response_format[/code]
	## object as defined by the OpenAI API — for example:
	## [codeblock]
	## opts.response_format = {
	##     "type": "json_schema",
	##     "json_schema": {
	##         "name": "joke_response",
	##         "strict": true,
	##         "schema": {
	##             "type": "object",
	##             "properties": {
	##                 "joke": {"type": "string"},
	##                 "punchline": {"type": "string"}
	##             },
	##             "required": ["joke", "punchline"],
	##             "additionalProperties": false
	##         }
	##     }
	## }
	## [/codeblock]
	## Leave empty to omit [code]response_format[/code] from the request entirely.
	## When set, [member ChatCompletionResponse.content] will contain a JSON string
	## that must be parsed by the caller. [br]
	## See the [url=https://developers.openai.com/api/docs/guides/structured-outputs]
	## OpenAI Structured Outputs guide[/url] for more information.
	var response_format := {}
	## Extra parameters merged into the request body for options this class does
	## not expose — for example server-specific fields on non-OpenAI servers.
	## Shallow-merged last, so its keys override the library's and each top-level
	## key is replaced whole (to change a nested object, pass the whole object).
	## Leave empty to send nothing extra.
	var extra_body := {}


## The response returned by [method chat_completion].
class ChatCompletionResponse:
	## [code]true[/code] if the request succeeded.
	var ok := true
	## Populated with error details when [member ok] is [code]false[/code].
	var error: ApiError = null
	var content := ""
	var refusal := ""
	var finish_reason := ""
	var model := ""
	## Token counts: [code]prompt_tokens[/code], [code]completion_tokens[/code],
	## and [code]total_tokens[/code]. Always populated by [method chat_completion].
	## For [method chat_completion_stream] this remains an empty [Dictionary]
	## unless [member ChatOptions.include_usage] was set to [code]true[/code].
	var usage := {}
	## The full parsed response body as a [Dictionary], for fields this class does
	## not surface. Populated whenever the server returned a valid JSON object;
	## [code]{}[/code] for streamed results (which have no single response body)
	## and on transport, HTTP, or non-JSON errors.
	var raw_body := {}


## A handle to an in-progress streaming chat completion, returned by
## [method chat_completion_stream]. Emits [signal delta] as text arrives and
## [signal finished] exactly once when the stream ends.
class ChatStream extends Node:

	## Emitted for each incremental piece of generated text as it arrives.
	signal delta(text: String)
	## Emitted exactly once when the stream ends — on success, on error, or
	## after [method cancel]. Carries the same [ChatCompletionResponse] that
	## [method chat_completion] returns.
	signal finished(result: ChatCompletionResponse)

	var _sse: C3SSERequest
	var _client: C3OpenAIClient
	var _res := ChatCompletionResponse.new()
	var _content := ""
	var _refusal := ""
	var _done := false

	## Aborts the in-flight request and resolves [signal finished] with
	## [member ChatCompletionResponse.ok] set to [code]false[/code].
	func cancel() -> void:
		_resolve(false, ApiError.cancelled("Stream cancelled."), false)

	# Kicks off the request. Called by chat_completion_stream() right after the
	# stream is added to the tree.
	func _start(
		sse: C3SSERequest,
		url: String,
		headers: PackedStringArray,
		body: String,
		client: C3OpenAIClient
	) -> void:
		_client = client
		_sse = sse
		add_child(_sse)
		_sse.event_received.connect(_on_event_received)
		_sse.finished.connect(_on_sse_finished)
		_sse.response_error.connect(_on_response_error)
		_sse.request_failed.connect(_on_sse_request_failed)
		var err := _sse.request(url, headers, HTTPClient.METHOD_POST, body)
		if err != OK:
			# Defer so the caller can connect to `finished` before it fires —
			# _start() runs synchronously inside chat_completion_stream().
			_resolve.call_deferred(
				false,
				ApiError.transport(
					"Failed to start stream request (error %d)." % err
				),
				true
			)

	func _on_response_error(code: int, body: String) -> void:
		_resolve(
			false, ApiError.from_response(code, body.to_utf8_buffer()), true
		)

	func _on_event_received(data: String, _event_type: String) -> void:
		if _done or data == "[DONE]":
			return
		var parser := JSON.new()
		if parser.parse(data) != OK:
			return
		var json: Variant = parser.get_data()
		if not json is Dictionary:
			return
		var json_dict: Dictionary = json
		var model: Variant = json_dict.get("model")
		if model is String and not (model as String).is_empty():
			_res.model = model
		var raw_usage: Variant = json_dict.get("usage")
		if raw_usage is Dictionary:
			_res.usage = {
				"prompt_tokens": int(raw_usage.get("prompt_tokens", 0)),
				"completion_tokens": int(raw_usage.get("completion_tokens", 0)),
				"total_tokens": int(raw_usage.get("total_tokens", 0)),
			}
		var choices: Variant = json_dict.get("choices")
		if not choices is Array or (choices as Array).is_empty():
			return
		var choice: Dictionary = (choices as Array)[0]
		var finish_reason: Variant = choice.get("finish_reason")
		if finish_reason is String:
			_res.finish_reason = finish_reason
		var delta_obj: Variant = choice.get("delta")
		if not delta_obj is Dictionary:
			return
		var delta_dict: Dictionary = delta_obj
		var piece: Variant = delta_dict.get("content")
		if piece is String and not (piece as String).is_empty():
			_content += piece
			delta.emit(piece)
		var refusal_piece: Variant = delta_dict.get("refusal")
		if refusal_piece is String:
			_refusal += refusal_piece

	func _on_sse_finished() -> void:
		_resolve(true, null, false)

	func _on_sse_request_failed(reason: String) -> void:
		_resolve(false, ApiError.transport(reason), true)

	# Single exit point: fills in the result, tears down the SSE node, and emits
	# finished once. `broadcast` re-emits the client's request_failed signal for
	# genuine failures (not user cancellation), mirroring chat_completion().
	func _resolve(ok: bool, error: ApiError, broadcast: bool) -> void:
		if _done:
			return
		_done = true
		_res.ok = ok
		_res.error = error
		if ok:
			_res.content = _content
			_res.refusal = _refusal
		if is_instance_valid(_sse):
			_sse.queue_free()
			_sse = null
		if broadcast and is_instance_valid(_client):
			_client.request_failed.emit(error)
		finished.emit(_res)
		queue_free()


## Optional parameters for a text-to-speech request.
class SpeechOptions:
	var model := ""
	var voice := ""
	## Sample rate of the [code]"pcm"[/code] response. Must match the server's
	## output. OpenAI and speaches both default to 24000 Hz.
	var pcm_sample_rate := 24000
	## Whether the [code]"pcm"[/code] response is stereo. Most TTS servers
	## output mono. Set to [code]true[/code] if the server produces stereo PCM.
	var pcm_stereo := false
	## Extra parameters merged into the request body for options this class does
	## not expose — for example server-specific fields on non-OpenAI servers.
	## Shallow-merged last, so its keys override the library's and each top-level
	## key is replaced whole (to change a nested object, pass the whole object).
	## Leave empty to send nothing extra.
	var extra_body := {}


## The response returned by [method create_speech].
class SpeechResponse:
	## [code]true[/code] if the request succeeded.
	var ok := true
	## Populated with error details when [member ok] is [code]false[/code].
	var error: ApiError = null
	## The resulting audio stream. Only valid when [member ok] is [code]true[/code].
	var stream: AudioStream


## Optional parameters for a transcription request.
class TranscriptionOptions:
	var model := ""
	## BCP-47 language code (e.g. [code]"en"[/code]). Leave empty to auto-detect.
	var language := ""
	## Extra parameters merged into the multipart form for options this class does
	## not expose — for example [code]prompt[/code], [code]temperature[/code], or
	## server-specific transcription fields. Shallow-merged last, so its keys
	## override the library's. Because the request is multipart/form-data, each
	## value is sent as an individually stringified form field — use scalar values
	## ([String]/[int]/[float]/[bool]); arrays and nested objects are not supported
	## here. Leave empty to send nothing extra.
	var extra_body := {}


## The response returned by [method create_transcription].
class TranscriptionResponse:
	## [code]true[/code] if the request succeeded.
	var ok := true
	## Populated with error details when [member ok] is [code]false[/code].
	var error: ApiError = null
	var text := ""
	## The full parsed response body as a [Dictionary], for fields this class does
	## not surface — for example [code]"segments"[/code]/[code]"words"[/code] when
	## [code]response_format[/code] is [code]"verbose_json"[/code]. Populated whenever
	## the server returned a valid JSON object; [code]{}[/code] on transport,
	## HTTP, or non-JSON errors.
	var raw_body := {}


## The response returned by [method get_models].
class ModelsResponse:
	## [code]true[/code] if the request succeeded.
	var ok := true
	## Populated with error details when [member ok] is [code]false[/code].
	var error: ApiError = null
	var ids := PackedStringArray()
	## The full parsed response body as a [Dictionary], for fields this class does
	## not surface (for example each model's [code]"created"[/code]/[code]"owned_by"[/code]).
	## Populated whenever the server returned a valid JSON object; [code]{}[/code]
	## on transport, HTTP, or non-JSON errors.
	var raw_body := {}


## Optional parameters for an image generation request.
class ImageOptions:
	var model := ""
	## Image dimensions as [code]"WIDTHxHEIGHT"[/code] (e.g. [code]"1024x1024"[/code]).
	## Valid values vary by model. Leave empty to omit and use the server default.
	var size := ""
	## Quality tier. Valid values vary by model — for example
	## [code]"low"[/code]/[code]"medium"[/code]/[code]"high"[/code] for the
	## gpt-image family, or [code]"standard"[/code]/[code]"hd"[/code] for dall-e-3.
	## Leave empty to omit and use the server default.
	var quality := ""
	## Background transparency, supported by the gpt-image models:
	## [code]"transparent"[/code], [code]"opaque"[/code], or [code]"auto"[/code]
	## (the server default). [code]"transparent"[/code] requires a PNG or WebP
	## output — the default output is PNG, which Godot decodes with its alpha
	## channel intact, so a transparent result is ready to drop onto a sprite.
	## Leave empty to omit and use the server default.
	var background := ""
	## How the request's [code]response_format[/code] field is chosen: [br]
	## • [code]"auto"[/code] (default) — sends [code]"b64_json"[/code] when
	## [member model] contains [code]"dall-e"[/code] (those models default to a
	## URL), and omits the field otherwise (the gpt-image models return base64 by
	## default and reject it). This keeps [member ImageGenerationResponse.image]
	## populated out of the box for both families. [br]
	## • [code]""[/code] — always omit the field, taking the server's default
	## (use this to deliberately get a URL from dall-e). [br]
	## • any other value (e.g. [code]"b64_json"[/code], [code]"url"[/code]) — sent
	## as-is, for servers with their own conventions.
	var response_format := "auto"
	## Extra parameters merged into the request body for options this class does
	## not expose — for example server-specific fields on non-OpenAI servers.
	## Shallow-merged last, so its keys override the library's and each top-level
	## key is replaced whole (to change a nested object, pass the whole object).
	## Leave empty to send nothing extra.
	var extra_body := {}


## The response returned by [method create_image].
class ImageGenerationResponse:
	## [code]true[/code] if the request succeeded.
	var ok := true
	## Populated with error details when [member ok] is [code]false[/code].
	var error: ApiError = null
	## The decoded image, ready to use — for example with
	## [method ImageTexture.create_from_image]. Populated when the response carried
	## base64 bytes; [code]null[/code] when the server returned a [code]"url"[/code]
	## instead (fetch it with [method download_image] using [member data]).
	var image: Image = null
	## The first entry of the API's [code]data[/code] array, as returned. Its keys
	## depend on the model and [member ImageOptions.response_format] — typically
	## [code]"b64_json"[/code] or [code]"url"[/code], plus [code]"revised_prompt"[/code]
	## when the model revises the prompt. Populated on success, and also when a
	## present-but-undecodable [code]"b64_json"[/code] fails the response, so the
	## raw bytes stay available.
	var data := {}
	## The full parsed response body as a [Dictionary], for fields this class does
	## not surface (for example top-level [code]"created"[/code] or [code]"usage"[/code]).
	## [member data] is the first entry of its [code]"data"[/code] array. Populated
	## whenever the server returned a valid JSON object; [code]{}[/code] on
	## transport, HTTP, or non-JSON errors.
	var raw_body := {}


## The response returned by [method custom_request].
class CustomRequestResponse:
	## [code]true[/code] if the request succeeded.
	var ok := true
	## Populated with error details when [member ok] is [code]false[/code].
	var error: ApiError = null
	## The full parsed response body as a [Dictionary] — [method custom_request]
	## does not interpret it beyond parsing. Populated whenever the server
	## returned a JSON object; [code]{}[/code] when the 2xx body was empty (e.g.
	## [code]204 No Content[/code]) and on transport, HTTP, or non-JSON errors.
	var raw_body := {}
