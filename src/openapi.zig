//! OpenAPI v3.0 Specification Data Structures
//! Implementation based on the official OpenAPI v3.0 JSON Schema
//! https://spec.openapis.org/oas/3.0/schema/2024-10-18

const std = @import("std");
const json = std.json;

/// Root OpenAPI Document Object
/// This is the root document object of the OpenAPI document.
pub const OpenAPI = struct {
    /// REQUIRED. This string MUST be the semantic version number of the OpenAPI Specification version
    /// that the OpenAPI document uses. The openapi field SHOULD be used by tooling specifications
    /// and clients to interpret the OpenAPI document.
    openapi: []const u8,
    
    /// REQUIRED. Provides metadata about the API.
    info: Info,
    
    /// REQUIRED. The available paths and operations for the API.
    paths: Paths,
    
    /// Additional metadata.
    externalDocs: ?ExternalDocumentation = null,
    
    /// An array of Server Objects, which provide connectivity information to a target server.
    servers: ?[]const Server = null,
    
    /// A declaration of which security mechanisms can be used across the API.
    security: ?[]const SecurityRequirement = null,
    
    /// A list of tags used by the specification with additional metadata.
    tags: ?[]const Tag = null,
    
    /// An element to hold various schemas for the specification.
    components: ?Components = null,

    pub fn parse(allocator: std.mem.Allocator, json_string: []const u8) !OpenAPI {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        var parsed = try json.parseFromSlice(json.Value, arena_allocator, json_string, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        const root = parsed.value.object;
        
        const info = try Info.parse(root.get("info").?);
        const paths = try Paths.parse(allocator, root.get("paths").?);
        
        var servers: ?[]const Server = null;
        if (root.get("servers")) |servers_val| {
            servers = try parseServers(allocator, servers_val);
        }
        
        var security: ?[]const SecurityRequirement = null;
        if (root.get("security")) |security_val| {
            security = try parseSecurityRequirements(allocator, security_val);
        }
        
        var tags: ?[]const Tag = null;
        if (root.get("tags")) |tags_val| {
            tags = try parseTags(allocator, tags_val);
        }
        
        var components: ?Components = null;
        if (root.get("components")) |components_val| {
            components = try Components.parse(allocator, components_val);
        }
        
        var externalDocs: ?ExternalDocumentation = null;
        if (root.get("externalDocs")) |external_docs_val| {
            externalDocs = try ExternalDocumentation.parse(external_docs_val);
        }

        return OpenAPI{
            .openapi = root.get("openapi").?.string,
            .info = info,
            .paths = paths,
            .externalDocs = externalDocs,
            .servers = servers,
            .security = security,
            .tags = tags,
            .components = components,
        };
    }

    fn parseServers(allocator: std.mem.Allocator, value: json.Value) ![]const Server {
        var servers_list = std.ArrayList(Server).init(allocator);
        for (value.array.items) |item| {
            try servers_list.append(try Server.parse(allocator, item));
        }
        return servers_list.items;
    }

    fn parseSecurityRequirements(allocator: std.mem.Allocator, value: json.Value) ![]const SecurityRequirement {
        var security_list = std.ArrayList(SecurityRequirement).init(allocator);
        for (value.array.items) |item| {
            try security_list.append(try SecurityRequirement.parse(allocator, item));
        }
        return security_list.items;
    }

    fn parseTags(allocator: std.mem.Allocator, value: json.Value) ![]const Tag {
        var tags_list = std.ArrayList(Tag).init(allocator);
        for (value.array.items) |item| {
            try tags_list.append(try Tag.parse(item));
        }
        return tags_list.items;
    }
};

/// Info Object
/// The object provides metadata about the API.
pub const Info = struct {
    /// REQUIRED. The title of the API.
    title: []const u8,
    
    /// REQUIRED. The version of the OpenAPI document.
    version: []const u8,
    
    /// A short description of the API.
    description: ?[]const u8 = null,
    
    /// A URL to the Terms of Service for the API.
    termsOfService: ?[]const u8 = null,
    
    /// The contact information for the exposed API.
    contact: ?Contact = null,
    
    /// The license information for the exposed API.
    license: ?License = null,

    pub fn parse(value: json.Value) !Info {
        const obj = value.object;
        return Info{
            .title = obj.get("title").?.string,
            .version = obj.get("version").?.string,
            .description = if (obj.get("description")) |val| val.string else null,
            .termsOfService = if (obj.get("termsOfService")) |val| val.string else null,
            .contact = if (obj.get("contact")) |val| try Contact.parse(val) else null,
            .license = if (obj.get("license")) |val| try License.parse(val) else null,
        };
    }
};

/// Contact Object
/// Contact information for the exposed API.
pub const Contact = struct {
    /// The identifying name of the contact person/organization.
    name: ?[]const u8 = null,
    
    /// The URL pointing to the contact information.
    url: ?[]const u8 = null,
    
    /// The email address of the contact person/organization.
    email: ?[]const u8 = null,

    pub fn parse(value: json.Value) !Contact {
        const obj = value.object;
        return Contact{
            .name = if (obj.get("name")) |val| val.string else null,
            .url = if (obj.get("url")) |val| val.string else null,
            .email = if (obj.get("email")) |val| val.string else null,
        };
    }
};

/// License Object
/// License information for the exposed API.
pub const License = struct {
    /// REQUIRED. The license name used for the API.
    name: []const u8,
    
    /// A URL to the license used for the API.
    url: ?[]const u8 = null,

    pub fn parse(value: json.Value) !License {
        const obj = value.object;
        return License{
            .name = obj.get("name").?.string,
            .url = if (obj.get("url")) |val| val.string else null,
        };
    }
};

/// Server Object
/// An object representing a Server.
pub const Server = struct {
    /// REQUIRED. A URL to the target host.
    url: []const u8,
    
    /// An optional string describing the host designated by the URL.
    description: ?[]const u8 = null,
    
    /// A map between a variable name and its value.
    variables: ?std.StringHashMap(ServerVariable) = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !Server {
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

/// Server Variable Object
/// An object representing a Server Variable for server URL template substitution.
pub const ServerVariable = struct {
    /// REQUIRED. The default value to use for substitution.
    default: []const u8,
    
    /// An enumeration of string values to be used if the substitution options are from a limited set.
    @"enum": ?[]const []const u8 = null,
    
    /// An optional description for the server variable.
    description: ?[]const u8 = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !ServerVariable {
        const obj = value.object;
        var enum_list = std.ArrayList([]const u8).init(allocator);
        
        if (obj.get("enum")) |enum_val| {
            for (enum_val.array.items) |item| {
                try enum_list.append(item.string);
            }
        }

        return ServerVariable{
            .default = obj.get("default").?.string,
            .@"enum" = if (enum_list.items.len > 0) enum_list.items else null,
            .description = if (obj.get("description")) |val| val.string else null,
        };
    }
};

/// External Documentation Object
/// Allows referencing an external document for extended documentation.
pub const ExternalDocumentation = struct {
    /// REQUIRED. The URL for the target documentation.
    url: []const u8,
    
    /// A short description of the target documentation.
    description: ?[]const u8 = null,

    pub fn parse(value: json.Value) !ExternalDocumentation {
        const obj = value.object;
        return ExternalDocumentation{
            .url = obj.get("url").?.string,
            .description = if (obj.get("description")) |val| val.string else null,
        };
    }
};

/// Tag Object
/// Adds metadata to a single tag that is used by the Operation Object.
pub const Tag = struct {
    /// REQUIRED. The name of the tag.
    name: []const u8,
    
    /// A short description for the tag.
    description: ?[]const u8 = null,
    
    /// Additional external documentation for this tag.
    externalDocs: ?ExternalDocumentation = null,

    pub fn parse(value: json.Value) !Tag {
        const obj = value.object;
        return Tag{
            .name = obj.get("name").?.string,
            .description = if (obj.get("description")) |val| val.string else null,
            .externalDocs = if (obj.get("externalDocs")) |val| try ExternalDocumentation.parse(val) else null,
        };
    }
};

/// Reference Object
/// A simple object to allow referencing other components in the specification, internally and externally.
pub const Reference = struct {
    /// REQUIRED. The reference string.
    @"$ref": []const u8,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !Reference {
        _ = allocator; // suppress unused variable warning
        const obj = value.object;
        return Reference{
            .@"$ref" = obj.get("$ref").?.string,
        };
    }
};

/// Paths Object
/// Holds the relative paths to the individual endpoints and their operations.
pub const Paths = struct {
    /// A map of path items keyed by their path.
    paths: std.StringHashMap(PathItem),

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !Paths {
        var paths_map = std.StringHashMap(PathItem).init(allocator);
        const obj = value.object;
        
        for (obj.keys()) |key| {
            // Skip extension fields (x-*)
            if (std.mem.startsWith(u8, key, "x-")) continue;
            try paths_map.put(key, try PathItem.parse(allocator, obj.get(key).?));
        }
        
        return Paths{ .paths = paths_map };
    }
};

/// Path Item Object
/// Describes the operations available on a single path.
pub const PathItem = struct {
    /// An optional, string summary, intended to apply to all operations in this path.
    summary: ?[]const u8 = null,
    
    /// An optional, string description, intended to apply to all operations in this path.
    description: ?[]const u8 = null,
    
    /// A definition of a GET operation on this path.
    get: ?Operation = null,
    
    /// A definition of a PUT operation on this path.
    put: ?Operation = null,
    
    /// A definition of a POST operation on this path.
    post: ?Operation = null,
    
    /// A definition of a DELETE operation on this path.
    delete: ?Operation = null,
    
    /// A definition of a OPTIONS operation on this path.
    options: ?Operation = null,
    
    /// A definition of a HEAD operation on this path.
    head: ?Operation = null,
    
    /// A definition of a PATCH operation on this path.
    patch: ?Operation = null,
    
    /// A definition of a TRACE operation on this path.
    trace: ?Operation = null,
    
    /// An alternative server array to service all operations in this path.
    servers: ?[]const Server = null,
    
    /// A list of parameters that are applicable for all the operations in this path.
    parameters: ?[]const ParameterOrReference = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !PathItem {
        const obj = value.object;
        
        var servers: ?[]const Server = null;
        if (obj.get("servers")) |servers_val| {
            servers = try parseServers(allocator, servers_val);
        }
        
        var parameters: ?[]const ParameterOrReference = null;
        if (obj.get("parameters")) |params_val| {
            parameters = try parseParametersOrReferences(allocator, params_val);
        }
        
        return PathItem{
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
            .servers = servers,
            .parameters = parameters,
        };
    }

    fn parseServers(allocator: std.mem.Allocator, value: json.Value) ![]const Server {
        var servers_list = std.ArrayList(Server).init(allocator);
        for (value.array.items) |item| {
            try servers_list.append(try Server.parse(allocator, item));
        }
        return servers_list.items;
    }

    fn parseParametersOrReferences(allocator: std.mem.Allocator, value: json.Value) ![]const ParameterOrReference {
        var params_list = std.ArrayList(ParameterOrReference).init(allocator);
        for (value.array.items) |item| {
            try params_list.append(try ParameterOrReference.parse(allocator, item));
        }
        return params_list.items;
    }
};

/// Operation Object
/// Describes a single API operation on a path.
pub const Operation = struct {
    /// A list of tags for API documentation control.
    tags: ?[]const []const u8 = null,
    
    /// A short summary of what the operation does.
    summary: ?[]const u8 = null,
    
    /// A verbose explanation of the operation behavior.
    description: ?[]const u8 = null,
    
    /// Additional external documentation for this operation.
    externalDocs: ?ExternalDocumentation = null,
    
    /// Unique string used to identify the operation.
    operationId: ?[]const u8 = null,
    
    /// A list of parameters that are applicable for this operation.
    parameters: ?[]const ParameterOrReference = null,
    
    /// The request body applicable for this operation.
    requestBody: ?RequestBodyOrReference = null,
    
    /// REQUIRED. The list of possible responses as they are returned from executing this operation.
    responses: Responses,
    
    /// A map of possible out-of band callbacks related to the parent operation.
    callbacks: ?std.StringHashMap(CallbackOrReference) = null,
    
    /// Declares this operation to be deprecated.
    deprecated: ?bool = null,
    
    /// A declaration of which security mechanisms can be used for this operation.
    security: ?[]const SecurityRequirement = null,
    
    /// An alternative server array to service this operation.
    servers: ?[]const Server = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !Operation {
        const obj = value.object;
        
        var tags: ?[]const []const u8 = null;
        if (obj.get("tags")) |tags_val| {
            var tags_list = std.ArrayList([]const u8).init(allocator);
            for (tags_val.array.items) |item| {
                try tags_list.append(item.string);
            }
            tags = tags_list.items;
        }
        
        var parameters: ?[]const ParameterOrReference = null;
        if (obj.get("parameters")) |params_val| {
            var params_list = std.ArrayList(ParameterOrReference).init(allocator);
            for (params_val.array.items) |item| {
                try params_list.append(try ParameterOrReference.parse(allocator, item));
            }
            parameters = params_list.items;
        }
        
        var callbacks: ?std.StringHashMap(CallbackOrReference) = null;
        if (obj.get("callbacks")) |callbacks_val| {
            var callbacks_map = std.StringHashMap(CallbackOrReference).init(allocator);
            for (callbacks_val.object.keys()) |key| {
                try callbacks_map.put(key, try CallbackOrReference.parse(allocator, callbacks_val.object.get(key).?));
            }
            callbacks = callbacks_map;
        }
        
        var security: ?[]const SecurityRequirement = null;
        if (obj.get("security")) |security_val| {
            var security_list = std.ArrayList(SecurityRequirement).init(allocator);
            for (security_val.array.items) |item| {
                try security_list.append(try SecurityRequirement.parse(allocator, item));
            }
            security = security_list.items;
        }
        
        var servers: ?[]const Server = null;
        if (obj.get("servers")) |servers_val| {
            var servers_list = std.ArrayList(Server).init(allocator);
            for (servers_val.array.items) |item| {
                try servers_list.append(try Server.parse(allocator, item));
            }
            servers = servers_list.items;
        }
        
        const responses = try Responses.parse(allocator, obj.get("responses").?);
        
        return Operation{
            .tags = tags,
            .summary = if (obj.get("summary")) |val| val.string else null,
            .description = if (obj.get("description")) |val| val.string else null,
            .externalDocs = if (obj.get("externalDocs")) |val| try ExternalDocumentation.parse(val) else null,
            .operationId = if (obj.get("operationId")) |val| val.string else null,
            .parameters = parameters,
            .requestBody = if (obj.get("requestBody")) |val| try RequestBodyOrReference.parse(allocator, val) else null,
            .responses = responses,
            .callbacks = callbacks,
            .deprecated = if (obj.get("deprecated")) |val| val.bool else null,
            .security = security,
            .servers = servers,
        };
    }
};

/// Security Requirement Object
/// Lists the required security schemes to execute this operation.
pub const SecurityRequirement = struct {
    /// Each name MUST correspond to a security scheme which is declared in the Security Schemes.
    schemes: std.StringHashMap([]const []const u8),

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !SecurityRequirement {
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

/// Components Object
/// Holds a set of reusable objects for different aspects of the OAS.
pub const Components = struct {
    /// An object to hold reusable Schema Objects.
    schemas: ?std.StringHashMap(SchemaOrReference) = null,
    
    /// An object to hold reusable Response Objects.
    responses: ?std.StringHashMap(ResponseOrReference) = null,
    
    /// An object to hold reusable Parameter Objects.
    parameters: ?std.StringHashMap(ParameterOrReference) = null,
    
    /// An object to hold reusable Example Objects.
    examples: ?std.StringHashMap(ExampleOrReference) = null,
    
    /// An object to hold reusable Request Body Objects.
    requestBodies: ?std.StringHashMap(RequestBodyOrReference) = null,
    
    /// An object to hold reusable Header Objects.
    headers: ?std.StringHashMap(HeaderOrReference) = null,
    
    /// An object to hold reusable Security Scheme Objects.
    securitySchemes: ?std.StringHashMap(SecuritySchemeOrReference) = null,
    
    /// An object to hold reusable Link Objects.
    links: ?std.StringHashMap(LinkOrReference) = null,
    
    /// An object to hold reusable Callback Objects.
    callbacks: ?std.StringHashMap(CallbackOrReference) = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !Components {
        const obj = value.object;
        
        var schemas: ?std.StringHashMap(SchemaOrReference) = null;
        if (obj.get("schemas")) |schemas_val| {
            var schemas_map = std.StringHashMap(SchemaOrReference).init(allocator);
            for (schemas_val.object.keys()) |key| {
                try schemas_map.put(key, try SchemaOrReference.parse(allocator, schemas_val.object.get(key).?));
            }
            schemas = schemas_map;
        }
        
        var responses: ?std.StringHashMap(ResponseOrReference) = null;
        if (obj.get("responses")) |responses_val| {
            var responses_map = std.StringHashMap(ResponseOrReference).init(allocator);
            for (responses_val.object.keys()) |key| {
                try responses_map.put(key, try ResponseOrReference.parse(allocator, responses_val.object.get(key).?));
            }
            responses = responses_map;
        }
        
        var parameters: ?std.StringHashMap(ParameterOrReference) = null;
        if (obj.get("parameters")) |parameters_val| {
            var parameters_map = std.StringHashMap(ParameterOrReference).init(allocator);
            for (parameters_val.object.keys()) |key| {
                try parameters_map.put(key, try ParameterOrReference.parse(allocator, parameters_val.object.get(key).?));
            }
            parameters = parameters_map;
        }
        
        var examples: ?std.StringHashMap(ExampleOrReference) = null;
        if (obj.get("examples")) |examples_val| {
            var examples_map = std.StringHashMap(ExampleOrReference).init(allocator);
            for (examples_val.object.keys()) |key| {
                try examples_map.put(key, try ExampleOrReference.parse(allocator, examples_val.object.get(key).?));
            }
            examples = examples_map;
        }
        
        var requestBodies: ?std.StringHashMap(RequestBodyOrReference) = null;
        if (obj.get("requestBodies")) |request_bodies_val| {
            var request_bodies_map = std.StringHashMap(RequestBodyOrReference).init(allocator);
            for (request_bodies_val.object.keys()) |key| {
                try request_bodies_map.put(key, try RequestBodyOrReference.parse(allocator, request_bodies_val.object.get(key).?));
            }
            requestBodies = request_bodies_map;
        }
        
        var headers: ?std.StringHashMap(HeaderOrReference) = null;
        if (obj.get("headers")) |headers_val| {
            var headers_map = std.StringHashMap(HeaderOrReference).init(allocator);
            for (headers_val.object.keys()) |key| {
                try headers_map.put(key, try HeaderOrReference.parse(allocator, headers_val.object.get(key).?));
            }
            headers = headers_map;
        }
        
        var securitySchemes: ?std.StringHashMap(SecuritySchemeOrReference) = null;
        if (obj.get("securitySchemes")) |security_schemes_val| {
            var security_schemes_map = std.StringHashMap(SecuritySchemeOrReference).init(allocator);
            for (security_schemes_val.object.keys()) |key| {
                try security_schemes_map.put(key, try SecuritySchemeOrReference.parse(allocator, security_schemes_val.object.get(key).?));
            }
            securitySchemes = security_schemes_map;
        }
        
        var links: ?std.StringHashMap(LinkOrReference) = null;
        if (obj.get("links")) |links_val| {
            var links_map = std.StringHashMap(LinkOrReference).init(allocator);
            for (links_val.object.keys()) |key| {
                try links_map.put(key, try LinkOrReference.parse(allocator, links_val.object.get(key).?));
            }
            links = links_map;
        }
        
        var callbacks: ?std.StringHashMap(CallbackOrReference) = null;
        if (obj.get("callbacks")) |callbacks_val| {
            var callbacks_map = std.StringHashMap(CallbackOrReference).init(allocator);
            for (callbacks_val.object.keys()) |key| {
                try callbacks_map.put(key, try CallbackOrReference.parse(allocator, callbacks_val.object.get(key).?));
            }
            callbacks = callbacks_map;
        }
        
        return Components{
            .schemas = schemas,
            .responses = responses,
            .parameters = parameters,
            .examples = examples,
            .requestBodies = requestBodies,
            .headers = headers,
            .securitySchemes = securitySchemes,
            .links = links,
            .callbacks = callbacks,
        };
    }
};

/// Schema or Reference union type
pub const SchemaOrReference = union(enum) {
    schema: Schema,
    reference: Reference,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !SchemaOrReference {
        if (value.object.get("$ref") != null) {
            return SchemaOrReference{ .reference = try Reference.parse(allocator, value) };
        } else {
            return SchemaOrReference{ .schema = try Schema.parse(allocator, value) };
        }
    }
};

/// Additional Properties
/// Can be either a boolean or a schema.
pub const AdditionalProperties = union(enum) {
    boolean: bool,
    schema: SchemaOrReference,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !AdditionalProperties {
        switch (value) {
            .bool => |bool_val| return AdditionalProperties{ .boolean = bool_val },
            .object => return AdditionalProperties{ .schema = try SchemaOrReference.parse(allocator, value) },
            else => return error.InvalidAdditionalProperties,
        }
    }
};

/// Schema Object
/// The Schema Object allows the definition of input and output data types.
pub const Schema = struct {
    /// The title of the schema.
    title: ?[]const u8 = null,
    
    /// Value must be a multiple of this.
    multipleOf: ?f64 = null,
    
    /// Maximum value for a numeric instance.
    maximum: ?f64 = null,
    
    /// Whether maximum is exclusive.
    exclusiveMaximum: ?bool = null,
    
    /// Minimum value for a numeric instance.
    minimum: ?f64 = null,
    
    /// Whether minimum is exclusive.
    exclusiveMinimum: ?bool = null,
    
    /// Maximum length of a string instance.
    maxLength: ?i64 = null,
    
    /// Minimum length of a string instance.
    minLength: ?i64 = null,
    
    /// Regular expression pattern.
    pattern: ?[]const u8 = null,
    
    /// Maximum number of items in an array instance.
    maxItems: ?i64 = null,
    
    /// Minimum number of items in an array instance.
    minItems: ?i64 = null,
    
    /// Whether items in array must be unique.
    uniqueItems: ?bool = null,
    
    /// Maximum number of properties in an object instance.
    maxProperties: ?i64 = null,
    
    /// Minimum number of properties in an object instance.
    minProperties: ?i64 = null,
    
    /// List of required properties.
    required: ?[]const []const u8 = null,
    
    /// Enumeration of possible values.
    @"enum": ?[]const json.Value = null,
    
    /// Type of the instance.
    type: ?[]const u8 = null,
    
    /// Schema that the instance must not validate against.
    not: ?*SchemaOrReference = null,
    
    /// Instance must validate against all schemas.
    allOf: ?[]const SchemaOrReference = null,
    
    /// Instance must validate against exactly one schema.
    oneOf: ?[]const SchemaOrReference = null,
    
    /// Instance must validate against any schemas.
    anyOf: ?[]const SchemaOrReference = null,
    
    /// Schema for array items.
    items: ?*SchemaOrReference = null,
    
    /// Schemas for object properties.
    properties: ?std.StringHashMap(SchemaOrReference) = null,
    
    /// Schema for additional properties.
    additionalProperties: ?AdditionalProperties = null,
    
    /// Description of the schema.
    description: ?[]const u8 = null,
    
    /// Format of the string.
    format: ?[]const u8 = null,
    
    /// Default value.
    default: ?json.Value = null,
    
    /// Whether the value can be null.
    nullable: ?bool = null,
    
    /// Discriminator for inheritance.
    discriminator: ?Discriminator = null,
    
    /// Whether the property is read-only.
    readOnly: ?bool = null,
    
    /// Whether the property is write-only.
    writeOnly: ?bool = null,
    
    /// Example value.
    example: ?json.Value = null,
    
    /// External documentation.
    externalDocs: ?ExternalDocumentation = null,
    
    /// Whether the schema is deprecated.
    deprecated: ?bool = null,
    
    /// XML metadata.
    xml: ?XML = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !Schema {
        const obj = value.object;
        
        var required: ?[]const []const u8 = null;
        if (obj.get("required")) |required_val| {
            var required_list = std.ArrayList([]const u8).init(allocator);
            for (required_val.array.items) |item| {
                try required_list.append(item.string);
            }
            required = required_list.items;
        }
        
        var enum_values: ?[]const json.Value = null;
        if (obj.get("enum")) |enum_val| {
            var enum_list = std.ArrayList(json.Value).init(allocator);
            for (enum_val.array.items) |item| {
                try enum_list.append(item);
            }
            enum_values = enum_list.items;
        }
        
        var allOf: ?[]const SchemaOrReference = null;
        if (obj.get("allOf")) |all_of_val| {
            var all_of_list = std.ArrayList(SchemaOrReference).init(allocator);
            for (all_of_val.array.items) |item| {
                try all_of_list.append(try SchemaOrReference.parse(allocator, item));
            }
            allOf = all_of_list.items;
        }
        
        var oneOf: ?[]const SchemaOrReference = null;
        if (obj.get("oneOf")) |one_of_val| {
            var one_of_list = std.ArrayList(SchemaOrReference).init(allocator);
            for (one_of_val.array.items) |item| {
                try one_of_list.append(try SchemaOrReference.parse(allocator, item));
            }
            oneOf = one_of_list.items;
        }
        
        var anyOf: ?[]const SchemaOrReference = null;
        if (obj.get("anyOf")) |any_of_val| {
            var any_of_list = std.ArrayList(SchemaOrReference).init(allocator);
            for (any_of_val.array.items) |item| {
                try any_of_list.append(try SchemaOrReference.parse(allocator, item));
            }
            anyOf = any_of_list.items;
        }
        
        var properties: ?std.StringHashMap(SchemaOrReference) = null;
        if (obj.get("properties")) |props_val| {
            var properties_map = std.StringHashMap(SchemaOrReference).init(allocator);
            for (props_val.object.keys()) |key| {
                try properties_map.put(key, try SchemaOrReference.parse(allocator, props_val.object.get(key).?));
            }
            properties = properties_map;
        }
        
        var not_schema: ?*SchemaOrReference = null;
        if (obj.get("not")) |not_val| {
            const not_ptr = try allocator.create(SchemaOrReference);
            not_ptr.* = try SchemaOrReference.parse(allocator, not_val);
            not_schema = not_ptr;
        }
        
        var items_schema: ?*SchemaOrReference = null;
        if (obj.get("items")) |items_val| {
            const items_ptr = try allocator.create(SchemaOrReference);
            items_ptr.* = try SchemaOrReference.parse(allocator, items_val);
            items_schema = items_ptr;
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
            .required = required,
            .@"enum" = enum_values,
            .type = if (obj.get("type")) |val| val.string else null,
            .not = not_schema,
            .allOf = allOf,
            .oneOf = oneOf,
            .anyOf = anyOf,
            .items = items_schema,
            .properties = properties,
            .additionalProperties = if (obj.get("additionalProperties")) |val| try AdditionalProperties.parse(allocator, val) else null,
            .description = if (obj.get("description")) |val| val.string else null,
            .format = if (obj.get("format")) |val| val.string else null,
            .default = if (obj.get("default")) |val| val else null,
            .nullable = if (obj.get("nullable")) |val| val.bool else null,
            .discriminator = if (obj.get("discriminator")) |val| try Discriminator.parse(allocator, val) else null,
            .readOnly = if (obj.get("readOnly")) |val| val.bool else null,
            .writeOnly = if (obj.get("writeOnly")) |val| val.bool else null,
            .example = if (obj.get("example")) |val| val else null,
            .externalDocs = if (obj.get("externalDocs")) |val| try ExternalDocumentation.parse(val) else null,
            .deprecated = if (obj.get("deprecated")) |val| val.bool else null,
            .xml = if (obj.get("xml")) |val| try XML.parse(val) else null,
        };
    }
};

/// Discriminator Object
/// When request bodies or response payloads may be one of a number of different schemas,
/// a discriminator object can be used to aid in serialization, deserialization, and validation.
pub const Discriminator = struct {
    /// REQUIRED. The name of the property in the payload that will hold the discriminator value.
    propertyName: []const u8,
    
    /// An object to hold mappings between payload values and schema names or references.
    mapping: ?std.StringHashMap([]const u8) = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !Discriminator {
        const obj = value.object;
        
        var mapping: ?std.StringHashMap([]const u8) = null;
        if (obj.get("mapping")) |mapping_val| {
            var mapping_map = std.StringHashMap([]const u8).init(allocator);
            for (mapping_val.object.keys()) |key| {
                try mapping_map.put(key, mapping_val.object.get(key).?.string);
            }
            mapping = mapping_map;
        }
        
        return Discriminator{
            .propertyName = obj.get("propertyName").?.string,
            .mapping = mapping,
        };
    }
};

/// XML Object
/// A metadata object that allows for more fine-tuned XML model definitions.
pub const XML = struct {
    /// Replaces the name of the element/attribute used for the described schema property.
    name: ?[]const u8 = null,
    
    /// The URI of the namespace definition.
    namespace: ?[]const u8 = null,
    
    /// The prefix to be used for the name.
    prefix: ?[]const u8 = null,
    
    /// Declares whether the property definition translates to an attribute instead of an element.
    attribute: ?bool = null,
    
    /// MAY be used only for an array definition.
    wrapped: ?bool = null,

    pub fn parse(value: json.Value) !XML {
        const obj = value.object;
        return XML{
            .name = if (obj.get("name")) |val| val.string else null,
            .namespace = if (obj.get("namespace")) |val| val.string else null,
            .prefix = if (obj.get("prefix")) |val| val.string else null,
            .attribute = if (obj.get("attribute")) |val| val.bool else null,
            .wrapped = if (obj.get("wrapped")) |val| val.bool else null,
        };
    }
};

/// Response Object
/// Describes a single response from an API Operation.
pub const Response = struct {
    /// REQUIRED. A short description of the response.
    description: []const u8,
    
    /// Maps a header name to its definition.
    headers: ?std.StringHashMap(HeaderOrReference) = null,
    
    /// A map containing descriptions of potential response payloads.
    content: ?std.StringHashMap(MediaType) = null,
    
    /// A map of operations links that can be followed from the response.
    links: ?std.StringHashMap(LinkOrReference) = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !Response {
        const obj = value.object;
        
        var headers: ?std.StringHashMap(HeaderOrReference) = null;
        if (obj.get("headers")) |headers_val| {
            var headers_map = std.StringHashMap(HeaderOrReference).init(allocator);
            for (headers_val.object.keys()) |key| {
                try headers_map.put(key, try HeaderOrReference.parse(allocator, headers_val.object.get(key).?));
            }
            headers = headers_map;
        }
        
        var content: ?std.StringHashMap(MediaType) = null;
        if (obj.get("content")) |content_val| {
            var content_map = std.StringHashMap(MediaType).init(allocator);
            for (content_val.object.keys()) |key| {
                try content_map.put(key, try MediaType.parse(allocator, content_val.object.get(key).?));
            }
            content = content_map;
        }
        
        var links: ?std.StringHashMap(LinkOrReference) = null;
        if (obj.get("links")) |links_val| {
            var links_map = std.StringHashMap(LinkOrReference).init(allocator);
            for (links_val.object.keys()) |key| {
                try links_map.put(key, try LinkOrReference.parse(allocator, links_val.object.get(key).?));
            }
            links = links_map;
        }
        
        return Response{
            .description = obj.get("description").?.string,
            .headers = headers,
            .content = content,
            .links = links,
        };
    }
};

/// Responses Object
/// A container for the expected responses of an operation.
pub const Responses = struct {
    /// Any HTTP status code can be used as the property name.
    responses: std.StringHashMap(ResponseOrReference),
    
    /// The documentation of responses other than the ones declared for specific HTTP response codes.
    default: ?ResponseOrReference = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !Responses {
        const obj = value.object;
        var responses_map = std.StringHashMap(ResponseOrReference).init(allocator);
        
        var default_response: ?ResponseOrReference = null;
        
        for (obj.keys()) |key| {
            if (std.mem.eql(u8, key, "default")) {
                default_response = try ResponseOrReference.parse(allocator, obj.get(key).?);
            } else {
                try responses_map.put(key, try ResponseOrReference.parse(allocator, obj.get(key).?));
            }
        }
        
        return Responses{
            .responses = responses_map,
            .default = default_response,
        };
    }
};

/// Parameter Object
/// Describes a single operation parameter.
pub const Parameter = struct {
    /// REQUIRED. The name of the parameter.
    name: []const u8,
    
    /// REQUIRED. The location of the parameter.
    in: []const u8,
    
    /// A brief description of the parameter.
    description: ?[]const u8 = null,
    
    /// Determines whether this parameter is mandatory.
    required: ?bool = null,
    
    /// Specifies that a parameter is deprecated.
    deprecated: ?bool = null,
    
    /// Sets the ability to pass empty-valued parameters.
    allowEmptyValue: ?bool = null,
    
    /// Describes how the parameter value will be serialized.
    style: ?[]const u8 = null,
    
    /// When this is true, parameter values of type array or object generate separate parameters.
    explode: ?bool = null,
    
    /// Determines whether the parameter value SHOULD allow reserved characters.
    allowReserved: ?bool = null,
    
    /// The schema defining the type used for the parameter.
    schema: ?SchemaOrReference = null,
    
    /// Example of the parameter's potential value.
    example: ?json.Value = null,
    
    /// Examples of the parameter's potential value.
    examples: ?std.StringHashMap(ExampleOrReference) = null,
    
    /// A map containing the representations for the parameter.
    content: ?std.StringHashMap(MediaType) = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !Parameter {
        const obj = value.object;
        
        var examples: ?std.StringHashMap(ExampleOrReference) = null;
        if (obj.get("examples")) |examples_val| {
            var examples_map = std.StringHashMap(ExampleOrReference).init(allocator);
            for (examples_val.object.keys()) |key| {
                try examples_map.put(key, try ExampleOrReference.parse(allocator, examples_val.object.get(key).?));
            }
            examples = examples_map;
        }
        
        var content: ?std.StringHashMap(MediaType) = null;
        if (obj.get("content")) |content_val| {
            var content_map = std.StringHashMap(MediaType).init(allocator);
            for (content_val.object.keys()) |key| {
                try content_map.put(key, try MediaType.parse(allocator, content_val.object.get(key).?));
            }
            content = content_map;
        }
        
        return Parameter{
            .name = obj.get("name").?.string,
            .in = obj.get("in").?.string,
            .description = if (obj.get("description")) |val| val.string else null,
            .required = if (obj.get("required")) |val| val.bool else null,
            .deprecated = if (obj.get("deprecated")) |val| val.bool else null,
            .allowEmptyValue = if (obj.get("allowEmptyValue")) |val| val.bool else null,
            .style = if (obj.get("style")) |val| val.string else null,
            .explode = if (obj.get("explode")) |val| val.bool else null,
            .allowReserved = if (obj.get("allowReserved")) |val| val.bool else null,
            .schema = if (obj.get("schema")) |val| try SchemaOrReference.parse(allocator, val) else null,
            .example = if (obj.get("example")) |val| val else null,
            .examples = examples,
            .content = content,
        };
    }
};

/// Request Body Object
/// Describes a single request body.
pub const RequestBody = struct {
    /// A brief description of the request body.
    description: ?[]const u8 = null,
    
    /// REQUIRED. The content of the request body.
    content: std.StringHashMap(MediaType),
    
    /// Determines if the request body is required in the request.
    required: ?bool = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !RequestBody {
        const obj = value.object;
        var content_map = std.StringHashMap(MediaType).init(allocator);
        
        if (obj.get("content")) |content_val| {
            for (content_val.object.keys()) |key| {
                try content_map.put(key, try MediaType.parse(allocator, content_val.object.get(key).?));
            }
        }
        
        return RequestBody{
            .description = if (obj.get("description")) |val| val.string else null,
            .content = content_map,
            .required = if (obj.get("required")) |val| val.bool else null,
        };
    }
};

/// Media Type Object
/// Each Media Type Object provides schema and examples for the media type identified by its key.
pub const MediaType = struct {
    /// The schema defining the content of the request, response, or parameter.
    schema: ?SchemaOrReference = null,
    
    /// Example of the media type.
    example: ?json.Value = null,
    
    /// Examples of the media type.
    examples: ?std.StringHashMap(ExampleOrReference) = null,
    
    /// A map between a property name and its encoding information.
    encoding: ?std.StringHashMap(Encoding) = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !MediaType {
        const obj = value.object;
        
        var examples: ?std.StringHashMap(ExampleOrReference) = null;
        if (obj.get("examples")) |examples_val| {
            var examples_map = std.StringHashMap(ExampleOrReference).init(allocator);
            for (examples_val.object.keys()) |key| {
                try examples_map.put(key, try ExampleOrReference.parse(allocator, examples_val.object.get(key).?));
            }
            examples = examples_map;
        }
        
        var encoding: ?std.StringHashMap(Encoding) = null;
        if (obj.get("encoding")) |encoding_val| {
            var encoding_map = std.StringHashMap(Encoding).init(allocator);
            for (encoding_val.object.keys()) |key| {
                try encoding_map.put(key, try Encoding.parse(allocator, encoding_val.object.get(key).?));
            }
            encoding = encoding_map;
        }
        
        return MediaType{
            .schema = if (obj.get("schema")) |val| try SchemaOrReference.parse(allocator, val) else null,
            .example = if (obj.get("example")) |val| val else null,
            .examples = examples,
            .encoding = encoding,
        };
    }
};

/// Encoding Object
/// A single encoding definition applied to a single schema property.
pub const Encoding = struct {
    /// The Content-Type for encoding a specific property.
    contentType: ?[]const u8 = null,
    
    /// A map allowing additional information to be provided as headers.
    headers: ?std.StringHashMap(HeaderOrReference) = null,
    
    /// Describes how a specific property value will be serialized.
    style: ?[]const u8 = null,
    
    /// When this is true, property values of type array or object generate separate parameters.
    explode: ?bool = null,
    
    /// Determines whether the parameter value SHOULD allow reserved characters.
    allowReserved: ?bool = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !Encoding {
        const obj = value.object;
        
        var headers: ?std.StringHashMap(HeaderOrReference) = null;
        if (obj.get("headers")) |headers_val| {
            var headers_map = std.StringHashMap(HeaderOrReference).init(allocator);
            for (headers_val.object.keys()) |key| {
                try headers_map.put(key, try HeaderOrReference.parse(allocator, headers_val.object.get(key).?));
            }
            headers = headers_map;
        }
        
        return Encoding{
            .contentType = if (obj.get("contentType")) |val| val.string else null,
            .headers = headers,
            .style = if (obj.get("style")) |val| val.string else null,
            .explode = if (obj.get("explode")) |val| val.bool else null,
            .allowReserved = if (obj.get("allowReserved")) |val| val.bool else null,
        };
    }
};

/// Example Object
/// An object to hold examples of the representation.
pub const Example = struct {
    /// Short description for the example.
    summary: ?[]const u8 = null,
    
    /// Long description for the example.
    description: ?[]const u8 = null,
    
    /// Embedded literal example.
    value: ?json.Value = null,
    
    /// A URL that points to the literal example.
    externalValue: ?[]const u8 = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !Example {
        _ = allocator; // suppress unused variable warning
        const obj = value.object;
        return Example{
            .summary = if (obj.get("summary")) |val| val.string else null,
            .description = if (obj.get("description")) |val| val.string else null,
            .value = if (obj.get("value")) |val| val else null,
            .externalValue = if (obj.get("externalValue")) |val| val.string else null,
        };
    }
};

/// Header Object
/// The Header Object follows the structure of the Parameter Object.
pub const Header = struct {
    /// A brief description of the parameter.
    description: ?[]const u8 = null,
    
    /// Determines whether this parameter is mandatory.
    required: ?bool = null,
    
    /// Specifies that a parameter is deprecated.
    deprecated: ?bool = null,
    
    /// Sets the ability to pass empty-valued parameters.
    allowEmptyValue: ?bool = null,
    
    /// Describes how the parameter value will be serialized.
    style: ?[]const u8 = null,
    
    /// When this is true, parameter values of type array or object generate separate parameters.
    explode: ?bool = null,
    
    /// Determines whether the parameter value SHOULD allow reserved characters.
    allowReserved: ?bool = null,
    
    /// The schema defining the type used for the parameter.
    schema: ?SchemaOrReference = null,
    
    /// Example of the parameter's potential value.
    example: ?json.Value = null,
    
    /// Examples of the parameter's potential value.
    examples: ?std.StringHashMap(ExampleOrReference) = null,
    
    /// A map containing the representations for the parameter.
    content: ?std.StringHashMap(MediaType) = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !Header {
        const obj = value.object;
        
        var examples: ?std.StringHashMap(ExampleOrReference) = null;
        if (obj.get("examples")) |examples_val| {
            var examples_map = std.StringHashMap(ExampleOrReference).init(allocator);
            for (examples_val.object.keys()) |key| {
                try examples_map.put(key, try ExampleOrReference.parse(allocator, examples_val.object.get(key).?));
            }
            examples = examples_map;
        }
        
        var content: ?std.StringHashMap(MediaType) = null;
        if (obj.get("content")) |content_val| {
            var content_map = std.StringHashMap(MediaType).init(allocator);
            for (content_val.object.keys()) |key| {
                try content_map.put(key, try MediaType.parse(allocator, content_val.object.get(key).?));
            }
            content = content_map;
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
            .example = if (obj.get("example")) |val| val else null,
            .examples = examples,
            .content = content,
        };
    }
};

/// Security Scheme Object
/// Defines a security scheme that can be used by the operations.
pub const SecurityScheme = union(enum) {
    apiKey: ApiKeySecurityScheme,
    http: HttpSecurityScheme,
    oauth2: OAuth2SecurityScheme,
    openIdConnect: OpenIdConnectSecurityScheme,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !SecurityScheme {
        const obj = value.object;
        const scheme_type = obj.get("type").?.string;
        
        if (std.mem.eql(u8, scheme_type, "apiKey")) {
            return SecurityScheme{ .apiKey = try ApiKeySecurityScheme.parse(value) };
        } else if (std.mem.eql(u8, scheme_type, "http")) {
            return SecurityScheme{ .http = try HttpSecurityScheme.parse(value) };
        } else if (std.mem.eql(u8, scheme_type, "oauth2")) {
            return SecurityScheme{ .oauth2 = try OAuth2SecurityScheme.parse(allocator, value) };
        } else if (std.mem.eql(u8, scheme_type, "openIdConnect")) {
            return SecurityScheme{ .openIdConnect = try OpenIdConnectSecurityScheme.parse(value) };
        } else {
            return error.UnknownSecuritySchemeType;
        }
    }
};

/// API Key Security Scheme
pub const ApiKeySecurityScheme = struct {
    type: []const u8,
    name: []const u8,
    in: []const u8,
    description: ?[]const u8 = null,

    pub fn parse(value: json.Value) !ApiKeySecurityScheme {
        const obj = value.object;
        return ApiKeySecurityScheme{
            .type = obj.get("type").?.string,
            .name = obj.get("name").?.string,
            .in = obj.get("in").?.string,
            .description = if (obj.get("description")) |val| val.string else null,
        };
    }
};

/// HTTP Security Scheme
pub const HttpSecurityScheme = struct {
    type: []const u8,
    scheme: []const u8,
    bearerFormat: ?[]const u8 = null,
    description: ?[]const u8 = null,

    pub fn parse(value: json.Value) !HttpSecurityScheme {
        const obj = value.object;
        return HttpSecurityScheme{
            .type = obj.get("type").?.string,
            .scheme = obj.get("scheme").?.string,
            .bearerFormat = if (obj.get("bearerFormat")) |val| val.string else null,
            .description = if (obj.get("description")) |val| val.string else null,
        };
    }
};

/// OAuth2 Security Scheme
pub const OAuth2SecurityScheme = struct {
    type: []const u8,
    flows: OAuthFlows,
    description: ?[]const u8 = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !OAuth2SecurityScheme {
        const obj = value.object;
        return OAuth2SecurityScheme{
            .type = obj.get("type").?.string,
            .flows = try OAuthFlows.parse(allocator, obj.get("flows").?),
            .description = if (obj.get("description")) |val| val.string else null,
        };
    }
};

/// OpenID Connect Security Scheme
pub const OpenIdConnectSecurityScheme = struct {
    type: []const u8,
    openIdConnectUrl: []const u8,
    description: ?[]const u8 = null,

    pub fn parse(value: json.Value) !OpenIdConnectSecurityScheme {
        const obj = value.object;
        return OpenIdConnectSecurityScheme{
            .type = obj.get("type").?.string,
            .openIdConnectUrl = obj.get("openIdConnectUrl").?.string,
            .description = if (obj.get("description")) |val| val.string else null,
        };
    }
};

/// OAuth Flows Object
/// Allows configuration of the supported OAuth Flows.
pub const OAuthFlows = struct {
    implicit: ?ImplicitOAuthFlow = null,
    password: ?PasswordOAuthFlow = null,
    clientCredentials: ?ClientCredentialsOAuthFlow = null,
    authorizationCode: ?AuthorizationCodeOAuthFlow = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !OAuthFlows {
        const obj = value.object;
        return OAuthFlows{
            .implicit = if (obj.get("implicit")) |val| try ImplicitOAuthFlow.parse(allocator, val) else null,
            .password = if (obj.get("password")) |val| try PasswordOAuthFlow.parse(allocator, val) else null,
            .clientCredentials = if (obj.get("clientCredentials")) |val| try ClientCredentialsOAuthFlow.parse(allocator, val) else null,
            .authorizationCode = if (obj.get("authorizationCode")) |val| try AuthorizationCodeOAuthFlow.parse(allocator, val) else null,
        };
    }
};

/// Implicit OAuth Flow
pub const ImplicitOAuthFlow = struct {
    authorizationUrl: []const u8,
    refreshUrl: ?[]const u8 = null,
    scopes: std.StringHashMap([]const u8),

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !ImplicitOAuthFlow {
        const obj = value.object;
        var scopes_map = std.StringHashMap([]const u8).init(allocator);
        
        if (obj.get("scopes")) |scopes_val| {
            for (scopes_val.object.keys()) |key| {
                try scopes_map.put(key, scopes_val.object.get(key).?.string);
            }
        }
        
        return ImplicitOAuthFlow{
            .authorizationUrl = obj.get("authorizationUrl").?.string,
            .refreshUrl = if (obj.get("refreshUrl")) |val| val.string else null,
            .scopes = scopes_map,
        };
    }
};

/// Password OAuth Flow
pub const PasswordOAuthFlow = struct {
    tokenUrl: []const u8,
    refreshUrl: ?[]const u8 = null,
    scopes: std.StringHashMap([]const u8),

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !PasswordOAuthFlow {
        const obj = value.object;
        var scopes_map = std.StringHashMap([]const u8).init(allocator);
        
        if (obj.get("scopes")) |scopes_val| {
            for (scopes_val.object.keys()) |key| {
                try scopes_map.put(key, scopes_val.object.get(key).?.string);
            }
        }
        
        return PasswordOAuthFlow{
            .tokenUrl = obj.get("tokenUrl").?.string,
            .refreshUrl = if (obj.get("refreshUrl")) |val| val.string else null,
            .scopes = scopes_map,
        };
    }
};

/// Client Credentials OAuth Flow
pub const ClientCredentialsOAuthFlow = struct {
    tokenUrl: []const u8,
    refreshUrl: ?[]const u8 = null,
    scopes: std.StringHashMap([]const u8),

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !ClientCredentialsOAuthFlow {
        const obj = value.object;
        var scopes_map = std.StringHashMap([]const u8).init(allocator);
        
        if (obj.get("scopes")) |scopes_val| {
            for (scopes_val.object.keys()) |key| {
                try scopes_map.put(key, scopes_val.object.get(key).?.string);
            }
        }
        
        return ClientCredentialsOAuthFlow{
            .tokenUrl = obj.get("tokenUrl").?.string,
            .refreshUrl = if (obj.get("refreshUrl")) |val| val.string else null,
            .scopes = scopes_map,
        };
    }
};

/// Authorization Code OAuth Flow
pub const AuthorizationCodeOAuthFlow = struct {
    authorizationUrl: []const u8,
    tokenUrl: []const u8,
    refreshUrl: ?[]const u8 = null,
    scopes: std.StringHashMap([]const u8),

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !AuthorizationCodeOAuthFlow {
        const obj = value.object;
        var scopes_map = std.StringHashMap([]const u8).init(allocator);
        
        if (obj.get("scopes")) |scopes_val| {
            for (scopes_val.object.keys()) |key| {
                try scopes_map.put(key, scopes_val.object.get(key).?.string);
            }
        }
        
        return AuthorizationCodeOAuthFlow{
            .authorizationUrl = obj.get("authorizationUrl").?.string,
            .tokenUrl = obj.get("tokenUrl").?.string,
            .refreshUrl = if (obj.get("refreshUrl")) |val| val.string else null,
            .scopes = scopes_map,
        };
    }
};

/// Link Object
/// The Link object represents a possible design-time link for a response.
pub const Link = struct {
    /// A relative or absolute URI reference to an OAS operation.
    operationRef: ?[]const u8 = null,
    
    /// The name of an existing, resolvable OAS operation.
    operationId: ?[]const u8 = null,
    
    /// A map representing parameters to pass to an operation.
    parameters: ?std.StringHashMap(json.Value) = null,
    
    /// A literal value or expression to use as a request body.
    requestBody: ?json.Value = null,
    
    /// A description of the link.
    description: ?[]const u8 = null,
    
    /// A server object to be used by the target operation.
    server: ?Server = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !Link {
        const obj = value.object;
        
        var parameters: ?std.StringHashMap(json.Value) = null;
        if (obj.get("parameters")) |params_val| {
            var params_map = std.StringHashMap(json.Value).init(allocator);
            for (params_val.object.keys()) |key| {
                try params_map.put(key, params_val.object.get(key).?);
            }
            parameters = params_map;
        }
        
        return Link{
            .operationRef = if (obj.get("operationRef")) |val| val.string else null,
            .operationId = if (obj.get("operationId")) |val| val.string else null,
            .parameters = parameters,
            .requestBody = if (obj.get("requestBody")) |val| val else null,
            .description = if (obj.get("description")) |val| val.string else null,
            .server = if (obj.get("server")) |val| try Server.parse(allocator, val) else null,
        };
    }
};

/// Callback Object
/// A map of possible out-of band callbacks related to the parent operation.
pub const Callback = struct {
    /// A Path Item Object used to define a callback request and expected responses.
    pathItems: std.StringHashMap(PathItem),

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !Callback {
        var path_items_map = std.StringHashMap(PathItem).init(allocator);
        const obj = value.object;
        
        for (obj.keys()) |key| {
            try path_items_map.put(key, try PathItem.parse(allocator, obj.get(key).?));
        }
        
        return Callback{ .pathItems = path_items_map };
    }
};

// Union types for references

/// Response or Reference union type
pub const ResponseOrReference = union(enum) {
    response: Response,
    reference: Reference,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !ResponseOrReference {
        if (value.object.get("$ref") != null) {
            return ResponseOrReference{ .reference = try Reference.parse(allocator, value) };
        } else {
            return ResponseOrReference{ .response = try Response.parse(allocator, value) };
        }
    }
};

/// Parameter or Reference union type
pub const ParameterOrReference = union(enum) {
    parameter: Parameter,
    reference: Reference,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !ParameterOrReference {
        if (value.object.get("$ref") != null) {
            return ParameterOrReference{ .reference = try Reference.parse(allocator, value) };
        } else {
            return ParameterOrReference{ .parameter = try Parameter.parse(allocator, value) };
        }
    }
};

/// Example or Reference union type
pub const ExampleOrReference = union(enum) {
    example: Example,
    reference: Reference,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !ExampleOrReference {
        if (value.object.get("$ref") != null) {
            return ExampleOrReference{ .reference = try Reference.parse(allocator, value) };
        } else {
            return ExampleOrReference{ .example = try Example.parse(allocator, value) };
        }
    }
};

/// Request Body or Reference union type
pub const RequestBodyOrReference = union(enum) {
    requestBody: RequestBody,
    reference: Reference,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !RequestBodyOrReference {
        if (value.object.get("$ref") != null) {
            return RequestBodyOrReference{ .reference = try Reference.parse(allocator, value) };
        } else {
            return RequestBodyOrReference{ .requestBody = try RequestBody.parse(allocator, value) };
        }
    }
};

/// Header or Reference union type
pub const HeaderOrReference = union(enum) {
    header: Header,
    reference: Reference,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !HeaderOrReference {
        if (value.object.get("$ref") != null) {
            return HeaderOrReference{ .reference = try Reference.parse(allocator, value) };
        } else {
            return HeaderOrReference{ .header = try Header.parse(allocator, value) };
        }
    }
};

/// Security Scheme or Reference union type
pub const SecuritySchemeOrReference = union(enum) {
    securityScheme: SecurityScheme,
    reference: Reference,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !SecuritySchemeOrReference {
        if (value.object.get("$ref") != null) {
            return SecuritySchemeOrReference{ .reference = try Reference.parse(allocator, value) };
        } else {
            return SecuritySchemeOrReference{ .securityScheme = try SecurityScheme.parse(allocator, value) };
        }
    }
};

/// Link or Reference union type
pub const LinkOrReference = union(enum) {
    link: Link,
    reference: Reference,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !LinkOrReference {
        if (value.object.get("$ref") != null) {
            return LinkOrReference{ .reference = try Reference.parse(allocator, value) };
        } else {
            return LinkOrReference{ .link = try Link.parse(allocator, value) };
        }
    }
};

/// Callback or Reference union type
pub const CallbackOrReference = union(enum) {
    callback: Callback,
    reference: Reference,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) !CallbackOrReference {
        if (value.object.get("$ref") != null) {
            return CallbackOrReference{ .reference = try Reference.parse(allocator, value) };
        } else {
            return CallbackOrReference{ .callback = try Callback.parse(allocator, value) };
        }
    }
};