//! YAML doc generation. Maps from doc/yaml_docs.go
const std = @import("std");
const command_mod = @import("../command.zig");
const Command = command_mod.Command;
const util = @import("util.zig");

fn yamlQuote(w: *std.Io.Writer, s: []const u8) void {
    w.print("\"", .{}) catch {};
    for (s) |c| {
        switch (c) {
            '"' => w.print("\\\"", .{}) catch {},
            '\\' => w.print("\\\\", .{}) catch {},
            '\n' => w.print("\\n", .{}) catch {},
            '\r' => w.print("\\r", .{}) catch {},
            '\t' => w.print("\\t", .{}) catch {},
            else => w.print("{c}", .{c}) catch {},
        }
    }
    w.print("\"", .{}) catch {};
}

fn printFlagOptions(w: *std.Io.Writer, header: []const u8, fs: ?*command_mod.pflag.FlagSet) void {
    const f = fs orelse return;
    if (!util.hasAvailableFlags(f)) return;
    w.print("{s}:\n", .{header}) catch {};
    for (f.ordered_formal.items) |flag| {
        if (flag.hidden) continue;
        w.print("    - name: {s}\n", .{flag.name}) catch {};
        if (flag.shorthand.len > 0) {
            w.print("      shorthand: ", .{}) catch {};
            yamlQuote(w, flag.shorthand);
            w.print("\n", .{}) catch {};
        }
        if (flag.usage.len > 0) {
            w.print("      usage: ", .{}) catch {};
            yamlQuote(w, flag.usage);
            w.print("\n", .{}) catch {};
        }
        w.print("      default_value: ", .{}) catch {};
        yamlQuote(w, flag.def_value);
        w.print("\n", .{}) catch {};
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

    w.print("name: {s}\n", .{cmd.commandPath()}) catch {};

    if (cmd.short.len > 0) {
        w.print("synopsis: ", .{}) catch {};
        yamlQuote(w, util.trimTrailingWhitespaces(cmd.short));
        w.print("\n", .{}) catch {};
    }
    if (cmd.long.len > 0) {
        w.print("description: ", .{}) catch {};
        yamlQuote(w, util.trimTrailingWhitespaces(cmd.long));
        w.print("\n", .{}) catch {};
    }
    if (cmd.runnable()) {
        w.print("usage: ", .{}) catch {};
        yamlQuote(w, cmd.useLine());
        w.print("\n", .{}) catch {};
    }

    printFlagOptions(w, "options", cmd.localFlagsView());
    printFlagOptions(w, "inherited_options", cmd.inheritedFlagsView());

    if (cmd.example.len > 0) {
        w.print("example: ", .{}) catch {};
        yamlQuote(w, cmd.example);
        w.print("\n", .{}) catch {};
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
        w.print("see_also:\n", .{}) catch {};
        if (cmd.parent) |parent| {
            w.print("    - ", .{}) catch {};
            yamlQuote(w, parent.commandPath());
            w.print("\n", .{}) catch {};
        }
        for (cmd.getCommands()) |child| {
            if (!child.isAvailableCommand() and !child.isAdditionalHelpTopicCommand()) continue;
            w.print("    - ", .{}) catch {};
            yamlQuote(w, child.commandPath());
            w.print("\n", .{}) catch {};
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
        pw.print("{s}", .{dir}) catch {};
        if (!std.mem.endsWith(u8, dir, "/")) pw.print("/", .{}) catch {};
    }
    pw.print("{s}", .{basename}) catch {};

    const file = try std.Io.Dir.cwd().createFile(io, path_buf[0..pw.end], .{});
    var fbuf: [8192]u8 = undefined;
    var file_writer = std.Io.File.Writer.init(file, io, &fbuf);
    try genYaml(gpa, cmd, io, &file_writer.interface);
    try file_writer.flush();
    file.close(io);
}

pub const genYamlTreeCustom = genYamlTree;
