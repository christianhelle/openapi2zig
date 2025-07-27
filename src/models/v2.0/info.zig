const std = @import("std");
const json = std.json;

pub const Contact = struct {
    name: ?[]const u8 = null,
    url: ?[]const u8 = null,
    email: ?[]const u8 = null,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Contact {
        return Contact{
            .name = if (value.object.get("name")) |val| try allocator.dupe(u8, val.string) else null,
            .url = if (value.object.get("url")) |val| try allocator.dupe(u8, val.string) else null,
            .email = if (value.object.get("email")) |val| try allocator.dupe(u8, val.string) else null,
        };
    }

    pub fn deinit(self: *Contact, allocator: std.mem.Allocator) void {
        if (self.name) |name| allocator.free(name);
        if (self.url) |url| allocator.free(url);
        if (self.email) |email| allocator.free(email);
    }
};

pub const License = struct {
    name: []const u8,
    url: ?[]const u8 = null,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!License {
        return License{
            .name = try allocator.dupe(u8, value.object.get("name").?.string),
            .url = if (value.object.get("url")) |val| try allocator.dupe(u8, val.string) else null,
        };
    }

    pub fn deinit(self: *License, allocator: std.mem.Allocator) void {
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
        return Info{
            .title = try allocator.dupe(u8, value.object.get("title").?.string),
            .version = try allocator.dupe(u8, value.object.get("version").?.string),
            .description = if (value.object.get("description")) |val| try allocator.dupe(u8, val.string) else null,
            .termsOfService = if (value.object.get("termsOfService")) |val| try allocator.dupe(u8, val.string) else null,
            .contact = if (value.object.get("contact")) |val| try Contact.parseFromJson(allocator, val) else null,
            .license = if (value.object.get("license")) |val| try License.parseFromJson(allocator, val) else null,
        };
    }

    pub fn deinit(self: *Info, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.version);
        if (self.description) |description| allocator.free(description);
        if (self.termsOfService) |terms| allocator.free(terms);
        if (self.contact) |*contact| contact.deinit(allocator);
        if (self.license) |*license| license.deinit(allocator);
    }
};
