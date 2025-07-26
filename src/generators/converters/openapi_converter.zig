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

const OpenApiDocument = @import("../../models/v3.0/openapi.zig").OpenApiDocument;
const Info3 = @import("../../models/v3.0/info.zig").Info;
const Contact3 = @import("../../models/v3.0/info.zig").Contact;
const License3 = @import("../../models/v3.0/info.zig").License;
const ExternalDocs3 = @import("../../models/v3.0/externaldocs.zig").ExternalDocumentation;
const Tag3 = @import("../../models/v3.0/tag.zig").Tag;
const Server3 = @import("../../models/v3.0/server.zig").Server;
const SecurityRequirement3 = @import("../../models/v3.0/security.zig").SecurityRequirement;
const Components3 = @import("../../models/v3.0/components.zig").Components;
const SchemaOrReference3 = @import("../../models/v3.0/schema.zig").SchemaOrReference;
const Schema3 = @import("../../models/v3.0/schema.zig").Schema;
const ParameterOrReference3 = @import("../../models/v3.0/parameter.zig").ParameterOrReference;
const Parameter3 = @import("../../models/v3.0/parameter.zig").Parameter;
const ResponseOrReference3 = @import("../../models/v3.0/response.zig").ResponseOrReference;
const Response3 = @import("../../models/v3.0/response.zig").Response;
const Operation3 = @import("../../models/v3.0/operation.zig").Operation;
const PathItem3 = @import("../../models/v3.0/paths.zig").PathItem;
const Paths3 = @import("../../models/v3.0/paths.zig").Paths;

pub const OpenApiConverter = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) OpenApiConverter {
        return OpenApiConverter{ .allocator = allocator };
    }

    pub fn convert(self: *OpenApiConverter, openapi: OpenApiDocument) !UnifiedDocument {
        const version = openapi.openapi; // Reference, don't duplicate
        const info = self.convertInfo(openapi.info);
        const paths = try self.convertPaths(openapi.paths);

        const servers = if (openapi.servers) |servers_list| try self.convertServers(servers_list) else null;
        const security = if (openapi.security) |security_list| try self.convertSecurityRequirements(security_list) else null;
        const tags = if (openapi.tags) |tags_list| try self.convertTags(tags_list) else null;
        const externalDocs = if (openapi.externalDocs) |ext_docs| try self.convertExternalDocs(ext_docs) else null;
        const schemas = if (openapi.components) |components| try self.convertSchemas(components) else null;

        return UnifiedDocument{
            .version = version,
            .info = info,
            .paths = paths,
            .servers = servers,
            .security = security,
            .tags = tags,
            .externalDocs = externalDocs,
            .schemas = schemas,
            .parameters = null,
            .responses = null,
        };
    }

    fn convertInfo(self: *OpenApiConverter, info: Info3) DocumentInfo {
        _ = self; // Not needed for reference-based conversion
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

    fn convertServers(self: *OpenApiConverter, servers: []Server3) ![]Server {
        var converted_servers = try self.allocator.alloc(Server, servers.len);
        for (servers, 0..) |server, i| {
            const url = try self.allocator.dupe(u8, server.url);
            const description = if (server.description) |desc| try self.allocator.dupe(u8, desc) else null;
            converted_servers[i] = Server{ .url = url, .description = description };
        }
        return converted_servers;
    }

    fn convertSecurityRequirements(self: *OpenApiConverter, security: []const SecurityRequirement3) ![]SecurityRequirement {
        var converted_security = try self.allocator.alloc(SecurityRequirement, security.len);
        for (security, 0..) |sec_req, i| {
            var schemes = std.StringHashMap([][]const u8).init(self.allocator);
            var sec_iterator = sec_req.schemes.iterator();
            while (sec_iterator.next()) |entry| {
                const key = try self.allocator.dupe(u8, entry.key_ptr.*);
                const scopes = try self.allocator.alloc([]const u8, entry.value_ptr.*.len);
                for (entry.value_ptr.*, 0..) |scope, j| {
                    scopes[j] = scope; // Reference, don't duplicate
                }
                try schemes.put(key, scopes);
            }
            converted_security[i] = SecurityRequirement{ .schemes = schemes };
        }
        return converted_security;
    }

    fn convertTags(self: *OpenApiConverter, tags: []const Tag3) ![]Tag {
        var converted_tags = try self.allocator.alloc(Tag, tags.len);
        for (tags, 0..) |tag, i| {
            const name = tag.name; // Reference, don't duplicate
            const description = tag.description; // Reference, don't duplicate
            const externalDocs = if (tag.externalDocs) |ext_docs| try self.convertExternalDocs(ext_docs) else null;
            converted_tags[i] = Tag{ .name = name, .description = description, .externalDocs = externalDocs };
        }
        return converted_tags;
    }

    fn convertExternalDocs(self: *OpenApiConverter, externalDocs: ExternalDocs3) !ExternalDocumentation {
        _ = self; // Mark unused parameter
        const url = externalDocs.url; // Reference, don't duplicate
        const description = externalDocs.description; // Reference, don't duplicate
        return ExternalDocumentation{ .url = url, .description = description };
    }

    fn convertSchemas(self: *OpenApiConverter, components: Components3) !std.StringHashMap(Schema) {
        var schemas = std.StringHashMap(Schema).init(self.allocator);

        if (components.schemas) |schemas_map| {
            var schema_iterator = schemas_map.iterator();
            while (schema_iterator.next()) |entry| {
                const key = try self.allocator.dupe(u8, entry.key_ptr.*);
                const schema = try self.convertSchemaOrReference(entry.value_ptr.*);
                try schemas.put(key, schema);
            }
        }

        return schemas;
    }

    fn convertSchemaOrReference(self: *OpenApiConverter, schemaOrRef: SchemaOrReference3) anyerror!Schema {
        switch (schemaOrRef) {
            .reference => |ref| {
                const ref_str = ref.ref; // Reference, don't duplicate
                return Schema{ .type = .reference, .ref = ref_str };
            },
            .schema => |schema| {
                return self.convertSchema(schema.*);
            },
        }
    }

    fn convertSchema(self: *OpenApiConverter, schema: Schema3) anyerror!Schema {
        const schema_type = if (schema.type) |type_str| self.convertSchemaType(type_str) else null;
        const title = schema.title; // Reference, don't duplicate
        const description = schema.description; // Reference, don't duplicate
        const format = schema.format; // Reference, don't duplicate

        const required = if (schema.required) |req_list| blk: {
            const req_array = try self.allocator.alloc([]const u8, req_list.len);
            for (req_list, 0..) |req, i| {
                req_array[i] = req; // Reference, don't duplicate
            }
            break :blk req_array;
        } else null;

        const properties = if (schema.properties) |props| blk: {
            var props_map = std.StringHashMap(Schema).init(self.allocator);
            var prop_iterator = props.iterator();
            while (prop_iterator.next()) |entry| {
                const key = try self.allocator.dupe(u8, entry.key_ptr.*);
                const prop_schema = try self.convertSchemaOrReference(entry.value_ptr.*);
                try props_map.put(key, prop_schema);
            }
            break :blk props_map;
        } else null;

        const items = if (schema.items) |items_ref| blk: {
            const items_schema = try self.convertSchemaOrReference(items_ref);
            const items_ptr = try self.allocator.create(Schema);
            items_ptr.* = items_schema;
            break :blk items_ptr;
        } else null;

        return Schema{
            .type = schema_type,
            .ref = null, // OpenAPI 3.0 Schema doesn't have ref, only SchemaOrReference does
            .title = title,
            .description = description,
            .format = format,
            .required = required,
            .properties = properties,
            .items = items,
            .enum_values = null, // TODO: convert enum values
            .default = schema.default,
            .example = schema.example,
        };
    }

    fn convertSchemaType(self: *OpenApiConverter, type_str: []const u8) SchemaType {
        _ = self;
        if (std.mem.eql(u8, type_str, "string")) return .string;
        if (std.mem.eql(u8, type_str, "number")) return .number;
        if (std.mem.eql(u8, type_str, "integer")) return .integer;
        if (std.mem.eql(u8, type_str, "boolean")) return .boolean;
        if (std.mem.eql(u8, type_str, "array")) return .array;
        if (std.mem.eql(u8, type_str, "object")) return .object;
        return .string; // default fallback
    }

    fn convertPaths(self: *OpenApiConverter, paths: Paths3) !std.StringHashMap(PathItem) {
        var converted_paths = std.StringHashMap(PathItem).init(self.allocator);

        var path_iterator = paths.path_items.iterator();
        while (path_iterator.next()) |entry| {
            const path = try self.allocator.dupe(u8, entry.key_ptr.*);
            const path_item = try self.convertPathItem(entry.value_ptr.*);
            try converted_paths.put(path, path_item);
        }

        return converted_paths;
    }

    fn convertPathItem(self: *OpenApiConverter, pathItem: PathItem3) !PathItem {
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

    fn convertOperation(self: *OpenApiConverter, operation: Operation3) !Operation {
        const tags = if (operation.tags) |tags_list| blk: {
            const tags_array = try self.allocator.alloc([]const u8, tags_list.len);
            for (tags_list, 0..) |tag, i| {
                tags_array[i] = tag; // Reference, don't duplicate
            }
            break :blk tags_array;
        } else null;

        const summary = operation.summary; // Reference, don't duplicate
        const description = operation.description; // Reference, don't duplicate
        const operationId = operation.operationId; // Reference, don't duplicate

        const parameters = if (operation.parameters) |params| try self.convertParameters(params) else null;

        var responses = std.StringHashMap(Response).init(self.allocator);

        // Add default response if present
        if (operation.responses.default) |default_response| {
            const response = try self.convertResponseOrReference(default_response);
            const default_key = try self.allocator.dupe(u8, "default"); // Must dupe to match other keys
            try responses.put(default_key, response);
        }

        // Add status code responses
        var resp_iterator = operation.responses.status_codes.iterator();
        while (resp_iterator.next()) |entry| {
            const key = try self.allocator.dupe(u8, entry.key_ptr.*);
            const response = try self.convertResponseOrReference(entry.value_ptr.*);
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

    fn convertParameters(self: *OpenApiConverter, parameters: []const ParameterOrReference3) ![]Parameter {
        var converted_params = try self.allocator.alloc(Parameter, parameters.len);
        for (parameters, 0..) |param_ref, i| {
            converted_params[i] = try self.convertParameterOrReference(param_ref);
        }
        return converted_params;
    }

    fn convertParameterOrReference(self: *OpenApiConverter, paramOrRef: ParameterOrReference3) !Parameter {
        switch (paramOrRef) {
            .reference => |ref| {
                // For references, we create a placeholder parameter
                // In a real implementation, you'd resolve the reference
                const name = try self.allocator.dupe(u8, ref.ref);
                return Parameter{
                    .name = name,
                    .location = .query, // default
                    .required = false,
                };
            },
            .parameter => |param| {
                return self.convertParameter(param);
            },
        }
    }

    fn convertParameter(self: *OpenApiConverter, parameter: Parameter3) !Parameter {
        const name = parameter.name; // Reference, don't duplicate
        const location = self.convertParameterLocation(parameter.in_field);
        const description = parameter.description; // Reference, don't duplicate
        const required = parameter.required orelse false;

        const schema = if (parameter.schema) |schema_ref| try self.convertSchemaOrReference(schema_ref) else null;

        return Parameter{
            .name = name,
            .location = location,
            .description = description,
            .required = required,
            .schema = schema,
            .type = null,
            .format = null,
        };
    }

    fn convertParameterLocation(self: *OpenApiConverter, location: []const u8) ParameterLocation {
        _ = self;
        if (std.mem.eql(u8, location, "query")) return .query;
        if (std.mem.eql(u8, location, "header")) return .header;
        if (std.mem.eql(u8, location, "path")) return .path;
        if (std.mem.eql(u8, location, "cookie")) return .query; // map to query as fallback
        return .query; // default fallback
    }

    fn convertResponseOrReference(self: *OpenApiConverter, respOrRef: ResponseOrReference3) !Response {
        switch (respOrRef) {
            .reference => |ref| {
                // For references, we create a placeholder response
                const description = try self.allocator.dupe(u8, ref.ref);
                return Response{ .description = description };
            },
            .response => |resp| {
                return self.convertResponse(resp);
            },
        }
    }

    fn convertResponse(self: *OpenApiConverter, response: Response3) !Response {
        _ = self; // Mark unused parameter
        const description = response.description; // Reference, don't duplicate
        // TODO: Convert schema from response content
        // TODO: Convert headers
        return Response{
            .description = description,
            .schema = null,
            .headers = null,
        };
    }
};
