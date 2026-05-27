//! Markdown doc generation. Maps from doc/md_docs.go
const std = @import("std");
const Command = @import("../command.zig").Command;
const util = @import("util.zig");

pub fn genMarkdown(cmd: *Command, io: std.Io, writer: *std.Io.Writer) anyerror!void {
    return genMarkdownCustom(cmd, io, writer, struct {
        fn inner(s: []const u8) []const u8 {
            return s;
        }
    }.inner);
}

pub fn genMarkdownCustom(cmd: *Command, io: std.Io, writer: *std.Io.Writer, link_handler: anytype) anyerror!void {
    try writer.interface.print("## {s}\n\n", .{cmd.commandPath()});
    try writer.interface.print("{s}\n\n", .{cmd.short});
    if (cmd.long.len > 0) try writer.interface.print("### Synopsis\n\n{s}\n\n", .{cmd.long});
    if (cmd.runnable()) try writer.interface.print("```\n{s}\n```\n\n", .{cmd.use});
    if (cmd.hasExample()) try writer.interface.print("### Examples\n\n```\n{s}\n```\n\n", .{cmd.example});
    if (util.hasSeeAlso(cmd)) try writer.interface.print("### SEE ALSO\n\n", .{});
}

pub fn genMarkdownTree(cmd: *Command, io: std.Io, dir: []const u8) anyerror!void {
    _ = cmd;
    _ = io;
    _ = dir;
}
pub fn genMarkdownTreeCustom(cmd: *Command, io: std.Io, dir: []const u8, file_prepender: anytype, link_handler: anytype) anyerror!void {
    _ = cmd;
    _ = io;
    _ = dir;
    _ = file_prepender;
    _ = link_handler;
}
