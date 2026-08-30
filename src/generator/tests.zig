const std = @import("std");
const cli = @import("../cli.zig");
const generator = @import("../generator.zig");
const openapi2zig = @import("../lib.zig");
const generated_header = @import("../generators/generated_header.zig");
const models = @import("../models.zig");
const OpenApiConverter = @import("../generators/converters/openapi_converter.zig").OpenApiConverter;
const validateExtension = generator.validateExtension;
const generateCode = generator.generateCode;
const generateCodeFromJsonContents = generator.generateCodeFromJsonContents;
const generateCodeFromUnifiedDocument = generator.generateCodeFromUnifiedDocument;
const generateRuntimeOnly = generator.generateRuntimeOnly;
const generateMultipleFiles = generator.generateMultipleFiles;
const writeFile = generator.writeFile;
const GeneratorErrors = generator.GeneratorErrors;

test "unsupported OpenAPI versions return a distinct generator error" {
    const test_utils = @import("../tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const json_contents =
        \\{
        \\  "openapi": "9.9.9",
        \\  "info": {
        \\    "title": "Unsupported",
        \\    "version": "1.0.0"
        \\  },
        \\  "paths": {}
        \\}
    ;

    try std.testing.expectError(
        GeneratorErrors.UnsupportedOpenAPIVersion,
        generateCodeFromJsonContents(allocator, std.testing.io, json_contents, .{
            .input_path = "unsupported.json",
        }),
    );
}

fn buildPetstoreUnified(allocator: std.mem.Allocator) !@import("../models/common/document.zig").UnifiedDocument {
    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {
        \\    "/pets": {
        \\      "post": {
        \\        "operationId": "addPet",
        \\        "requestBody": {
        \\          "required": true,
        \\          "content": {
        \\            "application/json": {
        \\              "schema": { "$ref": "#/components/schemas/Pet" }
        \\            }
        \\          }
        \\        },
        \\        "responses": {
        \\          "200": { "description": "ok" }
        \\        }
        \\      }
        \\    }
        \\  },
        \\  "components": {
        \\    "schemas": {
        \\      "Pet": {
        \\        "type": "object",
        \\        "properties": { "name": { "type": "string" } }
        \\      }
        \\    }
        \\  }
        \\}
    ;
    var openapi = try models.OpenApiDocument.parseFromJson(allocator, json);
    defer openapi.deinit(allocator);
    var converter = OpenApiConverter.init(allocator);
    return try converter.convert(openapi);
}

test "generateMultipleFiles writes custom file names with derived import aliases" {
    const test_utils = @import("../tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {
        \\    "/pets": {
        \\      "post": {
        \\        "operationId": "addPet",
        \\        "requestBody": {
        \\          "required": true,
        \\          "content": {
        \\            "application/json": {
        \\              "schema": { "$ref": "#/components/schemas/Pet" }
        \\            }
        \\          }
        \\        },
        \\        "responses": {
        \\          "200": { "description": "ok" }
        \\        }
        \\      }
        \\    }
        \\  },
        \\  "components": {
        \\    "schemas": {
        \\      "Pet": {
        \\        "type": "object",
        \\        "properties": { "name": { "type": "string" } }
        \\      }
        \\    }
        \\  }
        \\}
    ;

    var unified = try openapi2zig.parseToUnified(allocator, json);
    defer unified.deinit(allocator);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try generateMultipleFiles(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .multiple_files = true,
        .output_path = "out",
        .file_names = .{ .models = "types.zig", .runtime = "http.zig", .client = "api.zig" },
    });

    const types = try tmp.dir.readFileAlloc(std.testing.io, "out/types.zig", allocator, .unlimited);
    defer allocator.free(types);
    try std.testing.expect(std.mem.indexOf(u8, types, "pub const Pet") != null);

    const http = try tmp.dir.readFileAlloc(std.testing.io, "out/http.zig", allocator, .unlimited);
    defer allocator.free(http);
    try std.testing.expect(std.mem.indexOf(u8, http, "pub fn Owned") != null);

    const api = try tmp.dir.readFileAlloc(std.testing.io, "out/api.zig", allocator, .unlimited);
    defer allocator.free(api);
    try std.testing.expect(std.mem.indexOf(u8, api, "const types = @import(\"types.zig\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, api, "const http = @import(\"http.zig\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, api, "const Owned = http.Owned;") != null);

    try std.testing.expectError(error.FileNotFound, tmp.dir.access(std.testing.io, "out/models.zig", .{}));
    try std.testing.expectError(error.FileNotFound, tmp.dir.access(std.testing.io, "out/runtime.zig", .{}));
    try std.testing.expectError(error.FileNotFound, tmp.dir.access(std.testing.io, "out/client.zig", .{}));
}

test "generateMultipleFiles sanitizes the import alias from the file name" {
    const test_utils = @import("../tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {
        \\    "/pets": {
        \\      "post": {
        \\        "operationId": "addPet",
        \\        "requestBody": {
        \\          "required": true,
        \\          "content": {
        \\            "application/json": {
        \\              "schema": { "$ref": "#/components/schemas/Pet" }
        \\            }
        \\          }
        \\        },
        \\        "responses": {
        \\          "200": { "description": "ok" }
        \\        }
        \\      }
        \\    }
        \\  },
        \\  "components": {
        \\    "schemas": {
        \\      "Pet": {
        \\        "type": "object",
        \\        "properties": { "name": { "type": "string" } }
        \\      }
        \\    }
        \\  }
        \\}
    ;

    var unified = try openapi2zig.parseToUnified(allocator, json);
    defer unified.deinit(allocator);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try generateMultipleFiles(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .multiple_files = true,
        .output_path = "out",
        .file_names = .{ .models = "my-types.zig" },
    });

    const api = try tmp.dir.readFileAlloc(std.testing.io, "out/client.zig", allocator, .unlimited);
    defer allocator.free(api);
    try std.testing.expect(std.mem.indexOf(u8, api, "const my_types = @import(\"my-types.zig\");") != null);
}

test "generateMultipleFiles with models-only honors the custom models file name" {
    const test_utils = @import("../tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {
        \\    "/pets": {
        \\      "post": {
        \\        "operationId": "addPet",
        \\        "requestBody": {
        \\          "required": true,
        \\          "content": {
        \\            "application/json": {
        \\              "schema": { "$ref": "#/components/schemas/Pet" }
        \\            }
        \\          }
        \\        },
        \\        "responses": {
        \\          "200": { "description": "ok" }
        \\        }
        \\      }
        \\    }
        \\  },
        \\  "components": {
        \\    "schemas": {
        \\      "Pet": {
        \\        "type": "object",
        \\        "properties": { "name": { "type": "string" } }
        \\      }
        \\    }
        \\  }
        \\}
    ;

    var unified = try openapi2zig.parseToUnified(allocator, json);
    defer unified.deinit(allocator);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try generateMultipleFiles(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .multiple_files = true,
        .models_only = true,
        .output_path = "out",
        .file_names = .{ .models = "types.zig" },
    });

    const types = try tmp.dir.readFileAlloc(std.testing.io, "out/types.zig", allocator, .unlimited);
    defer allocator.free(types);
    try std.testing.expect(std.mem.indexOf(u8, types, "pub const Pet") != null);

    try std.testing.expectError(error.FileNotFound, tmp.dir.access(std.testing.io, "out/runtime.zig", .{}));
    try std.testing.expectError(error.FileNotFound, tmp.dir.access(std.testing.io, "out/client.zig", .{}));
}

test "generateMultipleFiles creates parent directories for file names with subpaths" {
    const test_utils = @import("../tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {}
        \\}
    ;

    var unified = try openapi2zig.parseToUnified(allocator, json);
    defer unified.deinit(allocator);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try generateMultipleFiles(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .multiple_files = true,
        .output_path = "out",
        .file_names = .{ .models = "gen/models.zig" },
    });

    const content = try tmp.dir.readFileAlloc(std.testing.io, "out/gen/models.zig", allocator, .unlimited);
    defer allocator.free(content);
    try std.testing.expect(content.len > 0);
}

test "generateMultipleFiles computes relative import paths for nested client" {
    const test_utils = @import("../tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {
        \\    "/pets": {
        \\      "get": {
        \\        "operationId": "listPets",
        \\        "responses": {
        \\          "200": {
        \\            "description": "ok",
        \\            "content": { "application/json": { "schema": { "type": "array", "items": { "$ref": "#/components/schemas/Pet" } } } }
        \\          }
        \\        }
        \\      }
        \\    }
        \\  },
        \\  "components": {
        \\    "schemas": {
        \\      "Pet": {
        \\        "type": "object",
        \\        "properties": { "name": { "type": "string" } }
        \\      }
        \\    }
        \\  }
        \\}
    ;

    var unified = try openapi2zig.parseToUnified(allocator, json);
    defer unified.deinit(allocator);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try generateMultipleFiles(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .multiple_files = true,
        .output_path = "out",
        .file_names = .{ .models = "types.zig", .runtime = "http.zig", .client = "sub/client.zig" },
    });

    const client = try tmp.dir.readFileAlloc(std.testing.io, "out/sub/client.zig", allocator, .unlimited);
    defer allocator.free(client);
    try std.testing.expect(std.mem.indexOf(u8, client, "@import(\"../types.zig\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, client, "@import(\"../http.zig\")") != null);
}

test "generateCodeFromUnifiedDocument filters operations and models by requested tags" {
    const test_utils = @import("../tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {
        \\    "/pets": {
        \\      "get": {
        \\        "operationId": "listPets",
        \\        "tags": ["pet"],
        \\        "responses": {
        \\          "200": {
        \\            "description": "ok",
        \\            "content": { "application/json": { "schema": { "type": "array", "items": { "$ref": "#/components/schemas/Pet" } } } }
        \\          }
        \\        }
        \\      }
        \\    },
        \\    "/store/order": {
        \\      "post": {
        \\        "operationId": "placeOrder",
        \\        "tags": ["store"],
        \\        "requestBody": {
        \\          "required": true,
        \\          "content": { "application/json": { "schema": { "$ref": "#/components/schemas/Order" } } }
        \\        },
        \\        "responses": {
        \\          "200": { "description": "ok" }
        \\        }
        \\      }
        \\    }
        \\  },
        \\  "components": {
        \\    "schemas": {
        \\      "Pet": {
        \\        "type": "object",
        \\        "properties": { "name": { "type": "string" } }
        \\      },
        \\      "Order": {
        \\        "type": "object",
        \\        "properties": { "id": { "type": "integer" } }
        \\      }
        \\    }
        \\  }
        \\}
    ;

    var unified = try openapi2zig.parseToUnified(allocator, json);
    defer unified.deinit(allocator);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try generateCodeFromUnifiedDocument(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .output_path = "api.zig",
        .tags = &.{"pet"},
    });

    const api = try tmp.dir.readFileAlloc(std.testing.io, "api.zig", allocator, .unlimited);
    defer allocator.free(api);

    try std.testing.expect(std.mem.indexOf(u8, api, "pub const Pet") != null);
    try std.testing.expect(std.mem.indexOf(u8, api, "pub const Order") == null);
    try std.testing.expect(std.mem.indexOf(u8, api, "pub fn listPets") != null);
    try std.testing.expect(std.mem.indexOf(u8, api, "placeOrder") == null);
}

test "generateMultipleFiles composes per-tag client structs into the client file" {
    const test_utils = @import("../tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {
        \\    "/pets": {
        \\      "get": {
        \\        "operationId": "listPets",
        \\        "tags": ["pet"],
        \\        "responses": {
        \\          "200": {
        \\            "description": "ok",
        \\            "content": { "application/json": { "schema": { "type": "array", "items": { "$ref": "#/components/schemas/Pet" } } } }
        \\          }
        \\        }
        \\      }
        \\    }
        \\  },
        \\  "components": {
        \\    "schemas": {
        \\      "Pet": {
        \\        "type": "object",
        \\        "properties": { "name": { "type": "string" } }
        \\      }
        \\    }
        \\  }
        \\}
    ;

    var unified = try openapi2zig.parseToUnified(allocator, json);
    defer unified.deinit(allocator);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try generateMultipleFiles(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .multiple_files = true,
        .multiple_clients = .per_tag,
        .output_path = "out",
    });

    const client = try tmp.dir.readFileAlloc(std.testing.io, "out/client.zig", allocator, .unlimited);
    defer allocator.free(client);
    try std.testing.expect(std.mem.indexOf(u8, client, "pub const PetClient = struct {") != null);
    try std.testing.expect(std.mem.indexOf(u8, client, "pub fn listPets(self: *PetClient") != null);

    const models_content = try tmp.dir.readFileAlloc(std.testing.io, "out/models.zig", allocator, .unlimited);
    defer allocator.free(models_content);
    try std.testing.expect(std.mem.indexOf(u8, models_content, "pub const Pet") != null);
    try std.testing.expect(std.mem.indexOf(u8, models_content, "PetClient") == null);
}

test "generateCodeFromUnifiedDocument preserves timestamp when code unchanged" {
    const test_utils = @import("../tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {}
        \\}
    ;

    var unified = try openapi2zig.parseToUnified(allocator, json);
    defer unified.deinit(allocator);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try generateCodeFromUnifiedDocument(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .output_path = "out/api.zig",
    });

    const first = try tmp.dir.readFileAlloc(std.testing.io, "out/api.zig", allocator, .unlimited);
    defer allocator.free(first);

    try generateCodeFromUnifiedDocument(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .output_path = "out/api.zig",
    });

    const second = try tmp.dir.readFileAlloc(std.testing.io, "out/api.zig", allocator, .unlimited);
    defer allocator.free(second);

    try std.testing.expectEqualStrings(first, second);
}

test "generateMultipleFiles preserves timestamps when code unchanged" {
    const test_utils = @import("../tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {}
        \\}
    ;

    var unified = try openapi2zig.parseToUnified(allocator, json);
    defer unified.deinit(allocator);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try generateMultipleFiles(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .multiple_files = true,
        .output_path = "out",
    });

    const first_models = try tmp.dir.readFileAlloc(std.testing.io, "out/models.zig", allocator, .unlimited);
    defer allocator.free(first_models);

    try generateMultipleFiles(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .multiple_files = true,
        .output_path = "out",
    });

    const second_models = try tmp.dir.readFileAlloc(std.testing.io, "out/models.zig", allocator, .unlimited);
    defer allocator.free(second_models);

    try std.testing.expectEqualStrings(first_models, second_models);
}

test "generateCodeFromUnifiedDocument overwrites unchanged file when force is set" {
    const test_utils = @import("../tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {}
        \\}
    ;

    var unified = try openapi2zig.parseToUnified(allocator, json);
    defer unified.deinit(allocator);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try generateCodeFromUnifiedDocument(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .output_path = "out/api.zig",
    });

    const first = try tmp.dir.readFileAlloc(std.testing.io, "out/api.zig", allocator, .unlimited);
    defer allocator.free(first);

    // Sleep to ensure timestamp in header will differ (header uses second precision)
    try std.Io.sleep(std.testing.io, .fromMilliseconds(1100), .real);

    // Force overwrites even when unchanged, so second file should have a new timestamp header
    try generateCodeFromUnifiedDocument(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .output_path = "out/api.zig",
        .force = true,
    });

    const second = try tmp.dir.readFileAlloc(std.testing.io, "out/api.zig", allocator, .unlimited);
    defer allocator.free(second);

    try std.testing.expect(!std.mem.eql(u8, first, second));
}

test "generateMultipleFiles overwrites unchanged files when force is set" {
    const test_utils = @import("../tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {}
        \\}
    ;

    var unified = try openapi2zig.parseToUnified(allocator, json);
    defer unified.deinit(allocator);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try generateMultipleFiles(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .multiple_files = true,
        .output_path = "out",
    });

    const first_models = try tmp.dir.readFileAlloc(std.testing.io, "out/models.zig", allocator, .unlimited);
    defer allocator.free(first_models);

    try std.Io.sleep(std.testing.io, .fromMilliseconds(1100), .real);

    try generateMultipleFiles(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .multiple_files = true,
        .output_path = "out",
        .force = true,
    });

    const second_models = try tmp.dir.readFileAlloc(std.testing.io, "out/models.zig", allocator, .unlimited);
    defer allocator.free(second_models);

    try std.testing.expect(!std.mem.eql(u8, first_models, second_models));
}

test "generateMultipleFiles with runtime_module reuses existing runtime" {
    const test_utils = @import("../tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {
        \\    "/pets": {
        \\      "post": {
        \\        "operationId": "addPet",
        \\        "requestBody": {
        \\          "required": true,
        \\          "content": {
        \\            "application/json": {
        \\              "schema": { "$ref": "#/components/schemas/Pet" }
        \\            }
        \\          }
        \\        },
        \\        "responses": {
        \\          "200": { "description": "ok" }
        \\        }
        \\      }
        \\    }
        \\  },
        \\  "components": {
        \\    "schemas": {
        \\      "Pet": {
        \\        "type": "object",
        \\        "properties": { "name": { "type": "string" } }
        \\      }
        \\    }
        \\  }
        \\}
    ;

    var unified = try openapi2zig.parseToUnified(allocator, json);
    defer unified.deinit(allocator);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Leader: normal generation that creates runtime.zig in shared location
    try generateMultipleFiles(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .multiple_files = true,
        .output_path = "shared",
    });

    const shared_runtime = try tmp.dir.readFileAlloc(std.testing.io, "shared/runtime.zig", allocator, .unlimited);
    defer allocator.free(shared_runtime);
    try std.testing.expect(std.mem.indexOf(u8, shared_runtime, "pub fn Owned") != null);

    // Follower: reuse existing runtime via client-relative import
    try generateMultipleFiles(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .multiple_files = true,
        .output_path = "client",
        .runtime_module = "../shared/runtime.zig",
    });

    const client = try tmp.dir.readFileAlloc(std.testing.io, "client/client.zig", allocator, .unlimited);
    defer allocator.free(client);
    try std.testing.expect(std.mem.indexOf(u8, client, "@import(\"../shared/runtime.zig\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, client, "const runtime = @import(\"../shared/runtime.zig\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, client, "const Owned = runtime.Owned;") != null);

    // No runtime should be emitted in the follower output
    try std.testing.expectError(error.FileNotFound, tmp.dir.access(std.testing.io, "client/runtime.zig", .{}));

    const models_content = try tmp.dir.readFileAlloc(std.testing.io, "client/models.zig", allocator, .unlimited);
    defer allocator.free(models_content);
    try std.testing.expect(std.mem.indexOf(u8, models_content, "pub const Pet") != null);
}

test "generateMultipleFiles with runtime_module derives alias from basename and supports custom models name" {
    const test_utils = @import("../tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {}
        \\}
    ;

    var unified = try openapi2zig.parseToUnified(allocator, json);
    defer unified.deinit(allocator);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try generateMultipleFiles(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .multiple_files = true,
        .output_path = "out",
        .runtime_module = "../shared/my_runtime.zig",
        .file_names = .{ .models = "contracts.zig" },
    });

    const client = try tmp.dir.readFileAlloc(std.testing.io, "out/client.zig", allocator, .unlimited);
    defer allocator.free(client);
    try std.testing.expect(std.mem.indexOf(u8, client, "const my_runtime = @import(\"../shared/my_runtime.zig\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, client, "const Owned = my_runtime.Owned;") != null);
    try std.testing.expect(std.mem.indexOf(u8, client, "const contracts = @import(\"contracts.zig\");") != null);
}

test "generateMultipleFiles with runtime_module and nested client preserves verbatim import" {
    const test_utils = @import("../tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {}
        \\}
    ;

    var unified = try openapi2zig.parseToUnified(allocator, json);
    defer unified.deinit(allocator);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try generateMultipleFiles(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .multiple_files = true,
        .output_path = "out",
        .file_names = .{ .client = "sub/client.zig" },
        .runtime_module = "../../shared/runtime.zig",
    });

    const client = try tmp.dir.readFileAlloc(std.testing.io, "out/sub/client.zig", allocator, .unlimited);
    defer allocator.free(client);
    try std.testing.expect(std.mem.indexOf(u8, client, "@import(\"../../shared/runtime.zig\")") != null);
}

test "generateMultipleFiles treats backslash-separated nested client path as a directory" {
    const test_utils = @import("../tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {}
        \\}
    ;

    var unified = try openapi2zig.parseToUnified(allocator, json);
    defer unified.deinit(allocator);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try generateMultipleFiles(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .multiple_files = true,
        .output_path = "out",
        .file_names = .{ .client = "sub\\client.zig" },
        .runtime_module = "../shared/runtime.zig",
    });

    const client = try tmp.dir.readFileAlloc(std.testing.io, "out/sub/client.zig", allocator, .unlimited);
    defer allocator.free(client);
    try std.testing.expect(std.mem.indexOf(u8, client, "@import(\"../shared/runtime.zig\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, client, "const models = @import(\"../models.zig\");") != null);
}

test "generateMultipleFiles with windows-style runtime_module normalizes separators" {
    const test_utils = @import("../tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {}
        \\}
    ;

    var unified = try openapi2zig.parseToUnified(allocator, json);
    defer unified.deinit(allocator);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try generateMultipleFiles(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .multiple_files = true,
        .output_path = "out",
        .runtime_module = "..\\shared\\my_runtime.zig",
    });

    const client = try tmp.dir.readFileAlloc(std.testing.io, "out/client.zig", allocator, .unlimited);
    defer allocator.free(client);
    // Import should be normalized to forward slashes even when input uses backslashes
    try std.testing.expect(std.mem.indexOf(u8, client, "@import(\"../shared/my_runtime.zig\")") != null);
    // Alias should be derived from basename only, not include path separators
    try std.testing.expect(std.mem.indexOf(u8, client, "const my_runtime = @import(\"../shared/my_runtime.zig\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, client, "const Owned = my_runtime.Owned;") != null);
}

test "generateMultipleFiles normalizes backslash-separated models and runtime file paths" {
    const test_utils = @import("../tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {}
        \\}
    ;

    var unified = try openapi2zig.parseToUnified(allocator, json);
    defer unified.deinit(allocator);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try generateMultipleFiles(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .multiple_files = true,
        .output_path = "out",
        .file_names = .{ .models = "gen\\models.zig", .runtime = "rt\\runtime.zig", .client = "client.zig" },
    });

    const models_source = try tmp.dir.readFileAlloc(std.testing.io, "out/gen/models.zig", allocator, .unlimited);
    defer allocator.free(models_source);
    const runtime_source = try tmp.dir.readFileAlloc(std.testing.io, "out/rt/runtime.zig", allocator, .unlimited);
    defer allocator.free(runtime_source);
    const client = try tmp.dir.readFileAlloc(std.testing.io, "out/client.zig", allocator, .unlimited);
    defer allocator.free(client);

    // Imports in the generated client should use forward slashes.
    try std.testing.expect(std.mem.indexOf(u8, client, "@import(\"gen/models.zig\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, client, "@import(\"rt/runtime.zig\")") != null);

    // No backslash-separated imports should leak into generated code.
    try std.testing.expect(std.mem.indexOf(u8, client, "@import(\"gen\\models.zig\")") == null);
    try std.testing.expect(std.mem.indexOf(u8, client, "@import(\"rt\\runtime.zig\")") == null);

    // Aliases are derived from the normalized path stems.
    try std.testing.expect(std.mem.indexOf(u8, client, "const gen_models = @import(\"gen/models.zig\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, client, "const rt_runtime = @import(\"rt/runtime.zig\");") != null);
}

test "generateCode with runtime_only ignores the input and writes only the runtime module" {
    const test_utils = @import("../tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const output_path = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", &tmp.sub_path, "runtime.zig" });
    defer allocator.free(output_path);

    // A bogus input path with an unsupported extension proves the input is
    // never validated or read when runtime_only is set.
    try generateCode(allocator, std.testing.io, .{
        .input_path = "does/not/exist.txt",
        .runtime_only = true,
        .output_path = output_path,
    });

    const runtime = try tmp.dir.readFileAlloc(std.testing.io, "runtime.zig", allocator, .unlimited);
    defer allocator.free(runtime);
    try std.testing.expect(std.mem.indexOf(u8, runtime, "pub fn Owned") != null);
    try std.testing.expect(std.mem.indexOf(u8, runtime, "pub const Pet") == null);
}

test "generateRuntimeOnly defaults the output file name to runtime.zig" {
    const test_utils = @import("../tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try generateRuntimeOnly(allocator, std.testing.io, tmp.dir, .{
        .input_path = "",
        .runtime_only = true,
    });

    const runtime = try tmp.dir.readFileAlloc(std.testing.io, "runtime.zig", allocator, .unlimited);
    defer allocator.free(runtime);
    try std.testing.expect(std.mem.indexOf(u8, runtime, "pub fn Owned") != null);
}

test "generateRuntimeOnly with multiple_files writes only the runtime file into the output dir" {
    const test_utils = @import("../tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try generateRuntimeOnly(allocator, std.testing.io, tmp.dir, .{
        .input_path = "",
        .runtime_only = true,
        .multiple_files = true,
        .output_path = "out",
    });

    const runtime = try tmp.dir.readFileAlloc(std.testing.io, "out/runtime.zig", allocator, .unlimited);
    defer allocator.free(runtime);
    try std.testing.expect(std.mem.indexOf(u8, runtime, "pub fn Owned") != null);

    try std.testing.expectError(error.FileNotFound, tmp.dir.access(std.testing.io, "out/models.zig", .{}));
    try std.testing.expectError(error.FileNotFound, tmp.dir.access(std.testing.io, "out/client.zig", .{}));
}

test "generateRuntimeOnly with multiple_files honors a custom runtime file name" {
    const test_utils = @import("../tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try generateRuntimeOnly(allocator, std.testing.io, tmp.dir, .{
        .input_path = "",
        .runtime_only = true,
        .multiple_files = true,
        .output_path = "out",
        .file_names = .{ .runtime = "shared/http.zig" },
    });

    const runtime = try tmp.dir.readFileAlloc(std.testing.io, "out/shared/http.zig", allocator, .unlimited);
    defer allocator.free(runtime);
    try std.testing.expect(std.mem.indexOf(u8, runtime, "pub fn Owned") != null);

    try std.testing.expectError(error.FileNotFound, tmp.dir.access(std.testing.io, "out/runtime.zig", .{}));
}

test "generateRuntimeOnly supports an absolute output path" {
    const test_utils = @import("../tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const cwd_path = try std.process.currentPathAlloc(std.testing.io, allocator);
    defer allocator.free(cwd_path);
    const output_path = try std.fs.path.join(allocator, &.{ cwd_path, ".zig-cache", "tmp", &tmp.sub_path, "abs", "runtime.zig" });
    defer allocator.free(output_path);
    try std.testing.expect(std.fs.path.isAbsolute(output_path));

    try generateRuntimeOnly(allocator, std.testing.io, std.Io.Dir.cwd(), .{
        .input_path = "",
        .runtime_only = true,
        .output_path = output_path,
    });

    const runtime = try tmp.dir.readFileAlloc(std.testing.io, "abs/runtime.zig", allocator, .unlimited);
    defer allocator.free(runtime);
    try std.testing.expect(std.mem.indexOf(u8, runtime, "pub fn Owned") != null);
}

const churn_spec =
    \\{
    \\  "openapi": "3.0.0",
    \\  "info": { "title": "fixture", "version": "1.0.0" },
    \\  "paths": {
    \\    "/pets": {
    \\      "get": {
    \\        "operationId": "listPets",
    \\        "summary": "List pets",
    \\        "description": "First line.\n\nSecond line.",
    \\        "responses": {
    \\          "200": {
    \\            "description": "ok",
    \\            "content": {
    \\              "application/json": {
    \\                "schema": { "$ref": "#/components/schemas/Pet" }
    \\              }
    \\            }
    \\          }
    \\        }
    \\      }
    \\    }
    \\  },
    \\  "components": {
    \\    "schemas": {
    \\      "Pet": {
    \\        "type": "object",
    \\        "required": ["name"],
    \\        "properties": {
    \\          "name": { "type": "string" },
    \\          "id": { "type": "integer", "format": "int64" }
    \\        }
    \\      }
    \\    }
    \\  }
    \\}
;

test "generateCodeFromUnifiedDocument skips rewriting a non-empty unchanged spec" {
    const test_utils = @import("../tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    var unified = try openapi2zig.parseToUnified(allocator, churn_spec);
    defer unified.deinit(allocator);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try generateCodeFromUnifiedDocument(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .output_path = "out/api.zig",
    });

    const first = try tmp.dir.readFileAlloc(std.testing.io, "out/api.zig", allocator, .unlimited);
    defer allocator.free(first);

    // The header timestamp has second precision, so a rewrite is only
    // detectable once the clock has advanced past a second boundary.
    try std.Io.sleep(std.testing.io, .fromMilliseconds(1100), .real);

    try generateCodeFromUnifiedDocument(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .output_path = "out/api.zig",
    });

    const second = try tmp.dir.readFileAlloc(std.testing.io, "out/api.zig", allocator, .unlimited);
    defer allocator.free(second);

    try std.testing.expectEqualStrings(first, second);
}

test "generateMultipleFiles skips rewriting a non-empty unchanged spec" {
    const test_utils = @import("../tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    var unified = try openapi2zig.parseToUnified(allocator, churn_spec);
    defer unified.deinit(allocator);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const args: cli.CliArgs = .{
        .input_path = "fixture.json",
        .multiple_files = true,
        .output_path = "out",
    };

    try generateMultipleFiles(allocator, std.testing.io, tmp.dir, unified, args);

    const first_models = try tmp.dir.readFileAlloc(std.testing.io, "out/models.zig", allocator, .unlimited);
    defer allocator.free(first_models);
    const first_client = try tmp.dir.readFileAlloc(std.testing.io, "out/client.zig", allocator, .unlimited);
    defer allocator.free(first_client);
    const first_runtime = try tmp.dir.readFileAlloc(std.testing.io, "out/runtime.zig", allocator, .unlimited);
    defer allocator.free(first_runtime);

    try std.Io.sleep(std.testing.io, .fromMilliseconds(1100), .real);

    try generateMultipleFiles(allocator, std.testing.io, tmp.dir, unified, args);

    const second_models = try tmp.dir.readFileAlloc(std.testing.io, "out/models.zig", allocator, .unlimited);
    defer allocator.free(second_models);
    const second_client = try tmp.dir.readFileAlloc(std.testing.io, "out/client.zig", allocator, .unlimited);
    defer allocator.free(second_client);
    const second_runtime = try tmp.dir.readFileAlloc(std.testing.io, "out/runtime.zig", allocator, .unlimited);
    defer allocator.free(second_runtime);

    try std.testing.expectEqualStrings(first_models, second_models);
    try std.testing.expectEqualStrings(first_client, second_client);
    try std.testing.expectEqualStrings(first_runtime, second_runtime);
}

test "generateCodeFromUnifiedDocument skips rewriting an unchanged absolute output path" {
    const test_utils = @import("../tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    var unified = try openapi2zig.parseToUnified(allocator, churn_spec);
    defer unified.deinit(allocator);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const cwd_path = try std.process.currentPathAlloc(std.testing.io, allocator);
    defer allocator.free(cwd_path);
    const output_path = try std.fs.path.join(allocator, &.{ cwd_path, ".zig-cache", "tmp", &tmp.sub_path, "abs", "api.zig" });
    defer allocator.free(output_path);
    try std.testing.expect(std.fs.path.isAbsolute(output_path));

    const args: cli.CliArgs = .{
        .input_path = "fixture.json",
        .output_path = output_path,
    };

    try generateCodeFromUnifiedDocument(allocator, std.testing.io, std.Io.Dir.cwd(), unified, args);

    const first = try tmp.dir.readFileAlloc(std.testing.io, "abs/api.zig", allocator, .unlimited);
    defer allocator.free(first);

    try std.Io.sleep(std.testing.io, .fromMilliseconds(1100), .real);

    try generateCodeFromUnifiedDocument(allocator, std.testing.io, std.Io.Dir.cwd(), unified, args);

    const second = try tmp.dir.readFileAlloc(std.testing.io, "abs/api.zig", allocator, .unlimited);
    defer allocator.free(second);

    try std.testing.expectEqualStrings(first, second);
}

test "generateRuntimeOnly skips rewriting an unchanged absolute output path" {
    const test_utils = @import("../tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const cwd_path = try std.process.currentPathAlloc(std.testing.io, allocator);
    defer allocator.free(cwd_path);
    const output_path = try std.fs.path.join(allocator, &.{ cwd_path, ".zig-cache", "tmp", &tmp.sub_path, "abs", "runtime.zig" });
    defer allocator.free(output_path);

    const args: cli.CliArgs = .{
        .input_path = "",
        .runtime_only = true,
        .output_path = output_path,
    };

    try generateRuntimeOnly(allocator, std.testing.io, std.Io.Dir.cwd(), args);

    const first = try tmp.dir.readFileAlloc(std.testing.io, "abs/runtime.zig", allocator, .unlimited);
    defer allocator.free(first);

    try std.Io.sleep(std.testing.io, .fromMilliseconds(1100), .real);

    try generateRuntimeOnly(allocator, std.testing.io, std.Io.Dir.cwd(), args);

    const second = try tmp.dir.readFileAlloc(std.testing.io, "abs/runtime.zig", allocator, .unlimited);
    defer allocator.free(second);

    try std.testing.expectEqualStrings(first, second);
}
