# C3 OpenAI-Compatible Client for Godot

A drop-in Godot 4 client node for OpenAI-compatible HTTP APIs. Works with [OpenAI](https://openai.com/api/), [LM Studio](https://lmstudio.ai/), [speaches](https://speaches.ai/), and any other server that speaks the OpenAI REST API. This is a runtime addon for adding AI features to your game, **not** an editor assistant or Copilot-style tool.

<img src="./media/banner.jpg" width="100%" alt="GDScript code from the C3 OpenAI Client addon" />

## Features

- Chat completions — non-streaming or streaming (token-by-token via signals)
- Vision (image input) support
- `"type": "json_schema"` [structured output](https://developers.openai.com/api/docs/guides/structured-outputs) support
- Image generation (returns a decoded `Image` in the response object)
- Text-to-speech (returns a ready-to-play `AudioStream`)
- Speech-to-text / transcription (`AudioStreamMP3` and `AudioStreamWAV`)
- List available models
- `custom_request()` escape hatch for any endpoint the client doesn't cover
- Every method returns a typed response object — check `.ok` to detect failure

## Design philosophy

This library prioritizes being easy to use over 100% API coverage — it is not trying to be "the OpenAI SDK for Godot" the way the [`openai` library](https://developers.openai.com/api/reference/python) is for Python. For example, the chat completion reply is available as `res.content` rather than `res.choices[0].message.content`.

When you need more than the defaults, every method accepts an `extra_body` dictionary that is merged into the request as-is, and every response carries a `raw_body` with the full server response. So if you do need `choices[0].message.content`, it's right there on `res.raw_body`. And for endpoints the client doesn't cover at all, `custom_request()` sends a request to any path on the server — same auth, same `.ok` pattern — and returns the parsed response on `raw_body`.

## Compatibility

Tested on Godot 4.6.x with automated ([GUT](https://github.com/bitwes/Gut)) and manual tests. Manually verified to work back to Godot 4.0.0.

## Installation

To install `C3OpenAIClient` in your Godot project, simply click on the "Asset Store" tab on the top of the Godot editor window and search for "C3 OpenAI-Compatible Client". Then, click "Download" and "Install". The addon will be automatically added to your project, and the `C3OpenAIClient` node will be available in the "Create New Node" dialog.

Alternatively, you may download the latest release from [GitHub](https://github.com/ChrisCrossCrash/c3-openai-client-for-godot/releases) and copy the contents of the `addons/c3_openai_client` folder into your project's `addons/c3_openai_client` directory.

## Quick start

1. In your scene, choose **Add Child Node** and search for `C3OpenAIClient`.
2. Set **Base URL** in the Inspector (e.g. `https://api.openai.com/v1`).
3. Reference it from your scene script:

    ```gdscript
    @onready var client: C3OpenAIClient = $C3OpenAIClient

    func _ready() -> void:
        # Get the API key from an environment variable and set it on the client.
		# You can skip this step for servers that don't require authentication.
		client.api_key = OS.get_environment("OPENAI_API_KEY")

		var messages := [
			C3OpenAIClient.make_system_msg("You are a poor villager."),
			C3OpenAIClient.make_user_msg("En garde!"),
		]
		var opts := C3OpenAIClient.ChatOptions.new()
		opts.model = "gpt-5.4-mini"

		var res := await client.chat_completion(messages, opts)
		if res.ok:
			print(res.content)  # *Gasps sharply, dropping my basket of half-rotten turnips...
		else:
			push_error("Chat failed: " + str(res.error))
	```

## Examples

- [`examples/openai_client_demo/openai_client_demo.gd`](examples/openai_client_demo/openai_client_demo.gd) — complete walkthrough covering model listing, chat (non-streaming and streaming), vision, structured output, image generation, text-to-speech, and speech-to-text
- [`examples/voice_chat_demo/voice_chat_demo.gd`](examples/voice_chat_demo/voice_chat_demo.gd) — real-time voice chat using microphone input, speech-to-text, chat, and text-to-speech
