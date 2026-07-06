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

    std.debug.print("Streaming chat with model: {s}\n\n", .{first_llm.key});

    const PrintCallback = struct {
        pub fn event(_: *@This(), data: []const u8) !void {
            std.debug.print("{s}\n", .{data});
        }
    };

    var callback = PrintCallback{};

    lmstudio.chatStreaming(&client, .{
        .model = first_llm.key,
        .input = .{ .string = "Hello, how are you?" },
    }, &callback) catch |err| {
        std.debug.print("\nStreaming error: {any}\n", .{err});
    };

    std.debug.print("\nDone.\n", .{});
}
