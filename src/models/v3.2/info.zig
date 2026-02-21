const std = @import("std");
const json = std.json;

pub const Contact = struct {
    name: ?[]const u8 = null,
    url: ?[]const u8 = null,
    email: ?[]const u8 = null,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Contact {
        const obj = value.object;
        return Contact{
            .name = if (obj.get("name")) |val| try allocator.dupe(u8, val.string) else null,
            .url = if (obj.get("url")) |val| try allocator.dupe(u8, val.string) else null,
            .email = if (obj.get("email")) |val| try allocator.dupe(u8, val.string) else null,
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
    identifier: ?[]const u8 = null,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!License {
        const obj = value.object;
        return License{
            .name = try allocator.dupe(u8, obj.get("name").?.string),
            .url = if (obj.get("url")) |val| try allocator.dupe(u8, val.string) else null,
            .identifier = if (obj.get("identifier")) |val| try allocator.dupe(u8, val.string) else null,
        };
    }

    pub fn deinit(self: License, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.url) |url| allocator.free(url);
        if (self.identifier) |identifier| allocator.free(identifier);
    }
};

pub const Info = struct {
    title: []const u8,
    version: []const u8,
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    termsOfService: ?[]const u8 = null,
    contact: ?Contact = null,
    license: ?License = null,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Info {
        const obj = value.object;
        return Info{
            .title = try allocator.dupe(u8, obj.get("title").?.string),
            .version = try allocator.dupe(u8, obj.get("version").?.string),
            .summary = if (obj.get("summary")) |val| try allocator.dupe(u8, val.string) else null,
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
            .termsOfService = if (obj.get("termsOfService")) |val| try allocator.dupe(u8, val.string) else null,
            .contact = if (obj.get("contact")) |val| try Contact.parseFromJson(allocator, val) else null,
            .license = if (obj.get("license")) |val| try License.parseFromJson(allocator, val) else null,
        };
    }

    pub fn deinit(self: Info, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.version);
        if (self.summary) |summary| allocator.free(summary);
        if (self.description) |desc| allocator.free(desc);
        if (self.termsOfService) |terms| allocator.free(terms);
        if (self.contact) |contact| contact.deinit(allocator);
        if (self.license) |license| license.deinit(allocator);
    }
};
