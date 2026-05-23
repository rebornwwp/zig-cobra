//! Tests for flag_groups. Maps from cobra/flag_groups_test.go
const std = @import("std");
const Command = @import("command.zig").Command;
const flag_groups = @import("flag_groups.zig");
const gpa = std.testing.allocator;

test "validateFlagGroups with no flags returns ok" {
    var cmd = Command{ .use = "test" };
    try flag_groups.validateFlagGroups(&cmd);
}

test "markFlagsRequiredTogether does not crash" {
    var cmd = Command{ .use = "test" };
    flag_groups.markFlagsRequiredTogether(&cmd, &.{});
}

test "markFlagsOneRequired does not crash" {
    var cmd = Command{ .use = "test" };
    flag_groups.markFlagsOneRequired(&cmd, &.{});
}

test "markFlagsMutuallyExclusive does not crash" {
    var cmd = Command{ .use = "test" };
    flag_groups.markFlagsMutuallyExclusive(&cmd, &.{});
}
