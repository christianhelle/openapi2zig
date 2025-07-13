// Re-export all model types for easy access
pub const OpenApiDocument = @import("models/openapi.zig").OpenApiDocument;

// Basic types
pub usingnamespace @import("models/info.zig");
pub usingnamespace @import("models/server.zig");
pub usingnamespace @import("models/documentation.zig");
pub usingnamespace @import("models/tag.zig");
pub usingnamespace @import("models/reference.zig");

// Schema related
pub usingnamespace @import("models/schema.zig");

// Media types and content
pub usingnamespace @import("models/media.zig");

// Parameters
pub usingnamespace @import("models/parameter.zig");

// Request/Response
pub usingnamespace @import("models/request_body.zig");
pub usingnamespace @import("models/response.zig");

// Paths and operations
pub usingnamespace @import("models/paths.zig");
pub usingnamespace @import("models/operation.zig");

// Links and callbacks
pub usingnamespace @import("models/link.zig");
pub usingnamespace @import("models/callback.zig");

// Security
pub usingnamespace @import("models/security.zig");

// Components
pub usingnamespace @import("models/components.zig");
