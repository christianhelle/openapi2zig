const std = @import("std");
const document = @import("../../../models/common/document.zig");
const Operation = document.Operation;
const Schema = document.Schema;
const UnifiedDocument = document.UnifiedDocument;
const UnifiedApiGenerator = @import("../api_generator.zig").UnifiedApiGenerator;

/// The runtime half of pagination: a type that walks `@odata.nextLink` style
/// links. Emitted into the client only when pagination is requested.
pub fn generatePagerType(self: *UnifiedApiGenerator) !void {
    try self.buffer.appendSlice(self.allocator,
        \\
        \\/// Walks a paged collection. Create one with an operation's `...Pages`
        \\/// function, read `page()`, then call `advance()` until it returns false.
        \\pub fn Pager(comptime Page: type, comptime next_link_field: []const u8) type {
        \\    return struct {
        \\        const Self = @This();
        \\
        \\        client: *Client,
        \\        current: Owned(Page),
        \\
        \\        pub fn init(client: *Client, first_page: Owned(Page)) Self {
        \\            return .{ .client = client, .current = first_page };
        \\        }
        \\
        \\        pub fn deinit(self: *Self) void {
        \\            self.current.deinit();
        \\        }
        \\
        \\        /// The page fetched most recently.
        \\        pub fn page(self: *const Self) *const Page {
        \\            return &self.current.parsed.value;
        \\        }
        \\
        \\        /// The link to the next page, if the current page has one.
        \\        pub fn nextLink(self: *const Self) ?[]const u8 {
        \\            const link: ?[]const u8 = @field(self.current.parsed.value, next_link_field);
        \\            const value = link orelse return null;
        \\            if (value.len == 0) return null;
        \\            return value;
        \\        }
        \\
        \\        /// Replaces the current page with the next one. Returns false, and keeps
        \\        /// the current page, when there is no next page. Links that point to
        \\        /// another host are refused so the bearer token cannot be sent there.
        \\        pub fn advance(self: *Self) !bool {
        \\            const link = self.nextLink() orelse return false;
        \\            const client = self.client;
        \\            const allocator = client.allocator;
        \\            const url = try allocator.dupe(u8, link);
        \\            defer allocator.free(url);
        \\
        \\            const base = try std.Uri.parse(client.base_url);
        \\            const target = std.Uri.parse(url) catch return error.InvalidNextLink;
        \\            if (!isSameOrigin(base, target)) return error.UntrustedNextLink;
        \\
        \\            const token: []const u8 = if (client.token_provider) |provider| try provider.getToken(allocator, client.io) else client.api_key;
        \\            var bearer: ?[]u8 = null;
        \\            defer if (bearer) |value| allocator.free(value);
        \\            var auth_headers: [1]std.http.Header = undefined;
        \\            var extra_headers: []const std.http.Header = &.{};
        \\            if (token.len > 0) {
        \\                bearer = try std.fmt.allocPrint(allocator, "Bearer {s}", .{token});
        \\                auth_headers[0] = .{ .name = "Authorization", .value = bearer.? };
        \\                extra_headers = auth_headers[0..1];
        \\            }
        \\
        \\            var raw = try requestRawWithExtraHeaders(client, .GET, url, null, extra_headers);
        \\            errdefer raw.deinit();
        \\            if (@intFromEnum(raw.status) < 200 or @intFromEnum(raw.status) >= 300) return error.ResponseError;
        \\            const parsed = try std.json.parseFromSlice(Page, allocator, raw.body, .{ .ignore_unknown_fields = true });
        \\            self.current.deinit();
        \\            self.current = .{ .allocator = allocator, .body = raw.body, .parsed = parsed };
        \\            return true;
        \\        }
        \\    };
        \\}
        \\
    );
}

/// Emits `<operation>Pages`, which fetches the first page and wraps it in a
/// `Pager`. Only operations whose `x-ms-pageable` link property exists on the
/// response model get one.
pub fn generatePagesFunction(self: *UnifiedApiGenerator, method: []const u8, path: []const u8, operation: Operation, doc: UnifiedDocument) !void {
    if (!self.args.pagination) return;
    const next_link = operation.next_link_name orelse return;
    const operation_id = self.operationNameOf(operation) orelse return;
    const response = self.successResponseSchema(operation) orelse return;
    const ref = response.ref orelse return;
    const type_name_raw = if (std.mem.lastIndexOfScalar(u8, ref, '/')) |slash| ref[slash + 1 ..] else ref;
    const schemas = doc.schemas orelse return;
    const page_schema = schemas.get(type_name_raw) orelse return;
    const properties = page_schema.properties orelse return;
    const link_property = properties.get(next_link) orelse return;
    if (link_property.type != .string) return;

    const pages_name = try std.fmt.allocPrint(self.allocator, "{s}Pages", .{operation_id});
    defer self.allocator.free(pages_name);

    try self.buffer.appendSlice(self.allocator, "pub fn ");
    try self.appendIdentifier(pages_name);
    try self.buffer.appendSlice(self.allocator, "(client: *Client");
    try self.appendFlatOperationParameters(operation, method, path);
    try self.buffer.appendSlice(self.allocator, ") !");
    try self.appendPagerType(response, next_link);
    try self.buffer.appendSlice(self.allocator, " {\n    return ");
    try self.appendPagerType(response, next_link);
    try self.buffer.appendSlice(self.allocator, ".init(client, try ");
    try self.appendIdentifier(operation_id);
    try self.appendFlatCallArguments(operation);
    try self.buffer.appendSlice(self.allocator, ");\n}\n\n");
}

/// Appends `Pager(<response type>, "<link property>")`.
pub fn appendPagerType(self: *UnifiedApiGenerator, response: Schema, next_link: []const u8) !void {
    try self.buffer.appendSlice(self.allocator, "Pager(");
    try self.appendZigTypeFromSchema(response);
    try self.buffer.appendSlice(self.allocator, ", \"");
    try self.buffer.appendSlice(self.allocator, next_link);
    try self.buffer.appendSlice(self.allocator, "\")");
}
