const std = @import("std");
const cli = @import("../../cli.zig");
const UnifiedDocument = @import("../../models/common/document.zig").UnifiedDocument;
const SecurityScheme = @import("../../models/common/document.zig").SecurityScheme;
const Operation = @import("../../models/common/document.zig").Operation;
const Schema = @import("../../models/common/document.zig").Schema;
const SchemaType = @import("../../models/common/document.zig").SchemaType;
const Parameter = @import("../../models/common/document.zig").Parameter;
const media_type = @import("../../media_type.zig");
const ident = @import("ident_utils.zig");
const helpers = @import("api_generator/helpers.zig");

const BodyKind = helpers.BodyKind;
const AuthScheme = helpers.AuthScheme;
const HeaderLocalNames = helpers.HeaderLocalNames;
const startsWithIgnoreCase = helpers.startsWithIgnoreCase;
const endsWithIgnoreCase = helpers.endsWithIgnoreCase;
const escapeZigString = helpers.escapeZigString;
const classifyBody = helpers.classifyBody;
const findBodyParam = helpers.findBodyParam;
const bodyKindFor = helpers.bodyKindFor;
const hasHeaderParams = helpers.hasHeaderParams;
const QueryPrefixInfo = helpers.QueryPrefixInfo;
const computeQueryPrefixInfo = helpers.computeQueryPrefixInfo;
const OperationRef = helpers.OperationRef;
const documentHasStreamingOperations = helpers.documentHasStreamingOperations;
const authSchemeFor = helpers.authSchemeFor;
const authSchemeForOperation = helpers.authSchemeForOperation;
const ResourceWrapper = helpers.ResourceWrapper;
const TagClient = helpers.TagClient;
const operationRefLessThan = helpers.operationRefLessThan;
const collectOperationRefs = helpers.collectOperationRefs;
const tagClientLessThan = helpers.tagClientLessThan;
const toPascalCaseAlloc = helpers.toPascalCaseAlloc;
const resourceWrapperLessThan = helpers.resourceWrapperLessThan;
const stringLessThan = helpers.stringLessThan;
const stringListOrder = helpers.stringListOrder;
const sameStringList = helpers.sameStringList;
const containsString = helpers.containsString;
const isVersionSegment = helpers.isVersionSegment;
const isPathParam = helpers.isPathParam;

pub const UnifiedApiGenerator = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    args: cli.CliArgs,
    /// Reserved names of generated options struct types, keyed by operation id
    /// (or by path for operations without one). Options type names are
    /// disambiguated against every top-level declaration so generated clients
    /// always compile.
    options_type_names: std.StringHashMap([]const u8),
    /// Cached options struct field names, keyed by operation identity and
    /// parameter name/location. Populated on first use so repeated parameter
    /// references don't rescan the operation's parameter list.
    options_field_names: std.StringHashMap([]const u8),
    /// Zig-friendly declaration names, keyed by the raw operationId from the
    /// specification. Ids such as GitHub's
    /// `repos/list-pull-requests-associated-with-commit` are not valid Zig
    /// identifiers; caching the camel cased form keeps every declaration
    /// derived from one id consistent and keeps the names alive for the
    /// lifetime of the generator.
    operation_names: std.StringHashMap([]const u8),
    /// Schemas emitted as top-level types into the same file as the client.
    /// Zig forbids a parameter from shadowing a declaration in scope, so flat
    /// parameter names matching one of these get a suffix. Only set for
    /// single-file output; multi-file keeps models behind `model_prefix`.
    inlined_model_names: ?*const std.StringHashMap(Schema) = null,
    model_prefix: []const u8 = "",
    emit_imports: bool = true,
    models_import: []const u8 = "models.zig",
    models_import_alias: []const u8 = "models",
    runtime_import: []const u8 = "runtime.zig",
    runtime_import_alias: []const u8 = "runtime",
    has_streaming_operations: bool = false,
    auth_scheme: AuthScheme = .bearer,

    pub fn init(allocator: std.mem.Allocator, args: cli.CliArgs) UnifiedApiGenerator {
        return UnifiedApiGenerator{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).empty,
            .args = args,
            .options_type_names = std.StringHashMap([]const u8).init(allocator),
            .options_field_names = std.StringHashMap([]const u8).init(allocator),
            .operation_names = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn clearOptionsTypeNames(self: *UnifiedApiGenerator, allocator: std.mem.Allocator) void {
        var iterator = self.options_type_names.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.options_type_names.clearRetainingCapacity();
    }

    pub fn clearOptionsFieldNames(self: *UnifiedApiGenerator, allocator: std.mem.Allocator) void {
        var iterator = self.options_field_names.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.options_field_names.clearRetainingCapacity();
    }

    pub fn clearOperationNames(self: *UnifiedApiGenerator, allocator: std.mem.Allocator) void {
        var iterator = self.operation_names.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.operation_names.clearRetainingCapacity();
    }

    /// Assign a declaration name to every operation id in the document.
    /// Camel casing can collapse two distinct ids onto one name (e.g.
    /// `get-pet` and `getPet`), so later arrivals take an underscore suffix.
    /// Names are assigned in path/method order rather than hash order so the
    /// same document always generates the same names.
    pub fn reserveOperationNames(self: *UnifiedApiGenerator, document: UnifiedDocument) !void {
        var operations = std.ArrayList(OperationRef).empty;
        defer operations.deinit(self.allocator);
        try collectOperationRefs(&operations, self.allocator, document);
        std.mem.sort(OperationRef, operations.items, {}, operationRefLessThan);

        for (operations.items) |op_ref| {
            const operation_id = op_ref.operation.operationId orelse continue;
            if (self.operation_names.contains(operation_id)) continue;

            var name = try ident.toZigMethodNameAlloc(self.allocator, operation_id);
            errdefer self.allocator.free(name);
            while (self.operationNameTaken(name)) {
                const suffixed = try std.fmt.allocPrint(self.allocator, "{s}_", .{name});
                self.allocator.free(name);
                name = suffixed;
            }
            const key = try self.allocator.dupe(u8, operation_id);
            errdefer self.allocator.free(key);
            try self.operation_names.put(key, name);
        }
    }

    fn operationNameTaken(self: *UnifiedApiGenerator, name: []const u8) bool {
        var iterator = self.operation_names.valueIterator();
        while (iterator.next()) |taken| {
            if (std.mem.eql(u8, taken.*, name)) return true;
        }
        return false;
    }

    /// The name used for declarations generated from `operation_id`. The
    /// returned slice is owned by the generator and stays valid until the next
    /// `generate` call.
    pub fn operationName(self: *UnifiedApiGenerator, operation_id: []const u8) ![]const u8 {
        if (self.operation_names.get(operation_id)) |name| return name;
        const name = try ident.toZigMethodNameAlloc(self.allocator, operation_id);
        errdefer self.allocator.free(name);
        const key = try self.allocator.dupe(u8, operation_id);
        errdefer self.allocator.free(key);
        try self.operation_names.put(key, name);
        return name;
    }

    /// The declaration name for `operation`, or null when it has no operationId.
    pub fn operationNameOf(self: *UnifiedApiGenerator, operation: Operation) !?[]const u8 {
        const operation_id = operation.operationId orelse return null;
        return try self.operationName(operation_id);
    }

    pub fn deinit(self: *UnifiedApiGenerator) void {
        self.buffer.deinit(self.allocator);
        self.clearOptionsTypeNames(self.allocator);
        self.options_type_names.deinit();
        self.clearOptionsFieldNames(self.allocator);
        self.options_field_names.deinit();
        self.clearOperationNames(self.allocator);
        self.operation_names.deinit();
    }

    pub fn generate(self: *UnifiedApiGenerator, document: UnifiedDocument) ![]const u8 {
        if (document.schemas) |*schemas| self.inlined_model_names = schemas;
        defer self.inlined_model_names = null;
        self.buffer.clearRetainingCapacity();
        self.clearOptionsTypeNames(self.allocator);
        self.clearOptionsFieldNames(self.allocator);
        self.clearOperationNames(self.allocator);
        try self.reserveOperationNames(document);
        self.has_streaming_operations = documentHasStreamingOperations(document);
        self.auth_scheme = authSchemeFor(document);
        try self.generateHeader();
        try self.generateApiClient(document);
        if (self.args.resource_wrappers != .none) {
            try self.generateResourceWrappers(document);
        }
        if (self.args.multiple_clients == .per_tag) {
            try self.generateTagClients(document);
        }
        if (self.args.multiple_clients == .per_endpoint) {
            try self.generateEndpointClients(document);
        }
        return try self.allocator.dupe(u8, self.buffer.items);
    }

    pub fn generateClientOnly(self: *UnifiedApiGenerator, document: UnifiedDocument) ![]const u8 {
        self.buffer.clearRetainingCapacity();
        self.clearOptionsTypeNames(self.allocator);
        self.clearOptionsFieldNames(self.allocator);
        self.clearOperationNames(self.allocator);
        try self.reserveOperationNames(document);
        self.has_streaming_operations = documentHasStreamingOperations(document);
        self.auth_scheme = authSchemeFor(document);
        try self.generateHeaderMulti();
        try self.generateApiClient(document);
        if (self.args.resource_wrappers != .none) {
            try self.generateResourceWrappers(document);
        }
        if (self.args.multiple_clients == .per_tag) {
            try self.generateTagClients(document);
        }
        if (self.args.multiple_clients == .per_endpoint) {
            try self.generateEndpointClients(document);
        }
        return try self.allocator.dupe(u8, self.buffer.items);
    }

    pub fn appendIdentifier(self: *UnifiedApiGenerator, name: []const u8) !void {
        try ident.appendIdentifier(&self.buffer, self.allocator, name);
    }

    pub fn appendFieldIdentifier(self: *UnifiedApiGenerator, name: []const u8) !void {
        try ident.appendFieldIdentifier(&self.buffer, self.allocator, name);
    }

    pub fn appendEscapedIdentifier(self: *UnifiedApiGenerator, name: []const u8) !void {
        try ident.appendEscapedIdentifier(&self.buffer, self.allocator, name);
    }

    /// True when this name is a model type declared at the top level of the same
    /// file, and so cannot be reused or referenced bare from a nested scope.
    pub fn isInlinedModelName(self: *UnifiedApiGenerator, name: []const u8) bool {
        const schemas = self.inlined_model_names orelse return false;
        return schemas.contains(name);
    }

    /// Append a flat parameter identifier, renaming it when the spec's parameter
    /// name collides with a model type sharing the output file.
    pub fn appendFlatParamIdentifier(self: *UnifiedApiGenerator, name: []const u8) !void {
        if (!self.isInlinedModelName(name)) {
            try self.appendIdentifier(name);
            return;
        }
        const safe_name = try self.sanitizeIdentifierAlloc(name);
        defer self.allocator.free(safe_name);
        try self.buffer.appendSlice(self.allocator, safe_name);
        try self.buffer.appendSlice(self.allocator, "_param");
    }

    pub fn appendLineComment(self: *UnifiedApiGenerator, text: []const u8) !void {
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |line| {
            try self.buffer.appendSlice(self.allocator, "// ");
            // Zig rejects tabs inside comments, so descriptions carried over from
            // the specification (markdown tables, indented text) get spaces here.
            // Most lines have no tab at all, so those are copied in one go.
            const trimmed = std.mem.trim(u8, line, "\r");
            if (std.mem.indexOfScalar(u8, trimmed, '\t') == null) {
                try self.buffer.appendSlice(self.allocator, trimmed);
            } else {
                for (trimmed) |c| {
                    try self.buffer.append(self.allocator, if (c == '\t') ' ' else c);
                }
            }
            try self.buffer.appendSlice(self.allocator, "\n");
        }
    }

    pub const generateHeader = @import("api_generator/preamble.zig").generateHeader;
    pub const generateHeaderMulti = @import("api_generator/preamble.zig").generateHeaderMulti;
    pub const generateRuntimePreamble = @import("api_generator/preamble.zig").generateRuntimePreamble;
    pub const generateRuntimeReexports = @import("api_generator/preamble.zig").generateRuntimeReexports;
    pub const generateClientPreamble = @import("api_generator/preamble.zig").generateClientPreamble;
    pub const generateCancelWatcher = @import("api_generator/preamble.zig").generateCancelWatcher;
    pub const generateSsePreamble = @import("api_generator/preamble.zig").generateSsePreamble;
    pub const generateStreamAuthCode = @import("api_generator/preamble.zig").generateStreamAuthCode;
    pub const generateSseBufferConstants = @import("api_generator/preamble.zig").generateSseBufferConstants;
    pub const generateHttpObserverType = @import("api_generator/preamble.zig").generateHttpObserverType;
    pub const appendFlatCallArguments = @import("api_generator/options.zig").appendFlatCallArguments;
    pub const appendParamBaseType = @import("api_generator/options.zig").appendParamBaseType;
    pub const appendOptionsParam = @import("api_generator/options.zig").appendOptionsParam;
    pub const optionsTypeKeyAlloc = @import("api_generator/options.zig").optionsTypeKeyAlloc;
    pub const appendOptionsTypeName = @import("api_generator/options.zig").appendOptionsTypeName;
    pub const appendRawOptionsTypeName = @import("api_generator/options.zig").appendRawOptionsTypeName;
    pub const generateOptionsType = @import("api_generator/options.zig").generateOptionsType;
    pub const appendBodyParams = @import("api_generator/options.zig").appendBodyParams;
    pub const optionsFieldNameAlloc = @import("api_generator/options.zig").optionsFieldNameAlloc;
    pub const optionsFieldNameKeyAlloc = @import("api_generator/options.zig").optionsFieldNameKeyAlloc;
    pub const computeOptionsFieldName = @import("api_generator/options.zig").computeOptionsFieldName;
    pub const appendParamReference = @import("api_generator/options.zig").appendParamReference;
    pub const appendFlatOperationParameters = @import("api_generator/options.zig").appendFlatOperationParameters;
    pub const appendUnusedParameters = @import("api_generator/options.zig").appendUnusedParameters;
    pub const headerLocalNamesAlloc = @import("api_generator/request_building.zig").headerLocalNamesAlloc;
    pub const appendHeaderLocals = @import("api_generator/request_building.zig").appendHeaderLocals;
    pub const appendHeaderValuesLocal = @import("api_generator/request_building.zig").appendHeaderValuesLocal;
    pub const appendHeaderParamAppends = @import("api_generator/request_building.zig").appendHeaderParamAppends;
    pub const appendAuthHeader = @import("api_generator/request_building.zig").appendAuthHeader;
    pub const appendUrlConstruction = @import("api_generator/request_building.zig").appendUrlConstruction;
    pub const hasBodyParameter = @import("api_generator/request_building.zig").hasBodyParameter;
    pub const generateApiClient = @import("api_generator/operations.zig").generateApiClient;
    pub const generateOperations = @import("api_generator/operations.zig").generateOperations;
    pub const generateOperation = @import("api_generator/operations.zig").generateOperation;
    pub const generateFunctionResult = @import("api_generator/operations.zig").generateFunctionResult;
    pub const generateFunctionRaw = @import("api_generator/operations.zig").generateFunctionRaw;
    pub const generateStreamFunction = @import("api_generator/operations.zig").generateStreamFunction;
    pub const generateComments = @import("api_generator/operations.zig").generateComments;
    pub const generateFunctionSignature = @import("api_generator/operations.zig").generateFunctionSignature;
    pub const generateFunctionBody = @import("api_generator/operations.zig").generateFunctionBody;
    pub const generateFunctionBodyDirect = @import("api_generator/operations.zig").generateFunctionBodyDirect;
    pub const hasReturnValue = @import("api_generator/operations.zig").hasReturnValue;
    pub const successResponseSchema = @import("api_generator/operations.zig").successResponseSchema;
    pub const appendReturnType = @import("api_generator/operations.zig").appendReturnType;
    pub const appendZigQueryTypeFromSchema = @import("api_generator/operations.zig").appendZigQueryTypeFromSchema;
    pub const appendZigTypeFromSchema = @import("api_generator/operations.zig").appendZigTypeFromSchema;
    pub const appendZigTypeFromSchemaType = @import("api_generator/operations.zig").appendZigTypeFromSchemaType;
    pub const generateResourceWrappers = @import("api_generator/resource_wrappers.zig").generateResourceWrappers;
    pub const generateResourceLevel = @import("api_generator/resource_wrappers.zig").generateResourceLevel;
    pub const generateResourceMethod = @import("api_generator/resource_wrappers.zig").generateResourceMethod;
    pub const generateResourceResultMethod = @import("api_generator/resource_wrappers.zig").generateResourceResultMethod;
    pub const appendWrapperResultSignature = @import("api_generator/resource_wrappers.zig").appendWrapperResultSignature;
    pub const resourceWrapperNameAlloc = @import("api_generator/resource_wrappers.zig").resourceWrapperNameAlloc;
    pub const generateResourceStreamMethods = @import("api_generator/resource_wrappers.zig").generateResourceStreamMethods;
    pub const appendWrapperSignatureAndReturn = @import("api_generator/resource_wrappers.zig").appendWrapperSignatureAndReturn;
    pub const appendOperationParameters = @import("api_generator/resource_wrappers.zig").appendOperationParameters;
    pub const appendWrapperCallArguments = @import("api_generator/resource_wrappers.zig").appendWrapperCallArguments;
    pub const appendParameterName = @import("api_generator/resource_wrappers.zig").appendParameterName;
    pub const resourceAliasConflicts = @import("api_generator/resource_wrappers.zig").resourceAliasConflicts;
    pub const operationHasParameterNamed = @import("api_generator/resource_wrappers.zig").operationHasParameterNamed;
    pub const operationDeclaresTopLevelName = @import("api_generator/resource_wrappers.zig").operationDeclaresTopLevelName;
    pub const resourceSegments = @import("api_generator/resource_wrappers.zig").resourceSegments;
    pub const resourceSegmentsHybrid = @import("api_generator/resource_wrappers.zig").resourceSegmentsHybrid;
    pub const resourceSegmentsFromPath = @import("api_generator/resource_wrappers.zig").resourceSegmentsFromPath;
    pub const resourceMethodName = @import("api_generator/resource_wrappers.zig").resourceMethodName;
    pub const sanitizeIdentifierAlloc = @import("api_generator/resource_wrappers.zig").sanitizeIdentifierAlloc;
    pub const appendIndent = @import("api_generator/resource_wrappers.zig").appendIndent;
    pub const generateTagClients = @import("api_generator/tag_clients.zig").generateTagClients;
    pub const generateEndpointClients = @import("api_generator/tag_clients.zig").generateEndpointClients;
    pub const endpointFallbackNameAlloc = @import("api_generator/tag_clients.zig").endpointFallbackNameAlloc;
    pub const endpointClientNameAlloc = @import("api_generator/tag_clients.zig").endpointClientNameAlloc;
    pub const generateEndpointClient = @import("api_generator/tag_clients.zig").generateEndpointClient;
    pub const topLevelNameConflicts = @import("api_generator/tag_clients.zig").topLevelNameConflicts;
    pub const uniqueTagClientStructNameAlloc = @import("api_generator/tag_clients.zig").uniqueTagClientStructNameAlloc;
    pub const isReservedTagClientMethod = @import("api_generator/tag_clients.zig").isReservedTagClientMethod;
    pub const uniqueTagClientMethodNameAlloc = @import("api_generator/tag_clients.zig").uniqueTagClientMethodNameAlloc;
    pub const tagClientMethodNamesCollide = @import("api_generator/tag_clients.zig").tagClientMethodNamesCollide;
    pub const registerTagClientMethodNames = @import("api_generator/tag_clients.zig").registerTagClientMethodNames;
    pub const registerTagClientMethodName = @import("api_generator/tag_clients.zig").registerTagClientMethodName;
    pub const tagClientFallbackMethodNameAlloc = @import("api_generator/tag_clients.zig").tagClientFallbackMethodNameAlloc;
    pub const tagClientNameAlloc = @import("api_generator/tag_clients.zig").tagClientNameAlloc;
    pub const tagClientMethodNameAlloc = @import("api_generator/tag_clients.zig").tagClientMethodNameAlloc;
    pub const generateTagClientMethod = @import("api_generator/tag_clients.zig").generateTagClientMethod;
    pub const appendTagClientCallArguments = @import("api_generator/tag_clients.zig").appendTagClientCallArguments;
};

test "BodyKind :: classifyBody routes media types correctly" {
    const t = std.testing;
    try t.expectEqual(BodyKind.json, classifyBody(null));
    try t.expectEqual(BodyKind.json, classifyBody(""));
    try t.expectEqual(BodyKind.json, classifyBody("application/json"));
    try t.expectEqual(BodyKind.json, classifyBody("application/vnd.api+json"));
    try t.expectEqual(BodyKind.binary, classifyBody("application/octet-stream"));
    try t.expectEqual(BodyKind.binary, classifyBody("image/png"));
    try t.expectEqual(BodyKind.binary, classifyBody("audio/mpeg"));
    try t.expectEqual(BodyKind.binary, classifyBody("video/mp4"));
    try t.expectEqual(BodyKind.binary, classifyBody("*/*"));
    try t.expectEqual(BodyKind.binary, classifyBody("application/xml"));
    try t.expectEqual(BodyKind.binary, classifyBody("application/pdf"));
    try t.expectEqual(BodyKind.text, classifyBody("text/plain"));
    try t.expectEqual(BodyKind.text, classifyBody("text/csv"));
    try t.expectEqual(BodyKind.form, classifyBody("application/x-www-form-urlencoded"));
    try t.expectEqual(BodyKind.form, classifyBody("multipart/form-data"));
    // Media types with parameters must be classified by their base type.
    try t.expectEqual(BodyKind.json, classifyBody("application/json; charset=utf-8"));
    try t.expectEqual(BodyKind.json, classifyBody("application/vnd.api+json; charset=utf-8"));
    try t.expectEqual(BodyKind.text, classifyBody("text/plain; charset=utf-8"));
    try t.expectEqual(BodyKind.form, classifyBody("multipart/form-data; boundary=abc"));
}
