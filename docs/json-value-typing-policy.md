# `std.json.Value` typing policy

`openapi2zig` should generate typed Zig declarations when an OpenAPI schema gives enough structure, and use `std.json.Value` only when the schema is genuinely open-ended or ambiguous.

## Current behavior

The unified model generator maps schemas roughly as follows:

- `$ref` => referenced Zig declaration name.
- `type: string` => `[]const u8`.
- `type: integer` => `i64`.
- `type: number` => `f64`.
- `type: boolean` => `bool`.
- `type: array` with `items` => `[]const T` when item type/ref is known, otherwise `[]const std.json.Value`.
- `type: object` without generated properties => `std.json.Value`.
- schema with `properties` => generated `struct`, even if `type` is omitted.
- unknown schema => `std.json.Value`.
- string enums currently stay string aliases/types, not closed Zig enums.
- OpenAPI 3.1 `allOf` object/ref-to-object schemas are merged during conversion when possible.
- OpenAPI 3.1 `oneOf` / `anyOf` with a discriminator and all-ref object variants emit `union(enum)` with generated discriminator parsing and a `raw: std.json.Value` fallback.
- Other `oneOf` / `anyOf` schemas still fall back to `std.json.Value`.

The API generator also falls back to `std.json.Value` for ambiguous request/response schemas and for object/array cases where no named schema exists.

## Desired mapping

| OpenAPI schema shape | Generated Zig shape |
| --- | --- |
| Object with known `properties` | Generated `struct` |
| Object with `properties` but no `type` | Generated `struct` |
| Array with item schema | `[]const T` |
| `$ref` | Referenced Zig declaration |
| String enum | String alias or `[]const u8` until enum policy is chosen |
| Numeric/boolean enum | Underlying scalar or `std.json.Value` if mixed |
| `additionalProperties: true` / free-form object | `std.json.Value` now, future map type possible |
| `additionalProperties: {schema}` | Future `std.StringHashMap(T)` or equivalent owned map |
| `oneOf` / `anyOf` without discriminator | `std.json.Value` |
| `oneOf` / `anyOf` with discriminator and safe object refs | `union(enum)` with custom parse/stringify and `raw` fallback |
| `oneOf` / `anyOf` with discriminator but unsafe variants | `std.json.Value` with comment |
| `allOf` where all members are objects or refs to objects | Merged generated `struct` |
| `allOf` with conflicting fields | Prefer explicit fallback/comment, avoid silently wrong type |
| `allOf` mixing primitive and object | `std.json.Value` fallback |
| Nullable `T` | `?T` |
| Unknown/empty schema | `std.json.Value` |

## `oneOf` / `anyOf` policy

Discriminator unions become Zig `union(enum)` declarations when all variants are object refs and each target object has a single string enum value for the discriminator property.

Generated unions include:

```zig
raw: std.json.Value,
```

for unknown provider variants. The generated `jsonParse`/`jsonParseFromValue` parses known discriminator tags into typed variants and preserves unknown tags as raw JSON.

Unsafe discriminator unions still emit a comment and fall back to `std.json.Value`:

```zig
// OpenAPI oneOf with discriminator could not be generated safely; generator currently uses std.json.Value.
```

Without a discriminator, use `std.json.Value` to preserve pass-through behavior.

## `extra_body` policy

Extensible request structs can include:

```zig
extra_body: ?std.json.Value = null,
```

The generated `jsonStringify` flattens `extra_body.object` into the request object.

Callers must not include keys in `extra_body` that duplicate known generated fields. Current output writes known fields first, then extra fields, which can produce duplicate JSON object keys. This preserves pass-through but does not define override behavior.

## Default headers ownership

Generated clients store `default_headers` as borrowed slices:

```zig
client.default_headers = &.{
    .{ .name = "HTTP-Referer", .value = "https://example.com" },
};
```

The caller must keep the header slice and all header name/value storage alive for the duration of each request that uses them.

## Raw and result response policy

Generated clients should expose:

- parsed convenience endpoints: `op(...) !Owned(T)`
- endpoint-specific result endpoints: `opResult(...) !ApiResult(T)`
- endpoint-specific raw endpoints: `opRaw(...) !RawResponse`
- generic raw/result helpers for dynamic paths

`ApiResult(T)` preserves raw status/body for:

- non-2xx API responses via `.api_error`
- JSON parse failures via `.parse_error`

The parsed convenience endpoint may still return an error, but callers that need body/status must use `opResult` or `opRaw`.
