const std = @import("std");

pub const InputSource = union(enum) {
    file_path: []const u8,
    url: []const u8,
};

pub const LoadError = error{
    InvalidUrl,
    HttpRequestFailed,
    HttpTimeout,
    HttpNotFound,
    ConnectionFailed,
    InvalidResponse,
};

/// Loads input from either a file path or HTTP/HTTPS URL
/// Caller owns the returned memory and must free it with allocator.free()
pub fn loadInput(allocator: std.mem.Allocator, source: InputSource) ![]const u8 {
    return switch (source) {
        .file_path => |path| try loadFromFile(allocator, path),
        .url => |url| try loadFromUrl(allocator, url),
    };
}

/// Loads content from a file path
/// Caller owns the returned memory and must free it with allocator.free()
pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        std.debug.print("Failed to open file '{s}': {}\n", .{ path, err });
        return err;
    };
    defer file.close();

    const contents = file.readToEndAlloc(allocator, std.math.maxInt(usize)) catch |err| {
        std.debug.print("Failed to read file '{s}': {}\n", .{ path, err });
        return err;
    };

    return contents;
}

/// Loads content from an HTTP or HTTPS URL
/// Caller owns the returned memory and must free it with allocator.free()
pub fn loadFromUrl(allocator: std.mem.Allocator, url: []const u8) ![]const u8 {
    // Parse URI
    const uri = std.Uri.parse(url) catch |err| {
        std.debug.print("Invalid URL '{s}': {}\n", .{ url, err });
        return LoadError.InvalidUrl;
    };

    // Verify scheme is http or https
    const scheme = uri.scheme;
    if (!std.mem.eql(u8, scheme, "http") and !std.mem.eql(u8, scheme, "https")) {
        std.debug.print("Unsupported URL scheme '{s}'. Only http:// and https:// are supported.\n", .{scheme});
        return LoadError.InvalidUrl;
    }

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // Create and send request
    var req = client.request(.GET, uri, .{}) catch |err| {
        std.debug.print("Failed to create HTTP request to '{s}': {}\n", .{ url, err });
        return LoadError.ConnectionFailed;
    };
    defer req.deinit();

    req.sendBodiless() catch |err| {
        std.debug.print("Failed to send HTTP request to '{s}': {}\n", .{ url, err });
        return LoadError.HttpRequestFailed;
    };

    // Receive response headers
    var redirect_buffer: [1024]u8 = undefined;
    var response = req.receiveHead(&redirect_buffer) catch |err| {
        std.debug.print("Failed to receive HTTP response from '{s}': {}\n", .{ url, err });
        return LoadError.HttpRequestFailed;
    };

    // Check status code
    const status = response.head.status;
    if (status != .ok) {
        if (status == .not_found) {
            std.debug.print("HTTP 404: Resource not found at '{s}'\n", .{url});
            return LoadError.HttpNotFound;
        }
        std.debug.print("HTTP request failed with status {}: {s}\n", .{ @intFromEnum(status), url });
        return LoadError.HttpRequestFailed;
    }

    // Read response body (max 10MB for OpenAPI specs)
    const max_size = 10 * 1024 * 1024;
    var transfer_buffer: [4096]u8 = undefined;
    const reader = response.reader(&transfer_buffer);
    const body = reader.allocRemaining(allocator, std.io.Limit.limited(max_size)) catch |err| {
        std.debug.print("Failed to read HTTP response body from '{s}': {}\n", .{ url, err });
        return LoadError.InvalidResponse;
    };

    // Body ownership is transferred to caller
    return body;
}

/// Determines if a string is an HTTP/HTTPS URL
pub fn isUrl(input: []const u8) bool {
    return std.mem.startsWith(u8, input, "http://") or std.mem.startsWith(u8, input, "https://");
}
