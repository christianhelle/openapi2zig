const models = @import("models.zig");
const generator = @import("generator.zig");

const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    //defer _ = gpa.deinit(); // Not needed here, as we will deinit the allocator at the end of the program
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <path_to_openapi_json> <output_path>\n", .{args[0]});
        return;
    }

    const input_file_Path = args[1];
    const openapi_file = try std.fs.cwd().openFile(input_file_Path, .{});
    defer openapi_file.close();

    try openapi_file.seekBy(0);
    const file_contents = try openapi_file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(file_contents);

    var openapi = try models.OpenApiDocument.parse(allocator, file_contents);
    defer openapi.deinit(allocator);

    var model_generator = generator.ModelCodeGenerator.init(allocator);
    defer model_generator.deinit();

    const generated_code = try model_generator.generate(openapi);
    defer allocator.free(generated_code);

    if (args.len > 2) {
        const output_path = args[2];
        if (std.fs.path.dirname(output_path)) |dir_path| {
            try std.fs.cwd().makePath(dir_path);
        }
        const output_file = try std.fs.cwd().createFile(output_path, .{ .read = true });
        defer output_file.close();
        try output_file.writeAll(generated_code);
        std.debug.print("Models generated successfully and written to '{s}'.\n", .{output_path});
    } else {
        const output_file = try std.fs.cwd().createFile("generated_models.zig", .{ .read = true });
        defer output_file.close();
        try output_file.writeAll(generated_code);
        std.debug.print("Models generated successfully and written to 'generated_models.zig'.\n", .{});
    }
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

test "can generate data structures from petstore OpenAPI specification" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const file = try std.fs.cwd().openFile("openapi/petstore.json", .{});
    defer file.close();
    try file.seekBy(0);
    const file_contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(file_contents);

    var parsed = try models.OpenApiDocument.parse(allocator, file_contents);
    defer parsed.deinit(allocator);

    var code_gen = generator.ModelCodeGenerator.init(allocator);
    defer code_gen.deinit();

    const generated_code = try code_gen.generate(parsed);
    defer allocator.free(generated_code);

    std.debug.print("Generated code:\n{s}\n", .{generated_code});
    try std.testing.expect(generated_code.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "pub const Pet = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "name: []const u8") != null);
}
