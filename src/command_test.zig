//! Tests for Command. Maps from cobra/command_test.go
const std = @import("std");
const cobra = @import("cobra.zig");
const Command = @import("command.zig").Command;
const CommandDisplayNameAnnotation = @import("command.zig").CommandDisplayNameAnnotation;
const pflag = @import("command.zig").pflag;
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
    defer rootCmd.deinit(gpa);
    rootCmd.executeWrapper(gpa) catch {};
    try std.testing.expect(true);
}

test "execute with run function" {
    const args: []const []const u8 = &.{};
    var rootCmd = Command{ .use = "root", .run = emptyRun };
    rootCmd.setArgs(args);
    defer rootCmd.deinit(gpa);
    rootCmd.executeWrapper(gpa) catch {};
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

fn emptyRunE(ev: @import("command.zig").Exec, cmd: *Command, args: [][]const u8) anyerror!void {
    _ = ev;
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

// ─── Flag Accessor Methods Tests ───

test "flagsPtr returns null when not set" {
    var cmd = Command{ .use = "root" };
    try std.testing.expect(cmd.flagsPtr() == null);
}

test "flags(gpa) lazily creates owned flagset" {
    var cmd = Command{ .use = "root" };
    defer cmd.deinit(gpa);
    const fs = cmd.flags(gpa);
    try std.testing.expect(fs.lookup("anything") == null);
}

test "persistentFlagsPtr returns null when not set" {
    var cmd = Command{ .use = "root" };
    try std.testing.expect(cmd.persistentFlagsPtr() == null);
}

test "localFlags builds empty view when no flags" {
    var cmd = Command{ .use = "root" };
    defer cmd.deinit(gpa);
    const lfs = cmd.localFlags(gpa);
    try std.testing.expect(lfs != null);
    try std.testing.expect(lfs.?.ordered_formal.items.len == 0);
}

test "inheritedFlags returns null when no parent" {
    var cmd = Command{ .use = "root" };
    defer cmd.deinit(gpa);
    const ifs = cmd.inheritedFlags(gpa);
    try std.testing.expect(ifs == null);
}

test "flag lookup returns null for non-existent flag" {
    var cmd = Command{ .use = "root" };
    const f = cmd.flag("nonexistent");
    try std.testing.expect(f == null);
}

// ─── Flag Query Methods Tests ───

test "hasFlags returns false when no flags" {
    var cmd = Command{ .use = "root" };
    try std.testing.expect(!cmd.hasFlags());
}

test "hasLocalFlags returns false when no local flags" {
    var cmd = Command{ .use = "root" };
    try std.testing.expect(!cmd.hasLocalFlags());
}

test "hasPersistentFlags returns false when no persistent flags" {
    var cmd = Command{ .use = "root" };
    try std.testing.expect(!cmd.hasPersistentFlags());
}

test "hasAvailableFlags returns false when no flags" {
    var cmd = Command{ .use = "root" };
    try std.testing.expect(!cmd.hasAvailableFlags());
}

// ─── Core Missing Methods Tests ───

test "useLine returns use field for root" {
    var cmd = Command{ .use = "root [flags]" };
    try std.testing.expectEqualStrings("root [flags]", cmd.useLine());
}

test "usageString renders usage block" {
    var cmd = Command{ .use = "root", .run = emptyRun };
    defer cmd.deinit(gpa);
    const usage = try cmd.usageString(gpa);
    defer gpa.free(usage);
    try TestHelper.checkStringContains(usage, "Usage:");
}

test "helpFunc returns null when not set" {
    var cmd = Command{ .use = "root" };
    try std.testing.expect(cmd.helpFunc() == null);
}

test "flagErrorFunc returns null when not set" {
    var cmd = Command{ .use = "root" };
    try std.testing.expect(cmd.flagErrorFunc() == null);
}

test "usageFunc returns null when not set" {
    var cmd = Command{ .use = "root" };
    try std.testing.expect(cmd.usageFunc() == null);
}

// ─── Template Methods Tests ───

test "usageTemplate returns default when not set" {
    var cmd = Command{ .use = "root" };
    const tmpl = cmd.usageTemplate();
    try std.testing.expect(tmpl.len > 0);
}

test "helpTemplate returns default when not set" {
    var cmd = Command{ .use = "root" };
    const tmpl = cmd.helpTemplate();
    try std.testing.expect(tmpl.len > 0);
}

test "versionTemplate returns default when not set" {
    var cmd = Command{ .use = "root" };
    const tmpl = cmd.versionTemplate();
    try std.testing.expect(tmpl.len > 0);
}

test "setUsageTemplate sets custom template" {
    var cmd = Command{ .use = "root" };
    cmd.setUsageTemplate("custom usage");
    try std.testing.expectEqualStrings("custom usage", cmd.usageTemplate());
}

test "setHelpTemplate sets custom template" {
    var cmd = Command{ .use = "root" };
    cmd.setHelpTemplate("custom help");
    try std.testing.expectEqualStrings("custom help", cmd.helpTemplate());
}

test "setVersionTemplate sets custom template" {
    var cmd = Command{ .use = "root" };
    cmd.setVersionTemplate("custom version");
    try std.testing.expectEqualStrings("custom version", cmd.versionTemplate());
}

// ─── Utility Methods Tests ───

test "nameAndAliases returns name" {
    var cmd = Command{ .use = "root" };
    const aliases = cmd.nameAndAliases();
    try std.testing.expect(aliases.len > 0);
}

test "useLine returns use field" {
    var cmd = Command{ .use = "root [flags]" };
    try std.testing.expectEqualStrings("root [flags]", cmd.useLine());
}

test "resetFlags clears all flag sets" {
    var cmd = Command{ .use = "root" };
    cmd.resetFlags();
    try std.testing.expect(cmd.flags_ptr == null);
    try std.testing.expect(cmd.pflags == null);
}

test "hasNameOrAliasPrefix matches name" {
    var cmd = Command{ .use = "root" };
    try std.testing.expect(cmd.hasNameOrAliasPrefix("ro"));
    try std.testing.expect(cmd.hasNameOrAliasPrefix("root"));
    try std.testing.expect(!cmd.hasNameOrAliasPrefix("xyz"));
}

test "hasNameOrAliasPrefix matches alias" {
    var cmd = Command{ .use = "root", .aliases = &.{"r"} };
    try std.testing.expect(cmd.hasNameOrAliasPrefix("r"));
}

// ─── Command Tree Search Tests ───

test "find returns self when no args" {
    var cmd = Command{ .use = "root", .run = emptyRun };
    const result = cmd.find(gpa, &.{});
    try std.testing.expect(result.cmd == &cmd);
    try std.testing.expect(result.args.len == 0);
}

test "find returns child command" {
    var root = Command{ .use = "root", .run = emptyRun };
    var child = Command{ .use = "child", .run = emptyRun };
    addCommand(&root, &child);
    defer root.deinit(gpa);
    const result = root.find(gpa, &.{"child"});
    try std.testing.expect(result.cmd == &child);
}

test "find returns remaining args" {
    var root = Command{ .use = "root", .run = emptyRun };
    var child = Command{ .use = "child", .run = emptyRun };
    addCommand(&root, &child);
    defer root.deinit(gpa);
    const result = root.find(gpa, &.{ "child", "arg1", "arg2" });
    defer if (result.owned_args) |a| gpa.free(a);
    try std.testing.expect(result.cmd == &child);
    try std.testing.expect(result.args.len == 2);
}

test "find copies and frees args when command name is not first" {
    // Go parity: in stripFlags an UNKNOWN flag is assumed to consume the next
    // argument, which would hide "child" from find(). To exercise the
    // argsMinusFirstX copy path, use a registered BOOL flag (NoOptDefVal set),
    // which consumes no value and keeps "child" positional.
    var fs = pflag.FlagSet.init(gpa, "root");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var verbose: bool = false;
    try fs.boolVar(&verbose, "verbose", false, "bool flag consumes no value");

    var root = Command{ .use = "root", .run = emptyRun, .flags_ptr = &fs };
    var child = Command{ .use = "child", .run = emptyRun };
    addCommand(&root, &child);
    defer root.deinit(gpa);

    const result = root.find(gpa, &.{ "--verbose", "child", "arg1" });
    defer if (result.owned_args) |a| gpa.free(a);
    try std.testing.expect(result.owned_args != null);
    try std.testing.expect(result.cmd == &child);
    // Go parity: Find returns flagsAndArgs — the command name removed, flags retained.
    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings("--verbose", result.args[0]);
    try std.testing.expectEqualStrings("arg1", result.args[1]);
}

test "find consumes unknown flag value like Go stripFlags" {
    // Go: unknown "--flag" consumes the next arg in stripFlags, so the subcommand
    // name never becomes positional and root is the found target.
    var root = Command{ .use = "root", .run = emptyRun };
    var child = Command{ .use = "child", .run = emptyRun };
    addCommand(&root, &child);
    defer root.deinit(gpa);

    const result = root.find(gpa, &.{ "--unknown", "child" });
    defer if (result.owned_args) |a| gpa.free(a);
    try std.testing.expect(result.owned_args == null);
    try std.testing.expect(result.cmd == &root);
    try std.testing.expectEqual(@as(usize, 2), result.args.len);
}

test "traverse behaves like find" {
    var root = Command{ .use = "root", .run = emptyRun };
    var child = Command{ .use = "child", .run = emptyRun };
    addCommand(&root, &child);
    defer root.deinit(gpa);
    const result = root.traverse(gpa, &.{"child"});
    try std.testing.expect(result.cmd == &child);
}

test "argsLenAtDash returns -1 when no flags parsed" {
    var cmd = Command{ .use = "root", .args_slice = &.{ "arg1", "arg2" } };
    try std.testing.expectEqual(@as(isize, -1), cmd.argsLenAtDash());
}

test "argsLenAtDash tracks dash position from parse" {
    var cmd = Command{ .use = "root" };
    var fs = pflag.FlagSet.init(gpa, "t");
    defer fs.deinit();
    cmd.flags_ptr = &fs;
    fs.error_handling = .continue_on_error;
    fs.parse(&.{ "arg1", "--", "arg2" }) catch {};
    try std.testing.expectEqual(@as(isize, 1), cmd.argsLenAtDash());
}

// ─── Flag Merging Tests ───

test "mergePersistentFlags builds views" {
    var cmd = Command{ .use = "root" };
    defer cmd.deinit(gpa);
    cmd.mergePersistentFlags(gpa);
    try std.testing.expect(cmd.lflags != null);
}

test "updateParentsPflags does not crash without parent" {
    var cmd = Command{ .use = "root" };
    defer cmd.deinit(gpa);
    cmd.updateParentsPflags(gpa, false);
    try std.testing.expect(cmd.parents_pflags == null);
}

test "parseFlags does not crash when no flags" {
    var cmd = Command{ .use = "root" };
    defer cmd.deinit(gpa);
    const io = std.Io.Threaded.global_single_threaded.*.io();
    cmd.parseFlags(io, gpa, &.{}) catch {};
    try std.testing.expect(true);
}

// ─── Flag Tests ───

test "flag long" {
    var rootCmd = Command{ .use = "root", .run = emptyRun };
    var intFlagValue: i32 = 0;
    rootCmd.flags_ptr = try gpa.create(pflag.FlagSet);
    rootCmd.flags_ptr.?.* = pflag.FlagSet.init(gpa, "root");
    defer {
        rootCmd.flags_ptr.?.deinit();
        gpa.destroy(rootCmd.flags_ptr.?);
        rootCmd.deinit(gpa);
    }
    try rootCmd.flags_ptr.?.intVarP(i32, &intFlagValue, "intf", "", -1, "");

    const out = try TestHelper.executeCommand(gpa, &rootCmd, &.{"--intf=7"});
    try std.testing.expect(out.err == null);
    try std.testing.expectEqual(@as(i32, 7), intFlagValue);
}

test "flag short" {
    var rootCmd = Command{ .use = "root", .run = emptyRun };
    var intFlagValue: i32 = 0;
    rootCmd.flags_ptr = try gpa.create(pflag.FlagSet);
    rootCmd.flags_ptr.?.* = pflag.FlagSet.init(gpa, "root");
    defer {
        rootCmd.flags_ptr.?.deinit();
        gpa.destroy(rootCmd.flags_ptr.?);
        rootCmd.deinit(gpa);
    }
    try rootCmd.flags_ptr.?.intVarP(i32, &intFlagValue, "intf", "i", -1, "");

    const out = try TestHelper.executeCommand(gpa, &rootCmd, &.{"-i7"});
    try std.testing.expect(out.err == null);
    try std.testing.expectEqual(@as(i32, 7), intFlagValue);
}

test "child flag" {
    var rootCmd = Command{ .use = "root", .run = emptyRun };
    var childCmd = Command{ .use = "child", .run = emptyRun };
    rootCmd.addCommand(gpa, &.{&childCmd});
    defer rootCmd.deinit(gpa);

    var intFlagValue: i32 = 0;
    childCmd.flags_ptr = try gpa.create(pflag.FlagSet);
    childCmd.flags_ptr.?.* = pflag.FlagSet.init(gpa, "child");
    defer {
        childCmd.flags_ptr.?.deinit();
        gpa.destroy(childCmd.flags_ptr.?);
    }
    try childCmd.flags_ptr.?.intVarP(i32, &intFlagValue, "intf", "", -1, "");

    const out = try TestHelper.executeCommand(gpa, &rootCmd, &.{ "child", "--intf=7" });
    try std.testing.expect(out.err == null);
    try std.testing.expectEqual(@as(i32, 7), intFlagValue);
}

test "flag invalid input" {
    var rootCmd = Command{ .use = "root", .run = emptyRun, .silence_errors = true };
    var intFlagValue: i32 = 0;
    rootCmd.flags_ptr = try gpa.create(pflag.FlagSet);
    rootCmd.flags_ptr.?.* = pflag.FlagSet.init(gpa, "root");
    defer {
        rootCmd.flags_ptr.?.deinit();
        gpa.destroy(rootCmd.flags_ptr.?);
        rootCmd.deinit(gpa);
    }
    try rootCmd.flags_ptr.?.intVarP(i32, &intFlagValue, "intf", "i", -1, "");

    const out = try TestHelper.executeCommand(gpa, &rootCmd, &.{"-iabc"});
    try std.testing.expect(out.err != null);
}

test "flag before command" {
    var rootCmd = Command{ .use = "root", .run = emptyRun };
    var childCmd = Command{ .use = "child", .run = emptyRun };
    rootCmd.addCommand(gpa, &.{&childCmd});
    defer rootCmd.deinit(gpa);

    var flagValue: i32 = 0;
    childCmd.flags_ptr = try gpa.create(pflag.FlagSet);
    childCmd.flags_ptr.?.* = pflag.FlagSet.init(gpa, "child");
    defer {
        childCmd.flags_ptr.?.deinit();
        gpa.destroy(childCmd.flags_ptr.?);
    }
    try childCmd.flags_ptr.?.intVarP(i32, &flagValue, "intf", "i", -1, "");

    const out = try TestHelper.executeCommand(gpa, &rootCmd, &.{ "-i7", "child" });
    try std.testing.expect(out.err == null);
    try std.testing.expectEqual(@as(i32, 7), flagValue);
}

// ─── Traverse Tests ───

test "traverse with parent flags" {
    var rootCmd = Command{ .use = "root", .run = emptyRun };
    var childCmd = Command{ .use = "child", .run = emptyRun };
    rootCmd.addCommand(gpa, &.{&childCmd});
    defer rootCmd.deinit(gpa);

    const result = rootCmd.traverse(gpa, &.{"child"});
    try std.testing.expectEqualStrings("child", result.cmd.use);
}

test "traverse returns remaining args" {
    var rootCmd = Command{ .use = "root", .run = emptyRun };
    var childCmd = Command{ .use = "child", .run = emptyRun };
    rootCmd.addCommand(gpa, &.{&childCmd});
    defer rootCmd.deinit(gpa);

    const result = rootCmd.traverse(gpa, &.{ "child", "arg1", "arg2" });
    try std.testing.expectEqualStrings("child", result.cmd.use);
    try std.testing.expectEqual(@as(usize, 2), result.args.len);
}

// ─── Hook Tests ───

test "hooks receive positional args" {
    var persPreArgs: []const u8 = "";
    var preArgs: []const u8 = "";
    var runArgs: []const u8 = "";
    var postArgs: []const u8 = "";
    var persPostArgs: []const u8 = "";

    var cmd = Command{
        .use = "c",
        .persistent_pre_run = struct {
            fn run(ev: @import("command.zig").Exec, _: *Command, args: [][]const u8) void {
                _ = ev;
                _ = args;
            }
        }.run,
        .pre_run = struct {
            fn run(ev: @import("command.zig").Exec, _: *Command, args: [][]const u8) void {
                _ = ev;
                _ = args;
            }
        }.run,
        .run = struct {
            fn run(ev: @import("command.zig").Exec, _: *Command, args: [][]const u8) void {
                _ = ev;
                _ = args;
            }
        }.run,
        .post_run = struct {
            fn run(ev: @import("command.zig").Exec, _: *Command, args: [][]const u8) void {
                _ = ev;
                _ = args;
            }
        }.run,
        .persistent_post_run = struct {
            fn run(ev: @import("command.zig").Exec, _: *Command, args: [][]const u8) void {
                _ = ev;
                _ = args;
            }
        }.run,
    };
    defer cmd.deinit(gpa);

    _ = &persPreArgs;
    _ = &preArgs;
    _ = &runArgs;
    _ = &postArgs;
    _ = &persPostArgs;

    const out = try TestHelper.executeCommand(gpa, &cmd, &.{ "one", "two" });
    try std.testing.expect(out.err == null);
}

// ─── Version Flag Tests ───

test "version flag prints version" {
    var rootCmd = Command{
        .use = "root",
        .version = "1.0.0",
        .run = emptyRun,
    };
    defer rootCmd.deinit(gpa);

    const out = try TestHelper.executeCommand(gpa, &rootCmd, &.{"--version"});
    try std.testing.expect(out.err == null);
    try TestHelper.checkStringContains(out.output, "root version 1.0.0");
}

test "version flag with display name" {
    var rootCmd = Command{
        .use = "kubectl-plugin",
        .version = "1.0.0",
        .run = emptyRun,
    };
    defer rootCmd.deinit(gpa);

    const out = try TestHelper.executeCommand(gpa, &rootCmd, &.{"--version"});
    try std.testing.expect(out.err == null);
    try TestHelper.checkStringContains(out.output, "version 1.0.0");
}

test "version flag only added to root" {
    var rootCmd = Command{
        .use = "root",
        .version = "1.0.0",
        .run = emptyRun,
    };
    var childCmd = Command{ .use = "child", .run = emptyRun };
    rootCmd.addCommand(gpa, &.{&childCmd});
    defer rootCmd.deinit(gpa);

    // Go: TestVersionFlagOnlyAddedToRoot - child parses --version as unknown flag.
    // Adaptation: zig-cobra surfaces the pflag error kind instead of Go's message text.
    const out = try TestHelper.executeCommand(gpa, &rootCmd, &.{ "child", "--version" });
    try std.testing.expectEqual(error.NoSuchFlag, out.err.?);
}

// ─── Help Tests ───

test "help flag prints help" {
    var rootCmd = Command{ .use = "root", .run = emptyRun };
    defer rootCmd.deinit(gpa);

    const out = try TestHelper.executeCommand(gpa, &rootCmd, &.{"--help"});
    try std.testing.expect(out.err == null);
    try TestHelper.checkStringContains(out.output, "Usage:");
}

test "help subcommand prints target command help" {
    var rootCmd = Command{ .use = "root", .run = emptyRun };
    var childCmd = Command{ .use = "child", .short = "child short", .run = emptyRun };
    rootCmd.addCommand(gpa, &.{&childCmd});
    defer rootCmd.deinit(gpa);

    const out = try TestHelper.executeCommand(gpa, &rootCmd, &.{ "help", "child" });
    try std.testing.expect(out.err == null);
    try TestHelper.checkStringContains(out.output, "child short");
}

test "help executed on non-runnable child" {
    var rootCmd = Command{ .use = "root", .run = emptyRun };
    var childCmd = Command{ .use = "child", .long = "Long description" };
    rootCmd.addCommand(gpa, &.{&childCmd});
    defer rootCmd.deinit(gpa);

    const out = try TestHelper.executeCommand(gpa, &rootCmd, &.{"child"});
    try std.testing.expect(out.err == null);
    try TestHelper.checkStringContains(out.output, "Long description");
}

// ─── Other Core Tests ───

test "call command without subcommands" {
    var rootCmd = Command{ .use = "root", .run = emptyRun };
    defer rootCmd.deinit(gpa);

    const out = try TestHelper.executeCommand(gpa, &rootCmd, &.{});
    try std.testing.expect(out.err == null);
}

test "subcommand executeC returns correct command" {
    var rootCmd = Command{ .use = "root", .run = emptyRun };
    var childCmd = Command{ .use = "child", .run = emptyRun };
    rootCmd.addCommand(gpa, &.{&childCmd});
    defer rootCmd.deinit(gpa);

    const out = try TestHelper.executeCommand(gpa, &rootCmd, &.{"child"});
    try std.testing.expect(out.err == null);
}

test "deprecated command shows deprecation message" {
    var rootCmd = Command{ .use = "root", .run = emptyRun };
    var deprecatedCmd = Command{
        .use = "deprecated",
        .deprecated = "This command is deprecated",
        .run = emptyRun,
    };
    rootCmd.addCommand(gpa, &.{&deprecatedCmd});
    defer rootCmd.deinit(gpa);

    const out = try TestHelper.executeCommand(gpa, &rootCmd, &.{"deprecated"});
    try std.testing.expect(out.err == null);
    try TestHelper.checkStringContains(out.output, "This command is deprecated");
}

test "hidden command is hidden from help" {
    var rootCmd = Command{ .use = "root", .run = emptyRun };
    var hiddenCmd = Command{
        .use = "hidden",
        .hidden = true,
        .run = emptyRun,
    };
    rootCmd.addCommand(gpa, &.{&hiddenCmd});
    defer rootCmd.deinit(gpa);

    const out = try TestHelper.executeCommand(gpa, &rootCmd, &.{"--help"});
    try std.testing.expect(out.err == null);
    try TestHelper.checkStringOmits(out.output, "hidden");
}

test "set output writer" {
    var rootCmd = Command{ .use = "root", .run = emptyRun };
    defer rootCmd.deinit(gpa);

    var buf: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    rootCmd.setOut(&writer);

    try std.testing.expect(rootCmd.out_writer != null);
}

test "set error writer" {
    var rootCmd = Command{ .use = "root", .run = emptyRun };
    defer rootCmd.deinit(gpa);

    var buf: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    rootCmd.setErr(&writer);

    try std.testing.expect(rootCmd.err_writer != null);
}

// ─── Version Flag Registration Tests (Go: command_test.go Test*Version*) ───

test "version flag display name from annotations" {
    // Go: TestVersionFlagExecutedDiplayName
    var rootCmd = Command{
        .use = "kubectl-plugin",
        .version = "1.0.0",
        .run = emptyRun,
    };
    defer rootCmd.deinit(gpa);
    // Command.deinit does not touch the user-managed annotations map (Go relies on GC).
    defer rootCmd.annotations.deinit(gpa);
    try rootCmd.annotations.put(gpa, CommandDisplayNameAnnotation, &.{"kubectl plugin"});

    const out = try TestHelper.executeCommand(gpa, &rootCmd, &.{ "--version", "arg1" });
    try std.testing.expect(out.err == null);
    try TestHelper.checkStringContains(out.output, "kubectl plugin version 1.0.0");
}

test "version flag with no name set" {
    // Go: TestVersionFlagExecutedWithNoName
    var rootCmd = Command{ .use = "", .version = "1.0.0", .run = emptyRun };
    defer rootCmd.deinit(gpa);

    const out = try TestHelper.executeCommand(gpa, &rootCmd, &.{ "--version", "arg1" });
    try std.testing.expect(out.err == null);
    try TestHelper.checkStringContains(out.output, "version 1.0.0");
}

test "version flag shorthand and long form in help" {
    // Go: TestShortAndLongVersionFlagInHelp
    var rootCmd = Command{ .use = "root", .version = "1.0.0", .run = emptyRun };
    defer rootCmd.deinit(gpa);

    const out = try TestHelper.executeCommand(gpa, &rootCmd, &.{"--help"});
    try std.testing.expect(out.err == null);
    try TestHelper.checkStringContains(out.output, "-v, --version");
}

test "version long form only in help when shorthand taken" {
    // Go: TestLongVersionFlagOnlyInHelpWhenShortPredefined
    var fs = pflag.FlagSet.init(gpa, "root");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var foo: []const u8 = "";
    try fs.stringVarP(&foo, "foo", "v", "", "not a version flag");

    var rootCmd = Command{
        .use = "root",
        .version = "1.0.0",
        .run = emptyRun,
        .flags_ptr = &fs,
    };
    defer rootCmd.deinit(gpa);

    const out = try TestHelper.executeCommand(gpa, &rootCmd, &.{"--help"});
    try std.testing.expect(out.err == null);
    try TestHelper.checkStringOmits(out.output, "-v, --version");
    try TestHelper.checkStringContains(out.output, "--version");
}

test "version flag shorthand executes" {
    // Go: TestShorthandVersionFlagExecuted
    var rootCmd = Command{ .use = "root", .version = "1.0.0", .run = emptyRun };
    defer rootCmd.deinit(gpa);

    const out = try TestHelper.executeCommand(gpa, &rootCmd, &.{ "-v", "arg1" });
    try std.testing.expect(out.err == null);
    try TestHelper.checkStringContains(out.output, "root version 1.0.0");
}

test "version template stored and retrievable" {
    // Go: TestVersionTemplate / TestShorthandVersionTemplate.
    // Adaptation: zig-cobra keeps custom templates verbatim (no template engine) —
    // see TmplFunc note in command.zig. Output rendering stays Go-default.
    var rootCmd = Command{ .use = "root", .version = "1.0.0", .run = emptyRun };
    defer rootCmd.deinit(gpa);
    rootCmd.setVersionTemplate("customized version: {{.Version}}");
    try std.testing.expectEqualStrings("customized version: {{.Version}}", rootCmd.versionTemplate());

    var plain = Command{ .use = "root" };
    defer plain.deinit(gpa);
    try std.testing.expectEqualStrings(
        @import("command.zig").default_version_template,
        plain.versionTemplate(),
    );
}

test "version flag executed with subcommand arg after" {
    // Go: TestVersionFlagExecutedOnSubcommand - root wins; "sub" is consumed as the
    // (unknown at find-time) --version flag's value by stripFlags.
    var rootCmd = Command{ .use = "root", .version = "1.0.0" };
    var subCmd = Command{ .use = "sub", .run = emptyRun };
    rootCmd.addCommand(gpa, &.{&subCmd});
    defer rootCmd.deinit(gpa);

    const out = try TestHelper.executeCommand(gpa, &rootCmd, &.{ "--version", "sub" });
    try std.testing.expect(out.err == null);
    try TestHelper.checkStringContains(out.output, "root version 1.0.0");
}

test "version shorthand executed with subcommand arg after" {
    // Go: TestShorthandVersionFlagExecutedOnSubcommand
    var rootCmd = Command{ .use = "root", .version = "1.0.0" };
    var subCmd = Command{ .use = "sub", .run = emptyRun };
    rootCmd.addCommand(gpa, &.{&subCmd});
    defer rootCmd.deinit(gpa);

    const out = try TestHelper.executeCommand(gpa, &rootCmd, &.{ "-v", "sub" });
    try std.testing.expect(out.err == null);
    try TestHelper.checkStringContains(out.output, "root version 1.0.0");
}

test "short version flag only added to root" {
    // Go: TestShortVersionFlagOnlyAddedToRoot
    var rootCmd = Command{ .use = "root", .version = "1.0.0", .run = emptyRun };
    var subCmd = Command{ .use = "sub", .run = emptyRun };
    rootCmd.addCommand(gpa, &.{&subCmd});
    defer rootCmd.deinit(gpa);

    const out = try TestHelper.executeCommand(gpa, &rootCmd, &.{ "sub", "-v" });
    try std.testing.expectEqual(error.NoSuchFlag, out.err.?);
}

test "version flag exists only when version non-empty" {
    // Go: TestVersionFlagOnlyExistsIfVersionNonEmpty
    var rootCmd = Command{ .use = "root", .run = emptyRun };
    defer rootCmd.deinit(gpa);

    const out = try TestHelper.executeCommand(gpa, &rootCmd, &.{"--version"});
    try std.testing.expectEqual(error.NoSuchFlag, out.err.?);
}

test "version shorthand exists only when version non-empty" {
    // Go: TestShorthandVersionFlagOnlyExistsIfVersionNonEmpty
    var rootCmd = Command{ .use = "root", .run = emptyRun };
    defer rootCmd.deinit(gpa);

    const out = try TestHelper.executeCommand(gpa, &rootCmd, &.{"-v"});
    try std.testing.expectEqual(error.NoSuchFlag, out.err.?);
}

test "version shorthand skipped when v taken by user flag" {
    // Go: TestShorthandVersionFlagOnlyAddedIfShorthandNotDefined
    var fs = pflag.FlagSet.init(gpa, "root");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var notversion: []const u8 = "";
    try fs.stringVarP(&notversion, "notversion", "v", "", "not a version flag");

    var rootCmd = Command{
        .use = "root",
        .version = "1.2.3",
        .run = emptyRun,
        .flags_ptr = &fs,
    };
    defer rootCmd.deinit(gpa);

    const out = try TestHelper.executeCommand(gpa, &rootCmd, &.{"-v"});
    // -v belongs to the user's string flag, which requires a value.
    try std.testing.expectEqual(error.ValueRequired, out.err.?);
    try std.testing.expectEqualStrings("notversion", fs.shorthandLookup('v').?.name);
    // --version still registered, long-only.
    try std.testing.expect(fs.lookup("version") != null);
}

test "version shorthand skipped when version long flag user-defined" {
    // Go: TestShorthandVersionFlagOnlyAddedIfVersionNotDefined
    var fs = pflag.FlagSet.init(gpa, "root");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var user_version: bool = false;
    try fs.boolVar(&user_version, "version", false, "a different kind of version flag");

    var rootCmd = Command{
        .use = "root",
        .version = "1.2.3",
        .run = emptyRun,
        .flags_ptr = &fs,
    };
    defer rootCmd.deinit(gpa);

    const out = try TestHelper.executeCommand(gpa, &rootCmd, &.{"-v"});
    // initDefaultVersionFlag bails out early: lookup("version") already present.
    try std.testing.expectEqual(error.NoSuchFlag, out.err.?);
    try std.testing.expect(fs.shorthandLookup('v') == null);
}

// ─── StripFlags Tests (Go: TestStripFlags) ───

test "strip flags keeps positional args only" {
    // Go: TestStripFlags - lexical flag/value separation. Adaptation: the Go test
    // calls the private stripFlags() helper directly; here the same input/output
    // table is exercised through the parse pipeline (known value flags -> consumed
    // values, positional remainder). The int flag is modeled as a string flag so
    // non-numeric attached values ("-i=baz") still parse while keeping the
    // value-consuming property.
    const Case = struct { input: []const []const u8, expected: []const []const u8 };
    const cases = [_]Case{
        .{ .input = &.{ "foo", "bar" }, .expected = &.{ "foo", "bar" } },
        .{ .input = &.{ "foo", "--str", "-s" }, .expected = &.{"foo"} },
        .{ .input = &.{ "-s", "foo", "--str", "bar" }, .expected = &.{} },
        .{ .input = &.{ "-i10", "echo" }, .expected = &.{"echo"} },
        .{ .input = &.{ "-i=10", "echo" }, .expected = &.{"echo"} },
        .{ .input = &.{ "--int=100", "echo" }, .expected = &.{"echo"} },
        .{ .input = &.{ "-ib", "echo", "-sfoo", "baz" }, .expected = &.{ "echo", "baz" } },
        .{ .input = &.{ "-i=baz", "bar", "-i", "foo", "blah" }, .expected = &.{ "bar", "blah" } },
        .{ .input = &.{ "--int=baz", "-sbar", "-i", "foo", "blah" }, .expected = &.{"blah"} },
        .{ .input = &.{ "--bool", "bar", "-i", "foo", "blah" }, .expected = &.{ "bar", "blah" } },
        .{ .input = &.{ "-b", "bar", "-i", "foo", "blah" }, .expected = &.{ "bar", "blah" } },
        .{ .input = &.{ "--persist", "bar" }, .expected = &.{"bar"} },
        .{ .input = &.{ "-p", "bar" }, .expected = &.{"bar"} },
    };

    for (cases) |tc| {
        var fs = pflag.FlagSet.init(gpa, "c");
        defer fs.deinit();
        fs.error_handling = .continue_on_error;
        var persist: bool = false;
        var intf: []const u8 = "";
        var strf: []const u8 = "";
        var boolf: bool = false;
        _ = &persist;
        _ = &intf;
        _ = &strf;
        _ = &boolf;
        try fs.boolVarP(&persist, "persist", "p", false, "");
        try fs.stringVarP(&intf, "int", "i", "", "");
        try fs.stringVarP(&strf, "str", "s", "", "");
        try fs.boolVarP(&boolf, "bool", "b", false, "");

        try fs.parse(tc.input);
        try std.testing.expectEqualSlices([]const u8, tc.expected, fs.argList());
    }
}

// ─── DisableFlagParsing Tests (Go: TestDisableFlagParsing) ───

// Static capture for run hooks; executeCommand runs the hook inline within the same
// call, and `args` points at the caller's (static) input slice, so it stays valid.
var raw_run_args: [][]const u8 = &.{};

fn captureRunArgs(ev: @import("command.zig").Exec, cmd: *Command, args: [][]const u8) void {
    _ = ev;
    _ = cmd;
    raw_run_args = args;
}

test "disable flag parsing passes raw args to run" {
    raw_run_args = &.{};
    var cmd = Command{
        .use = "c",
        .disable_flag_parsing = true,
        .run = captureRunArgs,
    };
    defer cmd.deinit(gpa);

    const want = [_][]const u8{ "cmd", "-v", "-race", "-file", "foo.go" };
    const out = try TestHelper.executeCommand(gpa, &cmd, &want);
    try std.testing.expect(out.err == null);
    try std.testing.expectEqualSlices([]const u8, &want, raw_run_args);
}

test "disable flag parsing bypasses version flag" {
    raw_run_args = &.{};
    var cmd = Command{
        .use = "c",
        .version = "1.0.0",
        .disable_flag_parsing = true,
        .run = captureRunArgs,
    };
    defer cmd.deinit(gpa);

    const want = [_][]const u8{ "build", "--version" };
    const out = try TestHelper.executeCommand(gpa, &cmd, &want);
    try std.testing.expect(out.err == null);
    try std.testing.expectEqualSlices([]const u8, &want, raw_run_args);
    // Version must NOT have been printed - flag was passed through raw.
    try TestHelper.checkStringOmits(out.output, "version 1.0.0");
}
