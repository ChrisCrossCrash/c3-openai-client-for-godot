# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

C3 OpenAI Client for Godot is a Godot 4 addon providing an async `Node` wrapper for OpenAI-compatible HTTP APIs. It supports chat completions (streaming and non-streaming), vision, image generation, TTS, STT, and model listing. Compatible with OpenAI, LM Studio, speaches, and any OpenAI-compatible server.

## Commands

**Run all tests:**
```
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

**Run a single test file:**
```
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit -gtest=res://tests/test_chat_completion.gd
```

Tests require Godot 4.6+ on `$PATH`. CI runs on ubuntu-latest with Godot 4.6.2-stable via `.github/workflows/tests.yml`.

**Build asset for distribution:**
```
python scripts/build_asset.py
```

## Architecture

The addon lives entirely in [c3_openai_client/](c3_openai_client/).

**`C3OpenAIClient`** ([c3_openai_client/c3_openai_client.gd](c3_openai_client/c3_openai_client.gd)) — The main class. Extends `Node`, marked `@tool`. Callers instantiate it as a node and `await` its async methods. All public API is here:
- `get_models()` → `ModelsResponse`
- `chat_completion(messages, opts)` → `ChatCompletionResponse`
- `chat_completion_stream(messages, opts)` → `ChatStream` (SSE-backed, emits `delta` signal per token)
- `create_image(prompt, opts)` → `ImageGenerationResponse` (decodes base64 into `image`; raw entry kept on `data`. `ImageOptions.response_format` defaults to `"auto"`: `b64_json` for dall-e models, omitted otherwise)
- `image_from_base64(b64)` → `Image` (static helper; decodes PNG/JPEG/WebP from a `b64_json` value)
- `download_image(url)` → `Image` (async helper; downloads a `url` entry and decodes it)
- `create_speech(input, opts)` → `SpeechResponse`
- `create_transcription(audio, opts)` → `TranscriptionResponse`
- `custom_request(path, method, body, query)` → `CustomRequestResponse` (escape hatch for endpoints the client doesn't cover; parsed JSON object on `raw_body`, empty 2xx body succeeds, non-object JSON is a parse failure)

**`C3SSERequest`** ([c3_openai_client/utils/c3_sse_request.gd](c3_openai_client/utils/c3_sse_request.gd)) — Custom SSE implementation built on `StreamPeerTCP` + `StreamPeerTLS`. Godot's `HTTPRequest` doesn't support streaming, so this class handles raw TCP/TLS connection, HTTP request formatting, chunked transfer decoding, and SSE event parsing. Emits signals: `event_received`, `finished`, `response_error`, `request_failed`.

**Response/options types** are inner classes defined in `c3_openai_client.gd`:
- `ChatOptions`, `ImageOptions`, `SpeechOptions`, `TranscriptionOptions` — input option bags
- `ChatCompletionResponse`, `ImageGenerationResponse`, `SpeechResponse`, `TranscriptionResponse`, `ModelsResponse`, `CustomRequestResponse` — all carry `ok: bool` and optional `error: ApiError`
- `ApiError` — typed errors with `kind` string: `"transport"`, `"http"`, `"api"`, `"parse"`, `"client"`, `"cancelled"`

**Tests** are in [tests/](tests/) using the GUT framework (in [addons/gut/](addons/gut/)). Test doubles live in [tests/c3_test_doubles.gd](tests/c3_test_doubles.gd) — `TestableClient` exposes internals for unit testing and `FakeSSERequest` stubs streaming.

**Examples** in [examples/](examples/) demonstrate usage patterns but are not part of the addon itself.

## GDScript Style Guide

Follow [CONTRIBUTING.md](CONTRIBUTING.md) strictly. Key rules:

- **Tabs** for indentation (never spaces), one tab per level.
- **Type hints are mandatory** on all parameters and return types. Use `:=` for inference; use explicit type when inference would be too broad (e.g., `instantiate()` calls).
- Signal awaits require explicit type annotation (GDScript limitation); function awaits may use `:=`.
- Multi-line function signatures: closing `)` goes on its own line at zero indent, before `->`.
- `##` doc comments for classes, `@export` vars, and public methods. `#` for private methods only when non-obvious. Comments explain *why*, not *what*.
- Private members and methods prefixed with `_`.

**Declaration order within a class:**
1. `class_name` / `extends`
2. Class-level `##` doc comment
3. Signals → Enums → Constants → `@export` vars → public vars → private vars → `@onready` vars
4. Built-in virtual methods (`_ready`, `_process`, …)
5. Public methods
6. Private methods
7. Inner classes
