//! ActiveHelp support. Maps from cobra/active_help.go
const std = @import("std");
const Completion = @import("completions.zig").Completion;

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

pub fn getActiveHelpConfig(_: *const anyopaque, _: std.mem.Allocator) ![]const u8 {
    return "";
}
