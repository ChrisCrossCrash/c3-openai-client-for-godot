extends GutTest


## Tests for [method C3OpenAIClient.chat_completion_stream].
class TestChatCompletionStream extends GutTest:
	const C3HTTPRequest := preload("res://c3_openai_client/utils/c3_http_request.gd")

	var client: C3TestDoubles.TestableClient

	func before_each() -> void:
		client = C3TestDoubles.TestableClient.new()
		add_child_autofree(client)

	func after_each() -> void:
		# Resume any stream a test left parked (e.g. ones that only inspected the
		# request body) so its _http_stream coroutine returns and the ChatStream
		# node frees — otherwise the suspended state leaks at exit. Harmless when
		# nothing is parked (no coroutine is awaiting the signal).
		client._stream_drive.emit()

	## Chat options with a model set, to silence the empty-model warning.
	func opts_with_model(model := "gpt-4o") -> C3OpenAIClient.ChatOptions:
		var opts := C3OpenAIClient.ChatOptions.new()
		opts.model = model
		return opts

	## A streaming chunk carrying a content delta, as the server emits it.
	func content_chunk(text: String) -> String:
		return JSON.stringify(
			{"choices": [{"delta": {"content": text}, "finish_reason": null}]}
		)

	## The terminal chunk: empty delta, finish_reason, model, and usage.
	func final_chunk(finish_reason := "stop", model := "gpt-4o") -> String:
		return JSON.stringify(
			{
				"choices": [{"delta": {}, "finish_reason": finish_reason}],
				"model": model,
				"usage":
				{
					"prompt_tokens": 10,
					"completion_tokens": 5,
					"total_tokens": 15
				},
			}
		)

	## Starts a stream and returns it. The fake transport is parked on the client;
	## drive it via client.stream_on_event / client._stream_drive.
	func start_stream() -> C3OpenAIClient.ChatStream:
		return client.chat_completion_stream(
			[C3OpenAIClient.make_user_msg("Hello")], opts_with_model()
		)

	## Pushes one SSE event into the parked stream.
	func emit_event(data: String) -> void:
		client.stream_on_event.call(data, "message")

	## Finishes the parked stream by setting its result and resuming it. The emit
	## resumes the await synchronously, so `finished` fires before this returns.
	func finish_stream(result: C3HTTPRequest.Response) -> void:
		client.stream_result = result
		client._stream_drive.emit()

	## Connects a capturing callback to `finished` and returns the array it
	## appends the result to. Capturing up front works because the fake drives
	## the stream synchronously, so `finished` fires during the driving emits.
	func capture_finished(stream: C3OpenAIClient.ChatStream) -> Array:
		var captured := []
		stream.finished.connect(func(r: Variant) -> void: captured.append(r))
		return captured

	## Emits a full, successful two-token stream over the fake transport.
	func drive_success() -> void:
		emit_event(content_chunk("Hel"))
		emit_event(content_chunk("lo"))
		emit_event(final_chunk())
		emit_event("[DONE]")
		finish_stream(C3TestDoubles.ok_response())

	func test_returns_chat_stream() -> void:
		var stream := start_stream()
		assert_is(stream, C3OpenAIClient.ChatStream)

	func test_extra_body_merged_into_request() -> void:
		var opts := opts_with_model()
		opts.extra_body = {"top_p": 0.5}
		client.chat_completion_stream(
			[C3OpenAIClient.make_user_msg("Hello")], opts
		)
		var body: Dictionary = JSON.parse_string(client.last_stream_body)
		assert_eq(body["top_p"], 0.5)

	func test_extra_body_can_override_stream_flag() -> void:
		# extra_body always wins, even over the library's structural keys.
		var opts := opts_with_model()
		opts.extra_body = {"stream": false}
		client.chat_completion_stream(
			[C3OpenAIClient.make_user_msg("Hello")], opts
		)
		var body: Dictionary = JSON.parse_string(client.last_stream_body)
		assert_false(body["stream"])

	func test_emits_delta_per_content_chunk() -> void:
		var stream := start_stream()
		var deltas := []
		stream.delta.connect(func(t: String) -> void: deltas.append(t))
		drive_success()
		assert_eq(deltas, ["Hel", "lo"])

	func test_finished_result_is_chat_completion_response() -> void:
		var stream := start_stream()
		var captured := capture_finished(stream)
		drive_success()
		assert_is(captured[0], C3OpenAIClient.ChatCompletionResponse)

	func test_content_is_accumulated() -> void:
		var stream := start_stream()
		var captured := capture_finished(stream)
		drive_success()
		assert_eq(captured[0].content, "Hello")

	func test_finish_reason_is_populated() -> void:
		var stream := start_stream()
		var captured := capture_finished(stream)
		drive_success()
		assert_eq(captured[0].finish_reason, "stop")

	func test_model_is_populated() -> void:
		var stream := start_stream()
		var captured := capture_finished(stream)
		emit_event(final_chunk("stop", "llama-3.1-8b"))
		finish_stream(C3TestDoubles.ok_response())
		assert_eq(captured[0].model, "llama-3.1-8b")

	func test_usage_is_populated() -> void:
		var stream := start_stream()
		var captured := capture_finished(stream)
		drive_success()
		var usage: Dictionary = captured[0].usage
		assert_eq(typeof(usage["prompt_tokens"]), TYPE_INT)
		assert_eq(usage["prompt_tokens"], 10)
		assert_eq(usage["completion_tokens"], 5)
		assert_eq(usage["total_tokens"], 15)

	func test_ok_is_true_on_clean_finish() -> void:
		var stream := start_stream()
		var captured := capture_finished(stream)
		drive_success()
		assert_true(captured[0].ok)

	func test_finished_emitted_once_on_success() -> void:
		var stream := start_stream()
		var captured := capture_finished(stream)
		drive_success()
		assert_eq(captured.size(), 1)

	func test_done_sentinel_does_not_emit_delta() -> void:
		var stream := start_stream()
		var deltas := []
		stream.delta.connect(func(t: String) -> void: deltas.append(t))
		emit_event("[DONE]")
		finish_stream(C3TestDoubles.ok_response())
		assert_eq(deltas.size(), 0)

	func test_invalid_json_chunk_is_ignored() -> void:
		var stream := start_stream()
		var deltas := []
		stream.delta.connect(func(t: String) -> void: deltas.append(t))
		var captured := capture_finished(stream)
		emit_event("not json")
		finish_stream(C3TestDoubles.ok_response())
		assert_eq(deltas.size(), 0)
		assert_true(captured[0].ok)

	func test_empty_choices_chunk_is_ignored() -> void:
		var stream := start_stream()
		var deltas := []
		stream.delta.connect(func(t: String) -> void: deltas.append(t))
		var captured := capture_finished(stream)
		emit_event('{"choices": []}')
		finish_stream(C3TestDoubles.ok_response())
		assert_eq(deltas.size(), 0)
		assert_true(captured[0].ok)

	func test_refusal_is_accumulated() -> void:
		var stream := start_stream()
		var captured := capture_finished(stream)
		emit_event(
			JSON.stringify({"choices": [{"delta": {"refusal": "I can't help "}}]})
		)
		emit_event(
			JSON.stringify({"choices": [{"delta": {"refusal": "with that."}}]})
		)
		finish_stream(C3TestDoubles.ok_response())
		assert_eq(captured[0].refusal, "I can't help with that.")

	func test_uses_correct_endpoint() -> void:
		client.base_url = "http://example.com/v1"
		start_stream()
		assert_eq(
			client.last_stream_url, "http://example.com/v1/chat/completions"
		)

	func test_request_body_has_stream_true() -> void:
		start_stream()
		var body: Variant = JSON.parse_string(client.last_stream_body)
		assert_true(body["stream"])

	func test_omits_stream_options_by_default() -> void:
		start_stream()
		var body: Variant = JSON.parse_string(client.last_stream_body)
		assert_false(body.has("stream_options"))

	func test_include_usage_sets_stream_options() -> void:
		var opts := opts_with_model()
		opts.include_usage = true
		client.chat_completion_stream(
			[C3OpenAIClient.make_user_msg("Hello")], opts
		)
		var body: Variant = JSON.parse_string(client.last_stream_body)
		assert_eq(body["stream_options"], {"include_usage": true})

	func test_request_body_has_messages_and_model() -> void:
		client.chat_completion_stream(
			[C3OpenAIClient.make_user_msg("Hello")], opts_with_model("gpt-4o")
		)
		var body: Variant = JSON.parse_string(client.last_stream_body)
		assert_eq(body["model"], "gpt-4o")
		assert_eq(body["messages"], [{"role": "user", "content": "Hello"}])

	func test_warns_when_model_is_empty() -> void:
		client.chat_completion_stream([C3OpenAIClient.make_user_msg("Hello")])
		assert_push_warning(
			"C3OpenAIClient: opts.model is empty — using server default."
		)

	func test_non_200_resolves_failed() -> void:
		var stream := start_stream()
		var captured := capture_finished(stream)
		finish_stream(C3TestDoubles.http_error_response(404))
		assert_false(captured[0].ok)

	func test_non_200_error_has_status() -> void:
		var stream := start_stream()
		var captured := capture_finished(stream)
		finish_stream(C3TestDoubles.http_error_response(404))
		assert_eq(captured[0].error.status, 404)

	func test_non_200_emits_request_failed() -> void:
		start_stream()
		watch_signals(client)
		finish_stream(C3TestDoubles.http_error_response(500))
		assert_signal_emitted(client, "request_failed")

	func test_non_200_error_body_parsed_as_api_error() -> void:
		var stream := start_stream()
		var captured := capture_finished(stream)
		var body := JSON.stringify(
			{"error": {"message": "Bad key.", "code": "invalid_api_key"}}
		)
		finish_stream(C3TestDoubles.http_error_response(401, body))
		var err: C3OpenAIClient.ApiError = captured[0].error
		assert_eq(err.kind, &"api")
		assert_eq(err.status, 401)
		assert_eq(err.code, "invalid_api_key")
		assert_eq(err.message, "Bad key.")

	func test_non_200_empty_body_is_http_kind() -> void:
		var stream := start_stream()
		var captured := capture_finished(stream)
		finish_stream(C3TestDoubles.http_error_response(503))
		var err: C3OpenAIClient.ApiError = captured[0].error
		assert_eq(err.kind, &"http")
		assert_eq(err.message, "Request failed with status 503.")

	func test_transport_failure_error_is_transport_kind() -> void:
		var stream := start_stream()
		var captured := capture_finished(stream)
		finish_stream(C3TestDoubles.transport_error_response("Could not connect."))
		assert_eq(captured[0].error.kind, &"transport")

	func test_transport_failure_resolves_failed() -> void:
		var stream := start_stream()
		var captured := capture_finished(stream)
		finish_stream(C3TestDoubles.transport_error_response("Could not connect."))
		assert_false(captured[0].ok)

	func test_transport_failure_emits_request_failed() -> void:
		start_stream()
		watch_signals(client)
		finish_stream(C3TestDoubles.transport_error_response("Could not connect."))
		assert_signal_emitted(client, "request_failed")

	func test_client_error_resolves_failed() -> void:
		var stream := start_stream()
		var captured := capture_finished(stream)
		finish_stream(C3TestDoubles.client_error_response('Invalid URL.'))
		assert_false(captured[0].ok)

	func test_client_error_emits_request_failed() -> void:
		start_stream()
		watch_signals(client)
		finish_stream(C3TestDoubles.client_error_response('Invalid URL.'))
		assert_signal_emitted(client, "request_failed")

	func test_cancel_error_is_cancelled_kind() -> void:
		var stream := start_stream()
		var captured := capture_finished(stream)
		stream.cancel()
		assert_eq(captured[0].error.kind, &"cancelled")
		# Resume the parked transport so the stream node frees cleanly.
		finish_stream(C3TestDoubles.transport_error_response())

	func test_cancel_resolves_failed() -> void:
		var stream := start_stream()
		var captured := capture_finished(stream)
		stream.cancel()
		assert_false(captured[0].ok)
		finish_stream(C3TestDoubles.transport_error_response())

	func test_cancel_cancels_token() -> void:
		var stream := start_stream()
		stream.cancel()
		assert_true(client.stream_token.is_cancelled())
		finish_stream(C3TestDoubles.transport_error_response())

	func test_cancel_does_not_emit_request_failed() -> void:
		var stream := start_stream()
		watch_signals(client)
		stream.cancel()
		assert_signal_not_emitted(client, "request_failed")
		finish_stream(C3TestDoubles.transport_error_response())

	func test_cancel_after_finish_is_noop() -> void:
		var stream := start_stream()
		var captured := capture_finished(stream)
		drive_success()
		stream.cancel()
		assert_eq(captured.size(), 1)
		assert_true(captured[0].ok)
