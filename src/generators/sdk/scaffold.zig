const std = @import("std");
const cli = @import("../../cli.zig");
const config_mod = @import("config.zig");
const templates = @import("templates.zig");
const multi_file = @import("../../generator/multi_file.zig");
const output_writer = @import("../../generator/output_writer.zig");
const generated_header = @import("../generated_header.zig");
const UnifiedDocument = @import("../../models/common/document.zig").UnifiedDocument;
const version_info = @import("build_info");

pub const default_config_name = "openapi2zig.json";
pub const default_spec_path = "openapi/openapi.json";

pub const SdkError = error{ MissingSdkName, InvalidConfig };

/// Resolves the SDK config for `args`: reads the config file when it exists,
/// otherwise writes a default one named after `--sdk-name`. The file lives at
/// `--sdk-config`, or `<output>/openapi2zig.json`.
pub const Prepared = struct {
    parsed: config_mod.Parsed,
    config_path: []const u8,
    args: cli.CliArgs,
    input_path_owned: ?[]const u8 = null,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Prepared) void {
        self.parsed.deinit();
        self.allocator.free(self.config_path);
        if (self.input_path_owned) |path| self.allocator.free(path);
    }
};

pub fn prepare(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, args: cli.CliArgs) !Prepared {
    const repo_dir = args.output_path orelse ".";
    const config_path = if (args.sdk_config_path) |p|
        try allocator.dupe(u8, p)
    else
        try std.fs.path.join(allocator, &.{ repo_dir, default_config_name });
    errdefer allocator.free(config_path);

    const existing = cwd.readFileAlloc(io, config_path, allocator, .unlimited) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    defer if (existing) |bytes| allocator.free(bytes);

    var parsed = if (existing) |bytes|
        try config_mod.parse(allocator, bytes)
    else blk: {
        const name = args.sdk_name orelse return error.MissingSdkName;
        const spec = if (args.input_path.len > 0) args.input_path else default_spec_path;
        const rendered = try config_mod.renderDefault(allocator, name, spec);
        defer allocator.free(rendered);
        _ = try output_writer.writeOwned(allocator, io, cwd, config_path, rendered, .scaffold, false);
        break :blk try config_mod.parse(allocator, rendered);
    };
    errdefer parsed.deinit();

    var effective = parsed.value.toCliArgs(args);
    effective.sdk_config_path = config_path;
    // A spec from the config is relative to the repository root.
    var input_path_owned: ?[]const u8 = null;
    errdefer if (input_path_owned) |path| allocator.free(path);
    if (args.input_path.len == 0) {
        if (parsed.value.spec) |spec| {
            if (isUrl(spec) or std.fs.path.isAbsolute(spec)) {
                effective.input_path = spec;
            } else {
                input_path_owned = try std.fs.path.join(allocator, &.{ repo_dir, spec });
                effective.input_path = input_path_owned.?;
            }
        }
    }
    return .{ .parsed = parsed, .config_path = config_path, .args = effective, .input_path_owned = input_path_owned, .allocator = allocator };
}

fn isUrl(path: []const u8) bool {
    return std.mem.startsWith(u8, path, "http://") or std.mem.startsWith(u8, path, "https://");
}

/// Writes the whole SDK repository for `doc` below `args.output_path`.
pub fn generateSdk(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, doc: UnifiedDocument, args: cli.CliArgs) !void {
    const repo_dir = args.output_path orelse ".";
    const config_path = args.sdk_config_path orelse return error.InvalidConfig;

    const config_bytes = try cwd.readFileAlloc(io, config_path, allocator, .unlimited);
    defer allocator.free(config_bytes);
    var parsed = try config_mod.parse(allocator, config_bytes);
    defer parsed.deinit();
    const config = parsed.value;

    const src_dir = try std.fs.path.join(allocator, &.{ repo_dir, "src" });
    defer allocator.free(src_dir);
    var source_args = args;
    source_args.output_path = src_dir;
    source_args.multiple_files = true;
    try multi_file.generateMultipleFiles(allocator, io, cwd, doc, source_args);

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const examples = try discoverExamples(arena, io, cwd, repo_dir);
    const base_url = args.base_url orelse config.base_url orelse firstServerUrl(doc) orelse "";
    const repository = if (config.repository.len > 0) config.repository else config.name;

    const ctx: templates.SdkContext = .{
        .config = config,
        .generator_version = version_info.VERSION,
        .base_url = base_url,
        .path_count = doc.paths.count(),
        .operation_count = countOperations(doc),
        .schema_count = if (doc.schemas) |schemas| schemas.count() else 0,
        .year = generated_header.currentYear(io),
        .fingerprint = templates.fingerprintFor(config.name, repository),
        .spec = config.spec orelse default_spec_path,
        .examples = examples,
    };

    for (templates.all_kinds) |kind| {
        if (!templates.applies(kind, ctx)) {
            std.log.warn("Skipping '{s}': no bundled template for license '{s}'", .{ kind.path(), config.license });
            continue;
        }
        const content = try templates.render(allocator, kind, ctx);
        defer allocator.free(content);
        const path = try std.fs.path.join(allocator, &.{ repo_dir, kind.path() });
        defer allocator.free(path);
        _ = try output_writer.writeOwned(allocator, io, cwd, path, content, kind.ownership(), args.force);
    }
}

fn firstServerUrl(doc: UnifiedDocument) ?[]const u8 {
    const servers = doc.servers orelse return null;
    if (servers.len == 0) return null;
    return servers[0].url;
}

fn countOperations(doc: UnifiedDocument) usize {
    var count: usize = 0;
    var it = doc.paths.iterator();
    while (it.next()) |entry| {
        const item = entry.value_ptr.*;
        inline for (.{ "get", "put", "post", "delete", "options", "head", "patch" }) |method| {
            if (@field(item, method) != null) count += 1;
        }
    }
    return count;
}

/// Example names (file stems of `examples/*.zig`), always including
/// `quickstart`, sorted so the generated build.zig is stable.
fn discoverExamples(arena: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, repo_dir: []const u8) ![]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    try names.append(arena, "quickstart");

    const examples_path = try std.fs.path.join(arena, &.{ repo_dir, "examples" });
    var dir = cwd.openDir(io, examples_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return names.items,
        else => return err,
    };
    defer dir.close(io);

    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".zig")) continue;
        const stem = entry.name[0 .. entry.name.len - ".zig".len];
        if (std.mem.eql(u8, stem, "quickstart")) continue;
        try names.append(arena, try arena.dupe(u8, stem));
    }
    std.mem.sort([]const u8, names.items, {}, lessThan);
    return names.items;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}
