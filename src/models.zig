// Re-export all model types for easy access
pub const OpenApiDocument = @import("models/v3.0/openapi.zig").OpenApiDocument;
pub const SwaggerDocument = @import("models/v2.0/swagger.zig").SwaggerDocument;

// Export v3.0 models
pub usingnamespace @import("models/v3.0/info.zig");
pub usingnamespace @import("models/v3.0/server.zig");
pub usingnamespace @import("models/v3.0/externaldocs.zig");
pub usingnamespace @import("models/v3.0/tag.zig");
pub usingnamespace @import("models/v3.0/reference.zig");
pub usingnamespace @import("models/v3.0/schema.zig");
pub usingnamespace @import("models/v3.0/media.zig");
pub usingnamespace @import("models/v3.0/parameter.zig");
pub usingnamespace @import("models/v3.0/requestbody.zig");
pub usingnamespace @import("models/v3.0/response.zig");
pub usingnamespace @import("models/v3.0/paths.zig");
pub usingnamespace @import("models/v3.0/operation.zig");
pub usingnamespace @import("models/v3.0/link.zig");
pub usingnamespace @import("models/v3.0/callback.zig");
pub usingnamespace @import("models/v3.0/security.zig");
pub usingnamespace @import("models/v3.0/components.zig");

// Export v2.0 models with namespace to avoid conflicts
pub const v2 = @import("models/v2.0/models.zig");
