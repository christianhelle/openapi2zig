const std = @import("std");

///////////////////////////////////////////
// Generated Zig structures from OpenAPI
///////////////////////////////////////////

pub const Category = struct {
    id: ?i64 = null,
    name: ?[]const u8 = null,
};

pub const Pet = struct {
    status: ?[]const u8 = null,
    tags: ?[]const std.json.Value = null,
    category: ?Category = null,
    id: ?i64 = null,
    name: []const u8,
    photoUrls: []const []const u8,
};

pub const User = struct {
    password: ?[]const u8 = null,
    userStatus: ?i64 = null,
    username: ?[]const u8 = null,
    email: ?[]const u8 = null,
    firstName: ?[]const u8 = null,
    id: ?i64 = null,
    lastName: ?[]const u8 = null,
    phone: ?[]const u8 = null,
};

pub const Tag = struct {
    id: ?i64 = null,
    name: ?[]const u8 = null,
};

pub const Order = struct {
    status: ?[]const u8 = null,
    petId: ?i64 = null,
    complete: ?bool = null,
    id: ?i64 = null,
    quantity: ?i64 = null,
    shipDate: ?[]const u8 = null,
};

pub const ApiResponse = struct {
    type: ?[]const u8 = null,
    message: ?[]const u8 = null,
    code: ?i64 = null,
};

///////////////////////////////////////////
// Generated Zig API client from OpenAPI
///////////////////////////////////////////

/////////////////
// Summary:
// Place an order for a pet
//
// Description:
//
//
pub fn placeOrder(allocator: std.mem.Allocator, io: std.Io, requestBody: Order) !void {
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const uri_str = try std.fmt.allocPrint(allocator, "https://petstore.swagger.io/v2/store/order", .{});
    defer allocator.free(uri_str);
    const uri = try std.Uri.parse(uri_str);
    var str: std.Io.Writer.Allocating = .init(allocator);
    defer str.deinit();

    try std.json.Stringify.value(requestBody, .{ .emit_null_optional_fields = false }, &str.writer);
    const payload = str.written();

    const result = try client.fetch(.{
        .location = .{ .uri = uri },
        .method = std.http.Method.POST,
        .extra_headers = headers,
        .payload = payload,
    });
    if (result.status.class() != .success) {
        return error.ResponseError;
    }
}

/////////////////
// Summary:
// uploads an image
//
// Description:
//
//
pub fn uploadFile(allocator: std.mem.Allocator, io: std.Io, petId: i64, additionalMetadata: []const u8, file: []const u8) !void {
    _ = additionalMetadata;
    _ = file;
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const uri_str = try std.fmt.allocPrint(allocator, "https://petstore.swagger.io/v2/pet/{d}/uploadImage", .{
        petId,
    });
    defer allocator.free(uri_str);
    const uri = try std.Uri.parse(uri_str);
    const result = try client.fetch(.{
        .location = .{ .uri = uri },
        .method = std.http.Method.POST,
        .extra_headers = headers,
    });
    if (result.status.class() != .success) {
        return error.ResponseError;
    }
}

/////////////////
// Summary:
// Find pet by ID
//
// Description:
// Returns a single pet
//
pub fn getPetById(allocator: std.mem.Allocator, io: std.Io, petId: i64) !Pet {
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const uri_str = try std.fmt.allocPrint(allocator, "https://petstore.swagger.io/v2/pet/{d}", .{petId});
    defer allocator.free(uri_str);
    const uri = try std.Uri.parse(uri_str);
    var response_body: std.Io.Writer.Allocating = .init(allocator);
    defer response_body.deinit();

    const result = try client.fetch(.{
        .location = .{ .uri = uri },
        .method = std.http.Method.GET,
        .extra_headers = headers,
        .response_writer = &response_body.writer,
    });
    if (result.status.class() != .success) {
        return error.ResponseError;
    }

    const body = response_body.written();
    const parsed = try std.json.parseFromSlice(Pet, allocator, body, .{});
    defer parsed.deinit();

    return parsed.value;
}

/////////////////
// Summary:
// Updates a pet in the store with form data
//
// Description:
//
//
pub fn updatePetWithForm(allocator: std.mem.Allocator, io: std.Io, petId: i64, name: []const u8, status: []const u8) !void {
    _ = name;
    _ = status;
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const uri_str = try std.fmt.allocPrint(allocator, "https://petstore.swagger.io/v2/pet/{d}", .{
        petId,
    });
    defer allocator.free(uri_str);
    const uri = try std.Uri.parse(uri_str);
    const result = try client.fetch(.{
        .location = .{ .uri = uri },
        .method = std.http.Method.POST,
        .extra_headers = headers,
    });
    if (result.status.class() != .success) {
        return error.ResponseError;
    }
}

/////////////////
// Summary:
// Deletes a pet
//
// Description:
//
//
pub fn deletePet(allocator: std.mem.Allocator, io: std.Io, api_key: []const u8, petId: i64) !void {
    _ = api_key;
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const uri_str = try std.fmt.allocPrint(allocator, "https://petstore.swagger.io/v2/pet/{d}", .{
        petId,
    });
    defer allocator.free(uri_str);
    const uri = try std.Uri.parse(uri_str);
    const result = try client.fetch(.{
        .location = .{ .uri = uri },
        .method = std.http.Method.DELETE,
        .extra_headers = headers,
    });
    if (result.status.class() != .success) {
        return error.ResponseError;
    }
}

/////////////////
// Summary:
// Finds Pets by tags
//
// Description:
// Multiple tags can be provided with comma separated strings. Use tag1, tag2, tag3 for testing.
//
pub fn findPetsByTags(allocator: std.mem.Allocator, io: std.Io, tags: []const u8) ![]const u8 {
    _ = tags;
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const uri_str = try std.fmt.allocPrint(allocator, "https://petstore.swagger.io/v2/pet/findByTags", .{});
    defer allocator.free(uri_str);
    const uri = try std.Uri.parse(uri_str);
    var response_body: std.Io.Writer.Allocating = .init(allocator);
    defer response_body.deinit();

    const result = try client.fetch(.{
        .location = .{ .uri = uri },
        .method = std.http.Method.GET,
        .extra_headers = headers,
        .response_writer = &response_body.writer,
    });
    if (result.status.class() != .success) {
        return error.ResponseError;
    }

    const body = response_body.written();
    const parsed = try std.json.parseFromSlice([]const u8, allocator, body, .{});
    defer parsed.deinit();

    return parsed.value;
}

/////////////////
// Summary:
// Logs user into the system
//
// Description:
//
//
pub fn loginUser(allocator: std.mem.Allocator, io: std.Io, username: []const u8, password: []const u8) ![]const u8 {
    _ = username;
    _ = password;
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const uri_str = try std.fmt.allocPrint(allocator, "https://petstore.swagger.io/v2/user/login", .{});
    defer allocator.free(uri_str);
    const uri = try std.Uri.parse(uri_str);
    var response_body: std.Io.Writer.Allocating = .init(allocator);
    defer response_body.deinit();

    const result = try client.fetch(.{
        .location = .{ .uri = uri },
        .method = std.http.Method.GET,
        .extra_headers = headers,
        .response_writer = &response_body.writer,
    });
    if (result.status.class() != .success) {
        return error.ResponseError;
    }

    const body = response_body.written();
    const parsed = try std.json.parseFromSlice([]const u8, allocator, body, .{});
    defer parsed.deinit();

    return parsed.value;
}

/////////////////
// Summary:
// Creates list of users with given input array
//
// Description:
//
//
pub fn createUsersWithArrayInput(allocator: std.mem.Allocator, io: std.Io, requestBody: []const u8) !void {
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const uri_str = try std.fmt.allocPrint(allocator, "https://petstore.swagger.io/v2/user/createWithArray", .{});
    defer allocator.free(uri_str);
    const uri = try std.Uri.parse(uri_str);
    var str: std.Io.Writer.Allocating = .init(allocator);
    defer str.deinit();

    try std.json.Stringify.value(requestBody, .{ .emit_null_optional_fields = false }, &str.writer);
    const payload = str.written();

    const result = try client.fetch(.{
        .location = .{ .uri = uri },
        .method = std.http.Method.POST,
        .extra_headers = headers,
        .payload = payload,
    });
    if (result.status.class() != .success) {
        return error.ResponseError;
    }
}

/////////////////
// Summary:
// Finds Pets by status
//
// Description:
// Multiple status values can be provided with comma separated strings
//
pub fn findPetsByStatus(allocator: std.mem.Allocator, io: std.Io, status: []const u8) ![]const u8 {
    _ = status;
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const uri_str = try std.fmt.allocPrint(allocator, "https://petstore.swagger.io/v2/pet/findByStatus", .{});
    defer allocator.free(uri_str);
    const uri = try std.Uri.parse(uri_str);
    var response_body: std.Io.Writer.Allocating = .init(allocator);
    defer response_body.deinit();

    const result = try client.fetch(.{
        .location = .{ .uri = uri },
        .method = std.http.Method.GET,
        .extra_headers = headers,
        .response_writer = &response_body.writer,
    });
    if (result.status.class() != .success) {
        return error.ResponseError;
    }

    const body = response_body.written();
    const parsed = try std.json.parseFromSlice([]const u8, allocator, body, .{});
    defer parsed.deinit();

    return parsed.value;
}

/////////////////
// Summary:
// Returns pet inventories by status
//
// Description:
// Returns a map of status codes to quantities
//
pub fn getInventory(allocator: std.mem.Allocator, io: std.Io) !std.json.Value {
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const uri_str = try std.fmt.allocPrint(allocator, "https://petstore.swagger.io/v2/store/inventory", .{});
    defer allocator.free(uri_str);
    const uri = try std.Uri.parse(uri_str);
    var response_body: std.Io.Writer.Allocating = .init(allocator);
    defer response_body.deinit();

    const result = try client.fetch(.{
        .location = .{ .uri = uri },
        .method = std.http.Method.GET,
        .extra_headers = headers,
        .response_writer = &response_body.writer,
    });
    if (result.status.class() != .success) {
        return error.ResponseError;
    }

    const body = response_body.written();
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();

    return parsed.value;
}

/////////////////
// Summary:
// Get user by user name
//
// Description:
//
//
pub fn getUserByName(allocator: std.mem.Allocator, io: std.Io, username: []const u8) !User {
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const uri_str = try std.fmt.allocPrint(allocator, "https://petstore.swagger.io/v2/user/{s}", .{username});
    defer allocator.free(uri_str);
    const uri = try std.Uri.parse(uri_str);
    var response_body: std.Io.Writer.Allocating = .init(allocator);
    defer response_body.deinit();

    const result = try client.fetch(.{
        .location = .{ .uri = uri },
        .method = std.http.Method.GET,
        .extra_headers = headers,
        .response_writer = &response_body.writer,
    });
    if (result.status.class() != .success) {
        return error.ResponseError;
    }

    const body = response_body.written();
    const parsed = try std.json.parseFromSlice(User, allocator, body, .{});
    defer parsed.deinit();

    return parsed.value;
}

/////////////////
// Summary:
// Updated user
//
// Description:
// This can only be done by the logged in user.
//
pub fn updateUser(allocator: std.mem.Allocator, io: std.Io, username: []const u8, requestBody: User) !void {
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const uri_str = try std.fmt.allocPrint(allocator, "https://petstore.swagger.io/v2/user/{s}", .{
        username,
    });
    defer allocator.free(uri_str);
    const uri = try std.Uri.parse(uri_str);
    var str: std.Io.Writer.Allocating = .init(allocator);
    defer str.deinit();

    try std.json.Stringify.value(requestBody, .{ .emit_null_optional_fields = false }, &str.writer);
    const payload = str.written();

    const result = try client.fetch(.{
        .location = .{ .uri = uri },
        .method = std.http.Method.PUT,
        .extra_headers = headers,
        .payload = payload,
    });
    if (result.status.class() != .success) {
        return error.ResponseError;
    }
}

/////////////////
// Summary:
// Delete user
//
// Description:
// This can only be done by the logged in user.
//
pub fn deleteUser(allocator: std.mem.Allocator, io: std.Io, username: []const u8) !void {
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const uri_str = try std.fmt.allocPrint(allocator, "https://petstore.swagger.io/v2/user/{s}", .{username});
    defer allocator.free(uri_str);
    const uri = try std.Uri.parse(uri_str);
    const result = try client.fetch(.{
        .location = .{ .uri = uri },
        .method = std.http.Method.DELETE,
        .extra_headers = headers,
    });
    if (result.status.class() != .success) {
        return error.ResponseError;
    }
}

/////////////////
// Summary:
// Create user
//
// Description:
// This can only be done by the logged in user.
//
pub fn createUser(allocator: std.mem.Allocator, io: std.Io, requestBody: User) !void {
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const uri_str = try std.fmt.allocPrint(allocator, "https://petstore.swagger.io/v2/user", .{});
    defer allocator.free(uri_str);
    const uri = try std.Uri.parse(uri_str);
    var str: std.Io.Writer.Allocating = .init(allocator);
    defer str.deinit();

    try std.json.Stringify.value(requestBody, .{ .emit_null_optional_fields = false }, &str.writer);
    const payload = str.written();

    const result = try client.fetch(.{
        .location = .{ .uri = uri },
        .method = std.http.Method.POST,
        .extra_headers = headers,
        .payload = payload,
    });
    if (result.status.class() != .success) {
        return error.ResponseError;
    }
}

/////////////////
// Summary:
// Creates list of users with given input array
//
// Description:
//
//
pub fn createUsersWithListInput(allocator: std.mem.Allocator, io: std.Io, requestBody: []const u8) !void {
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const uri_str = try std.fmt.allocPrint(allocator, "https://petstore.swagger.io/v2/user/createWithList", .{});
    defer allocator.free(uri_str);
    const uri = try std.Uri.parse(uri_str);
    var str: std.Io.Writer.Allocating = .init(allocator);
    defer str.deinit();

    try std.json.Stringify.value(requestBody, .{ .emit_null_optional_fields = false }, &str.writer);
    const payload = str.written();

    const result = try client.fetch(.{
        .location = .{ .uri = uri },
        .method = std.http.Method.POST,
        .extra_headers = headers,
        .payload = payload,
    });
    if (result.status.class() != .success) {
        return error.ResponseError;
    }
}

/////////////////
// Summary:
// Add a new pet to the store
//
// Description:
//
//
pub fn addPet(allocator: std.mem.Allocator, io: std.Io, requestBody: Pet) !void {
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const uri_str = try std.fmt.allocPrint(allocator, "https://petstore.swagger.io/v2/pet", .{});
    defer allocator.free(uri_str);
    const uri = try std.Uri.parse(uri_str);
    var str: std.Io.Writer.Allocating = .init(allocator);
    defer str.deinit();

    try std.json.Stringify.value(requestBody, .{ .emit_null_optional_fields = false }, &str.writer);
    const payload = str.written();

    const result = try client.fetch(.{
        .location = .{ .uri = uri },
        .method = std.http.Method.POST,
        .extra_headers = headers,
        .payload = payload,
    });
    if (result.status.class() != .success) {
        return error.ResponseError;
    }
}

/////////////////
// Summary:
// Update an existing pet
//
// Description:
//
//
pub fn updatePet(allocator: std.mem.Allocator, io: std.Io, requestBody: Pet) !void {
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const uri_str = try std.fmt.allocPrint(allocator, "https://petstore.swagger.io/v2/pet", .{});
    defer allocator.free(uri_str);
    const uri = try std.Uri.parse(uri_str);
    var str: std.Io.Writer.Allocating = .init(allocator);
    defer str.deinit();

    try std.json.Stringify.value(requestBody, .{ .emit_null_optional_fields = false }, &str.writer);
    const payload = str.written();

    const result = try client.fetch(.{
        .location = .{ .uri = uri },
        .method = std.http.Method.PUT,
        .extra_headers = headers,
        .payload = payload,
    });
    if (result.status.class() != .success) {
        return error.ResponseError;
    }
}

/////////////////
// Summary:
// Find purchase order by ID
//
// Description:
// For valid response try integer IDs with value >= 1 and <= 10. Other values will generated exceptions
//
pub fn getOrderById(allocator: std.mem.Allocator, io: std.Io, orderId: i64) !Order {
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const uri_str = try std.fmt.allocPrint(allocator, "https://petstore.swagger.io/v2/store/order/{d}", .{orderId});
    defer allocator.free(uri_str);
    const uri = try std.Uri.parse(uri_str);
    var response_body: std.Io.Writer.Allocating = .init(allocator);
    defer response_body.deinit();

    const result = try client.fetch(.{
        .location = .{ .uri = uri },
        .method = std.http.Method.GET,
        .extra_headers = headers,
        .response_writer = &response_body.writer,
    });
    if (result.status.class() != .success) {
        return error.ResponseError;
    }

    const body = response_body.written();
    const parsed = try std.json.parseFromSlice(Order, allocator, body, .{});
    defer parsed.deinit();

    return parsed.value;
}

/////////////////
// Summary:
// Delete purchase order by ID
//
// Description:
// For valid response try integer IDs with positive integer value. Negative or non-integer values will generate API errors
//
pub fn deleteOrder(allocator: std.mem.Allocator, io: std.Io, orderId: i64) !void {
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const uri_str = try std.fmt.allocPrint(allocator, "https://petstore.swagger.io/v2/store/order/{d}", .{orderId});
    defer allocator.free(uri_str);
    const uri = try std.Uri.parse(uri_str);
    const result = try client.fetch(.{
        .location = .{ .uri = uri },
        .method = std.http.Method.DELETE,
        .extra_headers = headers,
    });
    if (result.status.class() != .success) {
        return error.ResponseError;
    }
}

/////////////////
// Summary:
// Logs out current logged in user session
//
// Description:
//
//
pub fn logoutUser(allocator: std.mem.Allocator, io: std.Io) !void {
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const uri_str = try std.fmt.allocPrint(allocator, "https://petstore.swagger.io/v2/user/logout", .{});
    defer allocator.free(uri_str);
    const uri = try std.Uri.parse(uri_str);
    const result = try client.fetch(.{
        .location = .{ .uri = uri },
        .method = std.http.Method.GET,
        .extra_headers = headers,
    });
    if (result.status.class() != .success) {
        return error.ResponseError;
    }
}
