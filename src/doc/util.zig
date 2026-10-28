//! Doc utilities. Maps from doc/util.go
const std = @import("std");
const command_mod = @import("../command.zig");
const Command = command_mod.Command;
const pflag = command_mod.pflag;

/// hasSeeAlso determines if a command has parent commands OR subcommands that
/// should appear under a "SEE ALSO" section.
pub fn hasSeeAlso(cmd: *const Command) bool {
    if (cmd.hasParent()) return true;
    for (cmd.commands.items) |c| {
        if (!c.isAvailableCommand() and !c.isAdditionalHelpTopicCommand()) continue;
        return true;
    }
    return false;
}

/// forceMultiLine appends a newline to long single-line strings (Go: forceMultiLine).
/// Returns an allocated copy when modified; caller frees with gpa.
pub fn forceMultiLine(gpa: std.mem.Allocator, s: []const u8) ![]const u8 {
    if (s.len > 60 and std.mem.indexOfScalar(u8, s, '\n') == null) {
        const result = try gpa.alloc(u8, s.len + 1);
        @memcpy(result[0..s.len], s);
        result[s.len] = '\n';
        return result;
    }
    return s;
}

pub fn lessThanByName(_: void, a: *Command, b: *Command) bool {
    return std.ascii.lessThanIgnoreCase(a.name(), b.name());
}

/// Renders a flag set's defaults into w (Go: flags.PrintDefaults()).
pub fn writeFlagUsages(w: *std.Io.Writer, fs: ?*pflag.FlagSet) void {
    const f = fs orelse return;
    if (f.ordered_formal.items.len == 0) return;
    var has_visible = false;
    for (f.ordered_formal.items) |flag| {
        if (!flag.hidden) {
            has_visible = true;
            break;
        }
    }
    if (!has_visible) return;
    const saved = f.out_writer;
    f.out_writer = w;
    f.printDefaults();
    f.out_writer = saved;
}

/// True when the set has at least one non-hidden flag.
pub fn hasAvailableFlags(fs: ?*pflag.FlagSet) bool {
    const f = fs orelse return false;
    for (f.ordered_formal.items) |flag| {
        if (!flag.hidden) return true;
    }
    return false;
}

/// Builds the documentation filename for a command: its full path with spaces
/// replaced by underscores, plus the given extension. Rendered into `buf`.
pub fn docFilename(cmd: *Command, extension: []const u8, buf: []u8) []const u8 {
    var w = std.Io.Writer.fixed(buf);
    const path = cmd.commandPath();
    for (path) |c| {
        if (c == ' ') {
            w.print("_", .{}) catch {};
        } else {
            w.print("{c}", .{c}) catch {};
        }
    }
    w.print("{s}", .{extension}) catch {};
    return buf[0..w.end];
}

/// Same as docFilename but without an extension (used by ReST refs).
pub fn docFilenameSansExt(cmd: *Command, buf: []u8) []const u8 {
    return docFilename(cmd, "", buf);
}

/// Trims trailing whitespace (std.mem.trimRight was removed in Zig 0.17).
pub fn trimTrailingWhitespaces(s: []const u8) []const u8 {
    var end = s.len;
    while (end > 0) {
        const c = s[end - 1];
        if (c != ' ' and c != '\t' and c != '\n' and c != '\r') break;
        end -= 1;
    }
    return s[0..end];
}
