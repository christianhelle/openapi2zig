const std = @import("std");
const lmstudio = @import("lmstudio.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var client = lmstudio.Client.init(allocator, io, "");
    defer client.deinit();
    client.withBaseUrl("http://localhost:1234");

    var models_result = try lmstudio.listModels(&client);
    defer models_result.deinit();
    const models = models_result.value();

    const first_llm = for (models.models) |*model| {
        if (std.mem.eql(u8, model.@"type", "llm")) break model;
    } else {
        std.debug.print("No LLM models found\n", .{});
        return;
    };

    std.debug.print("Streaming chat with: {s}\n\n", .{first_llm.key});

    const SseCallback = struct {
        pub fn event(_: *@This(), data: []const u8) !void {
            if (std.mem.eql(u8, data, "[DONE]")) return;
            const trimmed = std.mem.trim(u8, data, " \t\n\r");
            if (std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, trimmed, .{})) |parsed| {
                defer parsed.deinit();
                if (parsed.value.object.get("type")) |type_val| {
                    const event_type = type_val.string;
                    std.debug.print("[{s}] ", .{event_type});
                    if (parsed.value.object.get("content")) |content| {
                        std.debug.print("{s}", .{content.string});
                    }
                    std.debug.print("\n", .{});
                }
            } else |_| {}
        }
    };

    var callback = SseCallback{};

    var raw = try lmstudio.chatRaw(&client, .{
        .model = first_llm.key,
        .stream = true,
        .input = .{ .string = "Hello, how are you?" },
    });
    defer raw.deinit();

    if (raw.status.class() != .success) {
        std.debug.print("Error {any}: {s}\n", .{ raw.status, raw.body });
        return;
    }

    try lmstudio.parseSseBytes(allocator, raw.body, &callback);

    std.debug.print("\nDone.\n", .{});
}
