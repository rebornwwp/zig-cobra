//! Tests for active_help. Maps from cobra/active_help_test.go
const std = @import("std");
const Command = @import("command.zig").Command;
const active_help = @import("active_help.zig");
const TestHelper = @import("test_helper.zig");
const Completion = @import("completions.zig").Completion;
const gpa = std.testing.allocator;

test "appendActiveHelp adds marker" {
    var comps = [2]Completion{ "option1", "option2" };
    const result = try active_help.appendActiveHelp(gpa, &comps, "help text");
    defer gpa.free(result);
    try std.testing.expect(result.len == 3);
    try std.testing.expectEqualStrings("option1", result[0]);
    try std.testing.expectEqualStrings("option2", result[1]);
    try std.testing.expect(std.mem.indexOf(u8, result[2], "_activeHelp_") != null);
}

test "appendActiveHelp with empty comps" {
    var comps: [0]Completion = .{};
    const result = try active_help.appendActiveHelp(gpa, &comps, "help");
    defer gpa.free(result);
    try std.testing.expect(result.len == 1);
}

test "getActiveHelpConfig returns empty" {
    var cmd = TestHelper.makeCommand("test", TestHelper.emptyRun);
    const config = try active_help.getActiveHelpConfig(&cmd, gpa);
    try std.testing.expectEqualStrings("", config);
}