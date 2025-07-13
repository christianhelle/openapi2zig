// Re-export all model types for easy access
pub const OpenApiDocument = @import("models/openapi.zig").OpenApiDocument;

pub usingnamespace @import("models/info.zig");
pub usingnamespace @import("models/server.zig");
pub usingnamespace @import("models/externaldocs.zig");
pub usingnamespace @import("models/tag.zig");
pub usingnamespace @import("models/reference.zig");
pub usingnamespace @import("models/schema.zig");
pub usingnamespace @import("models/media.zig");
pub usingnamespace @import("models/parameter.zig");
pub usingnamespace @import("models/requestbody.zig");
pub usingnamespace @import("models/response.zig");
pub usingnamespace @import("models/paths.zig");
pub usingnamespace @import("models/operation.zig");
pub usingnamespace @import("models/link.zig");
pub usingnamespace @import("models/callback.zig");
pub usingnamespace @import("models/security.zig");
pub usingnamespace @import("models/components.zig");
