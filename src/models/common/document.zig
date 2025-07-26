const std = @import("std");
const json = std.json;

pub const DocumentInfo = struct {
    title: []const u8,
    description: ?[]const u8 = null,
    version: []const u8,
    termsOfService: ?[]const u8 = null,
    contact: ?ContactInfo = null,
    license: ?LicenseInfo = null,

    pub fn deinit(self: *DocumentInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        if (self.description) |desc| allocator.free(desc);
        allocator.free(self.version);
        if (self.termsOfService) |tos| allocator.free(tos);
        if (self.contact) |*contact| contact.deinit(allocator);
        if (self.license) |*license| license.deinit(allocator);
    }
};

pub const ContactInfo = struct {
    name: ?[]const u8 = null,
    url: ?[]const u8 = null,
    email: ?[]const u8 = null,

    pub fn deinit(self: *ContactInfo, allocator: std.mem.Allocator) void {
        if (self.name) |name| allocator.free(name);
        if (self.url) |url| allocator.free(url);
        if (self.email) |email| allocator.free(email);
    }
};

pub const LicenseInfo = struct {
    name: []const u8,
    url: ?[]const u8 = null,

    pub fn deinit(self: *LicenseInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.url) |url| allocator.free(url);
    }
};

pub const ExternalDocumentation = struct {
    url: []const u8,
    description: ?[]const u8 = null,

    pub fn deinit(self: ExternalDocumentation, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        if (self.description) |desc| allocator.free(desc);
    }
};

pub const Tag = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    externalDocs: ?ExternalDocumentation = null,

    pub fn deinit(self: Tag, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.description) |desc| allocator.free(desc);
        if (self.externalDocs) |extDocs| extDocs.deinit(allocator);
    }
};

pub const Server = struct {
    url: []const u8,
    description: ?[]const u8 = null,

    pub fn deinit(self: *Server, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        if (self.description) |desc| allocator.free(desc);
    }
};

pub const SecurityRequirement = struct {
    schemes: std.StringHashMap([][]const u8),

    pub fn deinit(self: *SecurityRequirement, allocator: std.mem.Allocator) void {
        var iterator = self.schemes.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.*) |scope| {
                allocator.free(scope);
            }
            allocator.free(entry.value_ptr.*);
        }
        self.schemes.deinit();
    }
};

pub const SchemaType = enum {
    string,
    number,
    integer,
    boolean,
    array,
    object,
    reference,
};

pub const Schema = struct {
    type: ?SchemaType = null,
    ref: ?[]const u8 = null,
    title: ?[]const u8 = null,
    description: ?[]const u8 = null,
    format: ?[]const u8 = null,
    required: ?[][]const u8 = null,
    properties: ?std.StringHashMap(Schema) = null,
    items: ?*Schema = null,
    enum_values: ?[]json.Value = null,
    default: ?json.Value = null,
    example: ?json.Value = null,

    pub fn deinit(self: *Schema, allocator: std.mem.Allocator) void {
        if (self.ref) |ref| allocator.free(ref);
        if (self.title) |title| allocator.free(title);
        if (self.description) |desc| allocator.free(desc);
        if (self.format) |fmt| allocator.free(fmt);

        if (self.required) |required| {
            for (required) |req| allocator.free(req);
            allocator.free(required);
        }

        if (self.properties) |*props| {
            var iterator = props.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(allocator);
            }
            props.deinit();
        }

        if (self.items) |items| {
            items.deinit(allocator);
            allocator.destroy(items);
        }

        if (self.enum_values) |enum_vals| {
            allocator.free(enum_vals);
        }
    }
};

pub const ParameterLocation = enum {
    query,
    header,
    path,
    body,
    form,
};

pub const Parameter = struct {
    name: []const u8,
    location: ParameterLocation,
    description: ?[]const u8 = null,
    required: bool = false,
    schema: ?Schema = null,
    type: ?SchemaType = null,
    format: ?[]const u8 = null,

    pub fn deinit(self: *Parameter, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.description) |desc| allocator.free(desc);
        if (self.schema) |*schema| schema.deinit(allocator);
        if (self.format) |fmt| allocator.free(fmt);
    }
};

pub const Response = struct {
    description: []const u8,
    schema: ?Schema = null,
    headers: ?std.StringHashMap(Parameter) = null,

    pub fn deinit(self: *Response, allocator: std.mem.Allocator) void {
        allocator.free(self.description);
        if (self.schema) |*schema| schema.deinit(allocator);

        if (self.headers) |*headers| {
            var iterator = headers.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(allocator);
            }
            headers.deinit();
        }
    }
};

pub const Operation = struct {
    tags: ?[][]const u8 = null,
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    operationId: ?[]const u8 = null,
    parameters: ?[]Parameter = null,
    responses: std.StringHashMap(Response),
    deprecated: bool = false,
    security: ?[]SecurityRequirement = null,

    pub fn deinit(self: *Operation, allocator: std.mem.Allocator) void {
        if (self.tags) |tags| {
            for (tags) |tag| allocator.free(tag);
            allocator.free(tags);
        }
        if (self.summary) |summary| allocator.free(summary);
        if (self.description) |desc| allocator.free(desc);
        if (self.operationId) |opId| allocator.free(opId);

        if (self.parameters) |params| {
            for (params) |*param| param.deinit(allocator);
            allocator.free(params);
        }

        var resp_iterator = self.responses.iterator();
        while (resp_iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        self.responses.deinit();

        if (self.security) |security| {
            for (security) |*sec| sec.deinit(allocator);
            allocator.free(security);
        }
    }
};

pub const PathItem = struct {
    get: ?Operation = null,
    put: ?Operation = null,
    post: ?Operation = null,
    delete: ?Operation = null,
    options: ?Operation = null,
    head: ?Operation = null,
    patch: ?Operation = null,
    parameters: ?[]Parameter = null,

    pub fn deinit(self: *PathItem, allocator: std.mem.Allocator) void {
        if (self.get) |*op| op.deinit(allocator);
        if (self.put) |*op| op.deinit(allocator);
        if (self.post) |*op| op.deinit(allocator);
        if (self.delete) |*op| op.deinit(allocator);
        if (self.options) |*op| op.deinit(allocator);
        if (self.head) |*op| op.deinit(allocator);
        if (self.patch) |*op| op.deinit(allocator);

        if (self.parameters) |params| {
            for (params) |*param| param.deinit(allocator);
            allocator.free(params);
        }
    }
};

/// Unified document abstraction that works with both OpenAPI 3.0 and Swagger 2.0
pub const UnifiedDocument = struct {
    /// Document version information
    version: []const u8, // "2.0", "3.0.2", etc.
    info: DocumentInfo,
    paths: std.StringHashMap(PathItem),

    /// Optional fields
    servers: ?[]Server = null,
    security: ?[]SecurityRequirement = null,
    tags: ?[]Tag = null,
    externalDocs: ?ExternalDocumentation = null,

    /// Schema definitions (definitions in v2.0, components.schemas in v3.0)
    schemas: ?std.StringHashMap(Schema) = null,

    /// Global parameters (v2.0 only, but can be present in unified model)
    parameters: ?std.StringHashMap(Parameter) = null,

    /// Global responses (v2.0 only, but can be present in unified model)
    responses: ?std.StringHashMap(Response) = null,

    pub fn deinit(self: *UnifiedDocument, allocator: std.mem.Allocator) void {
        allocator.free(self.version);
        self.info.deinit(allocator);

        var path_iterator = self.paths.iterator();
        while (path_iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        self.paths.deinit();

        if (self.servers) |servers| {
            for (servers) |*server| server.deinit(allocator);
            allocator.free(servers);
        }

        if (self.security) |security| {
            for (security) |*sec| sec.deinit(allocator);
            allocator.free(security);
        }

        if (self.tags) |tags| {
            for (tags) |tag| tag.deinit(allocator);
            allocator.free(tags);
        }

        if (self.externalDocs) |extDocs| {
            extDocs.deinit(allocator);
        }

        if (self.schemas) |*schemas| {
            var schema_iterator = schemas.iterator();
            while (schema_iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(allocator);
            }
            schemas.deinit();
        }

        if (self.parameters) |*params| {
            var param_iterator = params.iterator();
            while (param_iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(allocator);
            }
            params.deinit();
        }

        if (self.responses) |*responses| {
            var resp_iterator = responses.iterator();
            while (resp_iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(allocator);
            }
            responses.deinit();
        }
    }
};
