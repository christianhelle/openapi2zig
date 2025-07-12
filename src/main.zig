const models = @import("models.zig");

const std = @import("std");

pub fn main() !void {
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});
    try bw.flush(); // Don't forget to flush!
}

test "can deserialize petstore into OpenApiDocument" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const file = try std.fs.cwd().openFile("openapi/petstore.json", .{});
    defer file.close();
    try file.seekBy(0);
    const file_contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(file_contents);

    var parsed = try models.OpenApiDocument.parse(allocator, file_contents);
    defer parsed.deinit(allocator);

    try std.testing.expectEqualStrings("3.0.2", parsed.openapi);
    try std.testing.expectEqualStrings("Swagger Petstore", parsed.info.title);

    std.debug.print("Parsed OpenAPI document: {any}\n", .{parsed});

    var iterator = parsed.paths.path_items.iterator();
    while (iterator.next()) |path| {
        std.debug.print("Path: {s}\n", .{path.key_ptr.*});
        std.debug.print("{any}\n\n", .{path.value_ptr.*});
    }
}
