const std = @import("std");

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
