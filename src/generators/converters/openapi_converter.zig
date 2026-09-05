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
const mime = @import("../../media_type.zig");
const OpenApiDocument = @import("../../models/v3.0/openapi.zig").OpenApiDocument;
const Info3 = @import("../../models/v3.0/info.zig").Info;
const Contact3 = @import("../../models/v3.0/info.zig").Contact;
const License3 = @import("../../models/v3.0/info.zig").License;
const ExternalDocs3 = @import("../../models/v3.0/externaldocs.zig").ExternalDocumentation;
const Tag3 = @import("../../models/v3.0/tag.zig").Tag;
const Server3 = @import("../../models/v3.0/server.zig").Server;
const SecurityRequirement3 = @import("../../models/v3.0/security.zig").SecurityRequirement;
const UnifiedSecurityScheme = @import("../../models/common/document.zig").SecurityScheme;
const Components3 = @import("../../models/v3.0/components.zig").Components;
const SchemaOrReference3 = @import("../../models/v3.0/schema.zig").SchemaOrReference;
const Schema3 = @import("../../models/v3.0/schema.zig").Schema;
const ParameterOrReference3 = @import("../../models/v3.0/parameter.zig").ParameterOrReference;
const Parameter3 = @import("../../models/v3.0/parameter.zig").Parameter;
const ResponseOrReference3 = @import("../../models/v3.0/response.zig").ResponseOrReference;
const Response3 = @import("../../models/v3.0/response.zig").Response;
const RequestBodyOrReference3 = @import("../../models/v3.0/requestbody.zig").RequestBodyOrReference;
const RequestBody3 = @import("../../models/v3.0/requestbody.zig").RequestBody;
const Operation3 = @import("../../models/v3.0/operation.zig").Operation;
const PathItem3 = @import("../../models/v3.0/paths.zig").PathItem;
const Paths3 = @import("../../models/v3.0/paths.zig").Paths;

pub const OpenApiConverter = struct {
    allocator: std.mem.Allocator,
    /// Reusable parameters declared under `components.parameters`, so that a
    /// parameter given as a `$ref` resolves to the parameter it points at.
    component_parameters: ?*const std.StringHashMap(ParameterOrReference3) = null,

    pub fn init(allocator: std.mem.Allocator) OpenApiConverter {
        return OpenApiConverter{ .allocator = allocator };
    }

    pub fn convert(self: *OpenApiConverter, openapi: OpenApiDocument) !UnifiedDocument {
        const version = openapi.openapi;
        const info = self.convertInfo(openapi.info);
        if (openapi.components) |*components| {
            if (components.parameters) |*component_parameters| {
                self.component_parameters = component_parameters;
            }
        }
        defer self.component_parameters = null;
        const paths = try self.convertPaths(openapi.paths);
        const servers = if (openapi.servers) |servers_list| try self.convertServers(servers_list) else null;
        const security = if (openapi.security) |security_list| try self.convertSecurityRequirements(security_list) else null;
        const tags = if (openapi.tags) |tags_list| try self.convertTags(tags_list) else null;
        const externalDocs = if (openapi.externalDocs) |ext_docs| try self.convertExternalDocs(ext_docs) else null;
        const schemas = if (openapi.components) |components| try self.convertSchemas(components) else null;
        const security_schemes = if (openapi.components) |components| try self.convertSecuritySchemes(components) else null;
        return UnifiedDocument{
            .version = version,
            .info = info,
            .paths = paths,
            .servers = servers,
            .security = security,
            .security_schemes = security_schemes,
            .tags = tags,
            .externalDocs = externalDocs,
            .schemas = schemas,
            .parameters = null,
            .responses = null,
        };
    }

    fn convertSecuritySchemes(self: *OpenApiConverter, components: Components3) std.mem.Allocator.Error!?*std.StringHashMap(UnifiedSecurityScheme) {
        const source = components.securitySchemes orelse return null;
        const converted = try self.allocator.create(std.StringHashMap(UnifiedSecurityScheme));
        converted.* = std.StringHashMap(UnifiedSecurityScheme).init(self.allocator);
        errdefer {
            var iterator = converted.iterator();
            while (iterator.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(self.allocator);
            }
            converted.deinit();
            self.allocator.destroy(converted);
        }
        var iterator = source.iterator();
        while (iterator.next()) |entry| switch (entry.value_ptr.*) {
            .security_scheme => |scheme| switch (scheme) {
                .http => |http| if (std.ascii.eqlIgnoreCase(http.scheme, "bearer")) {
                    const key = try self.allocator.dupe(u8, entry.key_ptr.*);
                    converted.put(key, .bearer) catch |err| {
                        self.allocator.free(key);
                        return err;
                    };
                },
                .api_key => |api_key| if (std.mem.eql(u8, api_key.in_field, "header")) {
                    const key = try self.allocator.dupe(u8, entry.key_ptr.*);
                    const name = self.allocator.dupe(u8, api_key.name) catch |err| {
                        self.allocator.free(key);
                        return err;
                    };
                    const scheme_value: UnifiedSecurityScheme = .{ .api_key_header = .{ .name = name } };
                    converted.put(key, scheme_value) catch |err| {
                        self.allocator.free(key);
                        self.allocator.free(name);
                        return err;
                    };
                },
                else => {},
            },
            .reference => {},
        };
        return converted;
    }

    fn convertInfo(self: *OpenApiConverter, info: Info3) DocumentInfo {
        _ = self;
        const title = info.title;
        const description = info.description;
        const version = info.version;
        const termsOfService = info.termsOfService;
        const contact = if (info.contact) |contact_info| blk: {
            const name = contact_info.name;
            const url = contact_info.url;
            const email = contact_info.email;
            break :blk ContactInfo{ .name = name, .url = url, .email = email };
        } else null;
        const license = if (info.license) |license_info| blk: {
            const name = license_info.name;
            const url = license_info.url;
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
            converted_servers[i] = Server{
                .url = url,
                .description = description,
                ._url_allocated = true,
                ._description_allocated = description != null,
            };
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
                    scopes[j] = scope;
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
            const name = tag.name;
            const description = tag.description;
            const externalDocs = if (tag.externalDocs) |ext_docs| try self.convertExternalDocs(ext_docs) else null;
            converted_tags[i] = Tag{ .name = name, .description = description, .externalDocs = externalDocs };
        }
        return converted_tags;
    }
    fn convertExternalDocs(self: *OpenApiConverter, externalDocs: ExternalDocs3) !ExternalDocumentation {
        _ = self;
        const url = externalDocs.url;
        const description = externalDocs.description;
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
                const ref_str = ref.ref;
                return Schema{ .type = .reference, .ref = ref_str };
            },
            .schema => |schema| {
                return self.convertSchema(schema.*);
            },
        }
    }

    /// Append every name not already present, so the required lists of the
    /// `allOf` members and their parent combine without duplicates.
    fn mergeRequiredNames(self: *OpenApiConverter, required_list: *std.ArrayList([]const u8), names: []const []const u8) !void {
        for (names) |name| {
            var exists = false;
            for (required_list.items) |existing| {
                if (std.mem.eql(u8, existing, name)) {
                    exists = true;
                    break;
                }
            }
            if (!exists) try required_list.append(self.allocator, name);
        }
    }

    /// Move the properties of an `allOf` member into the merged map, leaving
    /// the member without properties so the caller can deinitialize the rest
    /// of it. A member later in the list wins on a name conflict.
    fn takeProperties(self: *OpenApiConverter, merged: *std.StringHashMap(Schema), part: *Schema) !void {
        var props = part.properties orelse return;
        part.properties = null;
        var iterator = props.iterator();
        while (iterator.next()) |entry| {
            if (merged.getEntry(entry.key_ptr.*)) |existing| {
                existing.value_ptr.deinit(self.allocator);
                existing.value_ptr.* = entry.value_ptr.*;
                self.allocator.free(entry.key_ptr.*);
            } else {
                try merged.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }
        props.deinit();
    }

    /// Flatten an `allOf` composition into a single object schema by merging
    /// the properties and required lists of its members with the ones the
    /// composing schema declares itself.
    fn convertAllOfSchema(self: *OpenApiConverter, schema: Schema3) anyerror!Schema {
        var merged_properties = std.StringHashMap(Schema).init(self.allocator);
        var required_list = std.ArrayList([]const u8).empty;

        if (schema.allOf) |all_of| {
            for (all_of) |item| {
                var converted = try self.convertSchemaOrReference(item);
                try self.takeProperties(&merged_properties, &converted);
                if (converted.required) |required| try self.mergeRequiredNames(&required_list, required);
                converted.deinit(self.allocator);
            }
        }

        if (schema.properties) |props| {
            var prop_iterator = props.iterator();
            while (prop_iterator.next()) |entry| {
                const prop_schema = try self.convertSchemaOrReference(entry.value_ptr.*);
                if (merged_properties.getEntry(entry.key_ptr.*)) |existing| {
                    existing.value_ptr.deinit(self.allocator);
                    existing.value_ptr.* = prop_schema;
                } else {
                    const key = try self.allocator.dupe(u8, entry.key_ptr.*);
                    try merged_properties.put(key, prop_schema);
                }
            }
        }

        if (schema.required) |required| try self.mergeRequiredNames(&required_list, required);

        const required = if (required_list.items.len > 0) try required_list.toOwnedSlice(self.allocator) else null;
        const has_properties = merged_properties.count() > 0;
        if (!has_properties) merged_properties.deinit();

        return Schema{
            .type = .object,
            .ref = null,
            .title = schema.title,
            .description = schema.description,
            .format = schema.format,
            .required = required,
            .properties = if (has_properties) merged_properties else null,
            .items = null,
            .enum_values = null,
            .default = schema.default,
            .example = schema.example,
            .nullable = schema.nullable orelse false,
        };
    }

    fn convertSchema(self: *OpenApiConverter, schema: Schema3) anyerror!Schema {
        if (schema.allOf != null) return try self.convertAllOfSchema(schema);

        const schema_type = if (schema.type) |type_str| self.convertSchemaType(type_str) else null;
        const title = schema.title;
        const description = schema.description;
        const format = schema.format;
        const required = if (schema.required) |req_list| blk: {
            const req_array = try self.allocator.alloc([]const u8, req_list.len);
            for (req_list, 0..) |req, i| {
                req_array[i] = req;
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
        const additional_properties: ?bool = if (schema.additionalProperties) |ap| switch (ap) {
            .boolean => |b| b,
            .schema_or_reference => true,
        } else null;

        return Schema{
            .type = schema_type,
            .ref = null,
            .title = title,
            .description = description,
            .format = format,
            .required = required,
            .properties = properties,
            .items = items,
            .enum_values = null,
            .default = schema.default,
            .example = schema.example,
            .additional_properties = additional_properties,
            .nullable = schema.nullable orelse false,
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
        return .string;
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
                tags_array[i] = tag;
            }
            break :blk tags_array;
        } else null;
        const summary = operation.summary;
        const description = operation.description;
        const operationId = operation.operationId;

        var parameters_list = std.ArrayList(Parameter).empty;
        defer parameters_list.deinit(self.allocator);

        if (operation.parameters) |params| {
            for (params) |*param_ref| {
                try parameters_list.append(self.allocator, try self.convertParameterOrReference(param_ref));
            }
        }

        if (operation.requestBody) |*request_body_or_ref| {
            const request_body_param = try self.convertRequestBodyOrReference(request_body_or_ref);
            try parameters_list.append(self.allocator, request_body_param);
        }

        const parameters = if (parameters_list.items.len > 0) try parameters_list.toOwnedSlice(self.allocator) else null;

        var responses = std.StringHashMap(Response).init(self.allocator);
        var streaming = false;
        if (operation.responses.default) |default_response| {
            if (hasEventStreamContent(default_response)) streaming = true;
            const response = try self.convertResponseOrReference(default_response);
            const default_key = try self.allocator.dupe(u8, "default");
            try responses.put(default_key, response);
        }
        var resp_iterator = operation.responses.status_codes.iterator();
        while (resp_iterator.next()) |entry| {
            if (!streaming and hasEventStreamContent(entry.value_ptr.*)) streaming = true;
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
            .streaming = streaming,
        };
    }

    fn convertRequestBodyOrReference(self: *OpenApiConverter, requestBodyOrRef: *const RequestBodyOrReference3) !Parameter {
        switch (requestBodyOrRef.*) {
            .reference => |ref| {
                return Parameter{
                    .name = ref.ref,
                    .location = .body,
                    .required = false,
                };
            },
            .request_body => |*body| {
                return self.convertRequestBody(body);
            },
        }
    }

    fn convertRequestBody(self: *OpenApiConverter, requestBody: *const RequestBody3) !Parameter {
        var mut_request_body = requestBody.*;
        var schema: ?Schema = null;
        const selected_key = mime.selectBestJsonKey(@TypeOf(mut_request_body.content), mut_request_body.content);
        if (selected_key) |key| {
            if (mut_request_body.content.get(key)) |media| {
                if (media.schema) |schema_or_ref| {
                    schema = try self.convertSchemaOrReference(schema_or_ref);
                }
            }
        }
        const content_type: ?[]const u8 = if (selected_key) |k|
            (if (k.len == 0) null else try self.allocator.dupe(u8, k))
        else
            null;
        return Parameter{
            .name = "body",
            .location = .body,
            .description = requestBody.description,
            .required = requestBody.required orelse false,
            .schema = schema,
            .type = null,
            .format = null,
            .content_type = content_type,
        };
    }

    fn convertParameters(self: *OpenApiConverter, parameters: []const ParameterOrReference3) ![]Parameter {
        var converted_params = try self.allocator.alloc(Parameter, parameters.len);
        for (parameters, 0..) |param_ref, i| {
            converted_params[i] = try self.convertParameterOrReference(&param_ref);
        }
        return converted_params;
    }

    fn convertParameterOrReference(self: *OpenApiConverter, paramOrRef: *const ParameterOrReference3) !Parameter {
        switch (paramOrRef.*) {
            .reference => |ref| {
                if (self.resolveComponentParameter(ref.ref)) |resolved| {
                    return self.convertParameter(resolved);
                }
                // Nothing to resolve against; fall back to the ref itself so the
                // parameter still appears rather than silently disappearing.
                return Parameter{
                    .name = ref.ref,
                    .location = .query,
                    .required = false,
                };
            },
            .parameter => |param| {
                return self.convertParameter(param);
            },
        }
    }

    /// Look up a `#/components/parameters/<name>` reference. A component entry
    /// may itself be a Reference Object, so alias chains are followed until a
    /// Parameter Object is reached. The hop limit bounds cyclic definitions,
    /// which nothing in the document structure prevents.
    fn resolveComponentParameter(self: *OpenApiConverter, ref: []const u8) ?Parameter3 {
        const prefix = "#/components/parameters/";
        const max_hops = 32;
        const parameters = self.component_parameters orelse return null;

        var current = ref;
        var hops: usize = 0;
        while (hops < max_hops) : (hops += 1) {
            if (!std.mem.startsWith(u8, current, prefix)) return null;
            const entry = parameters.get(current[prefix.len..]) orelse return null;
            switch (entry) {
                .parameter => |param| return param,
                .reference => |next| current = next.ref,
            }
        }
        return null;
    }

    fn convertParameter(self: *OpenApiConverter, parameter: Parameter3) !Parameter {
        const name = parameter.name;
        const location = self.convertParameterLocation(parameter.in_field);
        const description = parameter.description;
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
        if (std.mem.eql(u8, location, "cookie")) return .query;
        return .query;
    }

    fn convertResponseOrReference(self: *OpenApiConverter, respOrRef: ResponseOrReference3) !Response {
        switch (respOrRef) {
            .reference => |ref| {
                return Response{ .description = ref.ref };
            },
            .response => |resp| {
                return self.convertResponse(resp);
            },
        }
    }

    fn convertResponse(self: *OpenApiConverter, response: Response3) !Response {
        const description = response.description;
        var schema: ?Schema = null;
        if (response.content) |content| {
            if (content.get("application/json")) |media_type| {
                if (media_type.schema) |schema_or_ref| {
                    schema = try self.convertSchemaOrReference(schema_or_ref);
                }
            } else {
                var content_iterator = content.iterator();
                if (content_iterator.next()) |entry| {
                    if (entry.value_ptr.schema) |schema_or_ref| {
                        schema = try self.convertSchemaOrReference(schema_or_ref);
                    }
                }
            }
        }

        return Response{
            .description = description,
            .schema = schema,
            .headers = null,
        };
    }
};

fn hasEventStreamContent(resp_or_ref: ResponseOrReference3) bool {
    switch (resp_or_ref) {
        .reference => return false,
        .response => |resp| {
            if (resp.content) |content| {
                if (content.get("text/event-stream") != null) return true;
            }
            return false;
        },
    }
}
