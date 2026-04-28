# OpenAI SDK Generation Issues

Validation date: 2026-04-25

This reflects current `openapi2zig` after commit `8195545 Fix real-world OpenAPI code generation`, tested from `openai.zig`.

## Commands run

```sh
cd ../openapi2zig
zig build test

cd ../openai.zig
zig build generate
zig build test
```

Additional checks:

- generated endpoint body compile smoke test: passed for all 241 generated public functions
- live OpenRouter basic chat call: reached API, failed during response parse with `error.UnknownField`

## Current status

Much improved:

- Generated `src/api.zig` compiles.
- No empty structs remain.
- Major types now exist:
  - `CreateResponse`
  - `Response`
  - `CreateChatCompletionRequest`
- Generated `Client` exists.
- Auth header exists.
- `base_url` override exists.
- Query params are no longer ignored.
- Endpoint functions return `Owned(T)` wrappers instead of dangling `parsed.value`.
- All generated endpoint function bodies compile when forced.

Current generated file stats:

- lines: 16,516
- generated types: 929
- generated functions: 242
- empty structs: 0
- dangling `parsed.value` returns: 0
- ignored params: 0
- `Owned(...)` returns: 234
- `error.ResponseError` sites: 241
- `std.json.Value` mentions: 828


## Update: streaming/OpenRouter usability pass

Implemented in the generator after the initial `8195545` pass:

- Generated endpoint response parsing uses `.ignore_unknown_fields = true`.
- Generated runtime exposes `RawResponse`, `requestRaw`, `getRaw`, and `postJsonRaw` so callers can inspect status and body.
- Generated runtime includes a bounded dynamic SSE parser:
  - LF and CRLF lines
  - comments starting with `:`
  - multiple `data:` lines joined with `\n`
  - blank-line dispatch
  - `data: [DONE]` stop
  - 256 KiB max line size
  - 1 MiB max event size
  - uses `streamDelimiterLimit`, so line size is not tied to the HTTP transfer buffer
- OpenAI generation emits:
  - `streamChatCompletion(client, requestBody, callback)`
  - `streamResponse(client, requestBody, callback)`
- Stream helpers force `stream: true` in the JSON payload and send `Accept: text/event-stream`.
- Live OpenRouter streaming smoke passed with `openrouter/free`.
- `CreateChatCompletionRequest` and `CreateResponse` include flattened `extra_body`.
- Assistant chat messages can carry provider data because `ChatCompletionRequestMessage` remains `std.json.Value`; generated assistant message structs also include `reasoning_details` when present/needed.

Still open:

- Typed stream event parsing. Current stream callbacks receive raw `data:` bytes.
- Typed API error result union. Current typed endpoints still return `error.ResponseError`; raw helpers expose body/status.
- Multipart/form-data and binary response ergonomics.
- Resource module SDK shape.

## Remaining issues

### 1. `zig build generate` fails after writing file

Observed:

```text
Code generated successfully and written to 'src/api.zig'.
thread ... panic: incorrect alignment
.../std/hash_map.zig:784:44 in header
.../openapi2zig/src/models/common/document.zig:92:33 in Schema.deinit
.../openapi2zig/src/models/common/document.zig:231:39 in UnifiedDocument.deinit
.../openapi2zig/src/generator.zig:139:29 in generateCodeFromOpenApi31Document
```

`src/api.zig` is written and compiles, but process exits via panic, causing `zig build generate` failure.

Likely cause:

- ownership/deinit bug in unified schema conversion
- possibly copied `std.StringHashMap(Schema)` values aliasing map internals
- double deinit or deinit of moved/uninitialized map

Acceptance:

- `zig build generate` exits 0.
- No panic after writing output.
- Run under debug allocator with leak/double-free checks.

### 2. Response parsing fails on unknown provider fields

Live OpenRouter test:

```zig
var client = openai.Client.init(allocator, init.io, api_key);
client.withBaseUrl("https://openrouter.ai/api/v1");

var response = try openai.createChatCompletion(&client, .{
    .model = "openrouter/free",
    .messages = parsed_messages.value,
});
```

Result:

```text
error: UnknownField
std/json/static.zig:380:25 in innerParse
src/api.zig:6515 in createChatCompletion
```

Generated code currently parses with strict options:

```zig
const parsed = try std.json.parseFromSlice(CreateChatCompletionResponse, allocator, body, .{});
```

This should be:

```zig
const parsed = try std.json.parseFromSlice(CreateChatCompletionResponse, allocator, body, .{
    .ignore_unknown_fields = true,
});
```

Especially important for:

- OpenRouter-compatible APIs
- OpenAI adding new fields before spec update
- event/message/provider extension fields

Acceptance:

- All generated response parsing uses `.ignore_unknown_fields = true` by default.
- Or client option controls strictness, default loose.

### 3. No `reasoning_details`

Observed:

```sh
rg reasoning_details src/api.zig
# no results
```

OpenRouter reasoning carry-forward needs assistant message support:

```zig
reasoning_details: ?std.json.Value = null,
```

Because OpenAI spec may not include this field, generator needs provider extension support.

Acceptance:

- Request structs can carry provider extension fields.
- Chat messages can preserve `reasoning_details` either via explicit field or `extra_body`/extra fields mechanism.

### 4. No `extra_body` flattening

Observed:

```sh
rg extra_body src/api.zig
# no results
```

OpenRouter Python pattern:

```python
extra_body={"reasoning": {"enabled": True}}
```

Generated request structs need an extension mechanism:

```zig
extra_body: ?std.json.Value = null,
```

Serializer must flatten `extra_body` into root JSON object, not emit literal `extra_body`.

Acceptance:

- Generated request serialization supports provider-specific fields.
- `extra_body` flattened.
- Tests prove no `"extra_body"` key emitted.

### 5. Streaming not implemented as streaming runtime

Generated file has stream-related types and params, but no obvious SSE runtime/callback/iterator.

Requirements:

- raw SSE parser
- `[DONE]` support
- comments beginning `:`
- CRLF/LF
- multiple `data:` lines joined with `\n`
- max event size

Acceptance:

```zig
try openai.createResponseStream(&client, .{ ... }, callback);
```

or resource-equivalent generated API.

### 6. Error bodies still discarded

All endpoints still use:

```zig
if (result.status.class() != .success) {
    return error.ResponseError;
}
```

This loses response body with OpenAI error details.

Acceptance:

Short term:

```zig
pub const RawResponse = struct {
    status: std.http.Status,
    body: []u8,
};
```

Long term:

```zig
pub const ApiResult(comptime T: type) = union(enum) {
    ok: Owned(T),
    api_error: Owned(ApiError),
};
```

### 7. Multipart/binary endpoints still questionable

Generated types include multipart body types:

```zig
CreateVideoExtendMultipartBody
CreateVideoEditMultipartBody
CreateVideoMultipartBody
```

But generated functions appear to select JSON bodies for video endpoints:

```zig
createVideo(... CreateVideoJsonBody)
CreateVideoExtend(... CreateVideoExtendJsonBody)
CreateVideoEdit(... CreateVideoEditJsonBody)
```

Also file/audio endpoints may still be JSON-only when spec requires multipart or binary response.

Acceptance:

- Inspect operation request content-type.
- Generate `multipart/form-data` runtime.
- Generate binary/raw response for file/audio content.
- Do not force `application/json` for multipart endpoints.

### 8. `std.json.Value` overuse remains

Current count: 828 mentions.

Some are fine. But several important semantic fields still collapse to `std.json.Value`.

Examples:

- complex message content
- response input/output unions
- reasoning and stream event unions

Acceptance:

- Keep `std.json.Value` fallback for ambiguous schemas.
- Improve discriminated unions later.
- Prioritize chat/messages/responses event types.

### 9. Top-level flat API remains

Current generated API is flat:

```zig
openai.createResponse(&client, ...)
openai.createChatCompletion(&client, ...)
```

This is usable, but eventual SDK mode should generate resources:

```zig
client.responses.create(...)
client.chat.completions.create(...)
```

or:

```zig
openai.resources.responses.create(&client, ...)
```

Flat API can remain for single-file/raw mode.

## Reproduction snippets

### Generate panic

```sh
cd openai.zig
zig build generate
```

Expected: exit 0.
Current: writes file, then panic in `UnifiedDocument.deinit`.

### Force all endpoint function bodies to compile

```zig
const api = @import("src/api.zig");

test "force all generated endpoint function bodies" {
    var run = false;
    _ = &run;
    if (run) {
        _ = try api.createResponse(undefined, undefined);
        // generated for all pub fns with undefined args
    }
}
```

Current: passes for all 241 endpoint functions.

### Basic OpenRouter live parse failure

```zig
var client = openai.Client.init(allocator, init.io, api_key);
defer client.deinit();
client.withBaseUrl("https://openrouter.ai/api/v1");

const messages_json =
    \\[{"role":"user","content":"How many r's are in strawberry? Answer briefly."}]
;
const parsed_messages = try std.json.parseFromSlice([]const std.json.Value, allocator, messages_json, .{});
defer parsed_messages.deinit();

var response = try openai.createChatCompletion(&client, .{
    .model = "openrouter/free",
    .messages = parsed_messages.value,
});
defer response.deinit();
```

Current result: `error.UnknownField` while parsing `CreateChatCompletionResponse`.

## Acceptance criteria for next pass

Must:

- `zig build generate` exits 0; no deinit panic.
- All generated response parsing ignores unknown fields by default.
- Basic OpenRouter chat call succeeds or at least returns inspectable non-2xx body.
- Error bodies are available via raw/detailed helper.

Should:

- Add `extra_body` flattening.
- Add `reasoning_details` extension support.
- Add first streaming/SSE runtime.
- Start multipart support or mark unsupported endpoints raw.
