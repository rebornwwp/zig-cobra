//! Shell completion types and logic. Maps from cobra/completions.go
const std = @import("std");
const Command = @import("command.zig").Command;

/// A single completion item (string slice).
pub const Completion = []const u8;
/// Return type for CompletionFunc: completion list + directive.
pub const CompResult = struct { completions: []Completion, directive: ShellCompDirective };
/// Completion function signature: (cmd, args, to_complete) -> CompResult
pub const CompletionFunc = *const fn (cmd: *Command, args: [][]const u8, to_complete: []const u8) anyerror!CompResult;

/// Configuration for shell completion behavior.
pub const CompletionOptions = struct {
    /// Disable default subcommand completions
    disable_default_cmd: bool = false,
    /// Disable completions for flags without descriptions
    disable_no_desc_flag: bool = false,
    /// Hide descriptions in completion results
    disable_descriptions: bool = false,
    /// Hide the default subcommand from completion output
    hidden_default_cmd: bool = false,
    /// Default ShellCompDirective (null means use zero directive)
    default_shell_comp_directive: ?ShellCompDirective = null,
};

/// Shell completion directive: controls the shell's behavior after a completion.
pub const ShellCompDirective = packed struct(u8) {
    e: bool = false,
    /// Do not append a space after the completion
    nospace: bool = false,
    /// Disable file completion fallback
    nofilecomp: bool = false,
    /// Filter completions by file extension
    filterfile: bool = false,
    /// Filter to directories only
    filterdirs: bool = false,
    /// Preserve the order of provided completions (don't sort)
    keeporder: bool = false,
    _: u2 = 0,
    /// Indicates a completion error occurred
    pub const error_flag = ShellCompDirective{ .e = true };
    /// Do not append a space after completion
    pub const no_space = ShellCompDirective{ .nospace = true };
    /// Do not fall back to file completion
    pub const no_file_comp = ShellCompDirective{ .nofilecomp = true };
    /// Filter results by file extension
    pub const filter_file_ext = ShellCompDirective{ .filterfile = true };
    /// Return only directories
    pub const filter_dirs = ShellCompDirective{ .filterdirs = true };
    /// Preserve provider order, do not sort
    pub const keep_order = ShellCompDirective{ .keeporder = true };
    /// Default directive (no special behavior)
    pub const default = ShellCompDirective{};
};

/// Create a completion entry with a description. Currently returns only choice (description param reserved).
pub fn completionWithDesc(choice: []const u8, _: []const u8) Completion {
    return choice;
}

/// Return a completion function that provides empty completions with no-file-comp directive.
pub fn noFileCompletions(_: *Command, _: [][]const u8, _: []const u8) anyerror!CompResult {
    return CompResult{ .completions = &.{}, .directive = .no_file_comp };
}

/// Create a completion function with a fixed list of choices and directive.
pub fn fixedCompletions(choices: []const Completion, directive: ShellCompDirective) CompletionFunc {
    _ = choices;
    _ = directive;
    return &fixedReturn;
}

fn fixedReturn(_: *Command, _: [][]const u8, _: []const u8) anyerror!CompResult {
    return CompResult{ .completions = &.{}, .directive = .no_file_comp };
}

/// Command name used by the shell to request completions
pub const shell_comp_request_cmd = "__complete";
/// Command name used by the shell to request completions without descriptions
pub const shell_comp_no_desc_request_cmd = "__completeNoDesc";

/// Completion debug output (stub)
pub fn compDebug(_: []const u8, _: bool) void {}
/// Completion debug output with newline (stub)
pub fn compDebugln(_: []const u8, _: bool) void {}
/// Completion error output (stub)
pub fn compError(_: []const u8) void {}
/// Completion error output with newline (stub)
pub fn compErrorln(_: []const u8) void {}
