//! Shared test helpers
const std = @import("std");
const Command = @import("command.zig").Command;

pub const TestOutput = struct {
    output: []const u8,
    err: ?anyerror,
};

pub const TestOutputC = struct {
    cmd: *Command,
    output: []const u8,
    err: ?anyerror,
};

pub fn executeCommand(gpa: std.mem.Allocator, root: *Command, args: []const []const u8) !TestOutput {
    const result = executeCommandC(gpa, root, args);
    return .{ .output = result.output, .err = result.err };
}

pub fn executeCommandC(gpa: std.mem.Allocator, root: *Command, args: []const []const u8) TestOutputC {
    var buf: [16384]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    var test_reader = std.Io.Reader.fixed("");

    root.setOut(&writer);
    root.setErr(&writer);
    root.setIn(&test_reader);
    root.setArgs(args);

    var err: ?anyerror = null;
    root.executeWrapper(gpa) catch |e| {
        err = e;
    };
    const output = std.Io.Writer.buffered(&writer);

    return .{
        .cmd = root,
        .output = output,
        .err = err,
    };
}

pub fn checkStringContains(got: []const u8, expected: []const u8) void {
    if (std.mem.indexOf(u8, got, expected) == null) {
        std.testing.failPrint("expected to contain: \"{s}\"\ngot: \"{s}\"", .{ expected, got });
    }
}

pub fn checkStringOmits(got: []const u8, expected: []const u8) void {
    if (std.mem.indexOf(u8, got, expected) != null) {
        std.testing.failPrint("expected NOT to contain: \"{s}\"\ngot: \"{s}\"", .{ expected, got });
    }
}

pub fn assertNoErr(e: anyerror!void) void {
    e catch |err| {
        std.testing.failPrint("Unexpected error: {s}", .{@errorName(err)});
    };
}

pub fn makeCommand(use: []const u8, run_fn: ?*const fn (*Command, [][]const u8) void) Command {
    return .{ .use = use, .run = run_fn };
}

pub fn emptyRun(cmd: *Command, args: [][]const u8) void {
    _ = cmd;
    _ = args;
}
