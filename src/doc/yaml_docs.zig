//! YAML doc generation. Maps from doc/yaml_docs.go
const std = @import("std");
const command_mod = @import("../command.zig");
const Command = command_mod.Command;
const util = @import("util.zig");

fn yamlQuote(w: *std.Io.Writer, s: []const u8) anyerror!void {
    try w.print("\"", .{});
    for (s) |c| {
        switch (c) {
            '"' => try w.print("\\\"", .{}),
            '\\' => try w.print("\\\\", .{}),
            '\n' => try w.print("\\n", .{}),
            '\r' => try w.print("\\r", .{}),
            '\t' => try w.print("\\t", .{}),
            else => try w.print("{c}", .{c}),
        }
    }
    try w.print("\"", .{});
}

fn printFlagOptions(w: *std.Io.Writer, header: []const u8, fs: ?*command_mod.pflag.FlagSet) anyerror!void {
    const f = fs orelse return;
    if (!util.hasAvailableFlags(f)) return;
    try w.print("{s}:\n", .{header});
    for (f.ordered_formal.items) |flag| {
        if (flag.hidden) continue;
        try w.print("    - name: {s}\n", .{flag.name});
        if (flag.shorthand.len > 0) {
            try w.print("      shorthand: ", .{});
            try yamlQuote(w, flag.shorthand);
            try w.print("\n", .{});
        }
        if (flag.usage.len > 0) {
            try w.print("      usage: ", .{});
            try yamlQuote(w, flag.usage);
            try w.print("\n", .{});
        }
        try w.print("      default_value: ", .{});
        try yamlQuote(w, flag.def_value);
        try w.print("\n", .{});
    }
}

/// genYaml creates yaml output (Go: GenYaml).
pub fn genYaml(gpa: std.mem.Allocator, cmd: *Command, io: std.Io, w: *std.Io.Writer) anyerror!void {
    return genYamlCustom(gpa, cmd, io, w, null);
}

/// genYamlCustom creates yaml output with an optional link handler.
/// The handler receives the referenced documentation filename.
pub fn genYamlCustom(
    gpa: std.mem.Allocator,
    cmd: *Command,
    io: std.Io,
    w: *std.Io.Writer,
    link_handler: ?*const fn (ctx: ?*anyopaque, name: []const u8) []const u8,
) anyerror!void {
    _ = link_handler;
    _ = io;
    cmd.initDefaultHelpCmd(gpa);
    cmd.initDefaultHelpFlag(gpa);
    cmd.mergePersistentFlags(gpa);

    try w.print("name: {s}\n", .{cmd.commandPath()});

    if (cmd.short.len > 0) {
        try w.print("synopsis: ", .{});
        try yamlQuote(w, util.trimTrailingWhitespaces(cmd.short));
        try w.print("\n", .{});
    }
    if (cmd.long.len > 0) {
        try w.print("description: ", .{});
        try yamlQuote(w, util.trimTrailingWhitespaces(cmd.long));
        try w.print("\n", .{});
    }
    if (cmd.runnable()) {
        try w.print("usage: ", .{});
        try yamlQuote(w, cmd.useLine());
        try w.print("\n", .{});
    }

    try printFlagOptions(w, "options", cmd.localFlagsView());
    try printFlagOptions(w, "inherited_options", cmd.inheritedFlagsView());

    if (cmd.example.len > 0) {
        try w.print("example: ", .{});
        try yamlQuote(w, cmd.example);
        try w.print("\n", .{});
    }

    // SEE ALSO
    var has_also = cmd.parent != null;
    if (!has_also) {
        for (cmd.commands.items) |c| {
            if (c.isAvailableCommand() or c.isAdditionalHelpTopicCommand()) {
                has_also = true;
                break;
            }
        }
    }
    if (has_also) {
        try w.print("see_also:\n", .{});
        if (cmd.parent) |parent| {
            try w.print("    - ", .{});
            try yamlQuote(w, parent.commandPath());
            try w.print("\n", .{});
        }
        for (cmd.getCommands()) |child| {
            if (!child.isAvailableCommand() and !child.isAdditionalHelpTopicCommand()) continue;
            try w.print("    - ", .{});
            try yamlQuote(w, child.commandPath());
            try w.print("\n", .{});
        }
    }
}

/// genYamlTree creates yaml ref files for cmd and all descendants (Go: GenYamlTree).
pub fn genYamlTree(gpa: std.mem.Allocator, cmd: *Command, io: std.Io, dir: []const u8) anyerror!void {
    for (cmd.getCommands()) |c| {
        if (!c.isAvailableCommand() or c.isAdditionalHelpTopicCommand()) continue;
        try genYamlTree(gpa, c, io, dir);
    }

    var name_buf: [512]u8 = undefined;
    const basename = util.docFilename(cmd, ".yaml", &name_buf);
    var path_buf: [1024]u8 = undefined;
    var pw = std.Io.Writer.fixed(&path_buf);
    if (dir.len > 0) {
        try pw.print("{s}", .{dir});
        if (!std.mem.endsWith(u8, dir, "/")) try pw.print("/", .{});
    }
    try pw.print("{s}", .{basename});

    const file = try std.Io.Dir.cwd().createFile(io, path_buf[0..pw.end], .{});
    var fbuf: [8192]u8 = undefined;
    var file_writer = std.Io.File.Writer.init(file, io, &fbuf);
    try genYaml(gpa, cmd, io, &file_writer.interface);
    try file_writer.flush();
    file.close(io);
}

pub const genYamlTreeCustom = genYamlTree;
