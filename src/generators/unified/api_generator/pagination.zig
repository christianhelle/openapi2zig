const std = @import("std");
const document = @import("../../../models/common/document.zig");
const Operation = document.Operation;
const Schema = document.Schema;
const UnifiedDocument = document.UnifiedDocument;
const UnifiedApiGenerator = @import("../api_generator.zig").UnifiedApiGenerator;
const escapeZigString = @import("helpers.zig").escapeZigString;
const authSchemeForOperation = @import("helpers.zig").authSchemeForOperation;

/// The runtime half of pagination: a type that walks `@odata.nextLink` style
/// links. Emitted into the client only when pagination is requested.
pub fn generatePagerType(self: *UnifiedApiGenerator) !void {
    try self.buffer.appendSlice(self.allocator,
        \\
        \\/// Walks a paged collection. Create one with an operation's `...Pages`
        \\/// function, read `page()`, then call `advance()` until it returns false.
        \\///
        \\/// Later pages are requested with the headers of the first request: the API
        \\/// key header of the operation, or a bearer token when `use_bearer` is set,
        \\/// plus the header parameters in `extra_headers`. The header names and
        \\/// values must outlive the pager; the slice itself is owned by it.
        \\pub fn Pager(comptime Page: type, comptime next_link_field: []const u8, comptime use_bearer: bool) type {
        \\    return struct {
        \\        const Self = @This();
        \\
        \\        client: *Client,
        \\        current: Owned(Page),
        \\        extra_headers: []const std.http.Header,
        \\
        \\        pub fn init(client: *Client, first_page: Owned(Page), extra_headers: []const std.http.Header) Self {
        \\            return .{ .client = client, .current = first_page, .extra_headers = extra_headers };
        \\        }
        \\
        \\        pub fn deinit(self: *Self) void {
        \\            self.client.allocator.free(self.extra_headers);
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
        \\            var headers: std.ArrayList(std.http.Header) = .empty;
        \\            defer headers.deinit(allocator);
        \\            try headers.appendSlice(allocator, self.extra_headers);
        \\            var bearer: ?[]u8 = null;
        \\            defer if (bearer) |value| allocator.free(value);
        \\            if (use_bearer) {
        \\                const holder = try requestToken(client, allocator);
        \\                defer holder.deinit(allocator);
        \\                if (holder.value.len > 0) {
        \\                    bearer = try std.fmt.allocPrint(allocator, "Bearer {s}", .{holder.value});
        \\                    try headers.append(allocator, .{ .name = "Authorization", .value = bearer.? });
        \\                }
        \\            }
        \\
        \\            var raw = try requestRawWithExtraHeaders(client, .GET, url, null, headers.items);
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
    const scheme = authSchemeForOperation(doc, operation);
    const use_bearer = if (scheme) |s| s == .bearer else false;

    try self.buffer.appendSlice(self.allocator, ") !");
    try self.appendPagerType(response, next_link, use_bearer);
    try self.buffer.appendSlice(self.allocator, " {\n");
    try self.buffer.appendSlice(self.allocator, "    const allocator = client.allocator;\n");
    try self.buffer.appendSlice(self.allocator, "    var page_headers: std.ArrayList(std.http.Header) = .empty;\n");
    try self.buffer.appendSlice(self.allocator, "    errdefer page_headers.deinit(allocator);\n");

    // Header parameters and the API key header belong to every page request.
    if (operation.parameters) |parameters| {
        for (parameters, 0..) |parameter, i| {
            if (parameter.location != .header or !isStringParameter(parameter)) continue;
            const escaped_name = try escapeZigString(self.allocator, parameter.name);
            defer self.allocator.free(escaped_name);
            if (parameter.required) {
                try self.buffer.appendSlice(self.allocator, "    try page_headers.append(allocator, .{ .name = \"");
                try self.buffer.appendSlice(self.allocator, escaped_name);
                try self.buffer.appendSlice(self.allocator, "\", .value = ");
                try self.appendParamReference(operation, method, path, i, parameter);
                try self.buffer.appendSlice(self.allocator, " });\n");
            } else {
                try self.buffer.appendSlice(self.allocator, "    if (");
                try self.appendParamReference(operation, method, path, i, parameter);
                try self.buffer.appendSlice(self.allocator, ") |header_value| try page_headers.append(allocator, .{ .name = \"");
                try self.buffer.appendSlice(self.allocator, escaped_name);
                try self.buffer.appendSlice(self.allocator, "\", .value = header_value });\n");
            }
        }
    }
    if (scheme) |s| switch (s) {
        .api_key_header => |key_header| {
            const escaped_name = try escapeZigString(self.allocator, key_header);
            defer self.allocator.free(escaped_name);
            try self.buffer.appendSlice(self.allocator, "    if (client.api_key.len > 0) try page_headers.append(allocator, .{ .name = \"");
            try self.buffer.appendSlice(self.allocator, escaped_name);
            try self.buffer.appendSlice(self.allocator, "\", .value = client.api_key });\n");
        },
        .bearer => {},
    };

    try self.buffer.appendSlice(self.allocator, "    var first_page = try ");
    try self.appendIdentifier(operation_id);
    try self.appendFlatCallArguments(operation);
    try self.buffer.appendSlice(self.allocator, ";\n    errdefer first_page.deinit();\n    return ");
    try self.appendPagerType(response, next_link, use_bearer);
    try self.buffer.appendSlice(self.allocator, ".init(client, first_page, try page_headers.toOwnedSlice(allocator));\n}\n\n");
}

fn isStringParameter(parameter: document.Parameter) bool {
    const schema_type = if (parameter.schema) |schema| schema.type else parameter.type;
    return schema_type == null or schema_type.? == .string;
}

/// Appends `Pager(<response type>, "<link property>")`.
pub fn appendPagerType(self: *UnifiedApiGenerator, response: Schema, next_link: []const u8, use_bearer: bool) !void {
    try self.buffer.appendSlice(self.allocator, "Pager(");
    try self.appendZigTypeFromSchema(response);
    try self.buffer.appendSlice(self.allocator, ", \"");
    const escaped = try escapeZigString(self.allocator, next_link);
    defer self.allocator.free(escaped);
    try self.buffer.appendSlice(self.allocator, escaped);
    try self.buffer.appendSlice(self.allocator, if (use_bearer) "\", true)" else "\", false)");
}
