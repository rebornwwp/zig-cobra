//! Behavior tests for the Go-parity execution flow and completion machinery.
//! These cover the semantics fixed in the v0.2 rewrite: hook ordering, args
//! stripping, persistent-flag inheritance, required flags, flag groups wiring,
//! version/help handling, find/suggestions, and the __complete protocol.
const std = @import("std");
const cobra = @import("cobra.zig");
const command_mod = @import("command.zig");
const Command = command_mod.Command;
const pflag = command_mod.pflag;
const completions = @import("completions.zig");
const shell_completions = @import("shell_completions.zig");
const TestHelper = @import("test_helper.zig");

const gpa = std.testing.allocator;
const emptyRun = TestHelper.emptyRun;

// ─── Shared capture state (single-threaded tests) ───

var last_run_args: [][]const u8 = &.{};
fn captureRun(_: *Command, a: [][]const u8) void {
    last_run_args = a;
}

var hook_log: [32]u8 = undefined;
var hook_len: usize = 0;
fn hookReset() void {
    hook_len = 0;
}
fn recHook(comptime mark: u8) *const fn (*Command, [][]const u8) void {
    return struct {
        fn f(_: *Command, _: [][]const u8) void {
            if (hook_len < hook_log.len) {
                hook_log[hook_len] = mark;
                hook_len += 1;
            }
        }
    }.f;
}
fn recHookE(comptime mark: u8, comptime fails: bool) *const fn (*Command, [][]const u8) anyerror!void {
    return struct {
        fn f(_: *Command, _: [][]const u8) anyerror!void {
            if (hook_len < hook_log.len) {
                hook_log[hook_len] = mark;
                hook_len += 1;
            }
            if (fails) return error.RunFailed;
        }
    }.f;
}

test "run receives positional args only (flags stripped)" {
    var fs = pflag.FlagSet.init(gpa, "t");
    defer fs.deinit();
    var verbose: bool = false;
    try fs.boolVar(&verbose, "verbose", false, "verbose");

    var cmd = Command{ .use = "app", .run = captureRun, .flags_ptr = &fs, .silence_errors = true, .silence_usage = true };
    defer cmd.deinit(gpa);

    const out = try TestHelper.executeCommand(gpa, &cmd, &.{ "--verbose", "pos1", "pos2" });
    try std.testing.expect(out.err == null);
    try std.testing.expect(verbose);
    try std.testing.expectEqual(@as(usize, 2), last_run_args.len);
    try std.testing.expectEqualStrings("pos1", last_run_args[0]);
}

test "hook order: nearest persistent pre, pre, run, post, nearest persistent post" {
    hookReset();
    var root = Command{
        .use = "root",
        .persistent_pre_run = recHook('A'),
        .persistent_post_run = recHook('a'),
    };
    var child = Command{
        .use = "child",
        .persistent_pre_run = recHook('B'),
        .pre_run = recHook('C'),
        .run = recHook('D'),
        .post_run = recHook('E'),
        .persistent_post_run = recHook('F'),
    };
    root.addCommand(gpa, &.{&child});
    defer root.deinit(gpa);

    const out = try TestHelper.executeCommand(gpa, &root, &.{"child"});
    try std.testing.expect(out.err == null);
    // Go parity: only the NEAREST persistent hook runs (A/a are shadowed by B/F).
    try std.testing.expectEqualStrings("BCDEF", hook_log[0..hook_len]);
}

test "traverse run hooks executes the whole chain" {
    hookReset();
    const orig = cobra.enable_traverse_run_hooks;
    cobra.enable_traverse_run_hooks = true;
    defer cobra.enable_traverse_run_hooks = orig;

    var root = Command{ .use = "root", .persistent_pre_run = recHook('A') };
    var child = Command{ .use = "child", .persistent_pre_run = recHook('B'), .run = recHook('D') };
    root.addCommand(gpa, &.{&child});
    defer root.deinit(gpa);

    const out = try TestHelper.executeCommand(gpa, &root, &.{"child"});
    try std.testing.expect(out.err == null);
    // Chain order: nearest-first upward (B then A), then the run hook D.
    try std.testing.expectEqualStrings("BAD", hook_log[0..hook_len]);
}

test "post hooks are skipped when run fails" {
    hookReset();
    var cmd = Command{
        .use = "app",
        .pre_run = recHook('C'),
        .run_e = recHookE('D', true),
        .post_run = recHook('E'),
        .silence_errors = true,
        .silence_usage = true,
    };
    defer cmd.deinit(gpa);

    const out = try TestHelper.executeCommand(gpa, &cmd, &.{});
    try std.testing.expect(out.err != null);
    try std.testing.expectEqualStrings("CD", hook_log[0..hook_len]);
    TestHelper.checkStringContains(out.output, "RunFailed");
}

test "persistent flags are inherited and parsed by children" {
    var root_pfs = pflag.FlagSet.init(gpa, "rootp");
    defer root_pfs.deinit();
    var config: []const u8 = "";
    try root_pfs.stringVar(&config, "config", "def", "config path");

    var root = Command{ .use = "root", .pflags = &root_pfs };
    var child = Command{ .use = "child", .run = captureRun };
    root.addCommand(gpa, &.{&child});
    defer root.deinit(gpa);

    const out = try TestHelper.executeCommand(gpa, &root, &.{ "child", "--config", "x" });
    try std.testing.expect(out.err == null);
    try std.testing.expectEqualStrings("x", config);
}

test "required flag violation reports Go-style message" {
    var fs = pflag.FlagSet.init(gpa, "t");
    defer fs.deinit();
    var name: []const u8 = "";
    try fs.stringVar(&name, "name", "", "name");

    var cmd = Command{ .use = "app", .run = emptyRun, .flags_ptr = &fs, .silence_errors = true, .silence_usage = true };
    defer cmd.deinit(gpa);
    try shell_completions.markFlagRequired(&cmd, gpa, "name");

    const out = try TestHelper.executeCommand(gpa, &cmd, &.{});
    try std.testing.expect(out.err != null);
    TestHelper.checkStringContains(out.output, "required flag(s) \"name\" not set");

    const ok = try TestHelper.executeCommand(gpa, &cmd, &.{ "--name", "x" });
    try std.testing.expect(ok.err == null);
}

test "version flag prints version and exits successfully" {
    var cmd = Command{ .use = "app", .version = "1.2.3", .run = emptyRun };
    defer cmd.deinit(gpa);

    const out = try TestHelper.executeCommand(gpa, &cmd, &.{"--version"});
    try std.testing.expect(out.err == null);
    TestHelper.checkStringContains(out.output, "app version 1.2.3");
}

test "help flag prints help" {
    var cmd = Command{ .use = "app", .short = "app short", .run = emptyRun };
    defer cmd.deinit(gpa);

    const out = try TestHelper.executeCommand(gpa, &cmd, &.{"--help"});
    try std.testing.expect(out.err == null);
    TestHelper.checkStringContains(out.output, "app short");
    TestHelper.checkStringContains(out.output, "Usage:");
}

test "help subcommand prints target command help" {
    var root = Command{ .use = "root", .run = emptyRun };
    var child = Command{ .use = "child", .short = "child short desc", .run = emptyRun };
    root.addCommand(gpa, &.{&child});
    defer root.deinit(gpa);

    const out = try TestHelper.executeCommand(gpa, &root, &.{ "help", "child" });
    try std.testing.expect(out.err == null);
    TestHelper.checkStringContains(out.output, "child short desc");
}

test "unknown command reports error with suggestions" {
    var root = Command{ .use = "root", .run = emptyRun, .silence_usage = true };
    var child = Command{ .use = "hello", .run = emptyRun };
    root.addCommand(gpa, &.{&child});
    defer root.deinit(gpa);

    const out = try TestHelper.executeCommand(gpa, &root, &.{"helo"});
    try std.testing.expect(out.err != null);
    TestHelper.checkStringContains(out.output, "unknown command \"helo\" for \"root\"");
    TestHelper.checkStringContains(out.output, "Did you mean this?");
    TestHelper.checkStringContains(out.output, "hello");
}

test "root with subcommands rejects stray positional args (legacyArgs)" {
    var root = Command{ .use = "root", .run = emptyRun, .silence_usage = true };
    var child = Command{ .use = "child", .run = emptyRun };
    root.addCommand(gpa, &.{&child});
    defer root.deinit(gpa);

    const out = try TestHelper.executeCommand(gpa, &root, &.{"stray"});
    try std.testing.expect(out.err != null);
}

test "onlyValidArgs requires exact match" {
    var cmd = Command{
        .use = "app",
        .run = captureRun,
        .valid_args = &.{"alpha"},
        .args_validator = cobra.OnlyValidArgs(),
        .silence_errors = true,
        .silence_usage = true,
    };
    defer cmd.deinit(gpa);

    const bad = try TestHelper.executeCommand(gpa, &cmd, &.{"alph"});
    try std.testing.expect(bad.err != null);
    const good = try TestHelper.executeCommand(gpa, &cmd, &.{"alpha"});
    try std.testing.expect(good.err == null);
}

test "__complete emits protocol: values with descriptions then directive" {
    const io = std.Io.Threaded.global_single_threaded.*.io();
    var root = Command{ .use = "root" };
    var child = Command{ .use = "hello", .short = "say hi", .run = emptyRun };
    root.addCommand(gpa, &.{&child});
    defer root.deinit(gpa);

    var buf: [4096]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    root.setOut(&w);

    var req = [_][]const u8{""};
    try completions.getCompletions(&root, io, gpa, &req, true);
    const out = std.Io.Writer.buffered(&w);
    TestHelper.checkStringContains(out, "hello\tsay hi");
    TestHelper.checkStringContains(out, ":4"); // NoFileComp
}

test "__complete flag-name completion returns long and short forms" {
    const io = std.Io.Threaded.global_single_threaded.*.io();
    var fs = pflag.FlagSet.init(gpa, "t");
    defer fs.deinit();
    var name: []const u8 = "";
    try fs.stringVarP(&name, "name", "n", "", "the name");

    var cmd = Command{ .use = "app", .run = emptyRun, .flags_ptr = &fs };
    defer cmd.deinit(gpa);

    var buf: [4096]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    cmd.setOut(&w);

    var req = [_][]const u8{"-"};
    try completions.getCompletions(&cmd, io, gpa, &req, true);
    const out = std.Io.Writer.buffered(&w);
    TestHelper.checkStringContains(out, "--name");
    TestHelper.checkStringContains(out, "-n");
    TestHelper.checkStringContains(out, ":4");
}

test "__complete flag-value completion uses registered func" {
    const io = std.Io.Threaded.global_single_threaded.*.io();
    var fs = pflag.FlagSet.init(gpa, "t");
    defer fs.deinit();
    var dir: []const u8 = "";
    try fs.stringVar(&dir, "dir", "", "directory");

    var cmd = Command{ .use = "app", .run = emptyRun, .flags_ptr = &fs };
    defer cmd.deinit(gpa);
    try cmd.registerFlagCompletionFunc(gpa, "dir", completions.fixedCompletions(&.{ "/tmp", "/var" }, .no_file_comp));

    var buf: [4096]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    cmd.setOut(&w);

    var req = [_][]const u8{ "--dir", "" };
    try completions.getCompletions(&cmd, io, gpa, &req, true);
    const out = std.Io.Writer.buffered(&w);
    TestHelper.checkStringContains(out, "/tmp");
    TestHelper.checkStringContains(out, "/var");
    TestHelper.checkStringContains(out, ":4");
}

test "genMarkdown renders core sections" {
    const io = std.Io.Threaded.global_single_threaded.*.io();
    var fs = pflag.FlagSet.init(gpa, "t");
    defer fs.deinit();
    var name: []const u8 = "";
    try fs.stringVar(&name, "name", "", "the name");

    var root = Command{ .use = "root", .short = "root short", .long = "root long", .run = emptyRun, .flags_ptr = &fs };
    var child = Command{ .use = "child", .short = "child short", .run = emptyRun };
    root.addCommand(gpa, &.{&child});
    defer root.deinit(gpa);

    var buf: [8192]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try cobra.doc_mod.genMarkdown(gpa, &root, io, &w);
    const out = std.Io.Writer.buffered(&w);
    TestHelper.checkStringContains(out, "## root");
    TestHelper.checkStringContains(out, "### Synopsis");
    TestHelper.checkStringContains(out, "root long");
    TestHelper.checkStringContains(out, "### Options");
    TestHelper.checkStringContains(out, "--name");
    TestHelper.checkStringContains(out, "### SEE ALSO");
    TestHelper.checkStringContains(out, "root_child.md");
}

test "genBashCompletionV2 substitutes program name" {
    var cmd = Command{ .use = "myapp", .run = emptyRun };
    var child = Command{ .use = "sub", .run = emptyRun };
    cmd.addCommand(gpa, &.{&child});
    defer cmd.deinit(gpa);

    var buf: [32768]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try completions.genBashCompletionV2(&cmd, &w, true);
    const out = std.Io.Writer.buffered(&w);
    TestHelper.checkStringContains(out, "__myapp_debug()");
    TestHelper.checkStringContains(out, "complete -o default -F __start_myapp myapp");
    TestHelper.checkStringOmits(out, "%[1]s");
}
