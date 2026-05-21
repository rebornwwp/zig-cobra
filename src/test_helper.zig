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
    _ = gpa;
    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    var test_reader = std.Io.Reader.fixed("");

    root.setOut(&writer);
    root.setErr(&writer);
    root.setIn(&test_reader);
    root.setArgs(args);

    root.executeWrapper() catch {};
    const output = std.Io.Writer.buffered(&writer);

    return .{
        .cmd = root,
        .output = output,
        .err = null,
    };
}

pub fn checkStringContains(t: *std.testing.T, got: []const u8, expected: []const u8) void {
    if (!std.mem.indexOf(u8, got, expected)) {
        t.fail("expected to contain: \"{s}\"\ngot: \"{s}\"", .{ expected, got });
    }
}

pub fn checkStringOmits(t: *std.testing.T, got: []const u8, expected: []const u8) void {
    if (std.mem.indexOf(u8, got, expected)) |_| {
        t.fail("expected NOT to contain: \"{s}\"\ngot: \"{s}\"", .{ expected, got });
    }
}

pub fn assertNoErr(t: *std.testing.T, e: anyerror!void) void {
    e catch |err| {
        t.fail("Unexpected error: {}", .{err});
    };
}

pub fn makeCommand(use: []const u8, run_fn: ?*const fn (*Command, [][]const u8) void) Command {
    return .{ .use = use, .run = run_fn };
}

pub fn emptyRun(cmd: *Command, args: [][]const u8) void {
    _ = cmd;
    _ = args;
}
