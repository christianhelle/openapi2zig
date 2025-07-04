const Example = @import("example.zig").Example;
const Schema = @import("schema.zig").Schema;

pub const Components = struct {
    schemas: ?std.AutoHashMap([]const u8, Schema) = null,
    responses: ?std.AutoHashMap([]const u8, Response) = null,
    parameters: ?std.AutoHashMap([]const u8, Parameter) = null,
    examples: ?std.AutoHashMap([]const u8, Example) = null,
    requestBodies: ?std.AutoHashMap([]const u8, RequestBody) = null,
    headers: ?std.AutoHashMap([]const u8, Header) = null,
    securitySchemes: ?std.AutoHashMap([]const u8, SecurityScheme) = null,
    links: ?std.AutoHashMap([]const u8, Link) = null,
    callbacks: ?std.AutoHashMap([]const u8, Callback) = null,
};

pub const Schema = struct {
    key: []const u8,
    value: std.ArrayHashMap([]const u8, std.ArrayHashMap(
        []const u8,
    )),
};
