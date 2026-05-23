//! Tests for args validators. Maps from cobra/args_test.go
const std = @import("std");
const Command = @import("command.zig").Command;
const args_mod = @import("args.zig");
const TestHelper = @import("test_helper.zig");

fn getCommand(args_validator: args_mod.PositionalArgs, with_valid: bool) !Command {
    var cmd = Command{
        .use = "c",
        .args_validator = args_validator,
        .run = TestHelper.emptyRun,
    };
    if (with_valid) {
        cmd.valid_args = &.{ "one", "two", "three" };
    }
    return cmd;
}

test "NoArgs - success with no args" {
    var cmd = try getCommand(args_mod.noArgs(), false);
    const result = cmd.args_validator.?.validate(&cmd, &.{});
    try std.testing.expectEqual({}, result);
}

test "NoArgs - error with args" {
    var cmd = try getCommand(args_mod.noArgs(), false);
    const result = cmd.args_validator.?.validate(&cmd, &.{"extra"}) catch |err| err;
    try std.testing.expectEqual(error.UnknownCommand, result);
}

test "ArbitraryArgs - always succeeds" {
    var cmd = try getCommand(args_mod.arbitraryArgs(), false);
    const result = cmd.args_validator.?.validate(&cmd, &.{ "a", "b", "c" });
    try std.testing.expectEqual({}, result);
}

test "ExactArgs - correct count succeeds" {
    var cmd = try getCommand(args_mod.exactArgs(2), false);
    const result = cmd.args_validator.?.validate(&cmd, &.{ "one", "two" });
    try std.testing.expectEqual({}, result);
}

test "ExactArgs - wrong count errors" {
    var cmd = try getCommand(args_mod.exactArgs(2), false);
    const result = cmd.args_validator.?.validate(&cmd, &.{"one"}) catch |err| err;
    try std.testing.expectEqual(error.ArgsCount, result);
}

test "MinimumNArgs - enough args succeeds" {
    var cmd = try getCommand(args_mod.minimumNArgs(2), false);
    const result = cmd.args_validator.?.validate(&cmd, &.{ "a", "b", "c" });
    try std.testing.expectEqual({}, result);
}

test "MinimumNArgs - too few args errors" {
    var cmd = try getCommand(args_mod.minimumNArgs(2), false);
    const result = cmd.args_validator.?.validate(&cmd, &.{"one"}) catch |err| err;
    try std.testing.expectEqual(error.ArgsCount, result);
}

test "MaximumNArgs - within limit succeeds" {
    var cmd = try getCommand(args_mod.maximumNArgs(2), false);
    const result = cmd.args_validator.?.validate(&cmd, &.{ "a", "b" });
    try std.testing.expectEqual({}, result);
}

test "MaximumNArgs - exceed limit errors" {
    var cmd = try getCommand(args_mod.maximumNArgs(2), false);
    const result = cmd.args_validator.?.validate(&cmd, &.{ "a", "b", "c" }) catch |err| err;
    try std.testing.expectEqual(error.ArgsCount, result);
}

test "RangeArgs - within range succeeds" {
    var cmd = try getCommand(args_mod.rangeArgs(2, 4), false);
    const r1 = cmd.args_validator.?.validate(&cmd, &.{ "a", "b" });
    try std.testing.expectEqual({}, r1);
    const r2 = cmd.args_validator.?.validate(&cmd, &.{ "a", "b", "c", "d" });
    try std.testing.expectEqual({}, r2);
    const r3 = cmd.args_validator.?.validate(&cmd, &.{ "a", "b", "c" });
    try std.testing.expectEqual({}, r3);
}

test "RangeArgs - below range errors" {
    var cmd = try getCommand(args_mod.rangeArgs(2, 4), false);
    const result = cmd.args_validator.?.validate(&cmd, &.{"one"}) catch |err| err;
    try std.testing.expectEqual(error.ArgsCount, result);
}

test "RangeArgs - above range errors" {
    var cmd = try getCommand(args_mod.rangeArgs(2, 4), false);
    const result = cmd.args_validator.?.validate(&cmd, &.{ "a", "b", "c", "d", "e" }) catch |err| err;
    try std.testing.expectEqual(error.ArgsCount, result);
}

test "MatchAll - combines validators" {
    const validators = [_]args_mod.PositionalArgs{ args_mod.minimumNArgs(1), args_mod.maximumNArgs(3) };
    var cmd = try getCommand(args_mod.matchAll(&validators), false);
    const r1 = cmd.args_validator.?.validate(&cmd, &.{"x"});
    try std.testing.expectEqual({}, r1);
    const r2 = cmd.args_validator.?.validate(&cmd, &.{}) catch |err| err;
    try std.testing.expectEqual(error.ArgsCount, r2);
    const r3 = cmd.args_validator.?.validate(&cmd, &.{ "a", "b", "c", "d" }) catch |err| err;
    try std.testing.expectEqual(error.ArgsCount, r3);
}

test "noDuplicateArgs - no duplicates succeeds" {
    var cmd = try getCommand(args_mod.noDuplicateArgs(), false);
    const result = cmd.args_validator.?.validate(&cmd, &.{ "a", "b", "c" });
    try std.testing.expectEqual({}, result);
}

test "noDuplicateArgs - duplicate errors" {
    var cmd = try getCommand(args_mod.noDuplicateArgs(), false);
    const result = cmd.args_validator.?.validate(&cmd, &.{ "a", "b", "a" }) catch |err| err;
    try std.testing.expectEqual(error.DuplicateArg, result);
}

test "legacyArgs - no subcommands accepts any args" {
    var cmd = Command{ .use = "c", .args_validator = args_mod.legacyArgs(), .run = TestHelper.emptyRun };
    const result = cmd.args_validator.?.validate(&cmd, &.{"anything"});
    try std.testing.expectEqual({}, result);
}
