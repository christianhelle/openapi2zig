const std = @import("std");
const UnifiedDocument = @import("../../models/common/document.zig").UnifiedDocument;
const DocumentInfo = @import("../../models/common/document.zig").DocumentInfo;
const ContactInfo = @import("../../models/common/document.zig").ContactInfo;
const LicenseInfo = @import("../../models/common/document.zig").LicenseInfo;
const ExternalDocumentation = @import("../../models/common/document.zig").ExternalDocumentation;
const Tag = @import("../../models/common/document.zig").Tag;
const Server = @import("../../models/common/document.zig").Server;
const SecurityRequirement = @import("../../models/common/document.zig").SecurityRequirement;
const Schema = @import("../../models/common/document.zig").Schema;
const SchemaType = @import("../../models/common/document.zig").SchemaType;
const Parameter = @import("../../models/common/document.zig").Parameter;
const ParameterLocation = @import("../../models/common/document.zig").ParameterLocation;
const Response = @import("../../models/common/document.zig").Response;
const Operation = @import("../../models/common/document.zig").Operation;
const PathItem = @import("../../models/common/document.zig").PathItem;

const SwaggerDocument = @import("../../models/v2.0/swagger.zig").SwaggerDocument;
const Info2 = @import("../../models/v2.0/info.zig").Info;
const Contact2 = @import("../../models/v2.0/info.zig").Contact;
const License2 = @import("../../models/v2.0/info.zig").License;
const ExternalDocs2 = @import("../../models/v2.0/externaldocs.zig").ExternalDocumentation;
const Tag2 = @import("../../models/v2.0/tag.zig").Tag;
const SecurityRequirement2 = @import("../../models/v2.0/security.zig").SecurityRequirement;
const Schema2 = @import("../../models/v2.0/schema.zig").Schema;
const Parameter2 = @import("../../models/v2.0/parameter.zig").Parameter;
const ParameterLocation2 = @import("../../models/v2.0/parameter.zig").ParameterLocation;
const PrimitiveType2 = @import("../../models/v2.0/parameter.zig").PrimitiveType;
const Response2 = @import("../../models/v2.0/response.zig").Response;
const Operation2 = @import("../../models/v2.0/operation.zig").Operation;
const PathItem2 = @import("../../models/v2.0/paths.zig").PathItem;
const Paths2 = @import("../../models/v2.0/paths.zig").Paths;

pub const SwaggerConverter = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SwaggerConverter {
        return SwaggerConverter{ .allocator = allocator };
    }

    pub fn convert(self: *SwaggerConverter, swagger: SwaggerDocument) !UnifiedDocument {
        const version = swagger.swagger; // Reference, don't duplicate
        const info = self.convertInfo(swagger.info);
        const paths = try self.convertPaths(swagger.paths);

        // Create servers from host and basePath (Swagger 2.0 style)
        const servers = try self.createServersFromHostAndBasePath(swagger.host, swagger.basePath, swagger.schemes);
        const security = if (swagger.security) |security_list| try self.convertSecurityRequirements(security_list) else null;
        const tags = if (swagger.tags) |tags_list| try self.convertTags(tags_list) else null;
        const externalDocs = if (swagger.externalDocs) |ext_docs| try self.convertExternalDocs(ext_docs) else null;
        const schemas = if (swagger.definitions) |definitions| try self.convertDefinitions(definitions) else null;
        const parameters = if (swagger.parameters) |params| try self.convertGlobalParameters(params) else null;
        const responses = if (swagger.responses) |resps| try self.convertGlobalResponses(resps) else null;

        return UnifiedDocument{
            .version = version,
            .info = info,
            .paths = paths,
            .servers = servers,
            .security = security,
            .tags = tags,
            .externalDocs = externalDocs,
            .schemas = schemas,
            .parameters = parameters,
            .responses = responses,
        };
    }

    fn convertInfo(self: *SwaggerConverter, info: Info2) DocumentInfo {
        _ = self; // Mark unused parameter
        const title = info.title; // Reference, don't duplicate
        const description = info.description; // Reference, don't duplicate
        const version = info.version; // Reference, don't duplicate
        const termsOfService = info.termsOfService; // Reference, don't duplicate

        const contact = if (info.contact) |contact_info| blk: {
            const name = contact_info.name; // Reference, don't duplicate
            const url = contact_info.url; // Reference, don't duplicate
            const email = contact_info.email; // Reference, don't duplicate
            break :blk ContactInfo{ .name = name, .url = url, .email = email };
        } else null;

        const license = if (info.license) |license_info| blk: {
            const name = license_info.name; // Reference, don't duplicate
            const url = license_info.url; // Reference, don't duplicate
            break :blk LicenseInfo{ .name = name, .url = url };
        } else null;

        return DocumentInfo{
            .title = title,
            .description = description,
            .version = version,
            .termsOfService = termsOfService,
            .contact = contact,
            .license = license,
        };
    }

    fn createServersFromHostAndBasePath(self: *SwaggerConverter, host: ?[]const u8, basePath: ?[]const u8, schemes: ?[][]const u8) ![]Server {
        if (host == null) {
            // No host specified, return empty array
            return try self.allocator.alloc(Server, 0);
        }

        const host_str = host.?;
        const base_path = basePath orelse "";
        const schemes_list = schemes orelse &[_][]const u8{"https"};

        var servers = try self.allocator.alloc(Server, schemes_list.len);
        for (schemes_list, 0..) |scheme, i| {
            const url = try std.fmt.allocPrint(self.allocator, "{s}://{s}{s}", .{ scheme, host_str, base_path });
            servers[i] = Server{ .url = url, .description = null };
        }

        return servers;
    }

    fn convertSecurityRequirements(self: *SwaggerConverter, security: []SecurityRequirement2) ![]SecurityRequirement {
        var converted_security = try self.allocator.alloc(SecurityRequirement, security.len);
        for (security, 0..) |sec_req, i| {
            var schemes = std.StringHashMap([][]const u8).init(self.allocator);
            var sec_iterator = sec_req.requirements.iterator();
            while (sec_iterator.next()) |entry| {
                const key = try self.allocator.dupe(u8, entry.key_ptr.*);
                const scopes = try self.allocator.alloc([]const u8, entry.value_ptr.*.len);
                for (entry.value_ptr.*, 0..) |scope, j| {
                    scopes[j] = try self.allocator.dupe(u8, scope);
                }
                try schemes.put(key, scopes);
            }
            converted_security[i] = SecurityRequirement{ .schemes = schemes };
        }
        return converted_security;
    }

    fn convertTags(self: *SwaggerConverter, tags: []Tag2) ![]Tag {
        var converted_tags = try self.allocator.alloc(Tag, tags.len);
        for (tags, 0..) |tag, i| {
            const name = try self.allocator.dupe(u8, tag.name);
            const description = if (tag.description) |desc| try self.allocator.dupe(u8, desc) else null;
            const externalDocs = if (tag.externalDocs) |ext_docs| try self.convertExternalDocs(ext_docs) else null;
            converted_tags[i] = Tag{ .name = name, .description = description, .externalDocs = externalDocs };
        }
        return converted_tags;
    }

    fn convertExternalDocs(self: *SwaggerConverter, externalDocs: ExternalDocs2) !ExternalDocumentation {
        const url = try self.allocator.dupe(u8, externalDocs.url);
        const description = if (externalDocs.description) |desc| try self.allocator.dupe(u8, desc) else null;
        return ExternalDocumentation{ .url = url, .description = description };
    }

    fn convertDefinitions(self: *SwaggerConverter, definitions: std.StringHashMap(Schema2)) !std.StringHashMap(Schema) {
        var schemas = std.StringHashMap(Schema).init(self.allocator);

        var def_iterator = definitions.iterator();
        while (def_iterator.next()) |entry| {
            const key = try self.allocator.dupe(u8, entry.key_ptr.*);
            const schema = try self.convertSchema(entry.value_ptr.*);
            try schemas.put(key, schema);
        }

        return schemas;
    }

    fn convertGlobalParameters(self: *SwaggerConverter, parameters: std.StringHashMap(Parameter2)) !std.StringHashMap(Parameter) {
        var converted_params = std.StringHashMap(Parameter).init(self.allocator);

        var param_iterator = parameters.iterator();
        while (param_iterator.next()) |entry| {
            const key = try self.allocator.dupe(u8, entry.key_ptr.*);
            const param = try self.convertParameter(entry.value_ptr.*);
            try converted_params.put(key, param);
        }

        return converted_params;
    }

    fn convertGlobalResponses(self: *SwaggerConverter, responses: std.StringHashMap(Response2)) !std.StringHashMap(Response) {
        var converted_responses = std.StringHashMap(Response).init(self.allocator);

        var resp_iterator = responses.iterator();
        while (resp_iterator.next()) |entry| {
            const key = try self.allocator.dupe(u8, entry.key_ptr.*);
            const response = try self.convertResponse(entry.value_ptr.*);
            try converted_responses.put(key, response);
        }

        return converted_responses;
    }

    fn convertSchema(self: *SwaggerConverter, schema: Schema2) !Schema {
        const schema_type = if (schema.type) |type_str| self.convertSchemaType(type_str) else null;
        const ref = if (schema.ref) |ref_str| try self.allocator.dupe(u8, ref_str) else null;
        const title = if (schema.title) |title_str| try self.allocator.dupe(u8, title_str) else null;
        const description = if (schema.description) |desc| try self.allocator.dupe(u8, desc) else null;
        const format = if (schema.format) |fmt| try self.allocator.dupe(u8, fmt) else null;

        const required = if (schema.required) |req_list| blk: {
            const req_array = try self.allocator.alloc([]const u8, req_list.len);
            for (req_list, 0..) |req, i| {
                req_array[i] = try self.allocator.dupe(u8, req);
            }
            break :blk req_array;
        } else null;

        const properties = if (schema.properties) |props| blk: {
            var props_map = std.StringHashMap(Schema).init(self.allocator);
            var prop_iterator = props.iterator();
            while (prop_iterator.next()) |entry| {
                const key = try self.allocator.dupe(u8, entry.key_ptr.*);
                const prop_schema = try self.convertSchema(entry.value_ptr.*);
                try props_map.put(key, prop_schema);
            }
            break :blk props_map;
        } else null;

        const items = if (schema.items) |items_schema| blk: {
            const converted_items = try self.convertSchema(items_schema.*);
            const items_ptr = try self.allocator.create(Schema);
            items_ptr.* = converted_items;
            break :blk items_ptr;
        } else null;

        return Schema{
            .type = schema_type,
            .ref = ref,
            .title = title,
            .description = description,
            .format = format,
            .required = required,
            .properties = properties,
            .items = items,
            .enum_values = schema.enum_values,
            .default = schema.default,
            .example = schema.example,
        };
    }

    fn convertSchemaType(self: *SwaggerConverter, type_str: []const u8) SchemaType {
        _ = self;
        if (std.mem.eql(u8, type_str, "string")) return .string;
        if (std.mem.eql(u8, type_str, "number")) return .number;
        if (std.mem.eql(u8, type_str, "integer")) return .integer;
        if (std.mem.eql(u8, type_str, "boolean")) return .boolean;
        if (std.mem.eql(u8, type_str, "array")) return .array;
        if (std.mem.eql(u8, type_str, "object")) return .object;
        return .string; // default fallback
    }

    fn convertPaths(self: *SwaggerConverter, paths: Paths2) !std.StringHashMap(PathItem) {
        var converted_paths = std.StringHashMap(PathItem).init(self.allocator);

        var path_iterator = paths.path_items.iterator();
        while (path_iterator.next()) |entry| {
            const path = try self.allocator.dupe(u8, entry.key_ptr.*);
            const path_item = try self.convertPathItem(entry.value_ptr.*);
            try converted_paths.put(path, path_item);
        }

        return converted_paths;
    }

    fn convertPathItem(self: *SwaggerConverter, pathItem: PathItem2) !PathItem {
        const get = if (pathItem.get) |op| try self.convertOperation(op) else null;
        const put = if (pathItem.put) |op| try self.convertOperation(op) else null;
        const post = if (pathItem.post) |op| try self.convertOperation(op) else null;
        const delete = if (pathItem.delete) |op| try self.convertOperation(op) else null;
        const options = if (pathItem.options) |op| try self.convertOperation(op) else null;
        const head = if (pathItem.head) |op| try self.convertOperation(op) else null;
        const patch = if (pathItem.patch) |op| try self.convertOperation(op) else null;

        const parameters = if (pathItem.parameters) |params| try self.convertParameters(params) else null;

        return PathItem{
            .get = get,
            .put = put,
            .post = post,
            .delete = delete,
            .options = options,
            .head = head,
            .patch = patch,
            .parameters = parameters,
        };
    }

    fn convertOperation(self: *SwaggerConverter, operation: Operation2) !Operation {
        const tags = if (operation.tags) |tags_list| blk: {
            const tags_array = try self.allocator.alloc([]const u8, tags_list.len);
            for (tags_list, 0..) |tag, i| {
                tags_array[i] = try self.allocator.dupe(u8, tag);
            }
            break :blk tags_array;
        } else null;

        const summary = if (operation.summary) |sum| try self.allocator.dupe(u8, sum) else null;
        const description = if (operation.description) |desc| try self.allocator.dupe(u8, desc) else null;
        const operationId = if (operation.operationId) |opId| try self.allocator.dupe(u8, opId) else null;

        const parameters = if (operation.parameters) |params| try self.convertParameters(params) else null;

        var responses = std.StringHashMap(Response).init(self.allocator);
        var resp_iterator = operation.responses.iterator();
        while (resp_iterator.next()) |entry| {
            const key = try self.allocator.dupe(u8, entry.key_ptr.*);
            const response = try self.convertResponse(entry.value_ptr.*);
            try responses.put(key, response);
        }

        const security = if (operation.security) |sec_list| try self.convertSecurityRequirements(sec_list) else null;

        return Operation{
            .tags = tags,
            .summary = summary,
            .description = description,
            .operationId = operationId,
            .parameters = parameters,
            .responses = responses,
            .deprecated = operation.deprecated orelse false,
            .security = security,
        };
    }

    fn convertParameters(self: *SwaggerConverter, parameters: []Parameter2) ![]Parameter {
        var converted_params = try self.allocator.alloc(Parameter, parameters.len);
        for (parameters, 0..) |param, i| {
            converted_params[i] = try self.convertParameter(param);
        }
        return converted_params;
    }

    fn convertParameter(self: *SwaggerConverter, parameter: Parameter2) !Parameter {
        const name = try self.allocator.dupe(u8, parameter.name);
        const location = self.convertParameterLocation(parameter.in);
        const description = if (parameter.description) |desc| try self.allocator.dupe(u8, desc) else null;
        const required = parameter.required;

        const schema = if (parameter.schema) |param_schema| blk: {
            const converted_schema = try self.convertSchema(param_schema);
            break :blk converted_schema;
        } else null;

        const param_type = if (parameter.type) |type_val| self.convertParameterType(type_val) else null;
        const format = if (parameter.format) |fmt| try self.allocator.dupe(u8, fmt) else null;

        return Parameter{
            .name = name,
            .location = location,
            .description = description,
            .required = required,
            .schema = schema,
            .type = param_type,
            .format = format,
        };
    }

    fn convertParameterLocation(self: *SwaggerConverter, location: ParameterLocation2) ParameterLocation {
        _ = self;
        return switch (location) {
            .query => .query,
            .header => .header,
            .path => .path,
            .body => .body,
            .formData => .form,
        };
    }

    fn convertParameterType(self: *SwaggerConverter, param_type: PrimitiveType2) SchemaType {
        _ = self;
        return switch (param_type) {
            .string => .string,
            .number => .number,
            .integer => .integer,
            .boolean => .boolean,
            .array => .array,
            .file => .string, // Map file to string
        };
    }

    fn convertResponse(self: *SwaggerConverter, response: Response2) !Response {
        const description = try self.allocator.dupe(u8, response.description);

        const schema = if (response.schema) |resp_schema| blk: {
            const converted_schema = try self.convertSchema(resp_schema);
            break :blk converted_schema;
        } else null;

        const headers = if (response.headers) |headers_map| blk: {
            var converted_headers = std.StringHashMap(Parameter).init(self.allocator);
            var header_iterator = headers_map.iterator();
            while (header_iterator.next()) |entry| {
                const key = try self.allocator.dupe(u8, entry.key_ptr.*);
                // Convert header to parameter (headers in Swagger 2.0 are similar to parameters)
                const header_param = Parameter{
                    .name = try self.allocator.dupe(u8, key),
                    .location = .header,
                    .description = entry.value_ptr.description,
                    .required = false,
                    .schema = null,
                    .type = null,
                    .format = null,
                };
                try converted_headers.put(key, header_param);
            }
            break :blk converted_headers;
        } else null;

        return Response{
            .description = description,
            .schema = schema,
            .headers = headers,
        };
    }
};
