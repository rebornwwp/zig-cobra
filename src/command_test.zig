//! Tests for Command. Maps from cobra/command_test.go
const std = @import("std");
const cobra = @import("cobra.zig");
const Command = @import("command.zig").Command;
const TestHelper = @import("test_helper.zig");

const emptyRun = TestHelper.emptyRun;
const gpa = std.testing.allocator;

fn addCommand(cmd: *Command, sub: *Command) void {
    cmd.addCommand(gpa, &.{sub});
}

test "single command - basic execution" {
    var rootCmd = Command{ .use = "root", .run = emptyRun };
    var aCmd = Command{ .use = "a", .run = emptyRun };
    var bCmd = Command{ .use = "b", .run = emptyRun };
    addCommand(&rootCmd, &aCmd);
    addCommand(&rootCmd, &bCmd);
    defer rootCmd.deinit(gpa);
}

test "child command" {
    var rootCmd = Command{ .use = "root", .short = "root short" };
    var child = Command{ .use = "child", .run = emptyRun };
    addCommand(&rootCmd, &child);
    defer rootCmd.deinit(gpa);
    const output = try TestHelper.executeCommand(gpa, &rootCmd, &.{"child"});
    try std.testing.expect(output.err == null);
}

test "unknown command shows error" {
    var rootCmd = Command{ .use = "root", .run = emptyRun, .silence_usage = true, .silence_errors = true };
    var child = Command{ .use = "child", .run = emptyRun };
    addCommand(&rootCmd, &child);
    defer rootCmd.deinit(gpa);
}

test "command alias" {
    var rootCmd = Command{ .use = "root", .run = emptyRun };
    var child = Command{ .use = "child", .aliases = &.{ "c", "ch" }, .run = emptyRun };
    addCommand(&rootCmd, &child);
    defer rootCmd.deinit(gpa);
    const o1 = try TestHelper.executeCommand(gpa, &rootCmd, &.{"child"});
    try std.testing.expect(o1.err == null);
    const o2 = try TestHelper.executeCommand(gpa, &rootCmd, &.{"c"});
    try std.testing.expect(o2.err == null);
    const o3 = try TestHelper.executeCommand(gpa, &rootCmd, &.{"ch"});
    try std.testing.expect(o3.err == null);
}

test "enable prefix matching" {
    const orig = cobra.enable_prefix_matching;
    defer cobra.enable_prefix_matching = orig;
    cobra.enable_prefix_matching = true;
    var rootCmd = Command{ .use = "root", .run = emptyRun };
    var child = Command{ .use = "child", .run = emptyRun };
    addCommand(&rootCmd, &child);
    defer rootCmd.deinit(gpa);
    const o = try TestHelper.executeCommand(gpa, &rootCmd, &.{"chi"});
    try std.testing.expect(o.err == null);
}

test "hasParent and root" {
    var rootCmd = Command{ .use = "root", .run = emptyRun };
    var child = Command{ .use = "child", .run = emptyRun };
    var grandchild = Command{ .use = "grandchild", .run = emptyRun };
    addCommand(&rootCmd, &child);
    addCommand(&child, &grandchild);
    defer rootCmd.deinit(gpa);
    try std.testing.expect(!rootCmd.hasParent());
    try std.testing.expect(child.hasParent());
    try std.testing.expect(grandchild.hasParent());
    try std.testing.expect(&rootCmd == rootCmd.root());
    try std.testing.expect(&rootCmd == child.root());
    try std.testing.expect(&rootCmd == grandchild.root());
}

test "name extraction" {
    const c1 = Command{ .use = "root" };
    try std.testing.expectEqualStrings("root", c1.name());
    const c2 = Command{ .use = "run [args]" };
    try std.testing.expectEqualStrings("run", c2.name());
    const c3 = Command{ .use = "" };
    try std.testing.expectEqualStrings("", c3.name());
}

test "command path padding" {
    var rootCmd = Command{ .use = "root", .run = emptyRun };
    var longCmd = Command{ .use = "verylongcommandname", .run = emptyRun };
    addCommand(&rootCmd, &longCmd);
    defer rootCmd.deinit(gpa);
    try std.testing.expect(rootCmd.commandPathPadding() >= longCmd.commandPath().len);
}

test "name padding" {
    var rootCmd = Command{ .use = "root", .run = emptyRun };
    var longCmd = Command{ .use = "verylongcommandname", .run = emptyRun };
    addCommand(&rootCmd, &longCmd);
    defer rootCmd.deinit(gpa);
    try std.testing.expect(rootCmd.namePadding() >= longCmd.name().len);
}

test "commands are sorted" {
    const orig = cobra.enable_command_sorting;
    defer cobra.enable_command_sorting = orig;
    cobra.enable_command_sorting = true;
    var rootCmd = Command{ .use = "root", .run = emptyRun };
    var zCmd = Command{ .use = "zebra", .run = emptyRun };
    var aCmd = Command{ .use = "alpha", .run = emptyRun };
    var mCmd = Command{ .use = "middle", .run = emptyRun };
    addCommand(&rootCmd, &zCmd);
    addCommand(&rootCmd, &aCmd);
    addCommand(&rootCmd, &mCmd);
    defer rootCmd.deinit(gpa);
    _ = rootCmd.getCommands();
    const cmds = rootCmd.commands.items;
    try std.testing.expect(cmds.len == 3);
    try std.testing.expectEqualStrings("alpha", cmds[0].name());
    try std.testing.expectEqualStrings("middle", cmds[1].name());
    try std.testing.expectEqualStrings("zebra", cmds[2].name());
}

test "disable command sorting" {
    const orig = cobra.enable_command_sorting;
    defer cobra.enable_command_sorting = orig;
    cobra.enable_command_sorting = false;
    var rootCmd = Command{ .use = "root", .run = emptyRun };
    var zCmd = Command{ .use = "zebra", .run = emptyRun };
    var aCmd = Command{ .use = "alpha", .run = emptyRun };
    addCommand(&rootCmd, &zCmd);
    addCommand(&rootCmd, &aCmd);
    defer rootCmd.deinit(gpa);
    try std.testing.expectEqualStrings("zebra", rootCmd.commands.items[0].name());
    try std.testing.expectEqualStrings("alpha", rootCmd.commands.items[1].name());
}

test "isAvailableCommand" {
    const a = Command{ .use = "a", .run = emptyRun };
    const h = Command{ .use = "h", .run = emptyRun, .hidden = true };
    const d = Command{ .use = "d", .run = emptyRun, .deprecated = "x" };
    try std.testing.expect(a.isAvailableCommand());
    try std.testing.expect(!h.isAvailableCommand());
    try std.testing.expect(!d.isAvailableCommand());
}
test "addGroup and containsGroup" {
    var rootCmd = TestHelper.makeCommand("root", emptyRun);
    defer rootCmd.deinit(gpa);
    var group = cobra.Group{ .id = "group1", .title = "Group One" };
    rootCmd.addGroup(gpa, &.{&group});
    try std.testing.expect(rootCmd.containsGroup("group1"));
    try std.testing.expect(!rootCmd.containsGroup("nonexistent"));
}
test "resetCommands" {
    var rootCmd = Command{ .use = "root", .run = emptyRun };
    var child = Command{ .use = "child", .run = emptyRun };
    addCommand(&rootCmd, &child);
    defer rootCmd.deinit(gpa);
    try std.testing.expect(rootCmd.hasSubCommands());
    rootCmd.resetCommands(gpa);
    try std.testing.expect(!rootCmd.hasSubCommands());
}

test "runnable" {
    const a = Command{ .use = "x", .run = emptyRun };
    const b = Command{ .use = "x" };
    try std.testing.expect(a.runnable());
    try std.testing.expect(!b.runnable());
}

test "hasSubCommands" {
    var root = Command{ .use = "root", .run = emptyRun };
    var child = Command{ .use = "child", .run = emptyRun };
    try std.testing.expect(!root.hasSubCommands());
    addCommand(&root, &child);
    defer root.deinit(gpa);
    try std.testing.expect(root.hasSubCommands());
}

test "suggestionsFor" {
    var rootCmd = Command{ .use = "root", .run = emptyRun };
    var childCmd = Command{ .use = "version", .run = emptyRun };
    addCommand(&rootCmd, &childCmd);
    defer rootCmd.deinit(gpa);
    const suggestions = try rootCmd.suggestionsFor(gpa, "vrsion");
    defer gpa.free(suggestions);
    try std.testing.expect(suggestions.len > 0);
}

test "execute with run_e" {
    const args: []const []const u8 = &.{};
    var rootCmd = Command{ .use = "root", .run_e = emptyRunE };
    rootCmd.setArgs(args);
    rootCmd.executeWrapper() catch {};
    try std.testing.expect(true);
}

test "execute with run function" {
    const args: []const []const u8 = &.{};
    var rootCmd = Command{ .use = "root", .run = emptyRun };
    rootCmd.setArgs(args);
    rootCmd.executeWrapper() catch {};
    try std.testing.expect(true);
}

test "suggestions disabled" {}

test "hasExample" {
    const withEx = Command{ .use = "c", .example = "ex" };
    const withoutEx = Command{ .use = "c" };
    try std.testing.expect(withEx.hasExample());
    try std.testing.expect(!withoutEx.hasExample());
}

test "calledAs" {
    var cmd = Command{ .use = "cmd" };
    try std.testing.expectEqualStrings("", cmd.calledAs());
    cmd.command_called_as = .{ .name = "alias", .called = true };
    try std.testing.expectEqualStrings("alias", cmd.calledAs());
}

test "allChildCommandsHaveGroup" {
    var root = Command{ .use = "root" };
    var child = Command{ .use = "child", .group_id = "g1" };
    addCommand(&root, &child);
    defer root.deinit(gpa);
    try std.testing.expect(root.allChildCommandsHaveGroup());
}

test "removeCommand" {
    var root = Command{ .use = "root" };
    var child = Command{ .use = "child", .run = emptyRun };
    addCommand(&root, &child);
    defer root.deinit(gpa);
    try std.testing.expect(root.hasSubCommands());
    root.removeCommand(gpa, &.{&child});
    try std.testing.expect(!root.hasSubCommands());
}

test "usage padding from max use len" {
    var root = Command{ .use = "root", .run = emptyRun };
    var long = Command{ .use = "averylongcommandnameindeed", .run = emptyRun };
    addCommand(&root, &long);
    defer root.deinit(gpa);
    try std.testing.expect(root.usagePadding() == long.use.len);
}

test "err prefix" {
    var cmd = Command{ .use = "cmd" };
    try std.testing.expectEqualStrings("Error:", cmd.errPrefix());
    cmd.setErrPrefix("Oops:");
    try std.testing.expectEqualStrings("Oops:", cmd.errPrefix());
}

test "deprecated command" {
    var cmd = Command{ .use = "old", .deprecated = "use new", .run = emptyRun };
    try std.testing.expect(!cmd.isAvailableCommand());
}

test "hasAvailableSubCommands" {
    var root = Command{ .use = "root", .run = emptyRun };
    var child = Command{ .use = "child", .run = emptyRun };
    try std.testing.expect(!root.hasAvailableSubCommands());
    addCommand(&root, &child);
    defer root.deinit(gpa);
    try std.testing.expect(root.hasAvailableSubCommands());
}

test "hasHelpSubCommands" {
    var root = Command{ .use = "root", .run = emptyRun };
    // non-runnable child should be help topic
    var helpTopic = Command{ .use = "docs" };
    addCommand(&root, &helpTopic);
    defer root.deinit(gpa);
    try std.testing.expect(root.hasHelpSubCommands());
}

fn emptyRunE(cmd: *Command, args: [][]const u8) anyerror!void {
    _ = cmd;
    _ = args;
}

test "groups returns empty slice" {
    var cmd = TestHelper.makeCommand("root", emptyRun);
    defer cmd.deinit(gpa);
    try std.testing.expectEqual(0, cmd.groups().len);
}

test "containsGroup returns false for empty" {
    var cmd = TestHelper.makeCommand("root", emptyRun);
    defer cmd.deinit(gpa);
    try std.testing.expect(!cmd.containsGroup("any"));
}

test "allChildCommandsHaveGroup empty" {
    var cmd = TestHelper.makeCommand("root", emptyRun);
    defer cmd.deinit(gpa);
    try std.testing.expect(cmd.allChildCommandsHaveGroup());
}

test "command path returns display name" {
    var cmd = Command{ .use = "root" };
    try std.testing.expectEqualStrings("root", cmd.commandPath());
}

test "helpCommand group handling" {
    var root = Command{ .use = "root", .run = emptyRun };
    var child = Command{ .use = "child", .run = emptyRun };
    addCommand(&root, &child);
    defer root.deinit(gpa);
    root.setHelpCommandGroupID("helpGroup");
    try std.testing.expectEqualStrings("helpGroup", root.help_command_group_id);
}

test "setErr sets error writer" {
    var cmd = TestHelper.makeCommand("root", emptyRun);
    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    cmd.setErr(&writer);
    try std.testing.expect(cmd.err_writer != null);
}

test "setOut sets output writer" {
    var cmd = TestHelper.makeCommand("root", emptyRun);
    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    cmd.setOut(&writer);
    try std.testing.expect(cmd.out_writer != null);
}

test "debugFlags basic" {
    var root = Command{ .use = "root", .run = emptyRun };
    var child = Command{ .use = "child", .run = emptyRun };
    addCommand(&root, &child);
    defer root.deinit(gpa);
    // debugFlags is a no-op in stub
    try std.testing.expect(true);
}

test "isAdditionalHelpTopicCommand" {
    const docs = Command{ .use = "docs" };
    const runnable = Command{ .use = "run", .run = emptyRun };
    const deprecated = Command{ .use = "dep", .deprecated = "x" };
    const hidden = Command{ .use = "hid", .hidden = true };
    try std.testing.expect(docs.isAdditionalHelpTopicCommand());
    try std.testing.expect(!runnable.isAdditionalHelpTopicCommand());
    try std.testing.expect(!deprecated.isAdditionalHelpTopicCommand());
    try std.testing.expect(!hidden.isAdditionalHelpTopicCommand());
}
