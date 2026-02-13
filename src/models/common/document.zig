const std = @import("std");
const json = std.json;

pub const DocumentInfo = struct {
    title: []const u8,
    description: ?[]const u8 = null,
    version: []const u8,
    termsOfService: ?[]const u8 = null,
    contact: ?ContactInfo = null,
    license: ?LicenseInfo = null,
};

pub const ContactInfo = struct {
    name: ?[]const u8 = null,
    url: ?[]const u8 = null,
    email: ?[]const u8 = null,
};

pub const LicenseInfo = struct {
    name: []const u8,
    url: ?[]const u8 = null,
};

pub const ExternalDocumentation = struct {
    url: []const u8,
    description: ?[]const u8 = null,
};

pub const Tag = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    externalDocs: ?ExternalDocumentation = null,
};

pub const Server = struct {
    url: []const u8,
    description: ?[]const u8 = null,
    _url_allocated: bool = false,
    _description_allocated: bool = false,
    pub fn deinit(self: *Server, allocator: std.mem.Allocator) void {
        if (self._url_allocated) {
            allocator.free(self.url);
        }
        if (self._description_allocated) {
            if (self.description) |desc| {
                allocator.free(desc);
            }
        }
    }
};

pub const SecurityRequirement = struct {
    schemes: std.StringHashMap([][]const u8),
    pub fn deinit(self: *SecurityRequirement, allocator: std.mem.Allocator) void {
        var iterator = self.schemes.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*); // Free the duped key
            allocator.free(entry.value_ptr.*); // Free the allocated scopes array
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
        if (self.required) |required| {
            allocator.free(required);
        }
        if (self.properties) |*props| {
            var iterator = props.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*); // Free the duped property name
                entry.value_ptr.deinit(allocator);
            }
            props.deinit();
        }
        if (self.items) |items| {
            items.deinit(allocator);
            allocator.destroy(items);
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
        if (self.schema) |*schema| schema.deinit(allocator);
    }
};

pub const Response = struct {
    description: []const u8,
    schema: ?Schema = null,
    headers: ?std.StringHashMap(Parameter) = null,
    pub fn deinit(self: *Response, allocator: std.mem.Allocator) void {
        if (self.schema) |*schema| schema.deinit(allocator);
        if (self.headers) |*headers| {
            var iterator = headers.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*); // Free the duped header name
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
            allocator.free(tags);
        }
        if (self.parameters) |params| {
            for (params) |*param| param.deinit(allocator);
            allocator.free(params);
        }
        var resp_iterator = self.responses.iterator();
        while (resp_iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*); // Free the duped response key
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

pub const UnifiedDocument = struct {
    version: []const u8, // "2.0", "3.0.2", etc.
    info: DocumentInfo,
    paths: std.StringHashMap(PathItem),
    servers: ?[]Server = null,
    security: ?[]SecurityRequirement = null,
    tags: ?[]Tag = null,
    externalDocs: ?ExternalDocumentation = null,
    schemas: ?std.StringHashMap(Schema) = null,
    parameters: ?std.StringHashMap(Parameter) = null,
    responses: ?std.StringHashMap(Response) = null,
    pub fn deinit(self: *UnifiedDocument, allocator: std.mem.Allocator) void {
        _ = self.info; // Suppress unused field warning
        var path_iterator = self.paths.iterator();
        while (path_iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*); // Free the duped path key
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
            allocator.free(tags);
        }
        if (self.schemas) |*schemas| {
            var schema_iterator = schemas.iterator();
            while (schema_iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*); // Free the duped schema name
                entry.value_ptr.deinit(allocator);
            }
            schemas.deinit();
        }
        if (self.parameters) |*params| {
            var param_iterator = params.iterator();
            while (param_iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*); // Free the duped parameter name
                entry.value_ptr.deinit(allocator);
            }
            params.deinit();
        }
        if (self.responses) |*responses| {
            var resp_iterator = responses.iterator();
            while (resp_iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*); // Free the duped response name
                entry.value_ptr.deinit(allocator);
            }
            responses.deinit();
        }
    }
};
