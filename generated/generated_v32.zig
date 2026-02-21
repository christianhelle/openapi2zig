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
// Returns pet inventories by status
//
// Description:
// Returns a map of status codes to quantities
//
pub fn getInventory(allocator: std.mem.Allocator) !std.json.Value {
    var client = std.http.Client { .allocator = allocator };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const uri = try std.Uri.parse("https://petstore3.swagger.io/api/v3/store/inventory");
    var req = try client.request(std.http.Method.GET, uri, .{ .extra_headers = headers });
    defer req.deinit();

    try req.sendBodiless();

    var response = try req.receiveHead(&.{});
    if (response.head.status != .ok) {
        return error.ResponseError;
    }

    var reader_buffer: [100]u8 = undefined;
    const body_reader = response.reader(&reader_buffer);
    const body = try body_reader.readAlloc(allocator, response.head.content_length orelse 1024 * 1024 * 4);
    defer allocator.free(body);

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
pub fn getUserByName(allocator: std.mem.Allocator, username: []const u8) !User {
    var client = std.http.Client { .allocator = allocator };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const uri_str = try std.fmt.allocPrint(allocator, "https://petstore3.swagger.io/api/v3/user/{s}", .{username});
    defer allocator.free(uri_str);
    const uri = try std.Uri.parse(uri_str);
    var req = try client.request(std.http.Method.GET, uri, .{ .extra_headers = headers });
    defer req.deinit();

    try req.sendBodiless();

    var response = try req.receiveHead(&.{});
    if (response.head.status != .ok) {
        return error.ResponseError;
    }

    var reader_buffer: [100]u8 = undefined;
    const body_reader = response.reader(&reader_buffer);
    const body = try body_reader.readAlloc(allocator, response.head.content_length orelse 1024 * 1024 * 4);
    defer allocator.free(body);

    const parsed = try std.json.parseFromSlice(User, allocator, body, .{});
    defer parsed.deinit();

    return parsed.value;
}

/////////////////
// Summary:
// Place an order for a pet
//
// Description:
// Place a new order in the store
//
pub fn placeOrder(allocator: std.mem.Allocator, requestBody: Order) !void {
    var client = std.http.Client { .allocator = allocator };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const uri_str = try std.fmt.allocPrint(allocator, "https://petstore3.swagger.io/api/v3/store/order", .{});
    defer allocator.free(uri_str);
    const uri = try std.Uri.parse(uri_str);
    var req = try client.request(std.http.Method.POST, uri, .{ .extra_headers = headers });
    defer req.deinit();

    var str = std.ArrayList(u8){};
    defer str.deinit(allocator);

    try std.json.stringify(requestBody, .{}, str.writer());
    const payload = str.items;

    req.transfer_encoding = .{ .content_length = payload.len };
    try req.sendBodyComplete(payload);

}

/////////////////
// Summary:
// Create user
//
// Description:
// This can only be done by the logged in user.
//
pub fn createUser(allocator: std.mem.Allocator, requestBody: User) !void {
    var client = std.http.Client { .allocator = allocator };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const uri_str = try std.fmt.allocPrint(allocator, "https://petstore3.swagger.io/api/v3/user", .{});
    defer allocator.free(uri_str);
    const uri = try std.Uri.parse(uri_str);
    var req = try client.request(std.http.Method.POST, uri, .{ .extra_headers = headers });
    defer req.deinit();

    var str = std.ArrayList(u8){};
    defer str.deinit(allocator);

    try std.json.stringify(requestBody, .{}, str.writer());
    const payload = str.items;

    req.transfer_encoding = .{ .content_length = payload.len };
    try req.sendBodyComplete(payload);

}

/////////////////
// Summary:
// Find pet by ID
//
// Description:
// Returns a single pet
//
pub fn getPetById(allocator: std.mem.Allocator, petId: []const u8) !Pet {
    var client = std.http.Client { .allocator = allocator };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const uri_str = try std.fmt.allocPrint(allocator, "https://petstore3.swagger.io/api/v3/pet/{s}", .{petId});
    defer allocator.free(uri_str);
    const uri = try std.Uri.parse(uri_str);
    var req = try client.request(std.http.Method.GET, uri, .{ .extra_headers = headers });
    defer req.deinit();

    try req.sendBodiless();

    var response = try req.receiveHead(&.{});
    if (response.head.status != .ok) {
        return error.ResponseError;
    }

    var reader_buffer: [100]u8 = undefined;
    const body_reader = response.reader(&reader_buffer);
    const body = try body_reader.readAlloc(allocator, response.head.content_length orelse 1024 * 1024 * 4);
    defer allocator.free(body);

    const parsed = try std.json.parseFromSlice(Pet, allocator, body, .{});
    defer parsed.deinit();

    return parsed.value;
}

/////////////////
// Summary:
// Deletes a pet
//
// Description:
// 
//
pub fn deletePet(allocator: std.mem.Allocator, api_key: []const u8, petId: []const u8) !void {
    _ = api_key;
    var client = std.http.Client { .allocator = allocator };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const uri_str = try std.fmt.allocPrint(allocator, "https://petstore3.swagger.io/api/v3/pet/{s}", .{petId, });
    defer allocator.free(uri_str);
    const uri = try std.Uri.parse(uri_str);
    var req = try client.request(std.http.Method.DELETE, uri, .{ .extra_headers = headers });
    defer req.deinit();

    try req.sendBodiless();
}

/////////////////
// Summary:
// Add a new pet to the store
//
// Description:
// Add a new pet to the store
//
pub fn addPet(allocator: std.mem.Allocator, requestBody: Pet) !void {
    var client = std.http.Client { .allocator = allocator };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const uri_str = try std.fmt.allocPrint(allocator, "https://petstore3.swagger.io/api/v3/pet", .{});
    defer allocator.free(uri_str);
    const uri = try std.Uri.parse(uri_str);
    var req = try client.request(std.http.Method.POST, uri, .{ .extra_headers = headers });
    defer req.deinit();

    var str = std.ArrayList(u8){};
    defer str.deinit(allocator);

    try std.json.stringify(requestBody, .{}, str.writer());
    const payload = str.items;

    req.transfer_encoding = .{ .content_length = payload.len };
    try req.sendBodyComplete(payload);

}

/////////////////
// Summary:
// Update an existing pet
//
// Description:
// Update an existing pet by Id
//
pub fn updatePet(allocator: std.mem.Allocator, requestBody: Pet) !void {
    var client = std.http.Client { .allocator = allocator };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const uri_str = try std.fmt.allocPrint(allocator, "https://petstore3.swagger.io/api/v3/pet", .{});
    defer allocator.free(uri_str);
    const uri = try std.Uri.parse(uri_str);
    var req = try client.request(std.http.Method.PUT, uri, .{ .extra_headers = headers });
    defer req.deinit();

    var str = std.ArrayList(u8){};
    defer str.deinit(allocator);

    try std.json.stringify(requestBody, .{}, str.writer());
    const payload = str.items;

    req.transfer_encoding = .{ .content_length = payload.len };
    try req.sendBodyComplete(payload);

}

/////////////////
// Summary:
// Finds Pets by status
//
// Description:
// Multiple status values can be provided with comma separated strings
//
pub fn findPetsByStatus(allocator: std.mem.Allocator, status: []const u8) ![]const u8 {
    _ = status;
    var client = std.http.Client { .allocator = allocator };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const uri_str = try std.fmt.allocPrint(allocator, "https://petstore3.swagger.io/api/v3/pet/findByStatus", .{});
    defer allocator.free(uri_str);
    const uri = try std.Uri.parse(uri_str);
    var req = try client.request(std.http.Method.GET, uri, .{ .extra_headers = headers });
    defer req.deinit();

    try req.sendBodiless();

    var response = try req.receiveHead(&.{});
    if (response.head.status != .ok) {
        return error.ResponseError;
    }

    var reader_buffer: [100]u8 = undefined;
    const body_reader = response.reader(&reader_buffer);
    const body = try body_reader.readAlloc(allocator, response.head.content_length orelse 1024 * 1024 * 4);
    defer allocator.free(body);

    const parsed = try std.json.parseFromSlice([]const u8, allocator, body, .{});
    defer parsed.deinit();

    return parsed.value;
}

