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
        .input = parsed_input.value,
    };

    const StreamHandler = struct {
        allocator: std.mem.Allocator,

        pub fn event(self: *@This(), data: []const u8) !void {
            var parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, data, .{ .ignore_unknown_fields = true });
            defer parsed.deinit();

            const value = parsed.value;
            if (value != .object) return;
            const event_type = value.object.get("type") orelse return;
            if (event_type != .string) return;
            if (!std.mem.eql(u8, event_type.string, "message.delta")) return;
            const content = value.object.get("content") orelse return;
            if (content != .string) return;
            std.debug.print("{s}", .{content.string});
        }
    };

    var handler = StreamHandler{ .allocator = allocator };
    std.debug.print("Chat response:\n\n", .{});
    lmstudio.chatStreaming(&client, request, &handler) catch |err| {
        std.debug.print("\n\nStream error: {any}\n", .{err});
        return;
    };
    std.debug.print("\n\nDone.\n", .{});
}
