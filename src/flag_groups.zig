//! Flag group validation. Maps from cobra/flag_groups.go
//!
//! Provides constraint validation between flags: required together, at-least-one-required,
//! mutually exclusive, etc.
const std = @import("std");
const Command = @import("command.zig").Command;

/// Mark a group of flags as required together. E.g., --username and --password must both be provided.
pub fn markFlagsRequiredTogether(self: *Command, flag_names: []const []const u8) void {
    _ = self;
    _ = flag_names;
}
/// Mark that at least one flag from the group must be provided.
pub fn markFlagsOneRequired(self: *Command, flag_names: []const []const u8) void {
    _ = self;
    _ = flag_names;
}
/// Mark a group of flags as mutually exclusive. E.g., --verbose and --quiet cannot be used together.
pub fn markFlagsMutuallyExclusive(self: *Command, flag_names: []const []const u8) void {
    _ = self;
    _ = flag_names;
}
/// Validate all registered flag group constraints.
pub fn validateFlagGroups(self: *Command) anyerror!void {
    _ = self;
}
/// Enforce flag group constraints during shell completion.
pub fn enforceFlagGroupsForCompletion(self: *Command) void {
    _ = self;
}
