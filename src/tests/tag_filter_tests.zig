const std = @import("std");
const common = @import("../models/common/document.zig");
const filter = @import("../document_filter.zig");
const test_utils = @import("test_utils.zig");

fn dupTags(allocator: std.mem.Allocator, tags: []const []const u8) ![][]const u8 {
    const out = try allocator.alloc([]const u8, tags.len);
    for (tags, 0..) |tag, i| out[i] = tag;
    return out;
}

fn operationWithRef(
    allocator: std.mem.Allocator,
    operation_id: []const u8,
    tags: ?[]const []const u8,
    body_ref: ?[]const u8,
    response_ref: ?[]const u8,
) !common.Operation {
    var params = std.ArrayList(common.Parameter).empty;
    errdefer params.deinit(allocator);
    const owned_tags = if (tags) |provided| try dupTags(allocator, provided) else null;
    errdefer if (owned_tags) |value| allocator.free(value);

    if (body_ref) |ref| {
        try params.append(allocator, .{
            .name = "body",
            .location = .body,
            .required = true,
            .schema = .{ .ref = ref },
        });
    }

    var responses = std.StringHashMap(common.Response).init(allocator);
    errdefer responses.deinit();
    const response_key = try allocator.dupe(u8, "200");
    errdefer allocator.free(response_key);
    try responses.put(response_key, .{
        .description = "ok",
        .schema = if (response_ref) |ref| common.Schema{ .ref = ref } else null,
    });

    return .{
        .tags = owned_tags,
        .operationId = operation_id,
        .parameters = if (params.items.len == 0) null else try params.toOwnedSlice(allocator),
        .responses = responses,
    };
}

fn buildFilteredFixture(allocator: std.mem.Allocator) !common.UnifiedDocument {
    var paths = std.StringHashMap(common.PathItem).init(allocator);
    errdefer paths.deinit();

    try paths.put(try allocator.dupe(u8, "/pets"), .{
        .get = try operationWithRef(allocator, "listPets", &.{"pet"}, null, "#/components/schemas/Pet"),
    });
    try paths.put(try allocator.dupe(u8, "/pets/{petId}"), .{
        .get = try operationWithRef(allocator, "getPetById", &.{"pet"}, null, "#/components/schemas/Pet"),
    });
    try paths.put(try allocator.dupe(u8, "/store/order"), .{
        .post = try operationWithRef(allocator, "placeOrder", &.{"store"}, "#/components/schemas/Order", "#/components/schemas/Order"),
    });
    try paths.put(try allocator.dupe(u8, "/users"), .{
        .get = try operationWithRef(allocator, "listUsers", &.{"user"}, null, "#/components/schemas/User"),
    });
    try paths.put(try allocator.dupe(u8, "/search"), .{
        .get = try operationWithRef(allocator, "search", null, null, "#/components/schemas/SearchResult"),
    });
    try paths.put(try allocator.dupe(u8, "/both"), .{
        .get = try operationWithRef(allocator, "both", &.{ "pet", "store" }, null, null),
    });

    var schemas = std.StringHashMap(common.Schema).init(allocator);
    errdefer schemas.deinit();

    try schemas.put(try allocator.dupe(u8, "Pet"), .{
        .type = .object,
        .properties = blk: {
            var props = std.StringHashMap(common.Schema).init(allocator);
            try props.put(try allocator.dupe(u8, "name"), .{ .type = .string });
            break :blk props;
        },
    });
    try schemas.put(try allocator.dupe(u8, "Order"), .{
        .type = .object,
        .properties = blk: {
            var props = std.StringHashMap(common.Schema).init(allocator);
            try props.put(try allocator.dupe(u8, "id"), .{ .type = .integer });
            break :blk props;
        },
    });
    try schemas.put(try allocator.dupe(u8, "User"), .{
        .type = .object,
        .properties = blk: {
            var props = std.StringHashMap(common.Schema).init(allocator);
            try props.put(try allocator.dupe(u8, "category"), .{ .ref = "#/components/schemas/Category" });
            break :blk props;
        },
    });
    try schemas.put(try allocator.dupe(u8, "Category"), .{
        .type = .object,
        .properties = blk: {
            var props = std.StringHashMap(common.Schema).init(allocator);
            try props.put(try allocator.dupe(u8, "name"), .{ .type = .string });
            break :blk props;
        },
    });
    try schemas.put(try allocator.dupe(u8, "SearchResult"), .{ .type = .object });

    return .{
        .version = "3.0.0",
        .info = .{ .title = "fixture", .version = "1.0.0" },
        .paths = paths,
        .schemas = schemas,
    };
}

test "filterByTags removes operations without a matching tag" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    var doc = try buildFilteredFixture(allocator);
    defer doc.deinit(allocator);

    try filter.filterByTags(allocator, &doc, &.{"pet"});

    try std.testing.expectEqual(@as(usize, 3), doc.paths.count());
    try std.testing.expect(doc.paths.contains("/pets"));
    try std.testing.expect(doc.paths.contains("/pets/{petId}"));
    try std.testing.expect(doc.paths.contains("/both"));
    try std.testing.expect(!doc.paths.contains("/store/order"));
    try std.testing.expect(!doc.paths.contains("/users"));
}

test "filterByTags removes paths left with no matching operations" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    var doc = try buildFilteredFixture(allocator);
    defer doc.deinit(allocator);

    try filter.filterByTags(allocator, &doc, &.{"user"});

    try std.testing.expectEqual(@as(usize, 1), doc.paths.count());
    try std.testing.expect(doc.paths.contains("/users"));
}

test "filterByTags removes operations without any tag" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    var doc = try buildFilteredFixture(allocator);
    defer doc.deinit(allocator);

    try filter.filterByTags(allocator, &doc, &.{"pet"});

    try std.testing.expect(!doc.paths.contains("/search"));
}

test "filterByTags keeps an operation matching any of the requested tags" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    var doc = try buildFilteredFixture(allocator);
    defer doc.deinit(allocator);

    try filter.filterByTags(allocator, &doc, &.{ "store", "user" });

    try std.testing.expect(doc.paths.contains("/store/order"));
    try std.testing.expect(doc.paths.contains("/users"));
    try std.testing.expect(doc.paths.contains("/both"));
    try std.testing.expect(!doc.paths.contains("/pets"));
}

test "filterByTags is a no-op when no tags are requested" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    var doc = try buildFilteredFixture(allocator);
    defer doc.deinit(allocator);

    try filter.filterByTags(allocator, &doc, &.{});

    try std.testing.expectEqual(@as(usize, 6), doc.paths.count());
}

test "filterByTags trims schemas unreferenced by kept operations" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    var doc = try buildFilteredFixture(allocator);
    defer doc.deinit(allocator);

    try filter.filterByTags(allocator, &doc, &.{"pet"});

    const schemas = doc.schemas.?;
    try std.testing.expectEqual(@as(usize, 1), schemas.count());
    try std.testing.expect(schemas.contains("Pet"));
    try std.testing.expect(!schemas.contains("Order"));
    try std.testing.expect(!schemas.contains("User"));
    try std.testing.expect(!schemas.contains("Category"));
    try std.testing.expect(!schemas.contains("SearchResult"));
}

test "filterByTags keeps nested schemas referenced by kept operations" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    var doc = try buildFilteredFixture(allocator);
    defer doc.deinit(allocator);

    try filter.filterByTags(allocator, &doc, &.{"user"});

    const schemas = doc.schemas.?;
    try std.testing.expect(schemas.contains("User"));
    try std.testing.expect(schemas.contains("Category"));
    try std.testing.expect(!schemas.contains("Pet"));
    try std.testing.expect(!schemas.contains("Order"));
    try std.testing.expect(!schemas.contains("SearchResult"));
}

test "filterByTags keeps schemas referenced by path-level parameters" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    var doc = common.UnifiedDocument{
        .version = "3.0.0",
        .info = .{ .title = "fixture", .version = "1.0.0" },
        .paths = std.StringHashMap(common.PathItem).init(allocator),
        .schemas = std.StringHashMap(common.Schema).init(allocator),
    };
    defer doc.deinit(allocator);

    var schemas = &(doc.schemas orelse unreachable);

    const path_key = try allocator.dupe(u8, "/regions/{region}");
    var path_parameters = try allocator.alloc(common.Parameter, 1);
    path_parameters[0] = .{
        .name = "region",
        .location = .path,
        .required = true,
        .schema = .{ .ref = "#/components/schemas/Region" },
    };

    try doc.paths.put(path_key, .{
        .get = try operationWithRef(allocator, "listRegions", &.{"geo"}, null, null),
        .parameters = path_parameters,
    });

    const schema_key = try allocator.dupe(u8, "Region");
    try schemas.put(schema_key, .{ .type = .string });

    try filter.filterByTags(allocator, &doc, &.{"geo"});

    try std.testing.expect(doc.paths.contains("/regions/{region}"));
    try std.testing.expect(doc.schemas.?.contains("Region"));
}
