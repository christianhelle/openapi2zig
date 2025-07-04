const std = @import("std");

pub const OpenApiDocument = struct {
    openapi: []const u8,
    info: Info,
    server: Server,
    paths: Paths,
    components: ?Components = null,
    security: ?Security = null,
    tags: ?[]Tag = null,
    externalDocs: ?ExternalDocs = null,
};

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

pub const Server = struct {
    url: []const u8,
    description: ?[]const u8 = null,
    variables: ?std.AutoHashMap([]const u8, ServerVariable) = null,
};

pub const ServerVariable = struct {
    default: []const u8,
    description: ?[]const u8 = null,
    _enum: ?[]const []const u8 = null,
};

pub const Paths = struct {
    items: std.AutoHashMap([]const u8, PathItem),
};

pub const PathItem = struct {
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
};

pub const Operation = struct {
    tags: ?[]Tag = null,
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    externalDocs: ?ExternalDocs = null,
    operationId: ?[]const u8 = null,
    parameters: ?[]Parameter = null,
    requestBody: ?RequestBody = null,
    responses: Responses,
    callbacks: ?std.AutoHashMap([]const u8, Callback) = null,
    deprecated: bool = false,
    security: ?[]SecurityRequirement = null,
};

pub const Callback = struct {
    name: PathItem,
};

pub const Tag = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    externalDocs: ?ExternalDocs = null,
};

pub const ExternalDocs = struct {
    description: ?[]const u8 = null,
    url: []const u8,
};

pub const Parameter = struct {
    name: []const u8,
    in: ParameterIn,
    description: ?[]const u8 = null,
    required: bool = false,
    deprecated: bool = false,
    allowEmptyValue: bool = false,
    style: ?ParameterStyle = null,
    explode: ?bool = null,
    allowReserved: bool = false,
    schema: ?Schema = null,
    example: ?anyopaque = null,
    examples: ?std.AutoHashMap([]const u8, Example) = null,
};

pub const ParameterIn = enum {
    query,
    header,
    path,
    cookie,
};

pub const ParameterStyle = enum {
    matrix,
    label,
    form,
    simple,
    spaceDelimited,
    pipeDelimited,
    deepObject,
};

pub const Schema = struct {
    type: ?SchemaType = null,
    properties: ?std.AutoHashMap([]const u8, Schema) = null,
    format: ?[]const u8 = null,
    title: ?[]const u8 = null,
    description: ?[]const u8 = null,
    default: ?anyopaque = null,
    multipleOf: ?f64 = null,
    maximum: ?f64 = null,
    exclusiveMaximum: bool = false,
    minimum: ?f64 = null,
    exclusiveMinimum: bool = false,
    maxLength: ?u64 = null,
    minLength: ?u64 = null,
    pattern: ?[]const u8 = null,
    maxItems: ?u64 = null,
    minItems: ?u64 = null,
    uniqueItems: bool = false,
    maxProperties: ?u64 = null,
    minProperties: ?u64 = null,
    required: ?[]const []const u8 = null,
    _enum: ?[]anyopaque = null,
};

pub const SchemaType = enum {
    string,
    number,
    integer,
    boolean,
    array,
    object,
    null,
};

pub const RequestBody = struct {
    description: ?[]const u8 = null,
    content: std.AutoHashMap([]const u8, MediaType),
    required: bool = false,
};

pub const MediaType = struct {
    schema: ?Schema = null,
    example: ?anyopaque = null,
    examples: ?std.AutoHashMap([]const u8, Example) = null,
    encoding: ?std.AutoHashMap([]const u8, Encoding) = null,
};

pub const Example = struct {
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    value: ?anyopaque = null,
    externalValue: ?[]const u8 = null,
};

pub const Encoding = struct {
    contentType: ?[]const u8 = null,
    headers: ?std.AutoHashMap([]const u8, Header) = null,
    style: ?ParameterStyle = null,
    explode: ?bool = null,
    allowReserved: bool = false,
};

pub const Header = struct {
    description: ?[]const u8 = null,
    required: bool = false,
    deprecated: bool = false,
    allowEmptyValue: bool = false,
    style: ?ParameterStyle = null,
    explode: ?bool = null,
    allowReserved: bool = false,
    schema: ?Schema = null,
    example: ?anyopaque = null,
    examples: ?std.AutoHashMap([]const u8, Example) = null,
};

pub const Components = struct {
    schemas: ?std.AutoHashMap([]const u8, Schema) = null,
    responses: ?std.AutoHashMap([]const u8, Response) = null,
    parameters: ?std.AutoHashMap([]const u8, Parameter) = null,
    examples: ?std.AutoHashMap([]const u8, Example) = null,
    requestBodies: ?std.AutoHashMap([]const u8, RequestBody) = null,
    headers: ?std.AutoHashMap([]const u8, Header) = null,
    securitySchemes: ?std.AutoHashMap([]const u8, SecurityScheme) = null,
    links: ?std.AutoHashMap([]const u8, Link) = null,
    callbacks: ?std.AutoHashMap([]const u8, Callback) = null,
};

pub const Security = struct {
    items: std.AutoHashMap([]const u8, [][]const u8),
};

pub const Response = struct {
    description: []const u8,
    headers: ?std.AutoHashMap([]const u8, Header) = null,
    content: ?std.AutoHashMap([]const u8, MediaType) = null,
    links: ?std.AutoHashMap([]const u8, Link) = null,
};

pub const SecurityScheme = struct {
    type: []const u8,
    description: ?[]const u8 = null,
    name: ?[]const u8 = null,
    in: ?SecurityIn = null,
    scheme: ?[]const u8 = null,
    bearerFormat: ?[]const u8 = null,
    flows: ?OAuthFlows = null,
    openIdConnectUrl: ?[]const u8 = null,
};

pub const SecurityIn = enum {
    query,
    header,
    cookie,
};

pub const OAuthFlows = struct {
    implicit: ?OAuthFlow = null,
    password: ?OAuthFlow = null,
    clientCredentials: ?OAuthFlow = null,
    authorizationCode: ?OAuthFlow = null,
};

pub const OAuthFlow = struct {
    authorizationUrl: ?[]const u8 = null,
    tokenUrl: ?[]const u8 = null,
    refreshUrl: ?[]const u8 = null,
    scopes: std.AutoHashMap([]const u8, []const u8),
};

pub const Responses = struct {
    default: std.AutoHashMap([]const u8, Response),
};
