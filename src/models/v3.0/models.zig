// Re-export all v3.0 model types for easy access
pub const OpenApiDocument = @import("openapi.zig").OpenApiDocument;

pub usingnamespace @import("info.zig");
pub usingnamespace @import("server.zig");
pub usingnamespace @import("externaldocs.zig");
pub usingnamespace @import("tag.zig");
pub usingnamespace @import("reference.zig");
pub usingnamespace @import("schema.zig");
pub usingnamespace @import("media.zig");
pub usingnamespace @import("parameter.zig");
pub usingnamespace @import("requestbody.zig");
pub usingnamespace @import("response.zig");
pub usingnamespace @import("paths.zig");
pub usingnamespace @import("operation.zig");
pub usingnamespace @import("link.zig");
pub usingnamespace @import("callback.zig");
pub usingnamespace @import("security.zig");
pub usingnamespace @import("components.zig");
