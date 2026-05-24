//! ActiveHelp support. Maps from cobra/active_help.go
//!
//! ActiveHelp enables dynamic help text display during shell completions,
//! guiding users through interactive workflows.
const std = @import("std");
const Completion = @import("completions.zig").Completion;

/// Append an ActiveHelp entry to the end of a completion array.
/// Returns a newly allocated owned slice; caller is responsible for cleanup.
/// The active_help_str is displayed to the user with an "_activeHelp_ " prefix.
pub fn appendActiveHelp(gpa: std.mem.Allocator, comp_array: []Completion, active_help_str: []const u8) ![]Completion {
    var result = std.ArrayList(Completion).initCapacity(gpa, comp_array.len + 1) catch unreachable;
    defer result.deinit(gpa);
    try result.appendSlice(gpa, comp_array);
    var buf = std.ArrayList(u8).initCapacity(gpa, 256) catch unreachable;
    defer buf.deinit(gpa);
    try buf.appendSlice(gpa, "_activeHelp_ ");
    try buf.appendSlice(gpa, active_help_str);
    try result.append(gpa, try buf.toOwnedSlice(gpa));
    return try result.toOwnedSlice(gpa);
}

/// Get the ActiveHelp configuration. Currently returns empty string (stub, to be implemented).
pub fn getActiveHelpConfig(_: *const anyopaque, _: std.mem.Allocator) ![]const u8 {
    return "";
}
