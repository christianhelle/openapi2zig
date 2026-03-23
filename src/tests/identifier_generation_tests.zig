const std = @import("std");
const cli = @import("../cli.zig");
const OpenApiConverter = @import("../generators/converters/openapi_converter.zig").OpenApiConverter;
const UnifiedApiGenerator = @import("../generators/unified/api_generator.zig").UnifiedApiGenerator;
const UnifiedModelGenerator = @import("../generators/unified/model_generator.zig").UnifiedModelGenerator;
const zig_identifier = @import("../generators/zig_identifier.zig");
const common = @import("../models/common/document.zig");
const models = @import("../models.zig");
const test_utils = @import("test_utils.zig");

fn loadOpenApiDocument(allocator: std.mem.Allocator, file_path: []const u8) !models.OpenApiDocument {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    try file.seekBy(0);
    const file_contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(file_contents);

    return try models.OpenApiDocument.parseFromJson(allocator, file_contents);
}

test "zig identifier helper preserves valid identifiers and escapes illegal ones" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    var buffer = std.ArrayList(u8){};
    defer buffer.deinit(allocator);

    try zig_identifier.append(&buffer, allocator, "Pet");
    try std.testing.expectEqualStrings("Pet", buffer.items);

    buffer.clearRetainingCapacity();
    try zig_identifier.append(&buffer, allocator, "enterprise-admin/list-global-webhooks");
    try std.testing.expectEqualStrings("@\"enterprise-admin/list-global-webhooks\"", buffer.items);

    buffer.clearRetainingCapacity();
    try zig_identifier.append(&buffer, allocator, "struct");
    try std.testing.expectEqualStrings("@\"struct\"", buffer.items);
}

test "unified model generator escapes schema declarations and references" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    var schemas = std.StringHashMap(common.Schema).init(allocator);
    try schemas.put(try allocator.dupe(u8, "webhook-repository-archived"), common.Schema{
        .type = .object,
    });

    var payload_properties = std.StringHashMap(common.Schema).init(allocator);
    try payload_properties.put(try allocator.dupe(u8, "payload"), common.Schema{
        .ref = "#/components/schemas/webhook-repository-archived",
    });
    try schemas.put(try allocator.dupe(u8, "event-payload"), common.Schema{
        .type = .object,
        .properties = payload_properties,
    });

    var unified = common.UnifiedDocument{
        .version = "3.0.3",
        .info = .{
            .title = "test",
            .version = "1.0.0",
        },
        .paths = std.StringHashMap(common.PathItem).init(allocator),
        .schemas = schemas,
    };
    defer unified.deinit(allocator);

    var generator = UnifiedModelGenerator.init(allocator);
    defer generator.deinit();

    const generated = try generator.generate(unified);
    defer allocator.free(generated);

    try std.testing.expect(std.mem.indexOf(u8, generated, "pub const @\"webhook-repository-archived\" = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "payload: ?@\"webhook-repository-archived\" = null") != null);
}

test "unified api generator escapes operation, parameter, and type identifiers" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const parameters = try allocator.alloc(common.Parameter, 2);
    parameters[0] = .{
        .name = "per-page",
        .location = .query,
        .type = .integer,
    };
    parameters[1] = .{
        .name = "X-GitHub-Api-Version",
        .location = .header,
        .type = .string,
    };

    var responses = std.StringHashMap(common.Response).init(allocator);
    try responses.put(try allocator.dupe(u8, "200"), .{
        .description = "ok",
        .schema = .{
            .ref = "#/components/schemas/pages-https-certificate",
        },
    });

    var paths = std.StringHashMap(common.PathItem).init(allocator);
    try paths.put(try allocator.dupe(u8, "/admin/hooks"), .{
        .get = .{
            .description = "line one\nline two",
            .operationId = "enterprise-admin/list-global-webhooks",
            .parameters = parameters,
            .responses = responses,
        },
    });

    var unified = common.UnifiedDocument{
        .version = "3.0.3",
        .info = .{
            .title = "test",
            .version = "1.0.0",
        },
        .paths = paths,
    };
    defer unified.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, cli.CliArgs{
        .input_path = "openapi/v3.0/ghes-3.20.json",
    });
    defer generator.deinit();

    const generated = try generator.generate(unified);
    defer allocator.free(generated);

    try std.testing.expect(std.mem.indexOf(u8, generated, "pub fn @\"enterprise-admin/list-global-webhooks\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "@\"query_per-page\": i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "@\"header_X-GitHub-Api-Version\": []const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, ") !@\"pages-https-certificate\" {") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "_ = @\"header_X-GitHub-Api-Version\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "// line one\n// line two\n") != null);
}

test "unified api generator sanitizes operation comments" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const responses = std.StringHashMap(common.Response).init(allocator);

    var paths = std.StringHashMap(common.PathItem).init(allocator);
    try paths.put(try allocator.dupe(u8, "/commented"), .{
        .get = .{
            .summary = "Summary\tcolumn\r\nSecond line",
            .description = "Carriage return\rBell\x07byte\n\tIndented line",
            .operationId = "getCommented",
            .responses = responses,
        },
    });

    var unified = common.UnifiedDocument{
        .version = "3.0.3",
        .info = .{
            .title = "test",
            .version = "1.0.0",
        },
        .paths = paths,
    };
    defer unified.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, cli.CliArgs{
        .input_path = "openapi/v3.0/petstore.json",
    });
    defer generator.deinit();

    const generated = try generator.generate(unified);
    defer allocator.free(generated);

    const bell = [_]u8{0x07};

    try std.testing.expect(std.mem.indexOf(u8, generated, "// Summary    column\n// Second line\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "// Carriage return\n// Bell\\x07byte\n//     Indented line\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "\t") == null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "\r") == null);
    try std.testing.expect(std.mem.indexOf(u8, generated, &bell) == null);
}

test "unified api generator only discards truly unused parameters" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const parameters = try allocator.alloc(common.Parameter, 3);
    parameters[0] = .{
        .name = "per-page",
        .location = .query,
        .type = .integer,
    };
    parameters[1] = .{
        .name = "id",
        .location = .path,
        .type = .string,
    };
    parameters[2] = .{
        .name = "body",
        .location = .body,
        .schema = .{
            .type = .object,
        },
    };

    const responses = std.StringHashMap(common.Response).init(allocator);

    var paths = std.StringHashMap(common.PathItem).init(allocator);
    try paths.put(try allocator.dupe(u8, "/commented/{id}"), .{
        .delete = .{
            .operationId = "submit-commented",
            .parameters = parameters,
            .responses = responses,
        },
    });

    var unified = common.UnifiedDocument{
        .version = "3.0.3",
        .info = .{
            .title = "test",
            .version = "1.0.0",
        },
        .paths = paths,
    };
    defer unified.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, cli.CliArgs{
        .input_path = "openapi/v3.0/petstore.json",
    });
    defer generator.deinit();

    const generated = try generator.generate(unified);
    defer allocator.free(generated);

    try std.testing.expect(std.mem.indexOf(u8, generated, "_ = @\"query_per-page\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "_ = path_id;") == null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "_ = requestBody;") == null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "_ = allocator;") == null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "try std.json.stringify(requestBody, .{}, str.writer());") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "try req.sendBodyComplete(payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "try req.sendBodiless();") == null);
}

test "ghes generation escapes invalid identifiers" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    var parsed = try loadOpenApiDocument(allocator, "openapi/v3.0/ghes-3.20.json");
    defer parsed.deinit(allocator);

    var converter = OpenApiConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);

    var model_generator = UnifiedModelGenerator.init(allocator);
    defer model_generator.deinit();
    const models_code = try model_generator.generate(unified);
    defer allocator.free(models_code);

    var api_generator = UnifiedApiGenerator.init(allocator, cli.CliArgs{
        .input_path = "openapi/v3.0/ghes-3.20.json",
    });
    defer api_generator.deinit();
    const api_code = try api_generator.generate(unified);
    defer allocator.free(api_code);

    try std.testing.expect(std.mem.indexOf(u8, models_code, "pub const @\"webhook-repository-archived\" = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, models_code, "@\"pages-https-certificate\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, api_code, "pub fn @\"enterprise-admin/list-global-webhooks\"") != null);
}
