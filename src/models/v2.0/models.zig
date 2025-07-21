// Re-export all v2.0 model types for easy access
pub const SwaggerDocument = @import("swagger.zig").SwaggerDocument;

pub usingnamespace @import("info.zig");
pub usingnamespace @import("externaldocs.zig");
pub usingnamespace @import("tag.zig");
pub usingnamespace @import("schema.zig");
pub usingnamespace @import("parameter.zig");
pub usingnamespace @import("response.zig");
pub usingnamespace @import("paths.zig");
pub usingnamespace @import("operation.zig");
pub usingnamespace @import("security.zig");
