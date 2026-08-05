const std = @import("std");
const multi_v3 = @import("client.zig");

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

    var multi_v3_client = multi_v3.Client.init(allocator, io, "");
    multi_v3_client.http_observer = .{
        .ctx = null,
        .onRequest = &logRequest,
        .onResponse = &logResponse,
        .onError = &logError,
    };
    defer multi_v3_client.deinit();

    std.debug.print("Generated models build and run !!\n", .{});
    std.debug.print("YAML-generated client modules initialize too.\n", .{});
    std.debug.print("Testing memory management in generated functions...\n", .{});

    var multi_pet = multi_v3.getPetById(&multi_v3_client, 1) catch |err| {
        std.debug.print("Failed to get Pet (multi-file): {any}\n", .{err});
        return;
    };
    defer multi_pet.deinit();
    std.debug.print("Found Pet (multi-file) with ID:{any}\n\n", .{multi_pet.value().id});
}
