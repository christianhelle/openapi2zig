const std = @import("std");
const json = std.json;

pub const OpenApiDocument = struct {
    openapi: []const u8,
    info: Info,
    paths: Paths,
    components: ?Components = null,

    pub fn parse(allocator: std.mem.Allocator, json_string: []const u8) anyerror!OpenApiDocument {
        var parsed = try json.parseFromSlice(json.Value, allocator, json_string, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        const root = parsed.value;

        // Copy the openapi string to ensure it's not tied to the parsed JSON
        const openapi_str = try allocator.dupe(u8, root.object.get("openapi").?.string);

        const info = try Info.parse(allocator, root.object.get("info").?);
        const paths = try Paths.parse(allocator, root.object.get("paths").?);
        const components = if (root.object.get("components")) |val| try Components.parse(allocator, val) else null;

        return OpenApiDocument{
            .openapi = openapi_str,
            .info = info,
            .paths = paths,
            .components = components,
        };
    }

    pub fn deinit(self: *OpenApiDocument, allocator: std.mem.Allocator) void {
        if (self.info.description) |desc| {
            allocator.free(desc);
        }
        if (self.info.title) |title| {
            allocator.free(title);
        }
        if (self.info.version) |version| {
            allocator.free(version);
        }

        self.paths.deinit(allocator);

        if (self.components) |*comp| {
            comp.deinit(allocator);
        }
    }
};

pub const Info = struct {
    title: []const u8,
    version: []const u8,
    description: ?[]const u8 = null,
    termsOfService: ?[]const u8 = null,
    contact: ?Contact = null,
    license: ?License = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!Info {
        std.debug.print("parsing info\n", .{}); // Debugging line
        const obj = value.object;
        return Info{
            .title = try allocator.dupe(u8, obj.get("title").?.string),
            .version = try allocator.dupe(u8, obj.get("version").?.string),
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
            .termsOfService = if (obj.get("termsOfService")) |val| try allocator.dupe(u8, val.string) else null,
            .contact = if (obj.get("contact")) |val| try Contact.parse(allocator, val) else null,
            .license = if (obj.get("license")) |val| try License.parse(allocator, val) else null,
        };
    }

    pub fn deinit(self: *Info, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.version);
        if (self.description) |desc| {
            allocator.free(desc);
        }
    }
};

pub const Contact = struct {
    name: ?[]const u8 = null,
    url: ?[]const u8 = null,
    email: ?[]const u8 = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!Contact {
        const obj = value.object;
        return Contact{
            .name = if (obj.get("name")) |val| try allocator.dupe(u8, val.string) else null,
            .url = if (obj.get("url")) |val| try allocator.dupe(u8, val.string) else null,
            .email = if (obj.get("email")) |val| try allocator.dupe(u8, val.string) else null,
        };
    }
};

pub const License = struct {
    name: []const u8,
    url: ?[]const u8 = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!License {
        const obj = value.object;
        return License{
            .name = try allocator.dupe(u8, obj.get("name").?.string),
            .url = if (obj.get("url")) |val| try allocator.dupe(u8, val.string) else null,
        };
    }
};

pub const Server = struct {
    url: []const u8,
    description: ?[]const u8 = null,
    variables: ?std.StringHashMap(ServerVariable) = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!Server {
        const obj = value.object;
        var variables_map = std.StringHashMap(ServerVariable).init(allocator);
        if (obj.get("variables")) |vars_val| {
            for (vars_val.object.keys()) |key| {
                try variables_map.put(key, try ServerVariable.parse(allocator, vars_val.object.get(key).?));
            }
        }
        return Server{
            .url = obj.get("url").?.string,
            .description = if (obj.get("description")) |val| val.string else null,
            .variables = if (variables_map.count() > 0) variables_map else null,
        };
    }
};

pub const ServerVariable = struct {
    default: []const u8,
    enum_values: ?[]const []const u8 = null,
    description: ?[]const u8 = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!ServerVariable {
        const obj = value.object;
        var enum_list = std.ArrayList([]const u8).init(allocator);
        if (obj.get("enum")) |enum_val| {
            for (enum_val.array.items) |item| {
                try enum_list.append(item.string);
            }
        }

        return ServerVariable{
            .default = obj.get("default").?.string,
            .enum_values = if (enum_list.items.len > 0) enum_list.items else null,
            .description = if (obj.get("description")) |val| val.string else null,
        };
    }
};

pub const Components = struct {
    schemas: ?std.StringHashMap(SchemaOrReference) = null,
    responses: ?std.StringHashMap(ResponseOrReference) = null,
    parameters: ?std.StringHashMap(ParameterOrReference) = null,
    examples: ?std.StringHashMap(ExampleOrReference) = null,
    requestBodies: ?std.StringHashMap(RequestBodyOrReference) = null,
    headers: ?std.StringHashMap(HeaderOrReference) = null,
    securitySchemes: ?std.StringHashMap(SecuritySchemeOrReference) = null,
    links: ?std.StringHashMap(LinkOrReference) = null,
    callbacks: ?std.StringHashMap(CallbackOrReference) = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!Components {
        std.debug.print("parsing components\n", .{}); // Debugging line
        const obj = value.object;
        var schemas_map = std.StringHashMap(SchemaOrReference).init(allocator);
        if (obj.get("schemas")) |schemas_val| {
            for (schemas_val.object.keys()) |key| {
                try schemas_map.put(key, try SchemaOrReference.parse(allocator, schemas_val.object.get(key).?));
            }
        }
        var responses_map = std.StringHashMap(ResponseOrReference).init(allocator);
        if (obj.get("responses")) |responses_val| {
            for (responses_val.object.keys()) |key| {
                try responses_map.put(key, try ResponseOrReference.parse(allocator, responses_val.object.get(key).?));
            }
        }
        var parameters_map = std.StringHashMap(ParameterOrReference).init(allocator);
        if (obj.get("parameters")) |parameters_val| {
            for (parameters_val.object.keys()) |key| {
                try parameters_map.put(key, try ParameterOrReference.parse(allocator, parameters_val.object.get(key).?));
            }
        }
        var examples_map = std.StringHashMap(ExampleOrReference).init(allocator);
        if (obj.get("examples")) |examples_val| {
            for (examples_val.object.keys()) |key| {
                try examples_map.put(key, try ExampleOrReference.parse(allocator, examples_val.object.get(key).?));
            }
        }
        var request_bodies_map = std.StringHashMap(RequestBodyOrReference).init(allocator);
        if (obj.get("requestBodies")) |request_bodies_val| {
            for (request_bodies_val.object.keys()) |key| {
                try request_bodies_map.put(key, try RequestBodyOrReference.parse(allocator, request_bodies_val.object.get(key).?));
            }
        }
        var headers_map = std.StringHashMap(HeaderOrReference).init(allocator);
        if (obj.get("headers")) |headers_val| {
            for (headers_val.object.keys()) |key| {
                try headers_map.put(key, try HeaderOrReference.parse(allocator, headers_val.object.get(key).?));
            }
        }
        var security_schemes_map = std.StringHashMap(SecuritySchemeOrReference).init(allocator);
        if (obj.get("securitySchemes")) |security_schemes_val| {
            for (security_schemes_val.object.keys()) |key| {
                try security_schemes_map.put(key, try SecuritySchemeOrReference.parse(allocator, security_schemes_val.object.get(key).?));
            }
        }
        var links_map = std.StringHashMap(LinkOrReference).init(allocator);
        if (obj.get("links")) |links_val| {
            for (links_val.object.keys()) |key| {
                try links_map.put(key, try LinkOrReference.parse(allocator, links_val.object.get(key).?));
            }
        }
        var callbacks_map = std.StringHashMap(CallbackOrReference).init(allocator);
        if (obj.get("callbacks")) |callbacks_val| {
            for (callbacks_val.object.keys()) |key| {
                try callbacks_map.put(key, try CallbackOrReference.parse(allocator, callbacks_val.object.get(key).?));
            }
        }

        std.debug.print("parsed components successfully\n", .{}); // Debugging line
        return Components{
            .schemas = if (schemas_map.count() > 0) schemas_map else null,
            .responses = if (responses_map.count() > 0) responses_map else null,
            .parameters = if (parameters_map.count() > 0) parameters_map else null,
            .examples = if (examples_map.count() > 0) examples_map else null,
            .requestBodies = if (request_bodies_map.count() > 0) request_bodies_map else null,
            .headers = if (headers_map.count() > 0) headers_map else null,
            .securitySchemes = if (security_schemes_map.count() > 0) security_schemes_map else null,
            .links = if (links_map.count() > 0) links_map else null,
            .callbacks = if (callbacks_map.count() > 0) callbacks_map else null,
        };
    }

    pub fn deinit(self: *Components, allocator: std.mem.Allocator) void {
        if (self.schemas) |*schemas| {
            var it = schemas.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit(allocator);
            }
            schemas.deinit();
        }

        if (self.request_bodies) |*bodies| {
            var it = bodies.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit(allocator);
            }
            bodies.deinit();
        }

        if (self.security_schemes) |*schemes| {
            var it = schemes.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit(allocator);
            }
            schemes.deinit();
        }
    }
};

pub const Paths = struct {
    items: std.StringHashMap(PathItem),

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!Paths {
        std.debug.print("parsing paths\n", .{}); // Debugging line
        var path_items_map = std.StringHashMap(PathItem).init(allocator);
        const obj = value.object;
        for (obj.keys()) |key| {
            if (key[0] == '/') { // Path items start with '/'
                try path_items_map.put(key, try PathItem.parse(allocator, obj.get(key).?));
            }
        }
        std.debug.print("parsed paths successfully\n", .{}); // Debugging line
        return Paths{ .items = path_items_map };
    }

    pub fn deinit(self: *Paths, allocator: std.mem.Allocator) void {
        var it = self.items.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        self.items.deinit();
    }
};

pub const PathItem = struct {
    ref: ?[]const u8 = null,
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    get: ?Operation = null,
    put: ?Operation = null,
    post: ?Operation = null,
    delete: ?Operation = null,
    options: ?Operation = null,
    head: ?Operation = null,
    patch: ?Operation = null,
    trace: ?Operation = null,
    parameters: ?std.ArrayList(ParameterOrReference) = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!PathItem {
        const obj = value.object;
        var parameters_list = std.ArrayList(ParameterOrReference).init(allocator);
        if (obj.get("parameters")) |params_val| {
            for (params_val.array.items) |item| {
                try parameters_list.append(try ParameterOrReference.parse(allocator, item));
            }
        }

        return PathItem{
            .ref = if (obj.get("$ref")) |val| val.string else null,
            .summary = if (obj.get("summary")) |val| val.string else null,
            .description = if (obj.get("description")) |val| val.string else null,
            .get = if (obj.get("get")) |val| try Operation.parse(allocator, val) else null,
            .put = if (obj.get("put")) |val| try Operation.parse(allocator, val) else null,
            .post = if (obj.get("post")) |val| try Operation.parse(allocator, val) else null,
            .delete = if (obj.get("delete")) |val| try Operation.parse(allocator, val) else null,
            .options = if (obj.get("options")) |val| try Operation.parse(allocator, val) else null,
            .head = if (obj.get("head")) |val| try Operation.parse(allocator, val) else null,
            .patch = if (obj.get("patch")) |val| try Operation.parse(allocator, val) else null,
            .trace = if (obj.get("trace")) |val| try Operation.parse(allocator, val) else null,
            .parameters = if (parameters_list.items.len > 0) parameters_list else null,
        };
    }

    pub fn deinit(self: *PathItem, allocator: std.mem.Allocator) void {
        if (self.parameters) |*params| {
            for (params.items) |*param| {
                param.deinit(allocator);
            }
            params.deinit();
        }

        if (self.get) |*op| {
            op.deinit(allocator);
        }
        if (self.post) |*op| {
            op.deinit(allocator);
        }
        if (self.put) |*op| {
            op.deinit(allocator);
        }
        if (self.delete) |*op| {
            op.deinit(allocator);
        }
    }
};

pub const Operation = struct {
    operationId: ?[]const u8 = null,
    tags: ?std.ArrayList([]const u8) = null,
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    externalDocs: ?ExternalDocumentation = null,
    deprecated: ?bool = null,
    security: ?[]SecurityRequirement = null,
    servers: ?[]Server = null,
    parameters: ?std.ArrayList(ParameterOrReference) = null,
    requestBody: ?RequestBodyOrReference = null,
    responses: Responses,
    callbacks: ?std.StringHashMap(CallbackOrReference) = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!Operation {
        const obj = value.object;
        var tags_list = std.ArrayList([]const u8).init(allocator);
        if (obj.get("tags")) |tags_val| {
            for (tags_val.array.items) |item| {
                try tags_list.append(item.string);
            }
        }
        var parameters_list = std.ArrayList(ParameterOrReference).init(allocator);
        if (obj.get("parameters")) |params_val| {
            for (params_val.array.items) |item| {
                try parameters_list.append(try ParameterOrReference.parse(allocator, item));
            }
        }
        var callbacks_map = std.StringHashMap(CallbackOrReference).init(allocator);
        if (obj.get("callbacks")) |callbacks_val| {
            for (callbacks_val.object.keys()) |key| {
                try callbacks_map.put(key, try CallbackOrReference.parse(allocator, callbacks_val.object.get(key).?));
            }
        }
        var security_list = std.ArrayList(SecurityRequirement).init(allocator);
        if (obj.get("security")) |security_val| {
            for (security_val.array.items) |item| {
                try security_list.append(try SecurityRequirement.parse(allocator, item));
            }
        }
        var servers_list = std.ArrayList(Server).init(allocator);
        if (obj.get("servers")) |servers_val| {
            for (servers_val.array.items) |item| {
                try servers_list.append(try Server.parse(allocator, item));
            }
        }

        return Operation{
            .responses = try Responses.parse(allocator, obj.get("responses").?),
            .tags = if (tags_list.items.len > 0) tags_list else null,
            .summary = if (obj.get("summary")) |val| val.string else null,
            .description = if (obj.get("description")) |val| val.string else null,
            .externalDocs = if (obj.get("externalDocs")) |val| try ExternalDocumentation.parse(allocator, val) else null,
            .operationId = if (obj.get("operationId")) |val| val.string else null,
            .parameters = if (parameters_list.items.len > 0) parameters_list else null,
            .requestBody = if (obj.get("requestBody")) |val| try RequestBodyOrReference.parse(allocator, val) else null,
            .callbacks = if (callbacks_map.count() > 0) callbacks_map else null,
            .deprecated = if (obj.get("deprecated")) |val| val.bool else null,
            .security = if (security_list.items.len > 0) security_list.items else null,
            .servers = if (servers_list.items.len > 0) servers_list.items else null,
        };
    }

    pub fn deinit(self: *Operation, allocator: std.mem.Allocator) void {
        if (self.parameters) |*params| {
            for (params.items) |*param| {
                param.deinit(allocator);
            }
            params.deinit();
        }

        self.responses.deinit(allocator);

        if (self.requestBody) |*body| {
            body.deinit(allocator);
        }
    }
};

pub const Responses = struct {
    status_codes: std.StringHashMap(ResponseOrReference),
    default: ?ResponseOrReference = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!Responses {
        var status_codes_map = std.StringHashMap(ResponseOrReference).init(allocator);
        const obj = value.object;
        for (obj.keys()) |key| {
            if (std.ascii.isDigit(key[0])) { // Status codes are numeric
                try status_codes_map.put(key, try ResponseOrReference.parse(allocator, obj.get(key).?));
            }
        }
        return Responses{
            .default = if (obj.get("default")) |val| try ResponseOrReference.parse(allocator, val) else null,
            .status_codes = status_codes_map,
        };
    }

    pub fn deinit(self: *Responses, allocator: std.mem.Allocator) void {
        var it = self.status_codes.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        self.status_codes.deinit();

        if (self.default) |*def| {
            def.deinit(allocator);
        }
    }
};

pub const SecurityRequirement = struct {
    schemes: std.StringHashMap([]const []const u8),

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!SecurityRequirement {
        var schemes_map = std.StringHashMap([]const []const u8).init(allocator);
        const obj = value.object;
        for (obj.keys()) |key| {
            var scopes_list = std.ArrayList([]const u8).init(allocator);
            for (obj.get(key).?.array.items) |item| {
                try scopes_list.append(item.string);
            }
            try schemes_map.put(key, scopes_list.items);
        }
        return SecurityRequirement{ .schemes = schemes_map };
    }
};

pub const Tag = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    externalDocs: ?ExternalDocumentation = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!Tag {
        const obj = value.object;
        return Tag{
            .name = try allocator.dupe(u8, obj.get("name").?.string),
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
            .externalDocs = if (obj.get("externalDocs")) |val| try ExternalDocumentation.parse(allocator, val) else null,
        };
    }
};

pub const ExternalDocumentation = struct {
    url: []const u8,
    description: ?[]const u8 = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!ExternalDocumentation {
        std.debug.print("parsed externalDocs\n", .{});
        const obj = value.object;
        return ExternalDocumentation{
            .url = try allocator.dupe(u8, obj.get("url").?.string),
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
        };
    }
};

// Union types for $ref
pub const SchemaOrReference = union(enum) {
    schema: *Schema,
    reference: Reference,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!SchemaOrReference {
        if (value.object.get("$ref") != null) {
            return SchemaOrReference{ .reference = try Reference.parse(allocator, value) };
        } else {
            const schema = try allocator.create(Schema);
            errdefer allocator.destroy(schema);
            schema.* = try Schema.parse(allocator, value);
            return SchemaOrReference{ .schema = schema };
        }
    }

    pub fn deinit(self: *SchemaOrReference, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .schema => |*schema| {
                schema.deinit(allocator);
                allocator.destroy(schema);
            },
            .reference => {},
        }
    }
};

pub const ResponseOrReference = union(enum) {
    response: Response,
    reference: Reference,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!ResponseOrReference {
        if (value.object.get("$ref") != null) {
            return ResponseOrReference{ .reference = try Reference.parse(allocator, value) };
        } else {
            return ResponseOrReference{ .response = try Response.parse(allocator, value) };
        }
    }

    pub fn deinit(self: *ResponseOrReference, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .response => |*resp| resp.deinit(allocator),
            .reference => {},
        }
    }
};

pub const ParameterOrReference = union(enum) {
    parameter: Parameter,
    reference: Reference,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!ParameterOrReference {
        if (value.object.get("$ref") != null) {
            return ParameterOrReference{ .reference = try Reference.parse(allocator, value) };
        } else {
            return ParameterOrReference{ .parameter = try Parameter.parse(allocator, value) };
        }
    }

    pub fn deinit(self: *ParameterOrReference, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .parameter => |*param| param.deinit(allocator),
            .reference => {},
        }
    }
};

pub const ExampleOrReference = union(enum) {
    example: Example,
    reference: Reference,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!ExampleOrReference {
        if (value.object.get("$ref") != null) {
            return ExampleOrReference{ .reference = try Reference.parse(allocator, value) };
        } else {
            return ExampleOrReference{ .example = try Example.parse(allocator, value) };
        }
    }
};

pub const RequestBodyOrReference = union(enum) {
    request_body: RequestBody,
    reference: Reference,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!RequestBodyOrReference {
        if (value.object.get("$ref") != null) {
            return RequestBodyOrReference{ .reference = try Reference.parse(allocator, value) };
        } else {
            return RequestBodyOrReference{ .request_body = try RequestBody.parse(allocator, value) };
        }
    }

    pub fn deinit(self: *RequestBodyOrReference, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .request_body => |*body| body.deinit(allocator),
            .reference => {},
        }
    }
};

pub const HeaderOrReference = union(enum) {
    header: Header,
    reference: Reference,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!HeaderOrReference {
        if (value.object.get("$ref") != null) {
            return HeaderOrReference{ .reference = try Reference.parse(allocator, value) };
        } else {
            return HeaderOrReference{ .header = try Header.parse(allocator, value) };
        }
    }

    pub fn deinit(self: *HeaderOrReference, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .header => |*header| header.deinit(allocator),
            .reference => {},
        }
    }
};

pub const SecuritySchemeOrReference = union(enum) {
    security_scheme: SecurityScheme,
    reference: Reference,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!SecuritySchemeOrReference {
        if (value.object.get("$ref") != null) {
            return SecuritySchemeOrReference{ .reference = try Reference.parse(allocator, value) };
        } else {
            return SecuritySchemeOrReference{ .security_scheme = try SecurityScheme.parse(allocator, value) };
        }
    }

    pub fn deinit(self: *SecuritySchemeOrReference, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .security_scheme => {},
            .reference => {},
        }
    }
};

pub const Schema = struct {
    type: ?[]const u8 = null,
    format: ?[]const u8 = null,
    title: ?[]const u8 = null,
    description: ?[]const u8 = null,
    multipleOf: ?f64 = null,
    maximum: ?f64 = null,
    exclusiveMaximum: ?bool = null,
    minimum: ?f64 = null,
    exclusiveMinimum: ?bool = null,
    maxLength: ?i64 = null,
    minLength: ?i64 = null,
    pattern: ?[]const u8 = null,
    maxItems: ?i64 = null,
    minItems: ?i64 = null,
    uniqueItems: ?bool = null,
    maxProperties: ?i64 = null,
    minProperties: ?i64 = null,
    required: ?[][]const u8 = null,
    enum_values: ?[]json.Value = null,
    not: ?SchemaOrReference = null,
    allOf: ?[]SchemaOrReference = null,
    oneOf: ?[]SchemaOrReference = null,
    anyOf: ?[]SchemaOrReference = null,
    items: ?SchemaOrReference = null,
    properties: ?std.StringHashMap(SchemaOrReference) = null,
    additionalProperties: ?AdditionalProperties = null,
    default: ?json.Value = null,
    nullable: ?bool = null,
    discriminator: ?Discriminator = null,
    readOnly: ?bool = null,
    writeOnly: ?bool = null,
    example: ?json.Value = null,
    externalDocs: ?ExternalDocumentation = null,
    deprecated: ?bool = null,
    xml: ?XML = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!Schema {
        const obj = value.object;
        var required_list = std.ArrayList([]const u8).init(allocator);
        if (obj.get("required")) |req_val| {
            for (req_val.array.items) |item| {
                try required_list.append(item.string);
            }
        }
        var enum_list = std.ArrayList(json.Value).init(allocator);
        if (obj.get("enum")) |enum_val| {
            for (enum_val.array.items) |item| {
                try enum_list.append(item);
            }
        }
        var all_of_list = std.ArrayList(SchemaOrReference).init(allocator);
        if (obj.get("allOf")) |all_of_val| {
            for (all_of_val.array.items) |item| {
                try all_of_list.append(try SchemaOrReference.parse(allocator, item));
            }
        }
        var one_of_list = std.ArrayList(SchemaOrReference).init(allocator);
        if (obj.get("oneOf")) |one_of_val| {
            for (one_of_val.array.items) |item| {
                try one_of_list.append(try SchemaOrReference.parse(allocator, item));
            }
        }
        var any_of_list = std.ArrayList(SchemaOrReference).init(allocator);
        if (obj.get("anyOf")) |any_of_val| {
            for (any_of_val.array.items) |item| {
                try any_of_list.append(try SchemaOrReference.parse(allocator, item));
            }
        }
        var properties_map = std.StringHashMap(SchemaOrReference).init(allocator);
        if (obj.get("properties")) |props_val| {
            for (props_val.object.keys()) |key| {
                try properties_map.put(key, try SchemaOrReference.parse(allocator, props_val.object.get(key).?));
            }
        }

        return Schema{
            .title = if (obj.get("title")) |val| val.string else null,
            .multipleOf = if (obj.get("multipleOf")) |val| val.float else null,
            .maximum = if (obj.get("maximum")) |val| val.float else null,
            .exclusiveMaximum = if (obj.get("exclusiveMaximum")) |val| val.bool else null,
            .minimum = if (obj.get("minimum")) |val| val.float else null,
            .exclusiveMinimum = if (obj.get("exclusiveMinimum")) |val| val.bool else null,
            .maxLength = if (obj.get("maxLength")) |val| val.integer else null,
            .minLength = if (obj.get("minLength")) |val| val.integer else null,
            .pattern = if (obj.get("pattern")) |val| val.string else null,
            .maxItems = if (obj.get("maxItems")) |val| val.integer else null,
            .minItems = if (obj.get("minItems")) |val| val.integer else null,
            .uniqueItems = if (obj.get("uniqueItems")) |val| val.bool else null,
            .maxProperties = if (obj.get("maxProperties")) |val| val.integer else null,
            .minProperties = if (obj.get("minProperties")) |val| val.integer else null,
            .required = if (required_list.items.len > 0) required_list.items else null,
            .enum_values = if (enum_list.items.len > 0) enum_list.items else null,
            .type = if (obj.get("type")) |val| val.string else null,
            .not = if (obj.get("not")) |val| try SchemaOrReference.parse(allocator, val) else null,
            .allOf = if (all_of_list.items.len > 0) all_of_list.items else null,
            .oneOf = if (one_of_list.items.len > 0) one_of_list.items else null,
            .anyOf = if (any_of_list.items.len > 0) any_of_list.items else null,
            .items = if (obj.get("items")) |val| try SchemaOrReference.parse(allocator, val) else null,
            .properties = if (properties_map.count() > 0) properties_map else null,
            .additionalProperties = if (obj.get("additionalProperties")) |val| try AdditionalProperties.parse(allocator, val) else null,
            .description = if (obj.get("description")) |val| val.string else null,
            .format = if (obj.get("format")) |val| val.string else null,
            .default = if (obj.get("default")) |val| val else null,
            .nullable = if (obj.get("nullable")) |val| val.bool else null,
            .discriminator = if (obj.get("discriminator")) |val| try Discriminator.parse(allocator, val) else null,
            .readOnly = if (obj.get("readOnly")) |val| val.bool else null,
            .writeOnly = if (obj.get("writeOnly")) |val| val.bool else null,
            .example = if (obj.get("example")) |val| val else null,
            .externalDocs = if (obj.get("externalDocs")) |val| try ExternalDocumentation.parse(allocator, val) else null,
            .deprecated = if (obj.get("deprecated")) |val| val.bool else null,
            .xml = if (obj.get("xml")) |val| try XML.parse(val) else null,
        };
    }

    pub fn deinit(self: *Schema, allocator: std.mem.Allocator) void {
        if (self.properties) |*props| {
            var it = props.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit(allocator);
            }
            props.deinit();
        }

        if (self.items) |*items| {
            items.deinit(allocator);
        }

        if (self.additionalProperties) |*add_props| {
            add_props.deinit(allocator);
        }
    }
};

pub const MediaType = struct {
    schema: ?SchemaOrReference = null,
    example: ?json.Value = null,
    examples: ?std.StringHashMap(ExampleOrReference) = null,
    encoding: ?std.StringHashMap(Encoding) = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!MediaType {
        const obj = value.object;
        var examples_map = std.StringHashMap(ExampleOrReference).init(allocator);
        if (obj.get("examples")) |examples_val| {
            for (examples_val.object.keys()) |key| {
                try examples_map.put(key, try ExampleOrReference.parse(allocator, examples_val.object.get(key).?));
            }
        }
        var encoding_map = std.StringHashMap(Encoding).init(allocator);
        if (obj.get("encoding")) |encoding_val| {
            for (encoding_val.object.keys()) |key| {
                try encoding_map.put(key, try Encoding.parse(allocator, encoding_val.object.get(key).?));
            }
        }

        return MediaType{
            .schema = if (obj.get("schema")) |val| try SchemaOrReference.parse(allocator, val) else null,
            .example = if (obj.get("example")) |val| val else null,
            .examples = if (examples_map.count() > 0) examples_map else null,
            .encoding = if (encoding_map.count() > 0) encoding_map else null,
        };
    }

    pub fn deinit(self: *MediaType, allocator: std.mem.Allocator) void {
        if (self.schema) |*schema| {
            schema.deinit(allocator);
        }
    }
};

pub const Example = struct {
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    value: ?json.Value = null,
    externalValue: ?[]const u8 = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!Example {
        _ = allocator; // autofix
        const obj = value.object;
        return Example{
            .summary = if (obj.get("summary")) |val| val.string else null,
            .description = if (obj.get("description")) |val| val.string else null,
            .value = if (obj.get("value")) |val| val else null,
            .externalValue = if (obj.get("externalValue")) |val| val.string else null,
        };
    }
};

pub const Header = struct {
    description: ?[]const u8 = null,
    required: ?bool = null,
    deprecated: ?bool = null,
    allowEmptyValue: ?bool = null,
    style: ?[]const u8 = null,
    explode: ?bool = null,
    allowReserved: ?bool = null,
    schema: ?SchemaOrReference = null,
    content: ?std.StringHashMap(MediaType) = null,
    example: ?json.Value = null,
    examples: ?std.StringHashMap(ExampleOrReference) = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!Header {
        const obj = value.object;

        var content_map = std.StringHashMap(MediaType).init(allocator);
        if (obj.get("content")) |content_val| {
            var content_iterator = content_val.object.iterator();
            while (content_iterator.next()) |entry| {
                try content_map.put(try allocator.dupe(u8, entry.key_ptr.*), try MediaType.parse(allocator, entry.value_ptr.*));
            }
        }

        var examples_map = std.StringHashMap(ExampleOrReference).init(allocator);
        if (obj.get("examples")) |examples_val| {
            var examples_iterator = examples_val.object.iterator();
            while (examples_iterator.next()) |entry| {
                try examples_map.put(try allocator.dupe(u8, entry.key_ptr.*), try ExampleOrReference.parse(allocator, entry.value_ptr.*));
            }
        }

        return Header{
            .description = if (obj.get("description")) |val| val.string else null,
            .required = if (obj.get("required")) |val| val.bool else null,
            .deprecated = if (obj.get("deprecated")) |val| val.bool else null,
            .allowEmptyValue = if (obj.get("allowEmptyValue")) |val| val.bool else null,
            .style = if (obj.get("style")) |val| val.string else null,
            .explode = if (obj.get("explode")) |val| val.bool else null,
            .allowReserved = if (obj.get("allowReserved")) |val| val.bool else null,
            .schema = if (obj.get("schema")) |val| try SchemaOrReference.parse(allocator, val) else null,
            .content = if (content_map.count() > 0) content_map else null,
            .example = if (obj.get("example")) |val| val else null,
            .examples = if (examples_map.count() > 0) examples_map else null,
        };
    }

    pub fn deinit(self: *Header, allocator: std.mem.Allocator) void {
        if (self.description) |desc| {
            allocator.free(desc);
        }
        if (self.schema) |*schema| {
            schema.deinit(allocator);
        }
    }
};

pub const Parameter = struct {
    name: []const u8,
    in: ParameterLocation,
    description: ?[]const u8 = null,
    required: bool = false,
    deprecated: ?bool = null,
    allowEmptyValue: ?bool = null,
    style: ?[]const u8 = null,
    explode: ?bool = null,
    allowReserved: ?bool = null,
    schema: ?SchemaOrReference = null,
    content: ?std.StringHashMap(MediaType) = null,
    example: ?json.Value = null,
    examples: ?std.StringHashMap(ExampleOrReference) = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!Parameter {
        const obj = value.object;

        var content_map = std.StringHashMap(MediaType).init(allocator);
        if (obj.get("content")) |content_val| {
            var content_iterator = content_val.object.iterator();
            while (content_iterator.next()) |entry| {
                try content_map.put(try allocator.dupe(u8, entry.key_ptr.*), try MediaType.parse(allocator, entry.value_ptr.*));
            }
        }

        var examples_map = std.StringHashMap(ExampleOrReference).init(allocator);
        if (obj.get("examples")) |examples_val| {
            var examples_iterator = examples_val.object.iterator();
            while (examples_iterator.next()) |entry| {
                try examples_map.put(try allocator.dupe(u8, entry.key_ptr.*), try ExampleOrReference.parse(allocator, entry.value_ptr.*));
            }
        }

        return Parameter{
            .name = try allocator.dupe(u8, obj.get("name").?.string),
            .in = try ParameterLocation.parse(obj.get("in").?.string),
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
            .required = if (obj.get("required")) |val| val.bool else false,
            .deprecated = if (obj.get("deprecated")) |val| val.bool else null,
            .allowEmptyValue = if (obj.get("allowEmptyValue")) |val| val.bool else null,
            .style = if (obj.get("style")) |val| try allocator.dupe(u8, val.string) else null,
            .explode = if (obj.get("explode")) |val| val.bool else null,
            .allowReserved = if (obj.get("allowReserved")) |val| val.bool else null,
            .schema = if (obj.get("schema")) |val| try SchemaOrReference.parse(allocator, val) else null,
            .content = if (content_map.count() > 0) content_map else null,
            .example = if (obj.get("example")) |val| val else null,
            .examples = if (examples_map.count() > 0) examples_map else null,
        };
    }

    pub fn deinit(self: *Parameter, allocator: std.mem.Allocator) void {
        if (self.schema) |*schema| {
            schema.deinit(allocator);
        }
    }
};
