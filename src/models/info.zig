pub const Info = struct {
    title: []const u8,
    version: []const u8,
    description: ?[]const u8 = null,
    termsOfService: ?[]const u8 = null,
    contact: ?Contact = null,
    license: ?License = null,
};

pub const Contact = struct {
    name: ?[]const u8 = null,
    url: ?[]const u8 = null,
    email: ?[]const u8 = null,
};

pub const License = struct {
    name: []const u8,
    url: ?[]const u8 = null,
};
