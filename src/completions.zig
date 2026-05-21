//! Shell completion types and logic. Maps from cobra/completions.go
const std = @import("std");
const Command = @import("command.zig").Command;

pub const Completion = []const u8;
/// Named result type for CompletionFunc to ensure type consistency across files.
pub const CompResult = struct { completions: []Completion, directive: ShellCompDirective };
pub const CompletionFunc = *const fn (cmd: *Command, args: [][]const u8, to_complete: []const u8) anyerror!CompResult;

pub const CompletionOptions = struct {
    disable_default_cmd: bool = false,
    disable_no_desc_flag: bool = false,
    disable_descriptions: bool = false,
    hidden_default_cmd: bool = false,
    default_shell_comp_directive: ?ShellCompDirective = null,
};

pub const ShellCompDirective = packed struct(u8) {
    e: bool = false, nospace: bool = false, nofilecomp: bool = false,
    filterfile: bool = false, filterdirs: bool = false, keeporder: bool = false,
    _: u2 = 0,
    pub const error_flag = ShellCompDirective{ .e = true };
    pub const no_space = ShellCompDirective{ .nospace = true };
    pub const no_file_comp = ShellCompDirective{ .nofilecomp = true };
    pub const filter_file_ext = ShellCompDirective{ .filterfile = true };
    pub const filter_dirs = ShellCompDirective{ .filterdirs = true };
    pub const keep_order = ShellCompDirective{ .keeporder = true };
    pub const default = ShellCompDirective{};
};

pub fn completionWithDesc(choice: []const u8, _: []const u8) Completion { return choice; }

pub fn noFileCompletions(_: *Command, _: [][]const u8, _: []const u8) anyerror!CompResult {
    return CompResult{ .completions = &.{}, .directive = .no_file_comp };
}

pub fn fixedCompletions(choices: []const Completion, directive: ShellCompDirective) CompletionFunc {
    _ = choices; _ = directive;
    return &fixedReturn;
}

fn fixedReturn(_: *Command, _: [][]const u8, _: []const u8) anyerror!CompResult {
    return CompResult{ .completions = &.{}, .directive = .no_file_comp };
}

pub const shell_comp_request_cmd = "__complete";
pub const shell_comp_no_desc_request_cmd = "__completeNoDesc";

pub fn compDebug(_: []const u8, _: bool) void {}
pub fn compDebugln(_: []const u8, _: bool) void {}
pub fn compError(_: []const u8) void {}
pub fn compErrorln(_: []const u8) void {}
