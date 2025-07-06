const std = @import("std");
const json = std.json;

pub const OpenApiDocument = struct {
    openapi: []const u8,
    info: Info,
    paths: Paths,
    externalDocs: ?ExternalDocumentation = null,
    servers: ?[]const Server = null,
    security: ?[]const SecurityRequirement = null,
    tags: ?[]const Tag = null,
    components: ?Components = null,

    pub fn deinit(self: *OpenApiDocument, allocator: std.mem.Allocator) void {
        // Free the openapi string
        allocator.free(self.openapi);
        
        // Free the info struct
        self.info.deinit(allocator);
        
        // Free the paths
        self.paths.deinit(allocator);
        
        // Free external docs if present
        if (self.externalDocs) |*external_docs| {
            external_docs.deinit(allocator);
        }
        
        // Free servers if present
        if (self.servers) |servers| {
            for (servers) |*server| {
                server.deinit(allocator);
            }
            allocator.free(servers);
        }
        
        // Free security requirements if present
        if (self.security) |security| {
            for (security) |*security_req| {
                security_req.deinit(allocator);
            }
            allocator.free(security);
        }
        
        // Free tags if present
        if (self.tags) |tags| {
            for (tags) |tag| {
                tag.deinit(allocator);
            }
            allocator.free(tags);
        }
        
        // Free components if present
        if (self.components) |*components| {
            components.deinit(allocator);
        }
    }

    pub fn parse(allocator: std.mem.Allocator, json_string: []const u8) anyerror!OpenApiDocument {
        var parsed = try json.parseFromSlice(json.Value, allocator, json_string, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        const root = parsed.value;
        
        // Allocate persistent copies of strings
        const openapi_str = try allocator.dupe(u8, root.object.get("openapi").?.string);
        
        const info = try Info.parse(allocator, root.object.get("info").?);
        const paths = try Paths.parse(allocator, root.object.get("paths").?);
        const externalDocs = if (root.object.get("externalDocs")) |val| try ExternalDocumentation.parse(allocator, val) else null;
        const servers = if (root.object.get("servers")) |val| try parseServers(allocator, val) else null;
        const security = if (root.object.get("security")) |val| try parseSecurityRequirements(allocator, val) else null;
        const tags = if (root.object.get("tags")) |val| try parseTags(allocator, val) else null;
        const components = if (root.object.get("components")) |val| try Components.parse(allocator, val) else null;

        return OpenApiDocument{
            .openapi = openapi_str,
            .info = info,
            .paths = paths,
            .externalDocs = externalDocs,
            .servers = servers,
            .security = security,
            .tags = tags,
            .components = components,
        };
    }

    fn parseServers(allocator: std.mem.Allocator, value: json.Value) anyerror![]const Server {
        var array_list = std.ArrayList(Server).init(allocator);
        for (value.array.items) |item| {
            try array_list.append(try Server.parse(allocator, item));
        }
        return array_list.items;
    }

    fn parseSecurityRequirements(allocator: std.mem.Allocator, value: json.Value) anyerror![]const SecurityRequirement {
        var array_list = std.ArrayList(SecurityRequirement).init(allocator);
        for (value.array.items) |item| {
            try array_list.append(try SecurityRequirement.parse(allocator, item));
        }
        return array_list.items;
    }

    fn parseTags(allocator: std.mem.Allocator, value: json.Value) anyerror![]const Tag {
        var array_list = std.ArrayList(Tag).init(allocator);
        for (value.array.items) |item| {
            try array_list.append(try Tag.parse(allocator, item));
        }
        return array_list.items;
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

    pub fn deinit(self: Info, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.version);
        if (self.description) |desc| allocator.free(desc);
        if (self.termsOfService) |terms| allocator.free(terms);
        if (self.contact) |contact| contact.deinit(allocator);
        if (self.license) |license| license.deinit(allocator);
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

    pub fn deinit(self: Contact, allocator: std.mem.Allocator) void {
        if (self.name) |name| allocator.free(name);
        if (self.url) |url| allocator.free(url);
        if (self.email) |email| allocator.free(email);
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

    pub fn deinit(self: License, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.url) |url| allocator.free(url);
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
                try variables_map.put(try allocator.dupe(u8, key), try ServerVariable.parse(allocator, vars_val.object.get(key).?));
            }
        }
        return Server{
            .url = try allocator.dupe(u8, obj.get("url").?.string),
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
            .variables = if (variables_map.count() > 0) variables_map else null,
        };
    }

    pub fn deinit(self: *Server, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        if (self.description) |desc| allocator.free(desc);
        if (self.variables) |*vars| {
            var iterator = vars.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(allocator);
            }
            vars.deinit();
        }
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
                try enum_list.append(try allocator.dupe(u8, item.string));
            }
        }

        return ServerVariable{
            .default = try allocator.dupe(u8, obj.get("default").?.string),
            .enum_values = if (enum_list.items.len > 0) enum_list.items else null,
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
        };
    }

    pub fn deinit(self: ServerVariable, allocator: std.mem.Allocator) void {
        allocator.free(self.default);
        if (self.description) |desc| allocator.free(desc);
        if (self.enum_values) |enum_vals| {
            for (enum_vals) |val| {
                allocator.free(val);
            }
            allocator.free(enum_vals);
        }
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
        const obj = value.object;
        var schemas_map = std.StringHashMap(SchemaOrReference).init(allocator);
        if (obj.get("schemas")) |schemas_val| {
            for (schemas_val.object.keys()) |key| {
                try schemas_map.put(try allocator.dupe(u8, key), try SchemaOrReference.parse(allocator, schemas_val.object.get(key).?));
            }
        }
        var responses_map = std.StringHashMap(ResponseOrReference).init(allocator);
        if (obj.get("responses")) |responses_val| {
            for (responses_val.object.keys()) |key| {
                try responses_map.put(try allocator.dupe(u8, key), try ResponseOrReference.parse(allocator, responses_val.object.get(key).?));
            }
        }
        var parameters_map = std.StringHashMap(ParameterOrReference).init(allocator);
        if (obj.get("parameters")) |parameters_val| {
            for (parameters_val.object.keys()) |key| {
                try parameters_map.put(try allocator.dupe(u8, key), try ParameterOrReference.parse(allocator, parameters_val.object.get(key).?));
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
                try request_bodies_map.put(try allocator.dupe(u8, key), try RequestBodyOrReference.parse(allocator, request_bodies_val.object.get(key).?));
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
                try security_schemes_map.put(try allocator.dupe(u8, key), try SecuritySchemeOrReference.parse(allocator, security_schemes_val.object.get(key).?));
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
        // For now, just basic cleanup of HashMaps - proper cleanup would need to deinit each value
        if (self.schemas) |*schemas| {
            var iterator = schemas.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
            }
            schemas.deinit();
        }
        if (self.responses) |*responses| responses.deinit();
        if (self.parameters) |*parameters| parameters.deinit();
        if (self.examples) |*examples| examples.deinit();
        if (self.requestBodies) |*request_bodies| {
            var iterator = request_bodies.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
            }
            request_bodies.deinit();
        }
        if (self.headers) |*headers| headers.deinit();
        if (self.securitySchemes) |*security_schemes| {
            var iterator = security_schemes.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
            }
            security_schemes.deinit();
        }
        if (self.links) |*links| links.deinit();
        if (self.callbacks) |*callbacks| callbacks.deinit();
    }
};

pub const Paths = struct {
    path_items: std.StringHashMap(PathItem),

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!Paths {
        var path_items_map = std.StringHashMap(PathItem).init(allocator);
        const obj = value.object;
        for (obj.keys()) |key| {
            if (key[0] == '/') { // Path items start with '/'
                try path_items_map.put(try allocator.dupe(u8, key), try PathItem.parse(allocator, obj.get(key).?));
            }
        }
        return Paths{ .path_items = path_items_map };
    }

    pub fn deinit(self: *Paths, allocator: std.mem.Allocator) void {
        var iterator = self.path_items.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        self.path_items.deinit();
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
    servers: ?[]const Server = null,
    parameters: ?[]const ParameterOrReference = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!PathItem {
        const obj = value.object;
        var parameters_list = std.ArrayList(ParameterOrReference).init(allocator);
        if (obj.get("parameters")) |params_val| {
            for (params_val.array.items) |item| {
                try parameters_list.append(try ParameterOrReference.parse(allocator, item));
            }
        }
        var servers_list = std.ArrayList(Server).init(allocator);
        if (obj.get("servers")) |servers_val| {
            for (servers_val.array.items) |item| {
                try servers_list.append(try Server.parse(allocator, item));
            }
        }

        return PathItem{
            .ref = if (obj.get("$ref")) |val| try allocator.dupe(u8, val.string) else null,
            .summary = if (obj.get("summary")) |val| try allocator.dupe(u8, val.string) else null,
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
            .get = if (obj.get("get")) |val| try Operation.parse(allocator, val) else null,
            .put = if (obj.get("put")) |val| try Operation.parse(allocator, val) else null,
            .post = if (obj.get("post")) |val| try Operation.parse(allocator, val) else null,
            .delete = if (obj.get("delete")) |val| try Operation.parse(allocator, val) else null,
            .options = if (obj.get("options")) |val| try Operation.parse(allocator, val) else null,
            .head = if (obj.get("head")) |val| try Operation.parse(allocator, val) else null,
            .patch = if (obj.get("patch")) |val| try Operation.parse(allocator, val) else null,
            .trace = if (obj.get("trace")) |val| try Operation.parse(allocator, val) else null,
            .servers = if (servers_list.items.len > 0) servers_list.items else null,
            .parameters = if (parameters_list.items.len > 0) parameters_list.items else null,
        };
    }

    pub fn deinit(self: PathItem, allocator: std.mem.Allocator) void {
        if (self.ref) |ref| allocator.free(ref);
        if (self.summary) |summary| allocator.free(summary);
        if (self.description) |description| allocator.free(description);
        // TODO: Add proper deinit for operations, servers, and parameters when needed
    }
};

pub const Operation = struct {
    responses: Responses,
    tags: ?[]const []const u8 = null,
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    externalDocs: ?ExternalDocumentation = null,
    operationId: ?[]const u8 = null,
    parameters: ?[]const ParameterOrReference = null,
    requestBody: ?RequestBodyOrReference = null,
    callbacks: ?std.StringHashMap(CallbackOrReference) = null,
    deprecated: ?bool = null,
    security: ?[]const SecurityRequirement = null,
    servers: ?[]const Server = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!Operation {
        const obj = value.object;
        var tags_list = std.ArrayList([]const u8).init(allocator);
        if (obj.get("tags")) |tags_val| {
            for (tags_val.array.items) |item| {
                try tags_list.append(try allocator.dupe(u8, item.string));
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
            .tags = if (tags_list.items.len > 0) tags_list.items else null,
            .summary = if (obj.get("summary")) |val| try allocator.dupe(u8, val.string) else null,
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
            .externalDocs = if (obj.get("externalDocs")) |val| try ExternalDocumentation.parse(allocator, val) else null,
            .operationId = if (obj.get("operationId")) |val| try allocator.dupe(u8, val.string) else null,
            .parameters = if (parameters_list.items.len > 0) parameters_list.items else null,
            .requestBody = if (obj.get("requestBody")) |val| try RequestBodyOrReference.parse(allocator, val) else null,
            .callbacks = if (callbacks_map.count() > 0) callbacks_map else null,
            .deprecated = if (obj.get("deprecated")) |val| val.bool else null,
            .security = if (security_list.items.len > 0) security_list.items else null,
            .servers = if (servers_list.items.len > 0) servers_list.items else null,
        };
    }
};

pub const Responses = struct {
    default: ?ResponseOrReference = null,
    status_codes: std.StringHashMap(ResponseOrReference),

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
};

pub const SecurityRequirement = struct {
    schemes: std.StringHashMap([]const []const u8),

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!SecurityRequirement {
        var schemes_map = std.StringHashMap([]const []const u8).init(allocator);
        const obj = value.object;
        for (obj.keys()) |key| {
            var scopes_list = std.ArrayList([]const u8).init(allocator);
            for (obj.get(key).?.array.items) |item| {
                try scopes_list.append(try allocator.dupe(u8, item.string));
            }
            try schemes_map.put(try allocator.dupe(u8, key), scopes_list.items);
        }
        return SecurityRequirement{ .schemes = schemes_map };
    }

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

    pub fn deinit(self: Tag, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.description) |desc| allocator.free(desc);
        if (self.externalDocs) |docs| docs.deinit(allocator);
    }
};

pub const ExternalDocumentation = struct {
    url: []const u8,
    description: ?[]const u8 = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!ExternalDocumentation {
        const obj = value.object;
        return ExternalDocumentation{
            .url = try allocator.dupe(u8, obj.get("url").?.string),
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
        };
    }

    pub fn deinit(self: ExternalDocumentation, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        if (self.description) |desc| allocator.free(desc);
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
};

pub const LinkOrReference = union(enum) {
    link: Link,
    reference: Reference,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!LinkOrReference {
        if (value.object.get("$ref") != null) {
            return LinkOrReference{ .reference = try Reference.parse(allocator, value) };
        } else {
            return LinkOrReference{ .link = try Link.parse(allocator, value) };
        }
    }
};

pub const CallbackOrReference = union(enum) {
    callback: Callback,
    reference: Reference,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!CallbackOrReference {
        if (value.object.get("$ref") != null) {
            return CallbackOrReference{ .reference = try Reference.parse(allocator, value) };
        } else {
            return CallbackOrReference{ .callback = try Callback.parse(allocator, value) };
        }
    }
};

pub const Reference = struct {
    ref: []const u8,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!Reference {
        const obj = value.object;
        return Reference{ .ref = try allocator.dupe(u8, obj.get("$ref").?.string) };
    }
};

pub const Schema = struct {
    title: ?[]const u8 = null,
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
    required: ?[]const []const u8 = null,
    enum_values: ?[]const json.Value = null, // Can be any type
    type: ?[]const u8 = null, // "array", "boolean", "integer", "number", "object", "string"
    not: ?SchemaOrReference = null,
    allOf: ?[]const SchemaOrReference = null,
    oneOf: ?[]const SchemaOrReference = null,
    anyOf: ?[]const SchemaOrReference = null,
    items: ?SchemaOrReference = null,
    properties: ?std.StringHashMap(SchemaOrReference) = null,
    additionalProperties: ?AdditionalProperties = null,
    description: ?[]const u8 = null,
    format: ?[]const u8 = null,
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
                try required_list.append(try allocator.dupe(u8, item.string));
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
            .title = if (obj.get("title")) |val| try allocator.dupe(u8, val.string) else null,
            .multipleOf = if (obj.get("multipleOf")) |val| val.float else null,
            .maximum = if (obj.get("maximum")) |val| val.float else null,
            .exclusiveMaximum = if (obj.get("exclusiveMaximum")) |val| val.bool else null,
            .minimum = if (obj.get("minimum")) |val| val.float else null,
            .exclusiveMinimum = if (obj.get("exclusiveMinimum")) |val| val.bool else null,
            .maxLength = if (obj.get("maxLength")) |val| val.integer else null,
            .minLength = if (obj.get("minLength")) |val| val.integer else null,
            .pattern = if (obj.get("pattern")) |val| try allocator.dupe(u8, val.string) else null,
            .maxItems = if (obj.get("maxItems")) |val| val.integer else null,
            .minItems = if (obj.get("minItems")) |val| val.integer else null,
            .uniqueItems = if (obj.get("uniqueItems")) |val| val.bool else null,
            .maxProperties = if (obj.get("maxProperties")) |val| val.integer else null,
            .minProperties = if (obj.get("minProperties")) |val| val.integer else null,
            .required = if (required_list.items.len > 0) required_list.items else null,
            .enum_values = if (enum_list.items.len > 0) enum_list.items else null,
            .type = if (obj.get("type")) |val| try allocator.dupe(u8, val.string) else null,
            .not = if (obj.get("not")) |val| try SchemaOrReference.parse(allocator, val) else null,
            .allOf = if (all_of_list.items.len > 0) all_of_list.items else null,
            .oneOf = if (one_of_list.items.len > 0) one_of_list.items else null,
            .anyOf = if (any_of_list.items.len > 0) any_of_list.items else null,
            .items = if (obj.get("items")) |val| try SchemaOrReference.parse(allocator, val) else null,
            .properties = if (properties_map.count() > 0) properties_map else null,
            .additionalProperties = if (obj.get("additionalProperties")) |val| try AdditionalProperties.parse(allocator, val) else null,
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
            .format = if (obj.get("format")) |val| try allocator.dupe(u8, val.string) else null,
            .default = if (obj.get("default")) |val| val else null,
            .nullable = if (obj.get("nullable")) |val| val.bool else null,
            .discriminator = if (obj.get("discriminator")) |val| try Discriminator.parse(allocator, val) else null,
            .readOnly = if (obj.get("readOnly")) |val| val.bool else null,
            .writeOnly = if (obj.get("writeOnly")) |val| val.bool else null,
            .example = if (obj.get("example")) |val| val else null,
            .externalDocs = if (obj.get("externalDocs")) |val| try ExternalDocumentation.parse(allocator, val) else null,
            .deprecated = if (obj.get("deprecated")) |val| val.bool else null,
            .xml = if (obj.get("xml")) |val| try XML.parse(allocator, val) else null,
        };
    }
};

pub const AdditionalProperties = union(enum) {
    schema_or_reference: SchemaOrReference,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!AdditionalProperties {
        return AdditionalProperties{ .schema_or_reference = try SchemaOrReference.parse(allocator, value) };
    }
};

pub const Discriminator = struct {
    propertyName: []const u8,
    mapping: ?std.StringHashMap([]const u8) = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!Discriminator {
        const obj = value.object;
        var mapping_map = std.StringHashMap([]const u8).init(allocator);
        if (obj.get("mapping")) |map_val| {
            for (map_val.object.keys()) |key| {
                try mapping_map.put(try allocator.dupe(u8, key), try allocator.dupe(u8, map_val.object.get(key).?.string));
            }
        }
        return Discriminator{
            .propertyName = try allocator.dupe(u8, obj.get("propertyName").?.string),
            .mapping = if (mapping_map.count() > 0) mapping_map else null,
        };
    }
};

pub const XML = struct {
    name: ?[]const u8 = null,
    namespace: ?[]const u8 = null,
    prefix: ?[]const u8 = null,
    attribute: ?bool = null,
    wrapped: ?bool = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!XML {
        const obj = value.object;
        return XML{
            .name = if (obj.get("name")) |val| try allocator.dupe(u8, val.string) else null,
            .namespace = if (obj.get("namespace")) |val| try allocator.dupe(u8, val.string) else null,
            .prefix = if (obj.get("prefix")) |val| try allocator.dupe(u8, val.string) else null,
            .attribute = if (obj.get("attribute")) |val| val.bool else null,
            .wrapped = if (obj.get("wrapped")) |val| val.bool else null,
        };
    }
};

pub const Response = struct {
    description: []const u8,
    headers: ?std.StringHashMap(HeaderOrReference) = null,
    content: ?std.StringHashMap(MediaType) = null,
    links: ?std.StringHashMap(LinkOrReference) = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!Response {
        const obj = value.object;
        var headers_map = std.StringHashMap(HeaderOrReference).init(allocator);
        if (obj.get("headers")) |headers_val| {
            for (headers_val.object.keys()) |key| {
                try headers_map.put(key, try HeaderOrReference.parse(allocator, headers_val.object.get(key).?));
            }
        }
        var content_map = std.StringHashMap(MediaType).init(allocator);
        if (obj.get("content")) |content_val| {
            for (content_val.object.keys()) |key| {
                try content_map.put(key, try MediaType.parse(allocator, content_val.object.get(key).?));
            }
        }
        var links_map = std.StringHashMap(LinkOrReference).init(allocator);
        if (obj.get("links")) |links_val| {
            for (links_val.object.keys()) |key| {
                try links_map.put(key, try LinkOrReference.parse(allocator, links_val.object.get(key).?));
            }
        }

        return Response{
            .description = try allocator.dupe(u8, obj.get("description").?.string),
            .headers = if (headers_map.count() > 0) headers_map else null,
            .content = if (content_map.count() > 0) content_map else null,
            .links = if (links_map.count() > 0) links_map else null,
        };
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
};

pub const Example = struct {
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    value: ?json.Value = null,
    externalValue: ?[]const u8 = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!Example {
        const obj = value.object;
        return Example{
            .summary = if (obj.get("summary")) |val| try allocator.dupe(u8, val.string) else null,
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
            .value = if (obj.get("value")) |val| val else null,
            .externalValue = if (obj.get("externalValue")) |val| try allocator.dupe(u8, val.string) else null,
        };
    }
};

pub const Header = struct {
    description: ?[]const u8 = null,
    required: ?bool = null,
    deprecated: ?bool = null,
    allowEmptyValue: ?bool = null,
    style: ?[]const u8 = null, // "simple"
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
            for (content_val.object.keys()) |key| {
                try content_map.put(key, try MediaType.parse(allocator, content_val.object.get(key).?));
            }
        }
        var examples_map = std.StringHashMap(ExampleOrReference).init(allocator);
        if (obj.get("examples")) |examples_val| {
            for (examples_val.object.keys()) |key| {
                try examples_map.put(key, try ExampleOrReference.parse(allocator, examples_val.object.get(key).?));
            }
        }

        return Header{
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
            .required = if (obj.get("required")) |val| val.bool else null,
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
};

pub const Parameter = struct {
    name: []const u8,
    in_field: []const u8, // Renamed 'in' to 'in_field' to avoid keyword conflict
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

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!Parameter {
        const obj = value.object;
        var content_map = std.StringHashMap(MediaType).init(allocator);
        if (obj.get("content")) |content_val| {
            for (content_val.object.keys()) |key| {
                try content_map.put(key, try MediaType.parse(allocator, content_val.object.get(key).?));
            }
        }
        var examples_map = std.StringHashMap(ExampleOrReference).init(allocator);
        if (obj.get("examples")) |examples_val| {
            for (examples_val.object.keys()) |key| {
                try examples_map.put(key, try ExampleOrReference.parse(allocator, examples_val.object.get(key).?));
            }
        }

        return Parameter{
            .name = try allocator.dupe(u8, obj.get("name").?.string),
            .in_field = try allocator.dupe(u8, obj.get("in").?.string),
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
            .required = if (obj.get("required")) |val| val.bool else null,
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
};

pub const RequestBody = struct {
    content: std.StringHashMap(MediaType),
    description: ?[]const u8 = null,
    required: ?bool = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!RequestBody {
        const obj = value.object;
        var content_map = std.StringHashMap(MediaType).init(allocator);
        if (obj.get("content")) |content_val| {
            for (content_val.object.keys()) |key| {
                try content_map.put(key, try MediaType.parse(allocator, content_val.object.get(key).?));
            }
        }
        return RequestBody{
            .content = content_map,
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
            .required = if (obj.get("required")) |val| val.bool else null,
        };
    }
};

pub const SecurityScheme = union(enum) {
    api_key: APIKeySecurityScheme,
    http: HTTPSecurityScheme,
    oauth2: OAuth2SecurityScheme,
    openIdConnect: OpenIdConnectSecurityScheme,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!SecurityScheme {
        const obj = value.object;
        const type_str = obj.get("type").?.string;
        if (std.mem.eql(u8, type_str, "apiKey")) {
            return SecurityScheme{ .api_key = try APIKeySecurityScheme.parse(allocator, value) };
        } else if (std.mem.eql(u8, type_str, "http")) {
            return SecurityScheme{ .http = try HTTPSecurityScheme.parse(allocator, value) };
        } else if (std.mem.eql(u8, type_str, "oauth2")) {
            return SecurityScheme{ .oauth2 = try OAuth2SecurityScheme.parse(allocator, value) };
        } else if (std.mem.eql(u8, type_str, "openIdConnect")) {
            return SecurityScheme{ .openIdConnect = try OpenIdConnectSecurityScheme.parse(allocator, value) };
        } else {
            return error.UnknownSecuritySchemeType;
        }
    }
};

pub const APIKeySecurityScheme = struct {
    type: []const u8, // "apiKey"
    name: []const u8,
    in_field: []const u8, // "header", "query", "cookie"
    description: ?[]const u8 = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!APIKeySecurityScheme {
        const obj = value.object;
        return APIKeySecurityScheme{
            .type = try allocator.dupe(u8, obj.get("type").?.string),
            .name = try allocator.dupe(u8, obj.get("name").?.string),
            .in_field = try allocator.dupe(u8, obj.get("in").?.string),
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
        };
    }
};

pub const HTTPSecurityScheme = struct {
    scheme: []const u8,
    type: []const u8, // "http"
    bearerFormat: ?[]const u8 = null,
    description: ?[]const u8 = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!HTTPSecurityScheme {
        const obj = value.object;
        return HTTPSecurityScheme{
            .scheme = try allocator.dupe(u8, obj.get("scheme").?.string),
            .type = try allocator.dupe(u8, obj.get("type").?.string),
            .bearerFormat = if (obj.get("bearerFormat")) |val| try allocator.dupe(u8, val.string) else null,
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
        };
    }
};

pub const OAuth2SecurityScheme = struct {
    type: []const u8, // "oauth2"
    flows: OAuthFlows,
    description: ?[]const u8 = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!OAuth2SecurityScheme {
        const obj = value.object;
        return OAuth2SecurityScheme{
            .type = try allocator.dupe(u8, obj.get("type").?.string),
            .flows = try OAuthFlows.parse(allocator, obj.get("flows").?),
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
        };
    }
};

pub const OpenIdConnectSecurityScheme = struct {
    type: []const u8, // "openIdConnect"
    openIdConnectUrl: []const u8,
    description: ?[]const u8 = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!OpenIdConnectSecurityScheme {
        const obj = value.object;
        return OpenIdConnectSecurityScheme{
            .type = try allocator.dupe(u8, obj.get("type").?.string),
            .openIdConnectUrl = try allocator.dupe(u8, obj.get("openIdConnectUrl").?.string),
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
        };
    }
};

pub const OAuthFlows = struct {
    implicit: ?ImplicitOAuthFlow = null,
    password: ?PasswordOAuthFlow = null,
    clientCredentials: ?ClientCredentialsFlow = null,
    authorizationCode: ?AuthorizationCodeOAuthFlow = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!OAuthFlows {
        const obj = value.object;
        return OAuthFlows{
            .implicit = if (obj.get("implicit")) |val| try ImplicitOAuthFlow.parse(allocator, val) else null,
            .password = if (obj.get("password")) |val| try PasswordOAuthFlow.parse(allocator, val) else null,
            .clientCredentials = if (obj.get("clientCredentials")) |val| try ClientCredentialsFlow.parse(allocator, val) else null,
            .authorizationCode = if (obj.get("authorizationCode")) |val| try AuthorizationCodeOAuthFlow.parse(allocator, val) else null,
        };
    }
};

pub const ImplicitOAuthFlow = struct {
    authorizationUrl: []const u8,
    scopes: std.StringHashMap([]const u8),
    refreshUrl: ?[]const u8 = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!ImplicitOAuthFlow {
        const obj = value.object;
        var scopes_map = std.StringHashMap([]const u8).init(allocator);
        if (obj.get("scopes")) |scopes_val| {
            for (scopes_val.object.keys()) |key| {
                try scopes_map.put(try allocator.dupe(u8, key), try allocator.dupe(u8, scopes_val.object.get(key).?.string));
            }
        }
        return ImplicitOAuthFlow{
            .authorizationUrl = try allocator.dupe(u8, obj.get("authorizationUrl").?.string),
            .scopes = scopes_map,
            .refreshUrl = if (obj.get("refreshUrl")) |val| try allocator.dupe(u8, val.string) else null,
        };
    }
};

pub const PasswordOAuthFlow = struct {
    tokenUrl: []const u8,
    scopes: std.StringHashMap([]const u8),
    refreshUrl: ?[]const u8 = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!PasswordOAuthFlow {
        const obj = value.object;
        var scopes_map = std.StringHashMap([]const u8).init(allocator);
        if (obj.get("scopes")) |scopes_val| {
            for (scopes_val.object.keys()) |key| {
                try scopes_map.put(try allocator.dupe(u8, key), try allocator.dupe(u8, scopes_val.object.get(key).?.string));
            }
        }
        return PasswordOAuthFlow{
            .tokenUrl = try allocator.dupe(u8, obj.get("tokenUrl").?.string),
            .scopes = scopes_map,
            .refreshUrl = if (obj.get("refreshUrl")) |val| try allocator.dupe(u8, val.string) else null,
        };
    }
};

pub const ClientCredentialsFlow = struct {
    tokenUrl: []const u8,
    scopes: std.StringHashMap([]const u8),
    refreshUrl: ?[]const u8 = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!ClientCredentialsFlow {
        const obj = value.object;
        var scopes_map = std.StringHashMap([]const u8).init(allocator);
        if (obj.get("scopes")) |scopes_val| {
            for (scopes_val.object.keys()) |key| {
                try scopes_map.put(try allocator.dupe(u8, key), try allocator.dupe(u8, scopes_val.object.get(key).?.string));
            }
        }
        return ClientCredentialsFlow{
            .tokenUrl = try allocator.dupe(u8, obj.get("tokenUrl").?.string),
            .scopes = scopes_map,
            .refreshUrl = if (obj.get("refreshUrl")) |val| try allocator.dupe(u8, val.string) else null,
        };
    }
};

pub const AuthorizationCodeOAuthFlow = struct {
    authorizationUrl: []const u8,
    tokenUrl: []const u8,
    scopes: std.StringHashMap([]const u8),
    refreshUrl: ?[]const u8 = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!AuthorizationCodeOAuthFlow {
        const obj = value.object;
        var scopes_map = std.StringHashMap([]const u8).init(allocator);
        if (obj.get("scopes")) |scopes_val| {
            for (scopes_val.object.keys()) |key| {
                try scopes_map.put(try allocator.dupe(u8, key), try allocator.dupe(u8, scopes_val.object.get(key).?.string));
            }
        }
        return AuthorizationCodeOAuthFlow{
            .authorizationUrl = try allocator.dupe(u8, obj.get("authorizationUrl").?.string),
            .tokenUrl = try allocator.dupe(u8, obj.get("token").?.string),
            .scopes = scopes_map,
            .refreshUrl = if (obj.get("refreshUrl")) |val| try allocator.dupe(u8, val.string) else null,
        };
    }
};

pub const Link = struct {
    operationId: ?[]const u8 = null,
    operationRef: ?[]const u8 = null,
    parameters: ?std.StringHashMap(json.Value) = null, // Can be any type
    requestBody: ?json.Value = null, // Can be any type
    description: ?[]const u8 = null,
    server: ?Server = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!Link {
        const obj = value.object;
        var parameters_map = std.StringHashMap(json.Value).init(allocator);
        if (obj.get("parameters")) |params_val| {
            for (params_val.object.keys()) |key| {
                try parameters_map.put(key, params_val.object.get(key).?);
            }
        }
        return Link{
            .operationId = if (obj.get("operationId")) |val| try allocator.dupe(u8, val.string) else null,
            .operationRef = if (obj.get("operationRef")) |val| try allocator.dupe(u8, val.string) else null,
            .parameters = if (parameters_map.count() > 0) parameters_map else null,
            .requestBody = if (obj.get("requestBody")) |val| val else null,
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
            .server = if (obj.get("server")) |val| try Server.parse(allocator, val) else null,
        };
    }
};

pub const Callback = struct {
    path_items: std.StringHashMap(PathItem),

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!Callback {
        var path_items_map = std.StringHashMap(PathItem).init(allocator);
        const obj = value.object;
        for (obj.keys()) |key| {
            // Assuming keys are path items, e.g., "$request.body#/url"
            try path_items_map.put(key, try PathItem.parse(allocator, obj.get(key).?));
        }
        return Callback{ .path_items = path_items_map };
    }
};

pub const Encoding = struct {
    contentType: ?[]const u8 = null,
    headers: ?std.StringHashMap(HeaderOrReference) = null,
    style: ?[]const u8 = null, // "form", "spaceDelimited", "pipeDelimited", "deepObject"
    explode: ?bool = null,
    allowReserved: ?bool = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!Encoding {
        const obj = value.object;
        var headers_map = std.StringHashMap(HeaderOrReference).init(allocator);
        if (obj.get("headers")) |headers_val| {
            for (headers_val.object.keys()) |key| {
                try headers_map.put(key, try HeaderOrReference.parse(allocator, headers_val.object.get(key).?));
            }
        }
        return Encoding{
            .contentType = if (obj.get("contentType")) |val| try allocator.dupe(u8, val.string) else null,
            .headers = if (headers_map.count() > 0) headers_map else null,
            .style = if (obj.get("style")) |val| try allocator.dupe(u8, val.string) else null,
            .explode = if (obj.get("explode")) |val| val.bool else null,
            .allowReserved = if (obj.get("allowReserved")) |val| val.bool else null,
        };
    }
};
