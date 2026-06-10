extends Control

const CHAT_MODEL := "gpt-5.4-mini"
const EMBEDDING_MODEL := "text-embedding-3-small"
const TTS_MODEL := "gpt-4o-mini-tts"
const TTS_VOICE := "marin"
const STT_MODEL := "whisper-1"
const IMAGE_MODEL := "gpt-image-1-mini"

@onready var client: C3OpenAIClient = $C3OpenAIClient
@onready var audio_stream_player: AudioStreamPlayer = $AudioStreamPlayer
@onready var label: Label = $HBoxContainer/ScrollContainer/Label
@onready var texture_rect: TextureRect = $HBoxContainer/PanelContainer/TextureRect


func _ready() -> void:
	if not OS.get_environment("OPENAI_API_KEY"):
		push_error("OPENAI_API_KEY environment variable is not set.")
		return

	client.api_key = OS.get_environment("OPENAI_API_KEY")

	var chat_res_str := await _chat_non_streaming()
	await _chat_structured_output()
	await _chat_streaming()
	await _chat_vision()
	await _image_generation()
	await _voice_tts(chat_res_str)
	await _voice_stt()
	await _custom_request()


func _chat_non_streaming() -> String:
	# --- Chat: non-streaming ---
	_render_text("Chat completion (non-streaming):")
	var user_msg := "What is an LLM?"
	var messages := [
		C3OpenAIClient.make_system_msg(
			"You are an assistant that gives one-sentence responses."
		),
		C3OpenAIClient.make_user_msg(user_msg)
	]
	var opts := C3OpenAIClient.ChatOptions.new()
	opts.model = CHAT_MODEL
	var response := await client.chat_completion(messages, opts)
	if not response.ok:
		push_error(
			"Error generating chat completion: " + str(response.error)
		)
		return "There was an error generating the chat completion."

	_render_text("User: " + user_msg)
	_render_text("Assistant: " + response.content)
	_render_text("---")
	return response.content


func _chat_structured_output() -> void:
	_render_text("Chat completion (structured output):")
	var opts := C3OpenAIClient.ChatOptions.new()
	opts.model = CHAT_MODEL
	opts.response_format = {
		"type": "json_schema",
		"json_schema": {
			"name": "joke_response",
			"strict": true,
			"schema": {
				"type": "object",
				"properties": {
					"joke": {"type": "string"},
					"punchline": {"type": "string"}
				},
				"required": ["joke", "punchline"],
				"additionalProperties": false
			}
		}
	}
	var response := await client.chat_completion(
		[C3OpenAIClient.make_user_msg("Tell me a joke.")],
		opts
	)
	if not response.ok:
		push_error(
			"Error generating structured completion: " + str(response.error)
		)
		return

	var parsed: Variant = JSON.parse_string(response.content)
	if not parsed is Dictionary:
		push_error(
			"Unexpected structured output format: " + str(response.content)
		)
		return
	var d: Dictionary = parsed
	_render_text("Joke: " + str(d.get("joke", "")))
	_render_text("Punchline: " + str(d.get("punchline", "")))
	_render_text("---")


func _chat_streaming() -> void:
	_render_text("Chat completion (streaming):")
	var messages := [C3OpenAIClient.make_user_msg("Count to ten.")]
	var opts := C3OpenAIClient.ChatOptions.new()
	opts.model = CHAT_MODEL

	var stream := client.chat_completion_stream(messages, opts)

	# Incremental updates as tokens arrive:
	stream.delta.connect(func(text: String) -> void: _render_text(text, ""))

	# Final result — same struct chat_completion() returns:
	var result: C3OpenAIClient.ChatCompletionResponse = await stream.finished
	if not result.ok:
		push_error(
			"Error streaming chat completion: " + str(result.error)
		)
		return

	_render_text("\n(full content: %d chars)\n---" % result.content.length())


func _chat_vision() -> void:
	_render_text("Vision chat completion:")
	var user_msg := "What do you see in this image? Describe in one sentence."
	var img := (
		(load("res://examples/openai_client_demo/test-img.jpg") as Texture2D)
		. get_image()
	)
	var b64 := Marshalls.raw_to_base64(img.save_jpg_to_buffer())
	var messages := [
		C3OpenAIClient.make_user_msg_with_parts([
			C3OpenAIClient.make_part_text(user_msg),
			C3OpenAIClient.make_part_image_url("data:image/jpeg;base64," + b64),
		])
	]
	var opts := C3OpenAIClient.ChatOptions.new()
	opts.model = CHAT_MODEL
	var response := await client.chat_completion(messages, opts)
	if not response.ok:
		push_error(
			"Error generating image chat completion:" + str(response.error)
		)
		return

	_render_text("User: " + user_msg)
	_render_text("Assistant: " + response.content)
	_render_text("---")


func _image_generation() -> void:
	_render_text("Generating image...")
	var prompt := "Pixel-art poor villager NPC"
	var opts := C3OpenAIClient.ImageOptions.new()
	opts.model = IMAGE_MODEL
	opts.size = "1024x1024"
	opts.quality = "low"
	opts.background = "transparent"
	var response := await client.create_image(prompt, opts)
	if not response.ok:
		push_error("Error generating image: " + str(response.error))
		return
	if response.image == null:
		push_error("Image response did not contain decodable image data.")
		return

	texture_rect.texture = ImageTexture.create_from_image(response.image)
	_render_text("Prompt: " + prompt)
	var revised_prompt: String = response.data.get("revised_prompt", "")
	if not revised_prompt.is_empty():
		_render_text("Revised prompt: " + revised_prompt)
	_render_text("Image generated.\n---")


func _voice_tts(text: String) -> void:
	var opts := C3OpenAIClient.SpeechOptions.new()
	opts.model = TTS_MODEL
	opts.voice = TTS_VOICE
	var response := await client.create_speech(text, opts)
	if not response.ok:
		push_error("Error generating speech: " + str(response.error))
		get_tree().quit()
		return
	audio_stream_player.stream = response.stream
	_render_text("Playing speech...\n---")
	audio_stream_player.play()


func _voice_stt() -> void:
	var clip := load("res://examples/openai_client_demo/demo-speech.mp3")
	var opts := C3OpenAIClient.TranscriptionOptions.new()
	opts.model = STT_MODEL
	var response := await client.create_transcription(clip, opts)
	if not response.ok:
		push_error(
			"Error generating transcription: " + str(response.error)
		)
		return
	_render_text("Transcription: " + response.text)


func _custom_request() -> void:
	# custom_request() as an escape hatch — here we call /v1/embeddings directly,
	# an endpoint the client doesn't cover, and compute cosine similarities.
	_render_text("Custom request (embeddings / cosine similarity):")
	var sentences := [
		"I lost my dog.",
		"My puppy is missing.",
		"Minneapolis is a nice city.",
	]
	var response := await client.custom_request(
		"/embeddings",
		"POST",
		{"model": EMBEDDING_MODEL, "input": sentences}
	)
	if not response.ok:
		push_error("Error fetching embeddings: " + str(response.error))
		return

	var data: Variant = response.raw_body.get("data")
	if not data is Array or (data as Array).size() != sentences.size():
		push_error("Unexpected embeddings response shape.")
		return

	# Extract the embedding vectors in index order.
	var vectors: Array[PackedFloat64Array] = []
	for entry in (data as Array):
		if not entry is Dictionary:
			push_error("Malformed embedding entry.")
			return
		var values: Variant = (entry as Dictionary).get("embedding")
		if not values is Array:
			push_error("Embedding entry missing vector.")
			return
		var vec := PackedFloat64Array(values)
		vectors.append(vec)

	# Print pairwise cosine similarities.
	for i in range(sentences.size()):
		for j in range(i + 1, sentences.size()):
			var similarity := _cosine_similarity(vectors[i], vectors[j])
			_render_text(
				'"%s" vs "%s": %.4f' % [sentences[i], sentences[j], similarity]
			)
	_render_text("---")


# Returns the cosine similarity (dot product of unit vectors) for two vectors.
func _cosine_similarity(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var dot := 0.0
	var mag_a := 0.0
	var mag_b := 0.0
	for i in a.size():
		dot += a[i] * b[i]
		mag_a += a[i] * a[i]
		mag_b += b[i] * b[i]
	if mag_a == 0.0 or mag_b == 0.0:
		return 0.0
	return dot / (sqrt(mag_a) * sqrt(mag_b))


func _render_text(txt: String, end: String = "\n") -> void:
	print(txt)
	label.text += txt + end
