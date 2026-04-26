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
const OpenApi31Document = @import("../../models/v3.1/openapi.zig").OpenApi31Document;
const Info31 = @import("../../models/v3.1/info.zig").Info;
const Contact31 = @import("../../models/v3.1/info.zig").Contact;
const License31 = @import("../../models/v3.1/info.zig").License;
const ExternalDocs31 = @import("../../models/v3.1/externaldocs.zig").ExternalDocumentation;
const Tag31 = @import("../../models/v3.1/tag.zig").Tag;
const Server31 = @import("../../models/v3.1/server.zig").Server;
const SecurityRequirement31 = @import("../../models/v3.1/security.zig").SecurityRequirement;
const Components31 = @import("../../models/v3.1/components.zig").Components;
const SchemaOrReference31 = @import("../../models/v3.1/schema.zig").SchemaOrReference;
const Schema31 = @import("../../models/v3.1/schema.zig").Schema;
const ParameterOrReference31 = @import("../../models/v3.1/parameter.zig").ParameterOrReference;
const Parameter31 = @import("../../models/v3.1/parameter.zig").Parameter;
const ResponseOrReference31 = @import("../../models/v3.1/response.zig").ResponseOrReference;
const Response31 = @import("../../models/v3.1/response.zig").Response;
const RequestBodyOrReference31 = @import("../../models/v3.1/requestbody.zig").RequestBodyOrReference;
const RequestBody31 = @import("../../models/v3.1/requestbody.zig").RequestBody;
const Operation31 = @import("../../models/v3.1/operation.zig").Operation;
const PathItem31 = @import("../../models/v3.1/paths.zig").PathItem;
const Paths31 = @import("../../models/v3.1/paths.zig").Paths;

pub const OpenApi31Converter = struct {
    allocator: std.mem.Allocator,
    source_schemas: ?*const std.StringHashMap(SchemaOrReference31) = null,

    pub fn init(allocator: std.mem.Allocator) OpenApi31Converter {
        return OpenApi31Converter{ .allocator = allocator };
    }

    pub fn convert(self: *OpenApi31Converter, openapi: OpenApi31Document) !UnifiedDocument {
        const version = openapi.openapi;
        const info = self.convertInfo(openapi.info);
        const paths = if (openapi.paths) |p| try self.convertPaths(p) else std.StringHashMap(PathItem).init(self.allocator);
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

    fn convertInfo(self: *OpenApi31Converter, info: Info31) DocumentInfo {
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

    fn convertServers(self: *OpenApi31Converter, servers: []Server31) ![]Server {
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

    fn convertSecurityRequirements(self: *OpenApi31Converter, security: []const SecurityRequirement31) ![]SecurityRequirement {
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

    fn convertTags(self: *OpenApi31Converter, tags: []const Tag31) ![]Tag {
        var converted_tags = try self.allocator.alloc(Tag, tags.len);
        for (tags, 0..) |tag, i| {
            const name = tag.name;
            const description = tag.description;
            const externalDocs = if (tag.externalDocs) |ext_docs| try self.convertExternalDocs(ext_docs) else null;
            converted_tags[i] = Tag{ .name = name, .description = description, .externalDocs = externalDocs };
        }
        return converted_tags;
    }

    fn convertExternalDocs(self: *OpenApi31Converter, externalDocs: ExternalDocs31) !ExternalDocumentation {
        _ = self;
        const url = externalDocs.url;
        const description = externalDocs.description;
        return ExternalDocumentation{ .url = url, .description = description };
    }

    fn convertSchemas(self: *OpenApi31Converter, components: Components31) !std.StringHashMap(Schema) {
        var schemas = std.StringHashMap(Schema).init(self.allocator);
        if (components.schemas) |schemas_map| {
            const previous_source_schemas = self.source_schemas;
            self.source_schemas = &schemas_map;
            defer self.source_schemas = previous_source_schemas;

            var schema_iterator = schemas_map.iterator();
            while (schema_iterator.next()) |entry| {
                const key = try self.allocator.dupe(u8, entry.key_ptr.*);
                const schema = try self.convertSchemaOrReference(entry.value_ptr.*);
                try schemas.put(key, schema);
            }
        }
        return schemas;
    }

    fn convertSchemaOrReference(self: *OpenApi31Converter, schemaOrRef: SchemaOrReference31) anyerror!Schema {
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

    fn refName(ref: []const u8) []const u8 {
        if (std.mem.lastIndexOf(u8, ref, "/")) |last_slash| {
            return ref[last_slash + 1 ..];
        }
        return ref;
    }

    fn convertResolvedSchemaReference(self: *OpenApi31Converter, ref: []const u8) anyerror!?Schema {
        const source_schemas = self.source_schemas orelse return null;
        const schema_or_ref = source_schemas.get(refName(ref)) orelse return null;
        return try self.convertSchemaOrReference(schema_or_ref);
    }

    fn mergeRequired(self: *OpenApi31Converter, required_list: *std.ArrayList([]const u8), required: ?[][]const u8) !void {
        if (required) |items| {
            for (items) |item| {
                var exists = false;
                for (required_list.items) |existing| {
                    if (std.mem.eql(u8, existing, item)) {
                        exists = true;
                        break;
                    }
                }
                if (!exists) try required_list.append(self.allocator, item);
            }
        }
    }

    fn cloneSchema(self: *OpenApi31Converter, schema: Schema) anyerror!Schema {
        const required = if (schema.required) |items| blk: {
            const cloned = try self.allocator.alloc([]const u8, items.len);
            @memcpy(cloned, items);
            break :blk cloned;
        } else null;

        const properties = if (schema.properties) |props| blk: {
            var cloned_props = std.StringHashMap(Schema).init(self.allocator);
            var iterator = props.iterator();
            while (iterator.next()) |entry| {
                const key = try self.allocator.dupe(u8, entry.key_ptr.*);
                try cloned_props.put(key, try self.cloneSchema(entry.value_ptr.*));
            }
            break :blk cloned_props;
        } else null;

        const items = if (schema.items) |item| blk: {
            const cloned_item = try self.allocator.create(Schema);
            cloned_item.* = try self.cloneSchema(item.*);
            break :blk cloned_item;
        } else null;

        const one_of_refs = if (schema.one_of_refs) |refs| try self.cloneStringList(refs) else null;
        const any_of_refs = if (schema.any_of_refs) |refs| try self.cloneStringList(refs) else null;
        const discriminator_property = if (schema.discriminator_property) |property| try self.allocator.dupe(u8, property) else null;
        const one_of = if (schema.one_of) |variants| try self.cloneSchemaList(variants) else null;
        const any_of = if (schema.any_of) |variants| try self.cloneSchemaList(variants) else null;

        return Schema{
            .type = schema.type,
            .ref = schema.ref,
            .title = schema.title,
            .description = schema.description,
            .format = schema.format,
            .required = required,
            .properties = properties,
            .items = items,
            .enum_values = schema.enum_values,
            .default = schema.default,
            .example = schema.example,
            .one_of_refs = one_of_refs,
            .any_of_refs = any_of_refs,
            .discriminator_property = discriminator_property,
            .one_of = one_of,
            .any_of = any_of,
        };
    }

    fn cloneSchemaList(self: *OpenApi31Converter, values: []const Schema) anyerror![]Schema {
        const cloned = try self.allocator.alloc(Schema, values.len);
        errdefer self.allocator.free(cloned);
        for (values, 0..) |value, i| cloned[i] = try self.cloneSchema(value);
        return cloned;
    }

    fn cloneStringList(self: *OpenApi31Converter, values: []const []const u8) ![][]const u8 {
        const cloned = try self.allocator.alloc([]const u8, values.len);
        errdefer self.allocator.free(cloned);
        for (values, 0..) |value, i| cloned[i] = try self.allocator.dupe(u8, value);
        return cloned;
    }

    fn mergeProperties(self: *OpenApi31Converter, merged: *std.StringHashMap(Schema), part: Schema) !void {
        if (part.properties) |props| {
            var iterator = props.iterator();
            while (iterator.next()) |entry| {
                const cloned = try self.cloneSchema(entry.value_ptr.*);
                if (merged.getEntry(entry.key_ptr.*)) |existing| {
                    existing.value_ptr.deinit(self.allocator);
                    existing.value_ptr.* = cloned;
                } else {
                    const key = try self.allocator.dupe(u8, entry.key_ptr.*);
                    try merged.put(key, cloned);
                }
            }
        }
    }

    fn convertAllOfSchema(self: *OpenApi31Converter, schema: Schema31) anyerror!Schema {
        var merged_properties = std.StringHashMap(Schema).init(self.allocator);
        var required_list = std.ArrayList([]const u8).empty;

        if (schema.allOf) |all_of| {
            for (all_of) |item| {
                var converted = switch (item) {
                    .reference => |ref| (try self.convertResolvedSchemaReference(ref.ref)) orelse Schema{ .type = .reference, .ref = ref.ref },
                    .schema => |child| try self.convertSchema(child.*),
                };
                try self.mergeProperties(&merged_properties, converted);
                try self.mergeRequired(&required_list, converted.required);
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

        if (schema.required) |required| {
            for (required) |item| try required_list.append(self.allocator, item);
        }

        const required = if (required_list.items.len > 0) try required_list.toOwnedSlice(self.allocator) else null;
        const has_properties = merged_properties.count() > 0;
        if (!has_properties) {
            merged_properties.deinit();
        }

        return Schema{
            .type = .object,
            .ref = null,
            .title = schema.title,
            .description = schema.description,
            .format = schema.format,
            .required = required,
            .properties = if (has_properties) merged_properties else null,
            .items = null,
            .enum_values = schema.enum_values,
            .default = schema.default,
            .example = schema.example,
        };
    }

    fn convertUnionVariants(self: *OpenApi31Converter, variants: []const SchemaOrReference31) ![]Schema {
        const converted = try self.allocator.alloc(Schema, variants.len);
        errdefer self.allocator.free(converted);
        for (variants, 0..) |variant, i| {
            converted[i] = try self.convertSchemaOrReference(variant);
        }
        return converted;
    }

    fn convertUnionRefs(self: *OpenApi31Converter, variants: []const SchemaOrReference31) !?[][]const u8 {
        var refs = try self.allocator.alloc([]const u8, variants.len);
        errdefer {
            for (refs[0..]) |ref| if (ref.len != 0) self.allocator.free(ref);
            self.allocator.free(refs);
        }
        for (refs) |*ref| ref.* = "";

        for (variants, 0..) |variant, i| {
            switch (variant) {
                .reference => |reference| refs[i] = try self.allocator.dupe(u8, refName(reference.ref)),
                .schema => {
                    for (refs) |ref| if (ref.len != 0) self.allocator.free(ref);
                    self.allocator.free(refs);
                    return null;
                },
            }
        }
        return refs;
    }

    fn convertUnionSchema(self: *OpenApi31Converter, schema: Schema31) anyerror!Schema {
        const discriminator = schema.discriminator;

        if (schema.oneOf) |one_of| {
            const variants = try self.convertUnionVariants(one_of);
            if (discriminator) |disc| {
                if (try self.convertUnionRefs(one_of)) |refs| {
                    return Schema{
                        .type = .object,
                        .one_of_refs = refs,
                        .discriminator_property = try self.allocator.dupe(u8, disc.propertyName),
                        .one_of = variants,
                    };
                }
            }
            return Schema{ .type = .object, .one_of = variants };
        }

        if (schema.anyOf) |any_of| {
            const variants = try self.convertUnionVariants(any_of);
            if (discriminator) |disc| {
                if (try self.convertUnionRefs(any_of)) |refs| {
                    return Schema{
                        .type = .object,
                        .any_of_refs = refs,
                        .discriminator_property = try self.allocator.dupe(u8, disc.propertyName),
                        .any_of = variants,
                    };
                }
            }
            return Schema{ .type = .object, .any_of = variants };
        }

        return Schema{
            .type = .object,
            .description = "OpenAPI oneOf with discriminator could not be generated safely; generator currently uses std.json.Value.",
        };
    }

    fn convertSchema(self: *OpenApi31Converter, schema: Schema31) anyerror!Schema {
        if (schema.allOf != null) {
            return try self.convertAllOfSchema(schema);
        }

        if ((schema.oneOf != null or schema.anyOf != null) and schema.properties == null) {
            return try self.convertUnionSchema(schema);
        }

        // Handle type_array (e.g. ["string", "null"]) by using the first non-null type
        const schema_type = blk: {
            if (schema.type) |type_str| {
                break :blk self.convertSchemaType(type_str);
            }
            if (schema.type_array) |type_arr| {
                for (type_arr) |t| {
                    if (!std.mem.eql(u8, t, "null")) {
                        break :blk self.convertSchemaType(t);
                    }
                }
            }
            break :blk null;
        };
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
        return Schema{
            .type = schema_type,
            .ref = null,
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

    fn convertSchemaType(self: *OpenApi31Converter, type_str: []const u8) SchemaType {
        _ = self;
        if (std.mem.eql(u8, type_str, "string")) return .string;
        if (std.mem.eql(u8, type_str, "number")) return .number;
        if (std.mem.eql(u8, type_str, "integer")) return .integer;
        if (std.mem.eql(u8, type_str, "boolean")) return .boolean;
        if (std.mem.eql(u8, type_str, "array")) return .array;
        if (std.mem.eql(u8, type_str, "object")) return .object;
        if (std.mem.eql(u8, type_str, "null")) return .null;
        return .string;
    }

    fn convertPaths(self: *OpenApi31Converter, paths: Paths31) !std.StringHashMap(PathItem) {
        var converted_paths = std.StringHashMap(PathItem).init(self.allocator);
        var path_iterator = paths.path_items.iterator();
        while (path_iterator.next()) |entry| {
            const path = try self.allocator.dupe(u8, entry.key_ptr.*);
            const path_item = try self.convertPathItem(entry.value_ptr.*);
            try converted_paths.put(path, path_item);
        }
        return converted_paths;
    }

    fn convertPathItem(self: *OpenApi31Converter, pathItem: PathItem31) !PathItem {
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

    fn convertOperation(self: *OpenApi31Converter, operation: Operation31) !Operation {
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
        if (operation.responses) |op_responses| {
            if (op_responses.default) |default_response| {
                const response = try self.convertResponseOrReference(default_response);
                const default_key = try self.allocator.dupe(u8, "default");
                try responses.put(default_key, response);
            }
            var resp_iterator = op_responses.status_codes.iterator();
            while (resp_iterator.next()) |entry| {
                const key = try self.allocator.dupe(u8, entry.key_ptr.*);
                const response = try self.convertResponseOrReference(entry.value_ptr.*);
                try responses.put(key, response);
            }
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

    fn convertRequestBodyOrReference(self: *OpenApi31Converter, requestBodyOrRef: *const RequestBodyOrReference31) !Parameter {
        switch (requestBodyOrRef.*) {
            .reference => |ref| {
                const name = try self.allocator.dupe(u8, ref.ref);
                return Parameter{
                    .name = name,
                    .location = .body,
                    .required = false,
                };
            },
            .request_body => |*body| {
                return self.convertRequestBody(body);
            },
        }
    }

    fn convertRequestBody(self: *OpenApi31Converter, requestBody: *const RequestBody31) !Parameter {
        var mut_request_body = requestBody.*;
        var schema: ?Schema = null;
        if (mut_request_body.content.get("application/json")) |media_type| {
            if (media_type.schema) |schema_or_ref| {
                schema = try self.convertSchemaOrReference(schema_or_ref);
            }
        } else if (mut_request_body.content.count() > 0) {
            var it = mut_request_body.content.iterator();
            if (it.next()) |entry| {
                if (entry.value_ptr.schema) |schema_or_ref| {
                    schema = try self.convertSchemaOrReference(schema_or_ref);
                }
            }
        }
        return Parameter{
            .name = "body",
            .location = .body,
            .description = requestBody.description,
            .required = requestBody.required orelse false,
            .schema = schema,
            .type = null,
            .format = null,
        };
    }

    fn convertParameters(self: *OpenApi31Converter, parameters: []const ParameterOrReference31) ![]Parameter {
        var converted_params = try self.allocator.alloc(Parameter, parameters.len);
        for (parameters, 0..) |param_ref, i| {
            converted_params[i] = try self.convertParameterOrReference(&param_ref);
        }
        return converted_params;
    }

    fn convertParameterOrReference(self: *OpenApi31Converter, paramOrRef: *const ParameterOrReference31) !Parameter {
        switch (paramOrRef.*) {
            .reference => |ref| {
                const name = try self.allocator.dupe(u8, ref.ref);
                return Parameter{
                    .name = name,
                    .location = .query,
                    .required = false,
                };
            },
            .parameter => |param| {
                return self.convertParameter(param);
            },
        }
    }

    fn convertParameter(self: *OpenApi31Converter, parameter: Parameter31) !Parameter {
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

    fn convertParameterLocation(self: *OpenApi31Converter, location: []const u8) ParameterLocation {
        _ = self;
        if (std.mem.eql(u8, location, "query")) return .query;
        if (std.mem.eql(u8, location, "header")) return .header;
        if (std.mem.eql(u8, location, "path")) return .path;
        if (std.mem.eql(u8, location, "cookie")) return .query;
        return .query;
    }

    fn convertResponseOrReference(self: *OpenApi31Converter, respOrRef: ResponseOrReference31) !Response {
        switch (respOrRef) {
            .reference => |ref| {
                const description = try self.allocator.dupe(u8, ref.ref);
                return Response{ .description = description };
            },
            .response => |resp| {
                return self.convertResponse(resp);
            },
        }
    }

    fn convertResponse(self: *OpenApi31Converter, response: Response31) !Response {
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
