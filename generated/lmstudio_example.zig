const std = @import("std");
const lmstudio = @import("lmstudio.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var client = lmstudio.Client.init(allocator, io, "");
    defer client.deinit();
    client.withBaseUrl("http://localhost:1234");

    std.debug.print("Fetching available models...\n\n", .{});

    var models_response = try lmstudio.listModels(&client);
    defer models_response.deinit();

    const models = models_response.value().models;
    if (models.len == 0) {
        std.debug.print("No models found. Make sure LM Studio is running.\n", .{});
        return;
    }

    for (models, 0..) |m, i| {
        const loaded = if (m.loaded_instances.len > 0) " (loaded)" else "";
        std.debug.print("  {d}. {s} [{s}]{s}\n", .{ i + 1, m.display_name, m.key, loaded });
    }

    const model = models[0];
    std.debug.print("\nUsing: {s} [{s}]\n", .{ model.display_name, model.key });

    if (model.loaded_instances.len == 0) {
        std.debug.print("Loading model...\n", .{});
        var load_result = try lmstudio.loadModel(&client, .{
            .model = model.key,
        });
        defer load_result.deinit();
        std.debug.print("Loaded (instance: {s})\n\n", .{load_result.value().instance_id});
    } else {
        std.debug.print("Already loaded\n\n", .{});
    }

    const input_str =
        \\[{"type": "text", "content": "Hello! What can you do?"}]
    ;
    var parsed_input = try std.json.parseFromSlice(std.json.Value, allocator, input_str, .{});
    defer parsed_input.deinit();

    const request = lmstudio.ChatRequest{
        .model = model.key,
        .input = .{ .raw = parsed_input.value },
    };

    const StreamHandler = struct {
        allocator: std.mem.Allocator,
        in_reasoning: bool,

        pub fn event(self: *@This(), data: []const u8) !void {
            var parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, data, .{ .ignore_unknown_fields = true });
            defer parsed.deinit();

            const value = parsed.value;
            if (value != .object) return;
            const event_type = value.object.get("type") orelse return;
            if (event_type != .string) return;

            if (std.mem.eql(u8, event_type.string, "reasoning.start")) {
                self.in_reasoning = true;
                std.debug.print("[reasoning]\n", .{});
                return;
            }
            if (std.mem.eql(u8, event_type.string, "reasoning.end")) {
                self.in_reasoning = false;
                std.debug.print("\n[/reasoning]\n\n", .{});
                return;
            }
            if (std.mem.eql(u8, event_type.string, "reasoning.delta")) {
                const content = value.object.get("content") orelse return;
                if (content != .string) return;
                std.debug.print("{s}", .{content.string});
                return;
            }
            if (std.mem.eql(u8, event_type.string, "message.delta")) {
                const content = value.object.get("content") orelse return;
                if (content != .string) return;
                std.debug.print("{s}", .{content.string});
                return;
            }
        }
    };

    var handler = StreamHandler{ .allocator = allocator, .in_reasoning = false };
    std.debug.print("Chat response:\n\n", .{});

    // First stream: run to completion without cancellation.
    lmstudio.chatStreaming(&client, request, &handler, null) catch |err| {
        std.debug.print("\n\nStream error: {any}\n", .{err});
        return;
    };
    std.debug.print("\n\nDone.\n", .{});

    // Second stream: cancel after a few seconds to demonstrate CancellationToken usage.
    std.debug.print("\nStarting a second stream and cancelling it after 2 seconds...\n", .{});
    var cancel_token = lmstudio.CancellationToken.init();
    const cancel_thread = try std.Thread.spawn(.{}, struct {
        fn run(cancellation_token: *lmstudio.CancellationToken, thread_io: std.Io) !void {
            try std.Io.sleep(thread_io, .fromSeconds(2), .real);
            cancellation_token.cancel();
        }
    }.run, .{ &cancel_token, io });
    defer cancel_thread.join();

    var handler2 = StreamHandler{ .allocator = allocator, .in_reasoning = false };
    lmstudio.chatStreaming(&client, request, &handler2, &cancel_token) catch |err| {
        std.debug.print("Second stream cancelled as expected: {any}\n", .{err});
    };
}
