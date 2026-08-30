const std = @import("std");

pub const ResourceWrapperMode = enum {
    none,
    tags,
    paths,
    hybrid,
};

pub const MultipleClientsMode = enum {
    per_tag,
    per_endpoint,

    pub fn displayName(self: MultipleClientsMode) []const u8 {
        return switch (self) {
            .per_tag => "PerTag",
            .per_endpoint => "PerEndpoint",
        };
    }
};

pub const FileKind = enum {
    models,
    runtime,
    client,

    pub fn fromString(value: []const u8) ?FileKind {
        if (std.mem.eql(u8, value, "models")) return .models;
        if (std.mem.eql(u8, value, "runtime")) return .runtime;
        if (std.mem.eql(u8, value, "client")) return .client;
        return null;
    }

    pub fn defaultName(self: FileKind) []const u8 {
        return switch (self) {
            .models => "models.zig",
            .runtime => "runtime.zig",
            .client => "client.zig",
        };
    }
};

pub const FileNameOverrides = struct {
    models: ?[]const u8 = null,
    runtime: ?[]const u8 = null,
    client: ?[]const u8 = null,

    pub fn get(self: FileNameOverrides, kind: FileKind) ?[]const u8 {
        return switch (kind) {
            .models => self.models,
            .runtime => self.runtime,
            .client => self.client,
        };
    }

    pub fn set(self: *FileNameOverrides, kind: FileKind, name: []const u8) error{DuplicateFileOverride}!void {
        switch (kind) {
            .models => {
                if (self.models != null) return error.DuplicateFileOverride;
                self.models = name;
            },
            .runtime => {
                if (self.runtime != null) return error.DuplicateFileOverride;
                self.runtime = name;
            },
            .client => {
                if (self.client != null) return error.DuplicateFileOverride;
                self.client = name;
            },
        }
    }

    pub fn any(self: FileNameOverrides) bool {
        return self.models != null or self.runtime != null or self.client != null;
    }
};

pub const CliArgs = struct {
    input_path: []const u8,
    output_path: ?[]const u8 = null,
    base_url: ?[]const u8 = null,
    resource_wrappers: ResourceWrapperMode = .paths,
    models_only: bool = false,
    multiple_files: bool = false,
    multiple_clients: ?MultipleClientsMode = null,
    file_names: FileNameOverrides = .{},
    /// Optional import path to an existing runtime.zig. When set, no
    /// runtime.zig is generated and the client imports this path instead.
    /// The path is relative to the generated client file.
    runtime_module: ?[]const u8 = null,
    /// OpenAPI tags to include. When empty, no tag filtering is applied.
    /// The slice is freed by `deinit(allocator)` when `owns_tags` is true.
    tags: []const []const u8 = &.{},
    /// Whether `tags` was allocated by the parser and must be freed.
    owns_tags: bool = false,
    force: bool = false,
    /// Generate only the runtime module. The input spec is not required and,
    /// when given, is ignored entirely.
    runtime_only: bool = false,
    /// Wrap non-body method parameters in a single `options` struct instead of
    /// emitting them as individual function arguments.
    parameters_as_struct: bool = false,

    pub fn deinit(self: *CliArgs, allocator: std.mem.Allocator) void {
        if (self.owns_tags) allocator.free(self.tags);
        self.tags = &.{};
        self.owns_tags = false;
    }
};

pub const ParsedArgs = struct {
    args: CliArgs,
    upgrade: bool = false,
    help: bool = false,

    pub fn deinit(self: *ParsedArgs, allocator: std.mem.Allocator) void {
        self.args.deinit(allocator);
    }
};
