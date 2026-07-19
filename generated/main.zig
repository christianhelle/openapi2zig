const std = @import("std");
const v2 = @import("generated_v2.zig");
const v2_yaml = @import("generated_v2_yaml.zig");
const v3 = @import("generated_v3.zig");
const v3_yaml = @import("generated_v3_yaml.zig");
const v31_yaml = @import("generated_v31_yaml.zig");
const lmstudio = @import("lmstudio.zig");
const openai = @import("openai.zig");

fn logRequest(ctx: ?*anyopaque, method: std.http.Method, url: []const u8, headers: []const std.http.Header, body: ?[]const u8) void {
    _ = ctx;
    std.debug.print("=== REQUEST ===\n", .{});
    std.debug.print("{s} {s}\n", .{ @tagName(method), url });
    std.debug.print("Headers:\n", .{});
    for (headers) |h| {
        std.debug.print("  {s}: {s}\n", .{ h.name, h.value });
    }
    if (body) |b| {
        std.debug.print("Body ({d} bytes):\n{s}\n", .{ b.len, b });
    }
}

fn logResponse(ctx: ?*anyopaque, method: std.http.Method, url: []const u8, status: std.http.Status, headers: []const std.http.Header, body: []const u8, duration_ns: u64) void {
    _ = ctx;
    const ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    std.debug.print("=== RESPONSE ===\n", .{});
    std.debug.print("{s} {s}\n", .{ @tagName(method), url });
    std.debug.print("Status: {d} ({s})\n", .{ @intFromEnum(status), @tagName(status) });
    std.debug.print("Duration: {d:.2}ms\n", .{ms});
    std.debug.print("Headers:\n", .{});
    for (headers) |h| {
        std.debug.print("  {s}: {s}\n", .{ h.name, h.value });
    }
    if (body.len > 0) {
        std.debug.print("Body ({d} bytes):\n{s}\n", .{ body.len, body });
    }
}

fn logError(ctx: ?*anyopaque, method: std.http.Method, url: []const u8, err_name: []const u8) void {
    _ = ctx;
    std.debug.print("=== ERROR ===\n", .{});
    std.debug.print("{s} {s}\n", .{ @tagName(method), url });
    std.debug.print("Error: {s}\n", .{err_name});
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    const observer = v3.HttpObserver{
        .ctx = null,
        .onRequest = &logRequest,
        .onResponse = &logResponse,
        .onError = &logError,
    };

    var v3_client = v3.Client.init(allocator, io, "");
    v3_client.http_observer = observer;
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
