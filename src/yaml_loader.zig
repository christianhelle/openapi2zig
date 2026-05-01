const std = @import("std");
const yaml = @import("yaml");

const YamlValue = yaml.Yaml.Value;
const lbrace_placeholder = "__openapi2zig_lbrace__";
const rbrace_placeholder = "__openapi2zig_rbrace__";
const unquoted_scalar_placeholder = "__openapi2zig_unquoted_scalar__";

pub const YamlToJsonError = error{
    EmptyYamlDocument,
    MultipleYamlDocumentsUnsupported,
};

pub fn yamlToJson(allocator: std.mem.Allocator, yaml_content: []const u8) ![]const u8 {
    // Normalize common OpenAPI YAML forms that zig-yaml does not parse directly.
    const block_folded_yaml = try foldBlockScalars(allocator, yaml_content);
    defer allocator.free(block_folded_yaml);

    const folded_yaml = try foldDoubleQuotedContinuations(allocator, block_folded_yaml);
    defer allocator.free(folded_yaml);

    const normalized_yaml = try normalizeQuotedMapKeys(allocator, folded_yaml);
    defer allocator.free(normalized_yaml);

    const marked_yaml = try markOriginallyUnquotedScalars(allocator, normalized_yaml);
    defer allocator.free(marked_yaml);

    var parsed: yaml.Yaml = .{ .source = marked_yaml };
    defer parsed.deinit(allocator);

    try parsed.load(allocator);

    if (parsed.docs.items.len == 0) return YamlToJsonError.EmptyYamlDocument;
    if (parsed.docs.items.len > 1) return YamlToJsonError.MultipleYamlDocumentsUnsupported;

    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();

    try writeJsonValue(allocator, &out.writer, parsed.docs.items[0], null);
    return try out.toOwnedSlice();
}

fn foldBlockScalars(allocator: std.mem.Allocator, yaml_content: []const u8) ![]const u8 {
    var source_lines = std.ArrayList([]const u8).empty;
    defer source_lines.deinit(allocator);

    var lines = std.mem.splitScalar(u8, yaml_content, '\n');
    while (lines.next()) |line| {
        try source_lines.append(allocator, line);
    }

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    var line_index: usize = 0;
    var first_output_line = true;
    while (line_index < source_lines.items.len) {
        const line = source_lines.items[line_index];
        if (blockScalarHeader(line)) |header| {
            if (!first_output_line) try out.append(allocator, '\n');
            first_output_line = false;

            try out.appendSlice(allocator, line[0 .. header.colon_index + 1]);
            try out.appendSlice(allocator, " \"");

            line_index += 1;
            var block_indent: ?usize = null;
            var first_block_line = true;
            var folded_paragraph_break = false;
            while (line_index < source_lines.items.len) {
                const block_line = source_lines.items[line_index];
                const trimmed_block_line = std.mem.trim(u8, block_line, " \t\r");
                const indent = countIndent(block_line);
                if (trimmed_block_line.len != 0 and indent <= header.parent_indent) break;

                if (trimmed_block_line.len == 0) {
                    if (!first_block_line and header.style == '|') {
                        try appendYamlDoubleQuotedChar(allocator, &out, '\n');
                    } else if (!first_block_line and header.style == '>') {
                        try appendYamlDoubleQuotedChar(allocator, &out, '\n');
                        try appendYamlDoubleQuotedChar(allocator, &out, '\n');
                        folded_paragraph_break = true;
                    }
                    line_index += 1;
                    continue;
                }

                if (block_indent == null) block_indent = indent;
                const content_start = @min(block_indent.?, block_line.len);
                const content = block_line[content_start..];
                if (!first_block_line) {
                    if (header.style == '|') {
                        try appendYamlDoubleQuotedChar(allocator, &out, '\n');
                    } else if (!folded_paragraph_break) {
                        try out.append(allocator, ' ');
                    }
                }
                try appendYamlDoubleQuotedContent(allocator, &out, content);
                first_block_line = false;
                folded_paragraph_break = false;
                line_index += 1;
            }

            try out.append(allocator, '"');
            continue;
        }

        if (!first_output_line) try out.append(allocator, '\n');
        first_output_line = false;
        try out.appendSlice(allocator, line);
        line_index += 1;
    }

    return try out.toOwnedSlice(allocator);
}

const BlockScalarHeader = struct {
    parent_indent: usize,
    colon_index: usize,
    style: u8,
};

fn blockScalarHeader(line: []const u8) ?BlockScalarHeader {
    const colon_index = std.mem.indexOfScalar(u8, line, ':') orelse return null;
    const value = std.mem.trim(u8, line[colon_index + 1 ..], " \t\r");
    if (value.len == 0) return null;
    if (value[0] != '|' and value[0] != '>') return null;
    return .{
        .parent_indent = countIndent(line),
        .colon_index = colon_index,
        .style = value[0],
    };
}

fn countIndent(line: []const u8) usize {
    var indent: usize = 0;
    while (indent < line.len and (line[indent] == ' ' or line[indent] == '\t')) : (indent += 1) {}
    return indent;
}

fn appendYamlDoubleQuotedContent(allocator: std.mem.Allocator, out: *std.ArrayList(u8), content: []const u8) !void {
    for (content) |char| {
        try appendYamlDoubleQuotedChar(allocator, out, char);
    }
}

fn appendYamlDoubleQuotedChar(allocator: std.mem.Allocator, out: *std.ArrayList(u8), char: u8) !void {
    switch (char) {
        '\n' => try out.appendSlice(allocator, "\\n"),
        '\t' => try out.appendSlice(allocator, "\\t"),
        '\\' => try out.appendSlice(allocator, "\\\\"),
        '"' => try out.appendSlice(allocator, "\\\""),
        else => try out.append(allocator, char),
    }
}

fn foldDoubleQuotedContinuations(allocator: std.mem.Allocator, yaml_content: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    var lines = std.mem.splitScalar(u8, yaml_content, '\n');
    var first_output_line = true;
    while (lines.next()) |line| {
        if (!first_output_line) try out.append(allocator, '\n');
        first_output_line = false;

        if (!hasUnclosedDoubleQuote(line)) {
            try out.appendSlice(allocator, line);
            continue;
        }

        try out.appendSlice(allocator, stripTrailingContinuationBackslash(line));
        while (lines.next()) |continuation_line| {
            const continuation = trimLineStart(continuation_line);
            const value = if (continuation.len > 0 and continuation[0] == '\\') continuation[1..] else continuation;
            const finished = !hasTrailingContinuationBackslash(continuation_line);
            try out.appendSlice(allocator, stripTrailingContinuationBackslash(value));
            if (finished) break;
        }
    }

    return try out.toOwnedSlice(allocator);
}

fn hasUnclosedDoubleQuote(line: []const u8) bool {
    var quote_count: usize = 0;
    var escaped = false;
    for (line) |char| {
        if (escaped) {
            escaped = false;
            continue;
        }
        if (char == '\\') {
            escaped = true;
            continue;
        }
        if (char == '"') quote_count += 1;
    }
    return quote_count % 2 == 1;
}

fn hasTrailingContinuationBackslash(line: []const u8) bool {
    const trimmed = trimLineEnd(line);
    return trimmed.len > 0 and trimmed[trimmed.len - 1] == '\\';
}

fn stripTrailingContinuationBackslash(line: []const u8) []const u8 {
    const trimmed = trimLineEnd(line);
    if (trimmed.len == 0 or trimmed[trimmed.len - 1] != '\\') return line;
    return trimmed[0 .. trimmed.len - 1];
}

fn trimLineStart(line: []const u8) []const u8 {
    var index: usize = 0;
    while (index < line.len and (line[index] == ' ' or line[index] == '\t')) : (index += 1) {}
    return line[index..];
}

fn trimLineEnd(line: []const u8) []const u8 {
    var end = line.len;
    while (end > 0 and (line[end - 1] == ' ' or line[end - 1] == '\t' or line[end - 1] == '\r')) : (end -= 1) {}
    return line[0..end];
}

fn normalizeQuotedMapKeys(allocator: std.mem.Allocator, yaml_content: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    var lines = std.mem.splitScalar(u8, yaml_content, '\n');
    var first_line = true;
    while (lines.next()) |line| {
        if (!first_line) try out.append(allocator, '\n');
        first_line = false;

        try appendNormalizedMapKeyLine(allocator, &out, line);
    }

    return try out.toOwnedSlice(allocator);
}

fn appendNormalizedMapKeyLine(allocator: std.mem.Allocator, out: *std.ArrayList(u8), line: []const u8) !void {
    var index: usize = 0;
    while (index < line.len and (line[index] == ' ' or line[index] == '\t')) : (index += 1) {}

    if (index >= line.len or (line[index] != '\'' and line[index] != '"')) {
        try appendLineWithEscapedKeyBraces(allocator, out, line);
        return;
    }

    const quote = line[index];
    const key_start = index + 1;
    var key_end = key_start;
    while (key_end < line.len) : (key_end += 1) {
        if (line[key_end] != quote) continue;
        if (quote == '\'' and key_end + 1 < line.len and line[key_end + 1] == '\'') {
            key_end += 1;
            continue;
        }
        break;
    }

    if (key_end >= line.len or key_end + 1 >= line.len or line[key_end + 1] != ':') {
        try out.appendSlice(allocator, line);
        return;
    }

    const key = if (quote == '\'')
        try unescapeSingleQuoted(allocator, line[key_start..key_end])
    else
        try unescapeDoubleQuoted(allocator, line[key_start..key_end]);
    defer allocator.free(key);

    try out.appendSlice(allocator, line[0..index]);
    try appendKeyWithEscapedBraces(allocator, out, key);
    try out.appendSlice(allocator, line[key_end + 1 ..]);
}

fn appendLineWithEscapedKeyBraces(allocator: std.mem.Allocator, out: *std.ArrayList(u8), line: []const u8) !void {
    const colon_index = std.mem.indexOfScalar(u8, line, ':') orelse {
        try out.appendSlice(allocator, line);
        return;
    };

    try appendKeyWithEscapedBraces(allocator, out, line[0..colon_index]);
    try out.appendSlice(allocator, line[colon_index..]);
}

fn appendKeyWithEscapedBraces(allocator: std.mem.Allocator, out: *std.ArrayList(u8), key: []const u8) !void {
    for (key) |char| {
        switch (char) {
            '{' => try out.appendSlice(allocator, lbrace_placeholder),
            '}' => try out.appendSlice(allocator, rbrace_placeholder),
            else => try out.append(allocator, char),
        }
    }
}

fn markOriginallyUnquotedScalars(allocator: std.mem.Allocator, yaml_content: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    var lines = std.mem.splitScalar(u8, yaml_content, '\n');
    var first_output_line = true;
    while (lines.next()) |line| {
        if (!first_output_line) try out.append(allocator, '\n');
        first_output_line = false;
        try appendMarkedLine(allocator, &out, line);
    }

    return try out.toOwnedSlice(allocator);
}

fn appendMarkedLine(allocator: std.mem.Allocator, out: *std.ArrayList(u8), line: []const u8) !void {
    const colon_index = std.mem.indexOfScalar(u8, line, ':') orelse {
        try out.appendSlice(allocator, line);
        return;
    };

    var value_start = colon_index + 1;
    while (value_start < line.len and (line[value_start] == ' ' or line[value_start] == '\t')) : (value_start += 1) {}

    if (value_start >= line.len) {
        try out.appendSlice(allocator, line);
        return;
    }

    const comment_index = findInlineCommentStart(line[value_start..]) orelse line[value_start..].len;
    const scalar_end = value_start + comment_index;
    const scalar = std.mem.trimEnd(u8, line[value_start..scalar_end], " \t\r");
    if (!shouldMarkOriginallyUnquotedScalar(scalar)) {
        try out.appendSlice(allocator, line);
        return;
    }

    try out.appendSlice(allocator, line[0..value_start]);
    try out.appendSlice(allocator, unquoted_scalar_placeholder);
    try out.appendSlice(allocator, line[value_start..]);
}

fn findInlineCommentStart(value: []const u8) ?usize {
    for (value, 0..) |char, index| {
        if (char == '#' and (index == 0 or value[index - 1] == ' ' or value[index - 1] == '\t')) {
            return index;
        }
    }
    return null;
}

fn shouldMarkOriginallyUnquotedScalar(value: []const u8) bool {
    if (value.len == 0) return false;

    switch (value[0]) {
        '"', '\'', '|', '>', '[', '{', '&', '*', '!' => return false,
        else => {},
    }

    return isNullScalar(value) or parseBoolScalar(value) != null or isJsonNumber(value);
}

fn writeJsonValue(allocator: std.mem.Allocator, writer: *std.Io.Writer, value: YamlValue, current_key: ?[]const u8) !void {
    switch (value) {
        .empty => try writer.writeAll("null"),
        .boolean => |boolean| try writer.writeAll(if (boolean) "true" else "false"),
        .scalar => |scalar| try writeJsonScalar(writer, scalar, current_key),
        .list => |list| {
            try writer.writeByte('[');
            for (list, 0..) |item, index| {
                if (index != 0) try writer.writeByte(',');
                try writeJsonValue(allocator, writer, item, null);
            }
            try writer.writeByte(']');
        },
        .map => |map| {
            try writer.writeByte('{');
            for (map.keys(), map.values(), 0..) |raw_key, item, index| {
                if (index != 0) try writer.writeByte(',');

                const key = try normalizeYamlKey(allocator, raw_key);
                defer allocator.free(key);

                try std.json.Stringify.value(key, .{}, writer);
                try writer.writeByte(':');
                try writeJsonValue(allocator, writer, item, key);
            }
            try writer.writeByte('}');
        },
    }
}

fn writeJsonScalar(writer: *std.Io.Writer, scalar: []const u8, current_key: ?[]const u8) !void {
    const scalar_info = stripOriginallyUnquotedScalarMarker(scalar);
    const trimmed = std.mem.trim(u8, scalar_info.value, " \t\r\n");

    if (scalar_info.originally_unquoted) {
        if (isNullScalar(trimmed)) {
            try writer.writeAll("null");
            return;
        }

        if (parseBoolScalar(trimmed)) |boolean| {
            try writer.writeAll(if (boolean) "true" else "false");
            return;
        }

        if (current_key) |key| {
            if (isFloatSchemaKeyword(key) and isJsonNumber(trimmed)) {
                try writer.writeAll(trimmed);
                if (!hasFractionOrExponent(trimmed)) try writer.writeAll(".0");
                return;
            }
            if (isIntegerSchemaKeyword(key) and isJsonNumber(trimmed)) {
                try writer.writeAll(trimmed);
                return;
            }
        }
    }

    try std.json.Stringify.value(scalar_info.value, .{}, writer);
}

fn stripOriginallyUnquotedScalarMarker(value: []const u8) struct { value: []const u8, originally_unquoted: bool } {
    if (std.mem.startsWith(u8, value, unquoted_scalar_placeholder)) {
        return .{
            .value = value[unquoted_scalar_placeholder.len..],
            .originally_unquoted = true,
        };
    }

    return .{
        .value = value,
        .originally_unquoted = false,
    };
}

fn normalizeYamlKey(allocator: std.mem.Allocator, raw_key: []const u8) ![]const u8 {
    const trimmed = std.mem.trim(u8, raw_key, " \t\r\n");
    const unquoted = if (trimmed.len >= 2 and trimmed[0] == '\'' and trimmed[trimmed.len - 1] == '\'')
        try unescapeSingleQuoted(allocator, trimmed[1 .. trimmed.len - 1])
    else if (trimmed.len >= 2 and trimmed[0] == '"' and trimmed[trimmed.len - 1] == '"')
        try unescapeDoubleQuoted(allocator, trimmed[1 .. trimmed.len - 1])
    else
        try allocator.dupe(u8, trimmed);
    defer allocator.free(unquoted);

    return try replaceKeyPlaceholders(allocator, unquoted);
}

fn replaceKeyPlaceholders(allocator: std.mem.Allocator, key: []const u8) ![]const u8 {
    const with_lbraces = try std.mem.replaceOwned(u8, allocator, key, lbrace_placeholder, "{");
    defer allocator.free(with_lbraces);
    return try std.mem.replaceOwned(u8, allocator, with_lbraces, rbrace_placeholder, "}");
}

fn unescapeSingleQuoted(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    var index: usize = 0;
    while (index < value.len) : (index += 1) {
        if (value[index] == '\'' and index + 1 < value.len and value[index + 1] == '\'') {
            try out.append(allocator, '\'');
            index += 1;
            continue;
        }
        try out.append(allocator, value[index]);
    }

    return try out.toOwnedSlice(allocator);
}

fn unescapeDoubleQuoted(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    var index: usize = 0;
    while (index < value.len) : (index += 1) {
        if (value[index] != '\\' or index + 1 >= value.len) {
            try out.append(allocator, value[index]);
            continue;
        }

        index += 1;
        const escaped = switch (value[index]) {
            '0' => 0,
            'a' => 0x07,
            'b' => 0x08,
            't', '\t' => 0x09,
            'n' => '\n',
            'v' => 0x0b,
            'f' => 0x0c,
            'r' => '\r',
            'e' => 0x1b,
            '"', '/', '\\' => value[index],
            else => value[index],
        };
        try out.append(allocator, escaped);
    }

    return try out.toOwnedSlice(allocator);
}

fn isNullScalar(value: []const u8) bool {
    return std.mem.eql(u8, value, "~") or std.ascii.eqlIgnoreCase(value, "null");
}

fn parseBoolScalar(value: []const u8) ?bool {
    if (std.ascii.eqlIgnoreCase(value, "true")) return true;
    if (std.ascii.eqlIgnoreCase(value, "false")) return false;
    return null;
}

fn isFloatSchemaKeyword(key: []const u8) bool {
    return std.mem.eql(u8, key, "multipleOf") or
        std.mem.eql(u8, key, "maximum") or
        std.mem.eql(u8, key, "minimum");
}

fn isIntegerSchemaKeyword(key: []const u8) bool {
    return std.mem.eql(u8, key, "maxLength") or
        std.mem.eql(u8, key, "minLength") or
        std.mem.eql(u8, key, "maxItems") or
        std.mem.eql(u8, key, "minItems") or
        std.mem.eql(u8, key, "maxProperties") or
        std.mem.eql(u8, key, "minProperties");
}

fn hasFractionOrExponent(value: []const u8) bool {
    return std.mem.indexOfAny(u8, value, ".eE") != null;
}

fn isJsonNumber(value: []const u8) bool {
    if (value.len == 0) return false;

    var index: usize = 0;
    if (value[index] == '-') {
        index += 1;
        if (index == value.len) return false;
    }

    if (value[index] == '0') {
        index += 1;
    } else if (std.ascii.isDigit(value[index])) {
        while (index < value.len and std.ascii.isDigit(value[index])) : (index += 1) {}
    } else {
        return false;
    }

    if (index < value.len and value[index] == '.') {
        index += 1;
        if (index == value.len or !std.ascii.isDigit(value[index])) return false;
        while (index < value.len and std.ascii.isDigit(value[index])) : (index += 1) {}
    }

    if (index < value.len and (value[index] == 'e' or value[index] == 'E')) {
        index += 1;
        if (index < value.len and (value[index] == '+' or value[index] == '-')) index += 1;
        if (index == value.len or !std.ascii.isDigit(value[index])) return false;
        while (index < value.len and std.ascii.isDigit(value[index])) : (index += 1) {}
    }

    return index == value.len;
}
