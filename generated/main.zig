const std = @import("std");
const v2 = @import("generated_v2.zig");
const v2_yaml = @import("generated_v2_yaml.zig");
const v3 = @import("generated_v3.zig");
const v3_yaml = @import("generated_v3_yaml.zig");
const v31_yaml = @import("generated_v31_yaml.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var v3_client = v3.Client.init(allocator, io, "");
    defer v3_client.deinit();
    var v2_client = v2.Client.init(allocator, io, "");
    defer v2_client.deinit();
    var v3_yaml_client = v3_yaml.Client.init(allocator, io, "");
    defer v3_yaml_client.deinit();
    var v2_yaml_client = v2_yaml.Client.init(allocator, io, "");
    defer v2_yaml_client.deinit();
    var v31_yaml_client = v31_yaml.Client.init(allocator, io, "");
    defer v31_yaml_client.deinit();
    _ = &v3_yaml_client;
    _ = &v2_yaml_client;
    _ = &v31_yaml_client;

    std.debug.print("Generated models build and run !!\n", .{});
    std.debug.print("YAML-generated client modules initialize too.\n", .{});
    std.debug.print("Testing memory management in generated functions...\n", .{});

    var pet3 = v3.getPetById(&v3_client, 1) catch |err| {
        std.debug.print("Failed to get Pet v3: {any}\n", .{err});
        return;
    };
    defer pet3.deinit();
    std.debug.print("Found Pet v3 with ID:{any}\n\n", .{pet3.value().id});

    var pet2 = v2.getPetById(&v2_client, 1) catch |err| {
        std.debug.print("Failed to get Pet v2: {any}\n", .{err});
        return;
    };
    defer pet2.deinit();
    std.debug.print("Found Pet v2 with ID:{any}\n\n", .{pet2.value().id});
}
