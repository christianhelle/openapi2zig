const std = @import("std");
const version_info = @import("build_info");
const ident = @import("generators/unified/ident_utils.zig");

const usage = @import("cli/usage.zig");
pub const printUsage = usage.printUsage;
pub const printError = usage.printError;
const types = @import("cli/types.zig");
pub const ResourceWrapperMode = types.ResourceWrapperMode;
pub const MultipleClientsMode = types.MultipleClientsMode;
pub const FileKind = types.FileKind;
pub const FileNameOverrides = types.FileNameOverrides;
pub const CliArgs = types.CliArgs;
pub const ParsedArgs = types.ParsedArgs;
const file_names_mod = @import("cli/file_names.zig");
pub const max_import_alias_len = file_names_mod.max_import_alias_len;
pub const findDuplicateFileName = file_names_mod.findDuplicateFileName;
pub const fileNamesCollide = file_names_mod.fileNamesCollide;
pub const deriveAliasInto = file_names_mod.deriveAliasInto;
pub const deriveAlias = file_names_mod.deriveAlias;
pub const importBasename = file_names_mod.importBasename;
pub const importDirname = file_names_mod.importDirname;
pub const resolveRuntimeModulePath = file_names_mod.resolveRuntimeModulePath;
pub const effectiveAliasesInto = file_names_mod.effectiveAliasesInto;
pub const findDuplicateAlias = file_names_mod.findDuplicateAlias;
pub const findReservedAlias = file_names_mod.findReservedAlias;
pub const validateFileName = file_names_mod.validateFileName;
pub const isAbsoluteImportPath = file_names_mod.isAbsoluteImportPath;
pub const validateImportPath = file_names_mod.validateImportPath;

const parse_mod = @import("cli/parse.zig");
pub const parse = parse_mod.parse;
pub const parseResourceWrapperMode = parse_mod.parseResourceWrapperMode;
pub const parseMultipleClientsMode = parse_mod.parseMultipleClientsMode;

test {
    _ = @import("cli/tests.zig");
}
