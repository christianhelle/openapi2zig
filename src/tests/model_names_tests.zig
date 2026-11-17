const std = @import("std");
const model_names = @import("../generators/unified/model_names.zig");
const Schema = @import("../models/common/document.zig").Schema;
const test_utils = @import("test_utils.zig");

const testing = std.testing;

fn schemasFor(allocator: std.mem.Allocator, names: []const []const u8) !std.StringHashMap(Schema) {
    var map = std.StringHashMap(Schema).init(allocator);
    errdefer map.deinit();
    for (names) |name| try map.put(name, .{});
    return map;
}

test "namespaced names strip the shared prefix and use PascalCase" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var schemas = try schemasFor(allocator, &.{
        "microsoft.graph.user",
        "microsoft.graph.security.alert",
        "microsoft.graph.callRecords.session",
        "microsoft.graph.partners.billing.invoice",
        "ODataCountResponse",
    });
    defer schemas.deinit();
    var map = try model_names.ModelNameMap.init(allocator, schemas);
    defer map.deinit();

    try testing.expectEqualStrings("User", map.flatName("microsoft.graph.user"));
    try testing.expectEqualStrings("SecurityAlert", map.flatName("microsoft.graph.security.alert"));
    try testing.expectEqualStrings("CallRecordsSession", map.flatName("microsoft.graph.callRecords.session"));
    try testing.expectEqualStrings("PartnersBillingInvoice", map.flatName("microsoft.graph.partners.billing.invoice"));
    try testing.expectEqualStrings("ODataCountResponse", map.flatName("ODataCountResponse"));
    try testing.expectEqualStrings("unknown", map.flatName("unknown"));
}

test "names without a shared prefix keep every segment" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var schemas = try schemasFor(allocator, &.{ "a.user", "b.group", "plain" });
    defer schemas.deinit();
    var map = try model_names.ModelNameMap.init(allocator, schemas);
    defer map.deinit();

    try testing.expectEqualStrings("AUser", map.flatName("a.user"));
    try testing.expectEqualStrings("BGroup", map.flatName("b.group"));
    try testing.expectEqualStrings("Plain", map.flatName("plain"));
}

test "colliding names get a suffix in a stable order" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var schemas = try schemasFor(allocator, &.{ "x.user", "x.User", "x.user_" });
    defer schemas.deinit();
    var map = try model_names.ModelNameMap.init(allocator, schemas);
    defer map.deinit();

    // Sorted order is "x.User", "x.user", "x.user_".
    try testing.expectEqualStrings("User", map.flatName("x.User"));
    try testing.expectEqualStrings("User_", map.flatName("x.user"));
    try testing.expectEqualStrings("User__", map.flatName("x.user_"));
}

test "namespace aliases nest by snake case namespace" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var schemas = try schemasFor(allocator, &.{
        "microsoft.graph.user",
        "microsoft.graph.security.alert",
        "microsoft.graph.security.incident",
        "microsoft.graph.callRecords.session",
        "microsoft.graph.partners.billing.invoice",
    });
    defer schemas.deinit();
    var map = try model_names.ModelNameMap.init(allocator, schemas);
    defer map.deinit();

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    try map.appendNamespaceAliases(allocator, &out);

    const expected =
        "const root = @This();\n" ++
        "pub const call_records = struct {\n" ++
        "pub const Session = root.CallRecordsSession;\n" ++
        "};\n" ++
        "pub const partners = struct {\n" ++
        "pub const billing = struct {\n" ++
        "pub const Invoice = root.PartnersBillingInvoice;\n" ++
        "};\n" ++
        "};\n" ++
        "pub const security = struct {\n" ++
        "pub const Alert = root.SecurityAlert;\n" ++
        "pub const Incident = root.SecurityIncident;\n" ++
        "};\n";
    try testing.expect(std.mem.indexOf(u8, out.items, expected) != null);
}

test "no aliases are emitted when nothing is namespaced" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var schemas = try schemasFor(allocator, &.{ "Pet", "Owner" });
    defer schemas.deinit();
    var map = try model_names.ModelNameMap.init(allocator, schemas);
    defer map.deinit();

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    try map.appendNamespaceAliases(allocator, &out);
    try testing.expectEqual(@as(usize, 0), out.items.len);
}
