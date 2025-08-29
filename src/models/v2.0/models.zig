pub const SwaggerDocument = @import("swagger.zig").SwaggerDocument;

// Export all types from the various modules
pub const Info = @import("info.zig").Info;
pub const License = @import("info.zig").License;
pub const Contact = @import("info.zig").Contact;

pub const ExternalDocumentation = @import("externaldocs.zig").ExternalDocumentation;

pub const Tag = @import("tag.zig").Tag;

pub const Schema = @import("schema.zig").Schema;
pub const Property = @import("schema.zig").Property;

pub const Parameter = @import("parameter.zig").Parameter;

pub const Response = @import("response.zig").Response;
pub const Responses = @import("response.zig").Responses;

pub const PathItem = @import("paths.zig").PathItem;
pub const Paths = @import("paths.zig").Paths;

pub const Operation = @import("operation.zig").Operation;

pub const SecurityDefinition = @import("security.zig").SecurityDefinition;
pub const SecurityDefinitions = @import("security.zig").SecurityDefinitions;
pub const SecurityRequirement = @import("security.zig").SecurityRequirement;
