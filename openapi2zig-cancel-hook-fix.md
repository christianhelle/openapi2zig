# Make generated streaming clients support inline cancellation via a caller-supplied hook

**Target:** `openapi2zig` 0.5.0 (b7e76d4), generating Zig clients consumed by the `puny` CLI (repo: `github.com/christianhelle/puny` pr: `https://github.com/christianhelle/puny/pull/161`, Zig 0.16.0).

## Background

`openapi2zig` generates per-operation API clients from OpenAPI specs. For SSE streaming operations (responses with `text/event-stream`), it emits a `streamJson`/`streamJsonTyped` path that reads the response body through `runtime.parseSseReader` and a `CancellationToken`:

The API clients were generated using the following command:

```bash
openapi2zig generate -i lmstudio.json -o ../lmstudio --multiple-files --file-name models=contracts.zig
openapi2zig generate -i anthropic.json -o ../anthropic --multiple-files --file-name models=contracts.zig
openapi2zig generate -i openai.json -o ../openai --multiple-files --file-name models=contracts.zig
```

where the input files are from [this branch](https://github.com/christianhelle/puny/tree/hybrid-openapi-clients/src/providers/openapi)

- `runtime.zig` provides `CancellationToken` (an atomic bool) and `checkCancellation(token)`, which is called once per SSE line in `parseSseReader` and once before the request is sent.
- The generated `Client` struct (openai example) currently has: `allocator`, `io`, `http`, `api_key`, `base_url`, `organization`, `project`, `default_headers`, `http_observer`.

The consumer (`puny`) needs to abort an in-flight stream when the user hits double-Escape. Cancellation is a **process-global atomic flag** (`src/core/cancel.zig`), set by a stdin monitor thread — not a per-request token.

## The problem (exact)

1. **The generated `CancellationToken` seam cannot interrupt a blocked read.** `checkCancellation` only runs before the request and between parsed SSE lines. If the response body stalls, the read blocks inside the response reader's `stream()` and cancellation is not observed until the next chunk arrives. The app previously worked around this with a polling thread that translated the global flag into `token.cancel()` — a thread per stream, joined on every request, which is wasteful and fiddly.

2. **The working fix had to be hand-patched into generated code.** `puny` wraps the response reader in a `CancelableReader` whose `stream()` vtable checks the global flag before every read, and maps the resulting `ReadFailed` to `error.Canceled` when the flag is set. But `streamJson` constructs `response.reader(...)` internally with no injection point, so the wrapper had to be spliced into the generated file (marked "Hand-wired (not generated)" at `src/providers/openai/client.zig:23-26, 259-268`, plus a standalone `src/providers/openai/cancel_reader.zig`). The generated file header warns "Changes to this file ... will be lost if the code is regenerated," and indeed any regeneration silently drops the cancellation behavior.

**Goal:** make this a first-class, regenerate-safe feature of the generator so consumers never hand-patch generated files, and the polling-thread workaround disappears.

## The fix

Make the generated runtime and client templates emit a generic, caller-supplied cancellation hook. No app-specific imports or app-specific types may appear in generated code; the hook is a plain `fn () bool`.

### 1. Add `CancelableReader` to the generated `runtime.zig` template

Each generated client already gets its own `runtime.zig`, so put it in the shared runtime template so all clients get it:

```zig
/// Wraps an underlying reader and checks an optional cancel predicate at the
/// top of every read. When the predicate returns true, the read fails with
/// error.ReadFailed; callers translate that into error.Cancelled. This is the
/// only way to interrupt a streaming read that is blocked between SSE events
/// (the CancellationToken only takes effect between events).
pub const CancelableReader = struct {
    inner: *std.Io.Reader,
    reader: std.Io.Reader,
    should_cancel: ?*const fn () bool,

    pub fn init(inner: *std.Io.Reader, buffer: []u8, should_cancel: ?*const fn () bool) CancelableReader {
        return .{
            .inner = inner,
            .reader = .{
                .buffer = buffer,
                .seek = 0,
                .end = 0,
                .vtable = &vtable,
            },
            .should_cancel = should_cancel,
        };
    }

    const vtable: std.Io.Reader.VTable = .{
        .stream = stream,
        .discard = std.Io.Reader.defaultDiscard,
        .readVec = std.Io.Reader.defaultReadVec,
        .rebase = std.Io.Reader.defaultRebase,
    };

    fn stream(ctx: *std.Io.Reader, w: *std.Io.Writer, limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
        const self: *CancelableReader = @fieldParentPtr("reader", ctx);
        if (self.should_cancel) |pred| {
            if (pred()) return error.ReadFailed;
        }
        return self.inner.stream(w, limit);
    }
};
```

Preserve the exact mechanics of the known-good hand-patch: the `@fieldParentPtr("reader", ctx)` pattern, delegating everything to `inner.stream`, and a buffer that is at least 1 byte (the SSE parser calls `peekByte`/`takeByte` on the wrapper to detect the delimiter — a 1-byte buffer is proven to work).

### 2. Add an optional `cancel_check` field to the generated `Client` struct

Mirror the existing `http_observer` optional-field pattern, default `null`:

```zig
    /// Optional predicate called before every read of a streaming response
    /// body. When it returns true, the in-flight SSE stream aborts with
    /// error.Cancelled. This is the only way to interrupt a streaming read
    /// that is blocked between SSE events; the CancellationToken only takes
    /// effect between events. Point it at an app-level cancel flag and pass
    /// null for the CancellationToken to streaming calls. When null (default)
    /// streaming reads cannot be interrupted until the next chunk arrives.
    cancel_check: ?*const fn () bool = null,
```

### 3. Update the generated `streamJson` template

Wrap the response reader automatically, with no behavior change when `cancel_check` is null:

```zig
    var transfer_buffer: [8 * 1024]u8 = undefined;
    var response_reader = response.reader(&transfer_buffer);
    if (client.cancel_check) |pred| {
        var cancelable_buffer: [1]u8 = undefined;
        var cancelable_reader = runtime.CancelableReader.init(&response_reader, &cancelable_buffer, pred);
        parseSseReader(allocator, &cancelable_reader.reader, callback, cancellation_token) catch |err| switch (err) {
            error.ReadFailed => {
                if (pred()) return error.Cancelled;
                return response.bodyErr() orelse err;
            },
            else => return err,
        };
    } else {
        parseSseReader(allocator, &response_reader, callback, cancellation_token) catch |err| switch (err) {
            error.ReadFailed => return response.bodyErr() orelse err,
            else => return err,
        };
    }
```

`streamJsonTyped` delegates to `streamJson`, so it is covered automatically. For the pre-buffered `parseSseBytes`/`parseSseBytesTyped` variants (no blocking read), the existing token check is sufficient; leave them unchanged unless you want consistency.

### 4. Keep `CancellationToken` and `checkCancellation` for backward compatibility

New consumers should prefer `cancel_check` and pass `null` tokens.

## Edge cases the implementation must handle

- **Distinguish real read failures from cancellation.** A dropped connection also surfaces as `error.ReadFailed` from the inner reader. When the predicate is set, disambiguate exactly like the hand-patch does: re-check the predicate before mapping to `error.Cancelled`; otherwise fall through to `response.bodyErr() orelse err`. When the predicate is null, a `ReadFailed` must never be reported as cancellation.
- **No behavior change for existing users** who set neither `cancel_check` nor a token.
- **No app-specific identifiers** in generated output (no imports of the consumer's modules).
- Generated-file header comment should note that `streamJson` honors `Client.cancel_check` (turn the "Hand-wired" comment into a normal generated comment).

## Acceptance criteria

1. Regenerating the `openai`, `anthropic`, and `lmstudio` clients from their specs yields output that compiles with **zero hand-patching** and no references to consumer modules.
2. The generated `runtime.zig` unit tests cover: predicate null → pass-through; predicate returning `true` → the streaming call fails with `error.Cancelled`; predicate returning `false` → pass-through.
3. The consumer (`puny`) can then change `src/providers/provider.zig` `chatStreamingOpenAi` to set `generated.cancel_check = cancel.isCancelled;`, pass a `null` CancellationToken, delete `src/providers/openai/cancel_reader.zig` and the "Hand-wired" block in `src/providers/openai/client.zig`, and still pass `zig build test` — including the cancel-during-stream tests.

## Expected consumer diff (shows the contract)

```zig
// provider.zig
var generated = adapter.openAiClient(c);
defer generated.deinit();
generated.cancel_check = cancel.isCancelled;   // pub fn isCancelled() bool
...
openai_client.createChatCompletionStreaming(&generated, adapter.OpenAiStreamingRequest{ .request = request }, &sse, null) catch |err| switch (err) {
    error.Cancelled, error.Canceled => return error.Canceled,
    else => return err,
};
```

## Design note

I recommend the `Client.cancel_check` field over adding a parameter to each streaming function because it matches the existing `http_observer` pattern and keeps the app's wiring in one place — but a per-call parameter is a fine alternative if it fits the generator's architecture better.
