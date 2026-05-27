//! ReST doc generation. Maps from doc/rest_docs.go
const std = @import("std");
const Command = @import("../command.zig").Command;
const util = @import("util.zig");

pub fn genReST(cmd: *Command, io: std.Io, writer: *std.Io.Writer) anyerror!void {
    _ = cmd;
    _ = io;
    _ = writer;
}
pub fn genReSTCustom(cmd: *Command, io: std.Io, writer: *std.Io.Writer, link_handler: anytype) anyerror!void {
    _ = cmd;
    _ = io;
    _ = writer;
    _ = link_handler;
}
pub fn genReSTTree(cmd: *Command, io: std.Io, dir: []const u8) anyerror!void {
    _ = cmd;
    _ = io;
    _ = dir;
}
pub fn genReSTTreeCustom(cmd: *Command, io: std.Io, dir: []const u8, file_prepender: anytype, link_handler: anytype) anyerror!void {
    _ = cmd;
    _ = io;
    _ = dir;
    _ = file_prepender;
    _ = link_handler;
}
