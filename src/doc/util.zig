//! Doc utilities. Maps from doc/util.go
const std = @import("std");
const Command = @import("../command.zig").Command;

pub fn hasSeeAlso(cmd: *Command) bool {
    if (cmd.hasParent()) return true;
    for (cmd.commands.items) |c| {
        if (!c.isAvailableCommand() and !c.isAdditionalHelpTopicCommand()) continue;
        return true;
    }
    return false;
}

pub fn forceMultiLine(gpa: std.mem.Allocator, s: []const u8) ![]const u8 {
    if (s.len > 60 and std.mem.indexOfScalar(u8, s, '\n') == null) {
        const result = try gpa.alloc(u8, s.len + 1);
        @memcpy(result[0..s.len], s);
        result[s.len] = '\n';
        return result;
    }
    return s;
}

pub fn lessThanByName(_: void, a: *Command, b: *Command) bool {
    return std.ascii.lessThanIgnoreCase(a.name(), b.name());
}
