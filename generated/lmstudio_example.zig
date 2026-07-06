const std = @import("std");
const lmstudio = @import("lmstudio.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var stdout_buf: [4096]u8 = undefined;
    const stdout_file = std.Io.File.stdout();
    var stdout_fw = std.Io.File.writer(stdout_file, io, &stdout_buf);
    const stdout_w = &stdout_fw.interface;

    var client = lmstudio.Client.init(allocator, io, "");
    defer client.deinit();
    client.withBaseUrl("http://localhost:1234");

    var models_result = try lmstudio.listModels(&client);
    defer models_result.deinit();
    const models = models_result.value();

    const first_llm = for (models.models) |*model| {
        if (std.mem.eql(u8, model.@"type", "llm")) break model;
    } else {
        try stdout_w.print("No LLM models found\n", .{});
        return;
    };

    try stdout_w.print("Streaming chat with: {s}\n\n", .{first_llm.key});
    try stdout_fw.flush();

    const SseCallback = struct {
        w: *std.Io.Writer,

        pub fn event(self: *@This(), data: []const u8) !void {
            if (std.mem.eql(u8, data, "[DONE]")) return;
            const trimmed = std.mem.trim(u8, data, " \t\n\r");
            if (std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, trimmed, .{})) |parsed| {
                defer parsed.deinit();
                if (parsed.value.object.get("type")) |type_val| {
                    const event_type = type_val.string;
                    try self.w.print("[{s}] ", .{event_type});
                    if (parsed.value.object.get("content")) |content| {
                        try self.w.print("{s}", .{content.string});
                    }
                    try self.w.print("\n", .{});
                }
            } else |_| {}
        }
    };

    var callback = SseCallback{ .w = stdout_w };

    var raw = try lmstudio.chatRaw(&client, .{
        .model = first_llm.key,
        .stream = true,
        .input = .{ .string = "Hello, how are you?" },
    });
    defer raw.deinit();

    if (raw.status.class() != .success) {
        try stdout_w.print("Error {any}: {s}\n", .{ raw.status, raw.body });
        try stdout_fw.flush();
        return;
    }

    try lmstudio.parseSseBytes(allocator, raw.body, &callback);

    try stdout_w.print("\nDone.\n", .{});
    try stdout_fw.flush();
}
