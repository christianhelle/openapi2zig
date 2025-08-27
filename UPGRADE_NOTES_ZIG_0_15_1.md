# Zig 0.15.1 Upgrade Notes

This document tracks the changes needed to upgrade openapi2zig from Zig 0.14.1 to Zig 0.15.1.

## Version References Updated ✅

All Zig version references have been updated from "0.14.1" to "0.15.1":

- `build.zig.zon`: `.minimum_zig_version = "0.15.1"`
- `.devcontainer/devcontainer.json`: `"version": "0.15.1"`
- `.github/workflows/ci.yml`: `ZIG_VERSION: "0.15.1"`  
- `.github/workflows/release.yml`: `ZIG_VERSION: "0.15.1"`
- `README.md`: Prerequisites mention Zig v0.15.1
- `examples/PACKAGE.md`: References Zig 0.15.1
- `.devcontainer/README.md`: References Zig 0.15.1
- `docs/index.html`: Badge and text references
- `.github/copilot-instructions.md`: All references updated

## Breaking Changes Identified ✅

The major breaking change in Zig 0.15.1 is the JSON API restructuring:

- `json.Value` is now a tagged union instead of struct with fields
- Direct field access like `value.object` no longer works
- Pattern matching with `switch` is required to access union members

## JSON API Conversion Patterns ✅

### Pattern 1: Object Access
```zig
// OLD (0.14.1):
const obj = value.object;

// NEW (0.15.1):  
const obj = switch (value) {
    .object => |o| o,
    else => return error.ExpectedObject,
};
```

### Pattern 2: String Access (Required Fields)
```zig
// OLD (0.14.1):
const str = try allocator.dupe(u8, obj.get("field").?.string);

// NEW (0.15.1):
const field_str = switch (obj.get("field") orelse return error.MissingField) {
    .string => |str| str,
    else => return error.ExpectedString,
};
const str = try allocator.dupe(u8, field_str);
```

### Pattern 3: String Access (Optional Fields)
```zig
// OLD (0.14.1):
.field = if (obj.get("field")) |val| try allocator.dupe(u8, val.string) else null,

// NEW (0.15.1):
.field = if (obj.get("field")) |val| switch (val) {
    .string => |str| try allocator.dupe(u8, str),
    else => null,
} else null,
```

### Pattern 4: Array Access
```zig
// OLD (0.14.1):
for (value.array.items) |item| {
    try list.append(try allocator.dupe(u8, item.string));
}

// NEW (0.15.1):
const arr = switch (value) {
    .array => |a| a,
    else => return error.ExpectedArray,
};

for (arr.items) |item| {
    switch (item) {
        .string => |str| try list.append(try allocator.dupe(u8, str)),
        else => return error.ExpectedString,
    }
}
```

## Files Updated ✅

### Core Entry Points
- ✅ `src/models/v2.0/swagger.zig` - Main Swagger 2.0 parser with helper functions
- ✅ `src/models/v3.0/openapi.zig` - Main OpenAPI 3.0 parser

### Common Models  
- ✅ `src/models/v2.0/info.zig` - Contact, License, Info structs
- ✅ `src/models/v3.0/info.zig` - Contact, License, Info structs  
- ✅ `src/models/v2.0/externaldocs.zig` - ExternalDocumentation
- ✅ `src/models/v3.0/externaldocs.zig` - ExternalDocumentation
- ✅ `src/models/v2.0/tag.zig` - Tag struct
- ✅ `src/models/v3.0/tag.zig` - Tag struct
- ✅ `src/models/v3.0/reference.zig` - Reference struct
- ✅ `src/models/v3.0/server.zig` - ServerVariable (with array handling example)

### Helper Functions Updated
- ✅ `parseStringArray()` in swagger.zig 
- ✅ `parseDefinitions()` in swagger.zig
- ✅ `parseParameters()` in swagger.zig

## Files Remaining ❌

The following files still need the same patterns applied:

### V2.0 Models
- ❌ `src/models/v2.0/security.zig`
- ❌ `src/models/v2.0/paths.zig`
- ❌ `src/models/v2.0/response.zig`
- ❌ `src/models/v2.0/operation.zig`
- ❌ `src/models/v2.0/schema.zig`
- ❌ `src/models/v2.0/parameter.zig`

### V3.0 Models  
- ❌ `src/models/v3.0/security.zig`
- ❌ `src/models/v3.0/components.zig`
- ❌ `src/models/v3.0/requestbody.zig`
- ❌ `src/models/v3.0/callback.zig`
- ❌ `src/models/v3.0/paths.zig`
- ❌ `src/models/v3.0/response.zig`
- ❌ `src/models/v3.0/operation.zig`
- ❌ `src/models/v3.0/schema.zig`
- ❌ `src/models/v3.0/media.zig`
- ❌ `src/models/v3.0/parameter.zig`
- ❌ `src/models/v3.0/link.zig`

## APIs That Don't Need Changes ✅

- `std.http.Client` usage remains compatible
- `std.json.parseFromSlice()` API unchanged  
- Build system (`build.zig`) unchanged
- `detector.zig` uses struct-based parsing, not affected

## Testing Required ❓

Once remaining files are updated:
1. Verify project builds with Zig 0.15.1
2. Run test suite: `zig build test`
3. Test code generation: `zig build run-generate`
4. Test cross-compilation targets

## How to Complete Remaining Updates

For each remaining file:
1. Open the file
2. Find all `parseFromJson` functions
3. Apply Pattern 1 for `value.object` → switch pattern
4. Apply Pattern 2/3 for `obj.get("field").?.string` → switch pattern
5. Apply Pattern 4 for any array access
6. Test the specific model if possible

The patterns are mechanical and consistent across all files.