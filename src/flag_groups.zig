//! Flag group validation. Maps from cobra/flag_groups.go
//!
//! Groups are stored as flag annotations (Go parity), which lets a group be
//! declared on flags from different flagsets (local, persistent, inherited).
//! The actual logic lives on Command; these free functions mirror the old API
//! shape and simply delegate.
const std = @import("std");
const Command = @import("command.zig").Command;

/// Mark a group of flags as required together. E.g., --username and --password
/// must both be provided or neither (Go: MarkFlagsRequiredTogether).
pub fn markFlagsRequiredTogether(self: *Command, gpa: std.mem.Allocator, flag_names: []const []const u8) anyerror!void {
    return self.markFlagsRequiredTogether(gpa, flag_names);
}

/// Mark that at least one flag from the group must be provided
/// (Go: MarkFlagsOneRequired).
pub fn markFlagsOneRequired(self: *Command, gpa: std.mem.Allocator, flag_names: []const []const u8) anyerror!void {
    return self.markFlagsOneRequired(gpa, flag_names);
}

/// Mark a group of flags as mutually exclusive. E.g., --verbose and --quiet
/// cannot be used together (Go: MarkFlagsMutuallyExclusive).
pub fn markFlagsMutuallyExclusive(self: *Command, gpa: std.mem.Allocator, flag_names: []const []const u8) anyerror!void {
    return self.markFlagsMutuallyExclusive(gpa, flag_names);
}

/// Validate all registered flag group constraints (Go: ValidateFlagGroups).
pub fn validateFlagGroups(self: *Command) anyerror!void {
    return self.validateFlagGroups();
}

/// Enforce flag group constraints during shell completion
/// (Go: enforceFlagGroupsForCompletion).
pub fn enforceFlagGroupsForCompletion(self: *Command) void {
    self.enforceFlagGroupsForCompletion();
}
