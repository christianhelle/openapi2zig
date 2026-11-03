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
const test_utils = @import("../../tests/test_utils.zig");
const OpenApi32Document = @import("../../models/v3.2/openapi.zig").OpenApi32Document;
const Info32 = @import("../../models/v3.2/info.zig").Info;
const ExternalDocs32 = @import("../../models/v3.2/externaldocs.zig").ExternalDocumentation;
const Tag32 = @import("../../models/v3.2/tag.zig").Tag;
const Server32 = @import("../../models/v3.2/server.zig").Server;
const SecurityRequirement32 = @import("../../models/v3.2/security.zig").SecurityRequirement;
const UnifiedSecurityScheme = @import("../../models/common/document.zig").SecurityScheme;
const Components32 = @import("../../models/v3.2/components.zig").Components;
const SchemaOrReference32 = @import("../../models/v3.2/schema.zig").SchemaOrReference;
const Schema32 = @import("../../models/v3.2/schema.zig").Schema;
const AdditionalProperties32 = @import("../../models/v3.2/schema.zig").AdditionalProperties;
const ParameterOrReference32 = @import("../../models/v3.2/parameter.zig").ParameterOrReference;
const Parameter32 = @import("../../models/v3.2/parameter.zig").Parameter;
const ResponseOrReference32 = @import("../../models/v3.2/response.zig").ResponseOrReference;
const Response32 = @import("../../models/v3.2/response.zig").Response;
const RequestBodyOrReference32 = @import("../../models/v3.2/requestbody.zig").RequestBodyOrReference;
const RequestBody32 = @import("../../models/v3.2/requestbody.zig").RequestBody;
const Operation32 = @import("../../models/v3.2/operation.zig").Operation;
const PathItem32 = @import("../../models/v3.2/paths.zig").PathItem;
const Paths32 = @import("../../models/v3.2/paths.zig").Paths;

const component_schema_prefix = "#/components/schemas/";
pub const OpenApi32Converter = struct {
    allocator: std.mem.Allocator,
    /// Bodies declared under `components.requestBodies`, so that a request body
    /// given as a `$ref` keeps the schema it points at.
    source_request_bodies: ?*const std.StringHashMap(RequestBodyOrReference32) = null,
    /// Schemas declared under `components.schemas`, so that an `allOf` member
    /// given as a `$ref` resolves to the schema it composes.
    source_schemas: ?*const std.StringHashMap(SchemaOrReference32) = null,
    /// Names of the schemas whose `allOf` composition is currently being
    /// resolved, so that a cycle between them stops instead of recursing.
    active_all_of_refs: std.ArrayList([]const u8) = .empty,

    pub fn init(allocator: std.mem.Allocator) OpenApi32Converter {
        return OpenApi32Converter{ .allocator = allocator };
    }

    pub fn convert(self: *OpenApi32Converter, openapi: OpenApi32Document) !UnifiedDocument {
        const version = openapi.openapi;
        const info = self.convertInfo(openapi.info);
        if (openapi.components) |*components| {
            if (components.requestBodies) |*bodies| self.source_request_bodies = bodies;
            if (components.schemas) |*component_schemas| self.source_schemas = component_schemas;
        }
        defer self.source_request_bodies = null;
        defer self.source_schemas = null;
        defer {
            self.active_all_of_refs.deinit(self.allocator);
            self.active_all_of_refs = .empty;
        }
        const paths = if (openapi.paths) |p| try self.convertPaths(p) else std.StringHashMap(PathItem).init(self.allocator);
        const servers = if (openapi.servers) |servers_list| try self.convertServers(servers_list) else null;
        const security = if (openapi.security) |security_list| try self.convertSecurityRequirements(security_list) else null;
        const tags = if (openapi.tags) |tags_list| try self.convertTags(tags_list) else null;
        const externalDocs = if (openapi.externalDocs) |ext_docs| try self.convertExternalDocs(ext_docs) else null;
        const schemas = if (openapi.components) |components| try self.convertSchemas(components) else null;
        const security_schemes = if (openapi.components) |components| try self.convertSecuritySchemes(components) else null;
        var document = UnifiedDocument{
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
        errdefer document.deinit(self.allocator);
        try @import("../../models/common/streaming.zig").detectRequestStreaming(self.allocator, paths, schemas);
        return document;
    }

    fn convertSecuritySchemes(self: *OpenApi32Converter, components: Components32) std.mem.Allocator.Error!?*std.StringHashMap(UnifiedSecurityScheme) {
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

    fn convertInfo(self: *OpenApi32Converter, info: Info32) DocumentInfo {
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

    fn convertServers(self: *OpenApi32Converter, servers: []Server32) ![]Server {
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

    fn convertSecurityRequirements(self: *OpenApi32Converter, security: []const SecurityRequirement32) ![]SecurityRequirement {
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

    fn convertTags(self: *OpenApi32Converter, tags: []const Tag32) ![]Tag {
        var converted_tags = try self.allocator.alloc(Tag, tags.len);
        for (tags, 0..) |tag, i| {
            const name = tag.name;
            const description = tag.description;
            const externalDocs = if (tag.externalDocs) |ext_docs| try self.convertExternalDocs(ext_docs) else null;
            converted_tags[i] = Tag{ .name = name, .description = description, .externalDocs = externalDocs };
        }
        return converted_tags;
    }

    fn convertExternalDocs(self: *OpenApi32Converter, externalDocs: ExternalDocs32) !ExternalDocumentation {
        _ = self;
        const url = externalDocs.url;
        const description = externalDocs.description;
        return ExternalDocumentation{ .url = url, .description = description };
    }

    fn convertSchemas(self: *OpenApi32Converter, components: Components32) !std.StringHashMap(Schema) {
        var schemas = std.StringHashMap(Schema).init(self.allocator);
        errdefer deinitSchemaMap(self.allocator, &schemas);
        if (components.schemas) |schemas_map| {
            var schema_iterator = schemas_map.iterator();
            while (schema_iterator.next()) |entry| {
                try schemas.ensureUnusedCapacity(1);
                const key = try self.allocator.dupe(u8, entry.key_ptr.*);
                errdefer self.allocator.free(key);
                const schema = try self.convertSchemaOrReference(entry.value_ptr.*);
                schemas.putAssumeCapacity(key, schema);
            }
        }
        return schemas;
    }

    fn convertSchemaOrReference(self: *OpenApi32Converter, schemaOrRef: SchemaOrReference32) anyerror!Schema {
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

    fn componentSchemaName(ref: []const u8) ?[]const u8 {
        if (!std.mem.startsWith(u8, ref, component_schema_prefix)) return null;
        const name = ref[component_schema_prefix.len..];
        if (name.len == 0) return null;
        if (std.mem.indexOfAny(u8, name, "/#") != null) return null;
        return name;
    }

    /// Convert the schema a `$ref` points at, or null when it names something
    /// absent from `components.schemas` or already being resolved further up
    /// the same `allOf` chain.
    fn convertResolvedSchemaReference(self: *OpenApi32Converter, ref: []const u8) anyerror!?Schema {
        const source_schemas = self.source_schemas orelse return null;
        const name = componentSchemaName(ref) orelse return null;
        for (self.active_all_of_refs.items) |active| {
            if (std.mem.eql(u8, active, name)) return null;
        }
        const schema_or_ref = source_schemas.get(name) orelse return null;
        try self.active_all_of_refs.append(self.allocator, name);
        defer _ = self.active_all_of_refs.pop();
        return switch (schema_or_ref) {
            // A component that is itself a reference is an alias; follow it so
            // the composing schema inherits the fields of the schema it names.
            .reference => |alias| try self.convertResolvedSchemaReference(alias.ref),
            .schema => |schema| try self.convertSchema(schema.*),
        };
    }

    /// Append every name not already present, so the required lists of the
    /// `allOf` members and their parent combine without duplicates.
    fn mergeRequiredNames(self: *OpenApi32Converter, required_list: *std.ArrayList([]const u8), names: []const []const u8) !void {
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
    fn takeProperties(self: *OpenApi32Converter, merged: *std.StringHashMap(Schema), part: *Schema) !void {
        var props = part.properties orelse return;
        // Reserve before detaching the map, so the transfer itself cannot fail
        // and leave entries owned by neither map.
        try merged.ensureUnusedCapacity(props.count());
        part.properties = null;
        var iterator = props.iterator();
        while (iterator.next()) |entry| {
            if (merged.getEntry(entry.key_ptr.*)) |existing| {
                existing.value_ptr.deinit(self.allocator);
                existing.value_ptr.* = entry.value_ptr.*;
                self.allocator.free(entry.key_ptr.*);
            } else {
                merged.putAssumeCapacity(entry.key_ptr.*, entry.value_ptr.*);
            }
        }
        props.deinit();
    }

    fn deinitSchemaMap(allocator: std.mem.Allocator, map: *std.StringHashMap(Schema)) void {
        var iterator = map.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        map.deinit();
    }

    fn freeItems(allocator: std.mem.Allocator, items: ?*Schema) void {
        const schema = items orelse return;
        schema.deinit(allocator);
        allocator.destroy(schema);
    }

    fn convertAdditionalProperties(additional: ?AdditionalProperties32) ?bool {
        const value = additional orelse return null;
        return switch (value) {
            .boolean => |allowed| allowed,
            .schema_or_reference => null,
        };
    }

    /// `allOf` conjoins its members, so a member that forbids additional
    /// properties forbids them for the whole composition.
    fn mergeAdditionalProperties(current: ?bool, incoming: ?bool) ?bool {
        const next = incoming orelse return current;
        const existing = current orelse return next;
        return existing and next;
    }

    /// Flatten an `allOf` composition into a single object schema by merging
    /// the properties and required lists of its members with the ones the
    /// composing schema declares itself.
    fn convertAllOfSchema(self: *OpenApi32Converter, schema: Schema32) anyerror!Schema {
        var merged_properties = std.StringHashMap(Schema).init(self.allocator);
        errdefer deinitSchemaMap(self.allocator, &merged_properties);
        var required_list = std.ArrayList([]const u8).empty;
        errdefer required_list.deinit(self.allocator);
        var additional_properties = convertAdditionalProperties(schema.additionalProperties);
        const declared_type = self.declaredSchemaType(schema);
        var boolean_type = declared_type == .boolean;
        var enum_values = schema.enum_values;
        var array_member = false;
        var items: ?*Schema = null;
        errdefer freeItems(self.allocator, items);

        if (schema.allOf) |all_of| {
            for (all_of) |item| {
                var converted = switch (item) {
                    .reference => |ref| (try self.convertResolvedSchemaReference(ref.ref)) orelse Schema{ .type = .reference, .ref = ref.ref },
                    .schema => |child| try self.convertSchema(child.*),
                };
                defer converted.deinit(self.allocator);
                try self.takeProperties(&merged_properties, &converted);
                if (converted.required) |required| try self.mergeRequiredNames(&required_list, required);
                additional_properties = mergeAdditionalProperties(additional_properties, converted.additional_properties);
                if (converted.type == .boolean) boolean_type = true;
                if (converted.type == .array) {
                    array_member = true;
                    if (converted.items) |member_items| {
                        freeItems(self.allocator, items);
                        items = member_items;
                        converted.items = null;
                    }
                }
                // Preserve an enum that rules true out when flattening a
                // boolean allOf. This is not a general satisfiability solver.
                if (converted.enum_values) |values| {
                    var permits_true = false;
                    for (values) |value| {
                        if (value == .bool and value.bool) permits_true = true;
                    }
                    if (!permits_true or enum_values == null) enum_values = values;
                }
            }
        }

        if (schema.properties) |props| {
            var prop_iterator = props.iterator();
            while (prop_iterator.next()) |entry| {
                var prop_schema = try self.convertSchemaOrReference(entry.value_ptr.*);
                errdefer prop_schema.deinit(self.allocator);
                if (merged_properties.getEntry(entry.key_ptr.*)) |existing| {
                    existing.value_ptr.deinit(self.allocator);
                    existing.value_ptr.* = prop_schema;
                } else {
                    try merged_properties.ensureUnusedCapacity(1);
                    const key = try self.allocator.dupe(u8, entry.key_ptr.*);
                    merged_properties.putAssumeCapacity(key, prop_schema);
                }
            }
        }

        if (schema.required) |required| try self.mergeRequiredNames(&required_list, required);

        if (try self.convertSchemaItems(schema)) |own_items| {
            freeItems(self.allocator, items);
            items = own_items;
        }
        const required = if (required_list.items.len > 0) try required_list.toOwnedSlice(self.allocator) else null;
        const has_properties = merged_properties.count() > 0;
        if (!has_properties) merged_properties.deinit();
        const member_type: SchemaType = if (boolean_type and !has_properties) .boolean else if (array_member and !has_properties) .array else .object;
        const merged_type: SchemaType = if (member_type == .boolean) .boolean else declared_type orelse member_type;

        return Schema{
            .type = merged_type,
            .ref = null,
            .title = schema.title,
            .description = schema.description,
            .format = schema.format,
            .required = required,
            .properties = if (has_properties) merged_properties else null,
            .items = items,
            .enum_values = if (merged_type == .boolean) enum_values else null,
            .default = schema.default,
            .example = schema.example,
            .additional_properties = additional_properties,
            .nullable = isNullable(schema),
        };
    }

    /// Handle type_array (e.g. ["string", "null"]) by using the first non-null type
    fn declaredSchemaType(self: *OpenApi32Converter, schema: Schema32) ?SchemaType {
        if (schema.type) |type_str| return self.convertSchemaType(type_str);
        if (schema.type_array) |type_arr| {
            for (type_arr) |t| {
                if (!std.mem.eql(u8, t, "null")) return self.convertSchemaType(t);
            }
        }
        return null;
    }

    fn isNullable(schema: Schema32) bool {
        if (schema.nullable) |nullable| return nullable;
        if (schema.type_array) |type_arr| {
            for (type_arr) |t| {
                if (std.mem.eql(u8, t, "null")) return true;
            }
        }
        return false;
    }

    fn convertSchemaItems(self: *OpenApi32Converter, schema: Schema32) anyerror!?*Schema {
        const items_ref = schema.items orelse return null;
        var items_schema = try self.convertSchemaOrReference(items_ref);
        errdefer items_schema.deinit(self.allocator);
        const items_ptr = try self.allocator.create(Schema);
        items_ptr.* = items_schema;
        return items_ptr;
    }

    fn convertSchema(self: *OpenApi32Converter, schema: Schema32) anyerror!Schema {
        if (schema.allOf != null) return try self.convertAllOfSchema(schema);

        const schema_type = self.declaredSchemaType(schema);
        const nullable = isNullable(schema);
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
        errdefer if (required) |req_array| self.allocator.free(req_array);
        var properties = if (schema.properties) |props| blk: {
            var props_map = std.StringHashMap(Schema).init(self.allocator);
            errdefer deinitSchemaMap(self.allocator, &props_map);
            var prop_iterator = props.iterator();
            while (prop_iterator.next()) |entry| {
                try props_map.ensureUnusedCapacity(1);
                const key = try self.allocator.dupe(u8, entry.key_ptr.*);
                errdefer self.allocator.free(key);
                const prop_schema = try self.convertSchemaOrReference(entry.value_ptr.*);
                props_map.putAssumeCapacity(key, prop_schema);
            }
            break :blk props_map;
        } else null;
        errdefer if (properties) |*props_map| deinitSchemaMap(self.allocator, props_map);
        const items = try self.convertSchemaItems(schema);
        const additional_properties: ?bool = if (schema.additionalProperties) |ap| switch (ap) {
            .boolean => |b| b,
            .schema_or_reference => null,
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
            .enum_values = if (schema_type == .boolean) schema.enum_values else null,
            .default = schema.default,
            .example = schema.example,
            .additional_properties = additional_properties,
            .nullable = nullable,
        };
    }

    fn convertSchemaType(self: *OpenApi32Converter, type_str: []const u8) SchemaType {
        _ = self;
        if (std.mem.eql(u8, type_str, "string")) return .string;
        if (std.mem.eql(u8, type_str, "number")) return .number;
        if (std.mem.eql(u8, type_str, "integer")) return .integer;
        if (std.mem.eql(u8, type_str, "boolean")) return .boolean;
        if (std.mem.eql(u8, type_str, "array")) return .array;
        if (std.mem.eql(u8, type_str, "object")) return .object;
        return .string;
    }

    fn convertPaths(self: *OpenApi32Converter, paths: Paths32) !std.StringHashMap(PathItem) {
        var converted_paths = std.StringHashMap(PathItem).init(self.allocator);
        var path_iterator = paths.path_items.iterator();
        while (path_iterator.next()) |entry| {
            const path = try self.allocator.dupe(u8, entry.key_ptr.*);
            const path_item = try self.convertPathItem(entry.value_ptr.*);
            try converted_paths.put(path, path_item);
        }
        return converted_paths;
    }

    fn convertPathItem(self: *OpenApi32Converter, pathItem: PathItem32) !PathItem {
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

    fn convertOperation(self: *OpenApi32Converter, operation: Operation32) !Operation {
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

    fn convertRequestBodyOrReference(self: *OpenApi32Converter, requestBodyOrRef: *const RequestBodyOrReference32) !Parameter {
        switch (requestBodyOrRef.*) {
            .reference => |ref| {
                // Follow component aliases iteratively; a local visited set
                // handles cycles without restricting valid alias-chain depth.
                var visited = std.StringHashMap(void).init(self.allocator);
                defer visited.deinit();
                var current = ref.ref;
                while (std.mem.startsWith(u8, current, "#/components/requestBodies/")) {
                    if ((try visited.getOrPut(current)).found_existing) break;
                    const bodies = self.source_request_bodies orelse break;
                    const target = bodies.get(current["#/components/requestBodies/".len..]) orelse break;
                    switch (target) {
                        .reference => |alias| current = alias.ref,
                        .request_body => |*body| {
                            var parameter = try self.convertRequestBody(body);
                            parameter.name = ref.ref;
                            return parameter;
                        },
                    }
                }
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

    fn convertRequestBody(self: *OpenApi32Converter, requestBody: *const RequestBody32) !Parameter {
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

    fn convertParameters(self: *OpenApi32Converter, parameters: []const ParameterOrReference32) ![]Parameter {
        var converted_params = try self.allocator.alloc(Parameter, parameters.len);
        for (parameters, 0..) |param_ref, i| {
            converted_params[i] = try self.convertParameterOrReference(&param_ref);
        }
        return converted_params;
    }

    fn convertParameterOrReference(self: *OpenApi32Converter, paramOrRef: *const ParameterOrReference32) !Parameter {
        switch (paramOrRef.*) {
            .reference => |ref| {
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

    fn convertParameter(self: *OpenApi32Converter, parameter: Parameter32) !Parameter {
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

    fn convertParameterLocation(self: *OpenApi32Converter, location: []const u8) ParameterLocation {
        _ = self;
        if (std.mem.eql(u8, location, "query")) return .query;
        if (std.mem.eql(u8, location, "header")) return .header;
        if (std.mem.eql(u8, location, "path")) return .path;
        if (std.mem.eql(u8, location, "cookie")) return .query;
        return .query;
    }

    fn convertResponseOrReference(self: *OpenApi32Converter, respOrRef: ResponseOrReference32) !Response {
        switch (respOrRef) {
            .reference => |ref| {
                return Response{ .description = ref.ref };
            },
            .response => |resp| {
                return self.convertResponse(resp);
            },
        }
    }

    fn convertResponse(self: *OpenApi32Converter, response: Response32) !Response {
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

fn hasEventStreamContent(resp_or_ref: ResponseOrReference32) bool {
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

fn exerciseSchemaConversion(allocator: std.mem.Allocator, document: *const OpenApi32Document) !void {
    var converter = OpenApi32Converter.init(allocator);
    defer converter.active_all_of_refs.deinit(allocator);
    const schemas = document.components.?.schemas.?;
    converter.source_schemas = &schemas;
    var converted = try converter.convertSchemas(document.components.?);
    OpenApi32Converter.deinitSchemaMap(allocator, &converted);
}

test "schema conversion frees partial results when allocation fails" {
    const source =
        \\{"openapi":"3.2.0","info":{"title":"t","version":"1"},"paths":{},"components":{"schemas":{
        \\"Base":{"type":"object","required":["id"],"properties":{"id":{"type":"string"},"nested":{"type":"object","required":["x"],"properties":{"x":{"type":"array","items":{"type":"string"}}}}}},
        \\"Names":{"type":"array","items":{"type":"string"}},
        \\"Derived":{"type":"array","items":{"type":"string"},"required":["own"],"allOf":[{"$ref":"#/components/schemas/Names"},{"$ref":"#/components/schemas/Base"},{"type":"object","required":["id","name"],"properties":{"id":{"type":"integer"},"name":{"type":"string"}}}],"properties":{"own":{"type":"string"},"name":{"type":"integer"}}}
        \\}}}
    ;
    var document = try OpenApi32Document.parseFromJson(std.testing.allocator, source);
    defer document.deinit(std.testing.allocator);
    var no_resize: test_utils.NoResizeAllocator = .{ .child = std.testing.allocator };
    try std.testing.checkAllAllocationFailures(no_resize.allocator(), exerciseSchemaConversion, .{&document});
}
