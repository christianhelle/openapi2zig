const std = @import("std");
const json = std.json;

pub const Contact = struct {
    name: ?[]const u8 = null,
    url: ?[]const u8 = null,
    email: ?[]const u8 = null,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Contact {
        const obj = switch (value) {
            .object => |o| o,
            else => return error.ExpectedObject,
        };
        
        return Contact{
            .name = if (obj.get("name")) |val| switch (val) {
                .string => |str| try allocator.dupe(u8, str),
                else => null,
            } else null,
            .url = if (obj.get("url")) |val| switch (val) {
                .string => |str| try allocator.dupe(u8, str),
                else => null,
            } else null,
            .email = if (obj.get("email")) |val| switch (val) {
                .string => |str| try allocator.dupe(u8, str),
                else => null,
            } else null,
        };
    }

    pub fn deinit(self: Contact, allocator: std.mem.Allocator) void {
        if (self.name) |name| allocator.free(name);
        if (self.url) |url| allocator.free(url);
        if (self.email) |email| allocator.free(email);
    }
};

pub const License = struct {
    name: []const u8,
    url: ?[]const u8 = null,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!License {
        const obj = switch (value) {
            .object => |o| o,
            else => return error.ExpectedObject,
        };
        
        const name_str = switch (obj.get("name") orelse return error.MissingName) {
            .string => |str| str,
            else => return error.ExpectedString,
        };
        
        return License{
            .name = try allocator.dupe(u8, name_str),
            .url = if (obj.get("url")) |val| switch (val) {
                .string => |str| try allocator.dupe(u8, str),
                else => null,
            } else null,
        };
    }

    pub fn deinit(self: License, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.url) |url| allocator.free(url);
    }
};

pub const Info = struct {
    title: []const u8,
    version: []const u8,
    description: ?[]const u8 = null,
    termsOfService: ?[]const u8 = null,
    contact: ?Contact = null,
    license: ?License = null,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Info {
        const obj = switch (value) {
            .object => |o| o,
            else => return error.ExpectedObject,
        };
        
        const title_str = switch (obj.get("title") orelse return error.MissingTitle) {
            .string => |str| str,
            else => return error.ExpectedString,
        };
        
        const version_str = switch (obj.get("version") orelse return error.MissingVersion) {
            .string => |str| str,
            else => return error.ExpectedString,
        };
        
        return Info{
            .title = try allocator.dupe(u8, title_str),
            .version = try allocator.dupe(u8, version_str),
            .description = if (obj.get("description")) |val| switch (val) {
                .string => |str| try allocator.dupe(u8, str),
                else => null,
            } else null,
            .termsOfService = if (obj.get("termsOfService")) |val| switch (val) {
                .string => |str| try allocator.dupe(u8, str),
                else => null,
            } else null,
            .contact = if (obj.get("contact")) |val| try Contact.parseFromJson(allocator, val) else null,
            .license = if (obj.get("license")) |val| try License.parseFromJson(allocator, val) else null,
        };
    }

    pub fn deinit(self: Info, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.version);
        if (self.description) |desc| allocator.free(desc);
        if (self.termsOfService) |terms| allocator.free(terms);
        if (self.contact) |contact| contact.deinit(allocator);
        if (self.license) |license| license.deinit(allocator);
    }
};
