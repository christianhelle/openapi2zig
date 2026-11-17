const std = @import("std");
const cli = @import("../../cli.zig");
const model_names = @import("../unified/model_names.zig");

pub const ConfigError = error{InvalidConfig};

/// OAuth 2.0 endpoints. URLs may contain `{name}` placeholders, for example a
/// tenant, that callers fill in at run time.
pub const OAuth2 = struct {
    token_url: []const u8,
    device_authorization_url: ?[]const u8 = null,
    scopes: []const []const u8 = &.{},
};

pub const Auth = struct {
    oauth2: ?OAuth2 = null,
};

/// Retry behavior of the generated `init`.
pub const Retry = struct {
    max_retries: u8 = 0,
};

pub const Generator = struct {
    resource_wrappers: cli.ResourceWrapperMode = .paths,
    parameters_as_struct: bool = false,
    tags: []const []const u8 = &.{},
    model_naming: model_names.Mode = .raw,
    pagination: bool = false,
    typed_errors: bool = false,
    split_by_tag: bool = false,
    string_enums: bool = false,
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
    retry: Retry = .{},
    auth: Auth = .{},

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
        args.parameters_as_struct = self.generator.parameters_as_struct;
        args.model_naming = self.generator.model_naming;
        args.pagination = self.generator.pagination;
        args.typed_errors = self.generator.typed_errors;
        args.split_by_tag = self.generator.split_by_tag;
        args.string_enums = self.generator.string_enums;
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
