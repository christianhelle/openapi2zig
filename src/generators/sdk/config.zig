const std = @import("std");
const cli = @import("../../cli.zig");

pub const ConfigError = error{InvalidConfig};

pub const Generator = struct {
    resource_wrappers: cli.ResourceWrapperMode = .paths,
    parameters_as_struct: bool = false,
    tags: []const []const u8 = &.{},
};

/// Contents of `openapi2zig.json`, the file that describes an SDK repository.
pub const SdkConfig = struct {
    name: []const u8,
    version: []const u8 = "0.1.0",
    description: []const u8 = "",
    repository: []const u8 = "",
    author: []const u8 = "",
    license: []const u8 = "MIT",
    minimum_zig_version: []const u8 = "0.17.1",
    /// Spec path or URL, relative to the SDK repository root.
    spec: ?[]const u8 = null,
    /// Overrides the server URL declared by the spec.
    base_url: ?[]const u8 = null,
    generator: Generator = .{},

    /// Merges the config into the CLI args. Values given on the command line
    /// (input path, base URL) win over the config. The returned args borrow
    /// from `self`.
    pub fn toCliArgs(self: SdkConfig, base: cli.CliArgs) cli.CliArgs {
        var args = base;
        args.sdk = true;
        args.multiple_files = true;
        if (args.input_path.len == 0) args.input_path = self.spec orelse "";
        if (args.base_url == null) args.base_url = self.base_url;
        args.resource_wrappers = self.generator.resource_wrappers;
        args.parameters_as_struct = base.parameters_as_struct or self.generator.parameters_as_struct;
        if (args.tags.len == 0) args.tags = self.generator.tags;
        return args;
    }
};

pub const Parsed = std.json.Parsed(SdkConfig);

pub fn parse(allocator: std.mem.Allocator, json: []const u8) (ConfigError || std.mem.Allocator.Error)!Parsed {
    var parsed = std.json.parseFromSlice(SdkConfig, allocator, json, .{
        .ignore_unknown_fields = false,
        .allocate = .alloc_always,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidConfig,
    };
    errdefer parsed.deinit();
    if (!cli.isValidSdkName(parsed.value.name)) return error.InvalidConfig;
    return parsed;
}

/// Renders the config file written when an SDK is generated for the first time.
pub fn renderDefault(allocator: std.mem.Allocator, name: []const u8, spec: []const u8) ![]u8 {
    const config: SdkConfig = .{ .name = name, .spec = spec };
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try std.json.Stringify.value(config, .{ .whitespace = .indent_2 }, &out.writer);
    try out.writer.writeByte('\n');
    return out.toOwnedSlice();
}
