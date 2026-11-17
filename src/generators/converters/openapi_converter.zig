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
const param_merge = @import("param_merge.zig");
const OpenApiDocument = @import("../../models/v3.0/openapi.zig").OpenApiDocument;
const Info3 = @import("../../models/v3.0/info.zig").Info;
const ExternalDocs3 = @import("../../models/v3.0/externaldocs.zig").ExternalDocumentation;
const Tag3 = @import("../../models/v3.0/tag.zig").Tag;
const Server3 = @import("../../models/v3.0/server.zig").Server;
const SecurityRequirement3 = @import("../../models/v3.0/security.zig").SecurityRequirement;
const UnifiedSecurityScheme = @import("../../models/common/document.zig").SecurityScheme;
const Components3 = @import("../../models/v3.0/components.zig").Components;
const SchemaOrReference3 = @import("../../models/v3.0/schema.zig").SchemaOrReference;
const Schema3 = @import("../../models/v3.0/schema.zig").Schema;
const AdditionalProperties3 = @import("../../models/v3.0/schema.zig").AdditionalProperties;
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
    /// Bodies declared under `components.requestBodies`, so that a request body
    /// given as a `$ref` keeps the schema it points at.
    source_request_bodies: ?*const std.StringHashMap(RequestBodyOrReference3) = null,
    /// Reusable parameters declared under `components.parameters`, so that a
    /// parameter given as a `$ref` resolves to the parameter it points at.
    component_parameters: ?*const std.StringHashMap(ParameterOrReference3) = null,
    /// Schemas declared under `components.schemas`, so that an `allOf` member
    /// given as a `$ref` resolves to the schema it composes.
    source_schemas: ?*const std.StringHashMap(SchemaOrReference3) = null,
    /// Names of the schemas whose `allOf` composition is currently being
    /// resolved, so that a cycle between them stops instead of recursing.
    active_all_of_refs: std.ArrayList([]const u8) = .empty,
    /// Responses declared under `components.responses`, so that a response given
    /// as a `$ref` keeps the schema it points at.
    source_responses: ?*const std.StringHashMap(ResponseOrReference3) = null,

    pub fn init(allocator: std.mem.Allocator) OpenApiConverter {
        return OpenApiConverter{ .allocator = allocator };
    }

    pub fn convert(self: *OpenApiConverter, openapi: OpenApiDocument) !UnifiedDocument {
        const version = openapi.openapi;
        const info = self.convertInfo(openapi.info);
        if (openapi.components) |*components| {
            if (components.requestBodies) |*bodies| self.source_request_bodies = bodies;
        }
        defer self.source_request_bodies = null;
        if (openapi.components) |*components| {
            if (components.parameters) |*component_parameters| {
                self.component_parameters = component_parameters;
            }
            if (components.schemas) |*component_schemas| {
                self.source_schemas = component_schemas;
            }
        }
        if (openapi.components) |*components| {
            if (components.responses) |*component_responses| self.source_responses = component_responses;
        }
        defer self.source_responses = null;
        defer self.component_parameters = null;
        defer self.source_schemas = null;
        defer {
            self.active_all_of_refs.deinit(self.allocator);
            self.active_all_of_refs = .empty;
        }
        const paths = try self.convertPaths(openapi.paths);
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

    const component_schema_prefix = "#/components/schemas/";

    /// The name a local component schema reference points at, or null for a
    /// reference this converter cannot resolve — an external document, or a
    /// pointer into anything other than `components.schemas`.
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
    fn convertResolvedSchemaReference(self: *OpenApiConverter, ref: []const u8) anyerror!?Schema {
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

    fn convertAdditionalProperties(additional: ?AdditionalProperties3) ?bool {
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
    fn convertAllOfSchema(self: *OpenApiConverter, schema: Schema3) anyerror!Schema {
        var merged_properties = std.StringHashMap(Schema).init(self.allocator);
        var required_list = std.ArrayList([]const u8).empty;
        var additional_properties = convertAdditionalProperties(schema.additionalProperties);

        if (schema.allOf) |all_of| {
            for (all_of) |item| {
                var converted = switch (item) {
                    .reference => |ref| (try self.convertResolvedSchemaReference(ref.ref)) orelse Schema{ .type = .reference, .ref = ref.ref },
                    .schema => |child| try self.convertSchema(child.*),
                };
                try self.takeProperties(&merged_properties, &converted);
                if (converted.required) |required| try self.mergeRequiredNames(&required_list, required);
                additional_properties = mergeAdditionalProperties(additional_properties, converted.additional_properties);
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
            .additional_properties = additional_properties,
            .nullable = schema.nullable orelse false,
        };
    }

    fn convertSchema(self: *OpenApiConverter, schema: Schema3) anyerror!Schema {
        if (nullableReference(schema)) |ref| {
            return Schema{ .type = .reference, .ref = ref, .description = schema.description, .nullable = true };
        }
        if (schema.allOf != null) {
            var converted = try self.convertAllOfSchema(schema);
            try self.attachComposition(&converted, schema);
            return converted;
        }

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
        const additional_properties = convertAdditionalProperties(schema.additionalProperties);

        var converted = Schema{
            .type = schema_type orelse (if (schema.oneOf != null or schema.anyOf != null) SchemaType.object else null),
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
            .additional_properties = additional_properties,
            .nullable = schema.nullable orelse false,
        };
        try self.attachComposition(&converted, schema);
        return converted;
    }

    /// `anyOf: [{$ref: X}, {type: object, nullable: true}]` is how OpenAPI 3.0
    /// writes "X or null". Returns the reference when `schema` has that shape.
    fn nullableReference(schema: Schema3) ?[]const u8 {
        // Sibling constraints would be lost by collapsing to the reference.
        if (schema.properties != null or schema.required != null or schema.allOf != null) return null;
        if ((schema.anyOf != null) == (schema.oneOf != null)) return null;
        const variants = schema.anyOf orelse schema.oneOf orelse return null;
        if (variants.len != 2) return null;
        var found: ?[]const u8 = null;
        var has_null = false;
        for (variants) |variant| switch (variant) {
            .reference => |reference| {
                if (found != null) return null;
                found = reference.ref;
            },
            .schema => |inline_schema| {
                const s = inline_schema.*;
                const bare = s.properties == null and s.items == null and s.allOf == null and
                    s.anyOf == null and s.oneOf == null and s.enum_values == null;
                const object_like = s.type == null or std.mem.eql(u8, s.type.?, "object");
                if (!(bare and object_like and (s.nullable orelse false))) return null;
                has_null = true;
            },
        };
        if (!has_null) return null;
        return found;
    }

    // JSON Schema composition applies alongside properties, not instead of
    // them. Retain both union keywords even when both occur on one schema.
    fn attachComposition(self: *OpenApiConverter, converted: *Schema, schema: Schema3) !void {
        if (schema.oneOf) |variants| converted.one_of = try self.convertUnionVariants(variants);
        if (schema.anyOf) |variants| converted.any_of = try self.convertUnionVariants(variants);
        if (schema.discriminator) |disc| {
            converted.discriminator_property = try self.allocator.dupe(u8, disc.propertyName);
            if (schema.oneOf) |variants| converted.one_of_refs = try self.convertUnionRefs(variants);
            if (schema.anyOf) |variants| converted.any_of_refs = try self.convertUnionRefs(variants);
        }
    }

    fn convertUnionVariants(self: *OpenApiConverter, variants: []const SchemaOrReference3) ![]Schema {
        const converted = try self.allocator.alloc(Schema, variants.len);
        errdefer self.allocator.free(converted);
        for (variants, 0..) |variant, i| {
            converted[i] = try self.convertSchemaOrReference(variant);
        }
        return converted;
    }

    fn convertUnionRefs(self: *OpenApiConverter, variants: []const SchemaOrReference3) !?[][]const u8 {
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

    fn refName(ref: []const u8) []const u8 {
        if (std.mem.lastIndexOf(u8, ref, "/")) |last_slash| return ref[last_slash + 1 ..];
        return ref;
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
        const get = try self.convertPathOperation(pathItem.get, pathItem.parameters);
        const put = try self.convertPathOperation(pathItem.put, pathItem.parameters);
        const post = try self.convertPathOperation(pathItem.post, pathItem.parameters);
        const delete = try self.convertPathOperation(pathItem.delete, pathItem.parameters);
        const options = try self.convertPathOperation(pathItem.options, pathItem.parameters);
        const head = try self.convertPathOperation(pathItem.head, pathItem.parameters);
        const patch = try self.convertPathOperation(pathItem.patch, pathItem.parameters);
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

    /// Converts an operation and merges the path item's parameters into it.
    fn convertPathOperation(self: *OpenApiConverter, raw_operation: ?Operation3, path_parameters: anytype) !?Operation {
        const raw = raw_operation orelse return null;
        var operation = try self.convertOperation(raw);
        if (path_parameters) |params| {
            const path_level = try self.convertParameters(params);
            try param_merge.mergePathLevel(self.allocator, &operation, path_level);
        }
        return operation;
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
            .next_link_name = operation.next_link_name,
        };
    }

    fn convertRequestBodyOrReference(self: *OpenApiConverter, requestBodyOrRef: *const RequestBodyOrReference3) !Parameter {
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
                if (self.resolveComponentResponse(ref.ref)) |resolved| {
                    return self.convertResponse(resolved);
                }
                return Response{ .description = ref.ref };
            },
            .response => |resp| {
                return self.convertResponse(resp);
            },
        }
    }

    /// Look up a `#/components/responses/<name>` reference. A component entry
    /// may itself be a Reference Object, so alias chains are followed; the hop
    /// limit bounds cyclic definitions.
    fn resolveComponentResponse(self: *OpenApiConverter, ref: []const u8) ?Response3 {
        const prefix = "#/components/responses/";
        const max_hops = 32;
        const responses = self.source_responses orelse return null;

        var current = ref;
        var hops: usize = 0;
        while (hops < max_hops) : (hops += 1) {
            if (!std.mem.startsWith(u8, current, prefix)) return null;
            const entry = responses.get(current[prefix.len..]) orelse return null;
            switch (entry) {
                .response => |response| return response,
                .reference => |next| current = next.ref,
            }
        }
        return null;
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
