const std = @import("std");
const config_mod = @import("config.zig");
const template = @import("template.zig");
const output_writer = @import("../../generator/output_writer.zig");

pub const SdkConfig = config_mod.SdkConfig;

/// Everything the repository templates need to know about the SDK being built.
pub const SdkContext = struct {
    config: SdkConfig,
    generator_version: []const u8,
    /// Effective base URL: CLI flag, then config, then the spec's first server.
    base_url: []const u8,
    path_count: usize = 0,
    operation_count: usize = 0,
    schema_count: usize = 0,
    year: u16 = 2026,
    /// `build.zig.zon` package fingerprint.
    fingerprint: u64 = 0,
    /// Spec location relative to the repository, as written in the config.
    spec: []const u8 = "openapi/openapi.json",
    /// Example names (file stems in `examples/`), in build order.
    examples: []const []const u8 = &.{"quickstart"},
};

/// A non-Zig or hand-off file of the SDK repository.
pub const Kind = enum {
    root_zig,
    compile_check_zig,
    build_zig,
    build_zig_zon,
    gitignore,
    gitattributes,
    license,
    changelog,
    readme,
    usage,
    regenerating,
    ci,
    release,
    quickstart,

    pub fn path(self: Kind) []const u8 {
        return switch (self) {
            .root_zig => "src/root.zig",
            .compile_check_zig => "src/compile_check.zig",
            .build_zig => "build.zig",
            .build_zig_zon => "build.zig.zon",
            .gitignore => ".gitignore",
            .gitattributes => ".gitattributes",
            .license => "LICENSE",
            .changelog => "CHANGELOG.md",
            .readme => "README.md",
            .usage => "docs/USAGE.md",
            .regenerating => "docs/REGENERATING.md",
            .ci => ".github/workflows/ci.yml",
            .release => ".github/workflows/release.yml",
            .quickstart => "examples/quickstart.zig",
        };
    }

    pub fn ownership(self: Kind) output_writer.Ownership {
        return switch (self) {
            .root_zig, .compile_check_zig, .build_zig => .generated,
            .build_zig_zon, .gitignore, .license, .changelog => .scaffold,
            .gitattributes, .regenerating => .generated,
            .readme, .usage, .ci, .release, .quickstart => .scaffold,
        };
    }

    fn source(self: Kind) []const u8 {
        return switch (self) {
            .root_zig => @embedFile("templates/root.zig.tmpl"),
            .compile_check_zig => @embedFile("templates/compile_check.zig.tmpl"),
            .build_zig => @embedFile("templates/build.zig.tmpl"),
            .build_zig_zon => @embedFile("templates/build.zig.zon.tmpl"),
            .gitignore => @embedFile("templates/gitignore.tmpl"),
            .gitattributes => @embedFile("templates/gitattributes.tmpl"),
            .license => @embedFile("templates/LICENSE.tmpl"),
            .changelog => @embedFile("templates/CHANGELOG.md.tmpl"),
            .readme => @embedFile("templates/README.md.tmpl"),
            .usage => @embedFile("templates/USAGE.md.tmpl"),
            .regenerating => @embedFile("templates/REGENERATING.md.tmpl"),
            .ci => @embedFile("templates/ci.yml.tmpl"),
            .release => @embedFile("templates/release.yml.tmpl"),
            .quickstart => @embedFile("templates/quickstart.zig.tmpl"),
        };
    }
};

pub const all_kinds = std.enums.values(Kind);

/// Variables available to every template. Strings are allocated from `arena`.
pub fn buildVars(arena: std.mem.Allocator, ctx: SdkContext) ![]template.Var {
    const c = ctx.config;
    const description = if (c.description.len > 0) c.description else try std.fmt.allocPrint(arena, "{s} SDK for Zig", .{c.name});
    const repository = if (c.repository.len > 0) c.repository else try std.fmt.allocPrint(arena, "https://github.com/OWNER/{s}", .{c.name});
    const vars = [_]template.Var{
        .{ .name = "name", .value = c.name },
        .{ .name = "version", .value = c.version },
        .{ .name = "description", .value = description },
        .{ .name = "repository", .value = repository },
        .{ .name = "author", .value = c.author },
        .{ .name = "license", .value = c.license },
        .{ .name = "minimum_zig_version", .value = c.minimum_zig_version },
        .{ .name = "base_url", .value = ctx.base_url },
        .{ .name = "generator_version", .value = ctx.generator_version },
        .{ .name = "spec", .value = ctx.spec },
        .{ .name = "year", .value = try std.fmt.allocPrint(arena, "{d}", .{ctx.year}) },
        .{ .name = "examples_list", .value = try examplesList(arena, ctx.examples) },
        .{ .name = "fingerprint", .value = try std.fmt.allocPrint(arena, "0x{x:0>16}", .{ctx.fingerprint}) },
        .{ .name = "path_count", .value = try std.fmt.allocPrint(arena, "{d}", .{ctx.path_count}) },
        .{ .name = "operation_count", .value = try std.fmt.allocPrint(arena, "{d}", .{ctx.operation_count}) },
        .{ .name = "schema_count", .value = try std.fmt.allocPrint(arena, "{d}", .{ctx.schema_count}) },
    };
    return arena.dupe(template.Var, &vars);
}

pub fn render(allocator: std.mem.Allocator, kind: Kind, ctx: SdkContext) ![]u8 {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const vars = try buildVars(arena_state.allocator(), ctx);
    return template.expand(allocator, kind.source(), vars);
}

fn examplesList(arena: std.mem.Allocator, names: []const []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (names) |name| try out.print(arena, "    \"{s}\",\n", .{name});
    return out.items;
}

/// Computes a `build.zig.zon` fingerprint: the low 32 bits are a stable
/// package id derived from `seed`, the high 32 bits are the CRC-32 of `name`
/// that the Zig package manager validates.
pub fn fingerprintFor(name: []const u8, seed: []const u8) u64 {
    var id: u32 = @truncate(std.hash.Wyhash.hash(0, seed));
    if (id == 0 or id == 0xffffffff) id = 0x6f70656e;
    const checksum: u64 = std.hash.Crc32.hash(name);
    return (checksum << 32) | id;
}

/// Whether the template applies to this SDK. The bundled LICENSE text is MIT
/// only; other licenses are left for the user to add.
pub fn applies(kind: Kind, ctx: SdkContext) bool {
    return switch (kind) {
        .license => std.mem.eql(u8, ctx.config.license, "MIT"),
        else => true,
    };
}
