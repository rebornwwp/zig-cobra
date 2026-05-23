//! Shell completion flag marking. Maps from cobra/shell_completions.go
const std = @import("std");
const Command = @import("command.zig").Command;

pub fn markFlagRequired(self: *Command, name: []const u8) anyerror!void {
    _ = self;
    _ = name;
}
pub fn markPersistentFlagRequired(self: *Command, name: []const u8) anyerror!void {
    _ = self;
    _ = name;
}
pub fn markFlagFilename(self: *Command, name: []const u8, extensions: []const []const u8) anyerror!void {
    _ = self;
    _ = name;
    _ = extensions;
}
pub fn markFlagCustom(self: *Command, name: []const u8, f: []const u8) anyerror!void {
    _ = self;
    _ = name;
    _ = f;
}
pub fn markPersistentFlagFilename(self: *Command, name: []const u8, extensions: []const []const u8) anyerror!void {
    _ = self;
    _ = name;
    _ = extensions;
}
pub fn markFlagDirname(self: *Command, name: []const u8) anyerror!void {
    _ = self;
    _ = name;
}
pub fn markPersistentFlagDirname(self: *Command, name: []const u8) anyerror!void {
    _ = self;
    _ = name;
}
