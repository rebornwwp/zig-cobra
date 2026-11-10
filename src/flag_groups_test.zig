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
        .silence_errors = false, // keep error output so violations can be asserted on captured output
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
    try TestHelper.checkStringContains(out.output, "must all be set");
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
    try TestHelper.checkStringContains(out.output, "at least one of the flags");
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
    try TestHelper.checkStringContains(out.output, "none of the others can be");
}

// Additional combination tests from Go's table-driven testcases

test "no flags no problem" {
    var fs = pflag.FlagSet.init(gpa, "t");
    defer fs.deinit();
    var a: []const u8 = "";
    var b: []const u8 = "";
    try fs.stringVar(&a, "a", "", "");
    try fs.stringVar(&b, "b", "", "");

    var cmd = setupGroupCmd(&fs);
    defer cmd.deinit(gpa);
    try flag_groups.markFlagsRequiredTogether(&cmd, gpa, &.{ "a", "b" });
    try flag_groups.markFlagsMutuallyExclusive(&cmd, gpa, &.{ "a", "b" });

    const out = try TestHelper.executeCommand(gpa, &cmd, &.{});
    try std.testing.expect(out.err == null);
}

test "required together: error message format" {
    var fs = pflag.FlagSet.init(gpa, "t");
    defer fs.deinit();
    var a: []const u8 = "";
    var b: []const u8 = "";
    var c: []const u8 = "";
    try fs.stringVar(&a, "a", "", "");
    try fs.stringVar(&b, "b", "", "");
    try fs.stringVar(&c, "c", "", "");

    var cmd = setupGroupCmd(&fs);
    defer cmd.deinit(gpa);
    try flag_groups.markFlagsRequiredTogether(&cmd, gpa, &.{ "a", "b", "c" });

    const out = try TestHelper.executeCommand(gpa, &cmd, &.{"--a=foo"});
    try std.testing.expectEqual(error.FlagGroupViolation, out.err.?);
    try TestHelper.checkStringContains(out.output, "if any flags in the group [a b c] are set they must all be set; missing [b c]");
}

test "one required: error message format" {
    var fs = pflag.FlagSet.init(gpa, "t");
    defer fs.deinit();
    var a: []const u8 = "";
    var b: []const u8 = "";
    try fs.stringVar(&a, "a", "", "");
    try fs.stringVar(&b, "b", "", "");

    var cmd = setupGroupCmd(&fs);
    defer cmd.deinit(gpa);
    try flag_groups.markFlagsOneRequired(&cmd, gpa, &.{ "a", "b" });

    const out = try TestHelper.executeCommand(gpa, &cmd, &.{});
    try std.testing.expectEqual(error.FlagGroupViolation, out.err.?);
    try TestHelper.checkStringContains(out.output, "at least one of the flags in the group [a b] is required");
}

test "mutually exclusive: error message format" {
    var fs = pflag.FlagSet.init(gpa, "t");
    defer fs.deinit();
    var a: []const u8 = "";
    var b: []const u8 = "";
    var c: []const u8 = "";
    try fs.stringVar(&a, "a", "", "");
    try fs.stringVar(&b, "b", "", "");
    try fs.stringVar(&c, "c", "", "");

    var cmd = setupGroupCmd(&fs);
    defer cmd.deinit(gpa);
    try flag_groups.markFlagsMutuallyExclusive(&cmd, gpa, &.{ "a", "b", "c" });

    const out = try TestHelper.executeCommand(gpa, &cmd, &.{ "--a=foo", "--b=foo" });
    try std.testing.expectEqual(error.FlagGroupViolation, out.err.?);
    try TestHelper.checkStringContains(out.output, "if any flags in the group [a b c] are set none of the others can be; [a b] were all set");
}

test "mutually exclusive: none set passes" {
    var fs = pflag.FlagSet.init(gpa, "t");
    defer fs.deinit();
    var a: bool = false;
    var b: bool = false;
    try fs.boolVar(&a, "alpha", false, "alpha flag");
    try fs.boolVar(&b, "beta", false, "beta flag");

    var cmd = setupGroupCmd(&fs);
    defer cmd.deinit(gpa);
    try flag_groups.markFlagsMutuallyExclusive(&cmd, gpa, &.{ "alpha", "beta" });

    const out = try TestHelper.executeCommand(gpa, &cmd, &.{});
    try std.testing.expect(out.err == null);
}

test "mutually exclusive: one set passes" {
    var fs = pflag.FlagSet.init(gpa, "t");
    defer fs.deinit();
    var a: bool = false;
    var b: bool = false;
    try fs.boolVar(&a, "alpha", false, "alpha flag");
    try fs.boolVar(&b, "beta", false, "beta flag");

    var cmd = setupGroupCmd(&fs);
    defer cmd.deinit(gpa);
    try flag_groups.markFlagsMutuallyExclusive(&cmd, gpa, &.{ "alpha", "beta" });

    const out = try TestHelper.executeCommand(gpa, &cmd, &.{"--alpha"});
    try std.testing.expect(out.err == null);
}

test "required together: none set passes" {
    var fs = pflag.FlagSet.init(gpa, "t");
    defer fs.deinit();
    var a: bool = false;
    var b: bool = false;
    try fs.boolVar(&a, "alpha", false, "alpha flag");
    try fs.boolVar(&b, "beta", false, "beta flag");

    var cmd = setupGroupCmd(&fs);
    defer cmd.deinit(gpa);
    try flag_groups.markFlagsRequiredTogether(&cmd, gpa, &.{ "alpha", "beta" });

    const out = try TestHelper.executeCommand(gpa, &cmd, &.{});
    try std.testing.expect(out.err == null);
}

test "one required: one set passes" {
    var fs = pflag.FlagSet.init(gpa, "t");
    defer fs.deinit();
    var a: bool = false;
    var b: bool = false;
    try fs.boolVar(&a, "alpha", false, "alpha flag");
    try fs.boolVar(&b, "beta", false, "beta flag");

    var cmd = setupGroupCmd(&fs);
    defer cmd.deinit(gpa);
    try flag_groups.markFlagsOneRequired(&cmd, gpa, &.{ "alpha", "beta" });

    const out = try TestHelper.executeCommand(gpa, &cmd, &.{"--alpha"});
    try std.testing.expect(out.err == null);
}

test "one required: both set passes" {
    var fs = pflag.FlagSet.init(gpa, "t");
    defer fs.deinit();
    var a: bool = false;
    var b: bool = false;
    try fs.boolVar(&a, "alpha", false, "alpha flag");
    try fs.boolVar(&b, "beta", false, "beta flag");

    var cmd = setupGroupCmd(&fs);
    defer cmd.deinit(gpa);
    try flag_groups.markFlagsOneRequired(&cmd, gpa, &.{ "alpha", "beta" });

    const out = try TestHelper.executeCommand(gpa, &cmd, &.{ "--alpha", "--beta" });
    try std.testing.expect(out.err == null);
}
