//! Flag group validation. Maps from cobra/flag_groups.go
const std = @import("std");
const Command = @import("command.zig").Command;

pub fn markFlagsRequiredTogether(self: *Command, flag_names: []const []const u8) void {
    _ = self; _ = flag_names;
}
pub fn markFlagsOneRequired(self: *Command, flag_names: []const []const u8) void {
    _ = self; _ = flag_names;
}
pub fn markFlagsMutuallyExclusive(self: *Command, flag_names: []const []const u8) void {
    _ = self; _ = flag_names;
}
pub fn validateFlagGroups(self: *Command) anyerror!void { _ = self; }
pub fn enforceFlagGroupsForCompletion(self: *Command) void { _ = self; }
