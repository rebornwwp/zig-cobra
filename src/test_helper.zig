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

/// Static storage for captured output. executeCommandC previously returned a slice
/// into a stack-local buffer — dangling as soon as it returned, which made string
/// assertions flaky. Tests run sequentially, so module-scope storage is safe;
/// each executeCommandC call resets it.
var out_buf: [16384]u8 = undefined;
var out_writer: std.Io.Writer = undefined;
var in_reader: std.Io.Reader = undefined;

pub fn executeCommand(gpa: std.mem.Allocator, root: *Command, args: []const []const u8) !TestOutput {
    const result = executeCommandC(gpa, root, args);
    return .{ .output = result.output, .err = result.err };
}

pub fn executeCommandC(gpa: std.mem.Allocator, root: *Command, args: []const []const u8) TestOutputC {
    out_writer = std.Io.Writer.fixed(&out_buf);
    in_reader = std.Io.Reader.fixed("");

    root.setOut(&out_writer);
    root.setErr(&out_writer);
    root.setIn(&in_reader);
    root.setArgs(args);

    var err: ?anyerror = null;
    root.executeWrapper(gpa) catch |e| {
        err = e;
    };
    const output = std.Io.Writer.buffered(&out_writer);

    return .{
        .cmd = root,
        .output = output,
        .err = err,
    };
}

/// NOTE: std.testing.failPrint is print-only (void) in Zig 0.17 — helpers MUST
/// return an error for the test to actually fail. Call sites use `try`.
pub fn checkStringContains(got: []const u8, expected: []const u8) !void {
    if (std.mem.indexOf(u8, got, expected) == null) {
        std.testing.failPrint("expected to contain: \"{s}\"\ngot: \"{s}\"", .{ expected, got });
        return error.TestFailed;
    }
}

pub fn checkStringOmits(got: []const u8, expected: []const u8) !void {
    if (std.mem.indexOf(u8, got, expected) != null) {
        std.testing.failPrint("expected NOT to contain: \"{s}\"\ngot: \"{s}\"", .{ expected, got });
        return error.TestFailed;
    }
}

pub fn assertNoErr(e: anyerror!void) !void {
    e catch |err| {
        std.testing.failPrint("Unexpected error: {s}", .{@errorName(err)});
        return err;
    };
}

pub fn makeCommand(use: []const u8, run_fn: ?*const fn (*Command, [][]const u8) void) Command {
    return .{ .use = use, .run = run_fn };
}

pub fn emptyRun(cmd: *Command, args: [][]const u8) void {
    _ = cmd;
    _ = args;
}
