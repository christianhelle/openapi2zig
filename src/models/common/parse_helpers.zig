const std = @import("std");
const json = std.json;

pub fn parseArray(comptime T: type, allocator: std.mem.Allocator, value: json.Value) anyerror![]T {
    var array_list = std.ArrayList(T).empty;
    errdefer {
        for (array_list.items) |*item| {
            if (@hasDecl(T, "deinit")) {
                item.deinit(allocator);
            }
        }
        array_list.deinit(allocator);
    }
    for (value.array.items) |item| {
        try array_list.append(allocator, try T.parseFromJson(allocator, item));
    }
    return array_list.toOwnedSlice(allocator);
}
