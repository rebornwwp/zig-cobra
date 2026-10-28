//! Tests for flag_groups. Maps from cobra/flag_groups_test.go
const std = @import("std");
const command_mod = @import("command.zig");
const Command = command_mod.Command;
const pflag = command_mod.pflag;
const flag_groups = @import("flag_groups.zig");
const TestHelper = @import("test_helper.zig");
const gpa = std.testing.allocator;

const emptyRun = TestHelper.emptyRun;

fn setupGroupCmd(fs: *pflag.FlagSet) Command {
    return .{
        .use = "test",
        .run = emptyRun,
        .flags_ptr = fs,
        .silence_errors = true,
        .silence_usage = true,
    };
}

test "validateFlagGroups with no flags returns ok" {
    var cmd = Command{ .use = "test" };
    defer cmd.deinit(gpa);
    try flag_groups.validateFlagGroups(&cmd);
}

test "markFlagsRequiredTogether errors on unknown flag" {
    var cmd = Command{ .use = "test" };
    defer cmd.deinit(gpa);
    try std.testing.expectError(error.NoSuchFlag, flag_groups.markFlagsRequiredTogether(&cmd, gpa, &.{ "a", "b" }));
}

test "required together: partial set violates" {
    var fs = pflag.FlagSet.init(gpa, "t");
    defer fs.deinit();
    var alpha: bool = false;
    var beta: []const u8 = "";
    try fs.boolVar(&alpha, "alpha", false, "alpha flag");
    try fs.stringVar(&beta, "beta", "", "beta flag");

    var cmd = setupGroupCmd(&fs);
    defer cmd.deinit(gpa);
    try flag_groups.markFlagsRequiredTogether(&cmd, gpa, &.{ "alpha", "beta" });

    const out = try TestHelper.executeCommand(gpa, &cmd, &.{"--alpha"});
    try std.testing.expectEqual(error.FlagGroupViolation, out.err.?);
    TestHelper.checkStringContains(cmd.err_msg_buf[0..cmd.err_msg_len], "must all be set");
}

test "required together: both set passes" {
    var fs = pflag.FlagSet.init(gpa, "t");
    defer fs.deinit();
    var alpha: bool = false;
    var beta: []const u8 = "";
    try fs.boolVar(&alpha, "alpha", false, "alpha flag");
    try fs.stringVar(&beta, "beta", "", "beta flag");

    var cmd = setupGroupCmd(&fs);
    defer cmd.deinit(gpa);
    try flag_groups.markFlagsRequiredTogether(&cmd, gpa, &.{ "alpha", "beta" });

    const out = try TestHelper.executeCommand(gpa, &cmd, &.{ "--alpha", "--beta=x" });
    try std.testing.expect(out.err == null);
}

test "one required: none set violates" {
    var fs = pflag.FlagSet.init(gpa, "t");
    defer fs.deinit();
    var alpha: bool = false;
    var beta: bool = false;
    try fs.boolVar(&alpha, "alpha", false, "alpha flag");
    try fs.boolVar(&beta, "beta", false, "beta flag");

    var cmd = setupGroupCmd(&fs);
    defer cmd.deinit(gpa);
    try flag_groups.markFlagsOneRequired(&cmd, gpa, &.{ "alpha", "beta" });

    const out = try TestHelper.executeCommand(gpa, &cmd, &.{});
    try std.testing.expectEqual(error.FlagGroupViolation, out.err.?);
    TestHelper.checkStringContains(cmd.err_msg_buf[0..cmd.err_msg_len], "at least one of the flags");
}

test "mutually exclusive: both set violates" {
    var fs = pflag.FlagSet.init(gpa, "t");
    defer fs.deinit();
    var alpha: bool = false;
    var beta: bool = false;
    try fs.boolVar(&alpha, "alpha", false, "alpha flag");
    try fs.boolVar(&beta, "beta", false, "beta flag");

    var cmd = setupGroupCmd(&fs);
    defer cmd.deinit(gpa);
    try flag_groups.markFlagsMutuallyExclusive(&cmd, gpa, &.{ "alpha", "beta" });

    const out = try TestHelper.executeCommand(gpa, &cmd, &.{ "--alpha", "--beta" });
    try std.testing.expectEqual(error.FlagGroupViolation, out.err.?);
    TestHelper.checkStringContains(cmd.err_msg_buf[0..cmd.err_msg_len], "none of the others can be");
}
