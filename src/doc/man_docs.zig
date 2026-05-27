//! Man page generation. Maps from doc/man_docs.go
const std = @import("std");
const Command = @import("../command.zig").Command;
const util = @import("util.zig");

pub const GenManHeader = struct {
    title: []const u8 = "",
    section: []const u8 = "",
    date: ?std.time.Instant = null,
    source: []const u8 = "",
    manual: []const u8 = "",
};

pub fn genMan(cmd: *Command, io: std.Io, header: ?*GenManHeader, writer: *std.Io.Writer) anyerror!void {
    _ = cmd;
    _ = io;
    _ = header;
    _ = writer;
}
pub fn genManTree(cmd: *Command, io: std.Io, header: ?*GenManHeader, dir: []const u8) anyerror!void {
    _ = cmd;
    _ = io;
    _ = header;
    _ = dir;
}
