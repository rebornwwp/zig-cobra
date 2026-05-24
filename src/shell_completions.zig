//! Shell completion flag marking. Maps from cobra/shell_completions.go
//!
//! Utility functions for annotating flags with completion semantics:
//! required flags, filename completion, directory completion, etc.
const std = @import("std");
const Command = @import("command.zig").Command;

/// Mark a flag as required.
pub fn markFlagRequired(self: *Command, name: []const u8) anyerror!void {
    _ = self;
    _ = name;
}
/// Mark a persistent flag as required (applies to all subcommands).
pub fn markPersistentFlagRequired(self: *Command, name: []const u8) anyerror!void {
    _ = self;
    _ = name;
}
/// Mark a flag's value as a filename, optionally restricted to specific extensions.
pub fn markFlagFilename(self: *Command, name: []const u8, extensions: []const []const u8) anyerror!void {
    _ = self;
    _ = name;
    _ = extensions;
}
/// Mark a flag with custom completion behavior.
pub fn markFlagCustom(self: *Command, name: []const u8, f: []const u8) anyerror!void {
    _ = self;
    _ = name;
    _ = f;
}
/// Mark a persistent flag's value as a filename.
pub fn markPersistentFlagFilename(self: *Command, name: []const u8, extensions: []const []const u8) anyerror!void {
    _ = self;
    _ = name;
    _ = extensions;
}
/// Mark a flag's value as a directory name.
pub fn markFlagDirname(self: *Command, name: []const u8) anyerror!void {
    _ = self;
    _ = name;
}
/// Mark a persistent flag's value as a directory name.
pub fn markPersistentFlagDirname(self: *Command, name: []const u8) anyerror!void {
    _ = self;
    _ = name;
}
