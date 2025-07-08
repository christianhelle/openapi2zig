const std = @import("std");

pub fn OrRef(comptime T: type) type {
    return union(enum) {
        value: T,
        ref: []const u8,
    };
}

pub const OpenApiDocument = struct {
    openapi: []const u8,
    info: Info,
    paths: std.json.Value, // This can be a map of path items
    externalDocs: ?ExternalDocumentation = null,
    servers: ?[]Server = null,
    security: ?[]SecurityRequirement = null,
    tags: ?[]Tag = null,
    components: ?Components = null,
};

pub const Info = struct {
    title: []const u8,
    description: ?[]const u8 = null,
    termsOfService: ?[]const u8 = null,
    contact: ?Contact = null,
    license: ?License = null,
    version: []const u8,
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

pub const Server = struct {
    url: []const u8,
    description: ?[]const u8 = null,
    variables: ?std.json.Value = null,
};

pub const ServerVariable = struct {
    @"enum": ?[]const []const u8 = null,
    default: []const u8,
    description: ?[]const u8 = null,
};

pub const Components = struct {
    schemas: ?std.json.Value = null,
    responses: ?std.json.Value = null,
    parameters: ?std.json.Value = null,
    examples: ?std.json.Value = null,
    requestBodies: ?std.json.Value = null,
    headers: ?std.json.Value = null,
    securitySchemes: ?std.json.Value = null,
    links: ?std.json.Value = null,
    callbacks: ?std.json.Value = null,
};

pub const Paths = struct {
    path: []const u8,
    get: ?std.json.Value = null,
};

pub const PathItem = struct {
    ref: ?[]const u8 = null,
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    //get: ?Operation = null,
    //put: ?Operation = null,
    //post: ?Operation = null,
    //delete: ?Operation = null,
    //options: ?Operation = null,
    //head: ?Operation = null,
    //patch: ?Operation = null,
    //trace: ?Operation = null,
    //servers: ?[]Server = null,
    //parameters: ?[]OrRef(Parameter) = null,
};

pub const Operation = struct {
    tags: ?[]const []const u8 = null,
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    //externalDocs: ?ExternalDocumentation = null,
    OpenApiDocumenterationId: ?[]const u8 = null,
    //parameters: ?[]OrRef(Parameter) = null,
    //requestBody: ?OrRef(RequestBody) = null,
    //responses: Responses,
    //callbacks: ?std.json.Value = null,
    //deprecated: bool = false,
    //security: ?[]SecurityRequirement = null,
    //servers: ?[]Server = null,
};

pub const Responses = struct {
    default: ?OrRef(Response) = null,
    pattern: ?std.json.Value = null,
};

pub const SecurityRequirement = std.json.Value;

pub const Tag = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    externalDocs: ?ExternalDocumentation = null,
};

pub const ExternalDocumentation = struct {
    description: ?[]const u8 = null,
    url: []const u8,
};

pub const Schema = struct {
    title: ?[]const u8 = null,
    multipleOf: ?f64 = null,
    maximum: ?f64 = null,
    exclusiveMaximum: bool = false,
    minimum: ?f64 = null,
    exclusiveMinimum: bool = false,
    maxLength: ?u64 = null,
    minLength: u64 = 0,
    pattern: ?[]const u8 = null,
    maxItems: ?u64 = null,
    minItems: u64 = 0,
    uniqueItems: bool = false,
    maxProperties: ?u64 = null,
    minProperties: u64 = 0,
    required: ?[]const []const u8 = null,
    @"enum": ?[]std.json.Value = null,
    type: ?[]const u8 = null,
    not: ?*OrRef(Schema) = null,
    allOf: ?[]OrRef(Schema) = null,
    oneOf: ?[]OrRef(Schema) = null,
    anyOf: ?[]OrRef(Schema) = null,
    items: ?*OrRef(Schema) = null,
    properties: ?std.json.Value = null,
    additionalProperties: ?union(enum) { boolean: bool, schema: *OrRef(Schema) } = .{ .boolean = true },
    description: ?[]const u8 = null,
    format: ?[]const u8 = null,
    default: ?std.json.Value = null,
    nullable: bool = false,
    discriminator: ?Discriminator = null,
    readOnly: bool = false,
    writeOnly: bool = false,
    example: ?std.json.Value = null,
    deprecated: bool = false,
    xml: ?XML = null,
};

pub const Discriminator = struct {
    propertyName: []const u8,
    mapping: ?std.json.Value = null,
};

pub const XML = struct {
    name: ?[]const u8 = null,
    namespace: ?[]const u8 = null,
    prefix: ?[]const u8 = null,
    attribute: bool = false,
    wrapped: bool = false,
};

pub const Response = struct {
    description: []const u8,
    headers: ?std.json.Value = null,
    content: ?std.json.Value = null,
    links: ?std.json.Value = null,
};

pub const MediaType = struct {
    schema: ?OrRef(Schema) = null,
    example: ?std.json.Value = null,
    examples: ?std.json.Value = null,
    encoding: ?std.json.Value = null,
};

pub const Example = struct {
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    value: ?std.json.Value = null,
    externalValue: ?[]const u8 = null,
};

pub const Header = struct {
    description: ?[]const u8 = null,
    required: bool = false,
    deprecated: bool = false,
    allowEmptyValue: bool = false,
    style: []const u8 = "simple",
    explode: ?bool = null,
    allowReserved: bool = false,
    schema: ?OrRef(Schema) = null,
    content: ?std.json.Value = null,
    example: ?std.json.Value = null,
    examples: ?std.json.Value = null,
};

pub const Encoding = struct {
    contentType: ?[]const u8 = null,
    headers: ?std.json.Value = null,
    style: ?[]const u8 = null,
    explode: ?bool = null,
    allowReserved: bool = false,
};

pub const Link = struct {
    operationId: ?[]const u8 = null,
    operationRef: ?[]const u8 = null,
    parameters: ?std.json.Value = null,
    requestBody: ?std.json.Value = null,
    description: ?[]const u8 = null,
    server: ?Server = null,
};

pub const Parameter = struct {
    name: []const u8,
    in: []const u8,
    description: ?[]const u8 = null,
    required: bool = false,
    deprecated: bool = false,
    allowEmptyValue: bool = false,
    style: ?[]const u8 = null,
    explode: ?bool = null,
    allowReserved: bool = false,
    schema: ?OrRef(Schema) = null,
    content: ?std.json.Value = null,
    example: ?std.json.Value = null,
    examples: ?std.json.Value = null,
};

pub const RequestBody = struct {
    description: ?[]const u8 = null,
    content: std.json.Value,
    required: bool = false,
};

pub const SecurityScheme = union(enum) {
    apiKey: APIKeySecurityScheme,
    http: HTTPSecurityScheme,
    oauth2: OAuth2SecurityScheme,
    openIdConnect: OpenIdConnectSecurityScheme,
};

pub const APIKeySecurityScheme = struct {
    type: []const u8,
    name: []const u8,
    in: []const u8,
    description: ?[]const u8 = null,
};

pub const HTTPSecurityScheme = struct {
    scheme: []const u8,
    bearerFormat: ?[]const u8 = null,
    description: ?[]const u8 = null,
    type: []const u8,
};

pub const OAuth2SecurityScheme = struct {
    type: []const u8,
    flows: OAuthFlows,
    description: ?[]const u8 = null,
};

pub const OpenIdConnectSecurityScheme = struct {
    type: []const u8,
    openIdConnectUrl: []const u8,
    description: ?[]const u8 = null,
};

pub const OAuthFlows = struct {
    implicit: ?ImplicitOAuthFlow = null,
    password: ?PasswordOAuthFlow = null,
    clientCredentials: ?ClientCredentialsFlow = null,
    authorizationCode: ?AuthorizationCodeOAuthFlow = null,
};

pub const ImplicitOAuthFlow = struct {
    authorizationUrl: []const u8,
    refreshUrl: ?[]const u8 = null,
    scopes: std.json.Value,
};

pub const PasswordOAuthFlow = struct {
    tokenUrl: []const u8,
    refreshUrl: ?[]const u8 = null,
    scopes: std.json.Value,
};

pub const ClientCredentialsFlow = struct {
    tokenUrl: []const u8,
    refreshUrl: ?[]const u8 = null,
    scopes: std.json.Value,
};

pub const AuthorizationCodeOAuthFlow = struct {
    authorizationUrl: []const u8,
    tokenUrl: []const u8,
    refreshUrl: ?[]const u8 = null,
    scopes: std.json.Value,
};

pub const Callback = std.json.Value;
