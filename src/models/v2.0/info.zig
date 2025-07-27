const std = @import("std");
const json = std.json;
pub const Contact = struct {
    name: ?[]const u8 = null,
    url: ?[]const u8 = null,
    email: ?[]const u8 = null,
    pub fn deinit(self: *Contact, allocator: std.mem.Allocator) void {
        if (self.name) |name| {
            allocator.free(name);
        }
        if (self.url) |url| {
            allocator.free(url);
        }
        if (self.email) |email| {
            allocator.free(email);
        }
    }
    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Contact {
        const name = if (value.object.get("name")) |val| try allocator.dupe(u8, val.string) else null;
        const url = if (value.object.get("url")) |val| try allocator.dupe(u8, val.string) else null;
        const email = if (value.object.get("email")) |val| try allocator.dupe(u8, val.string) else null;
        return Contact{
            .name = name,
            .url = url,
            .email = email,
        };
    }
};
pub const License = struct {
    name: []const u8,
    url: ?[]const u8 = null,
    pub fn deinit(self: *License, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.url) |url| {
            allocator.free(url);
        }
    }
    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!License {
        const name = try allocator.dupe(u8, value.object.get("name").?.string);
        const url = if (value.object.get("url")) |val| try allocator.dupe(u8, val.string) else null;
        return License{
            .name = name,
            .url = url,
        };
    }
};
pub const Info = struct {
    title: []const u8,
    version: []const u8,
    description: ?[]const u8 = null,
    termsOfService: ?[]const u8 = null,
    contact: ?Contact = null,
    license: ?License = null,
    pub fn deinit(self: *Info, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.version);
        if (self.description) |description| {
            allocator.free(description);
        }
        if (self.termsOfService) |terms| {
            allocator.free(terms);
        }
        if (self.contact) |*contact| {
            contact.deinit(allocator);
        }
        if (self.license) |*license| {
            license.deinit(allocator);
        }
    }
    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Info {
        const title = try allocator.dupe(u8, value.object.get("title").?.string);
        const version = try allocator.dupe(u8, value.object.get("version").?.string);
        const description = if (value.object.get("description")) |val| try allocator.dupe(u8, val.string) else null;
        const termsOfService = if (value.object.get("termsOfService")) |val| try allocator.dupe(u8, val.string) else null;
        const contact = if (value.object.get("contact")) |val| try Contact.parseFromJson(allocator, val) else null;
        const license = if (value.object.get("license")) |val| try License.parseFromJson(allocator, val) else null;
        return Info{
            .title = title,
            .version = version,
            .description = description,
            .termsOfService = termsOfService,
            .contact = contact,
            .license = license,
        };
    }
};
