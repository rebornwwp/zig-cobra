//! Shell completion flag marking. Maps from cobra/shell_completions.go
//!
//! Flags are annotated with completion semantics via pflag annotations.
//! All functions return error.NoSuchFlag when the named flag does not exist
//! (Go returns an error / panics in the same situations).
const std = @import("std");
const command_mod = @import("command.zig");
const Command = command_mod.Command;
const completions_mod = @import("completions.zig");

/// Resolves the flagset (local or persistent) that owns `name` on this command.
fn localOrPersistentSet(self: *Command, name: []const u8, persistent: bool) ?*command_mod.pflag.FlagSet {
    if (persistent) return self.pflags;
    if (self.flags_ptr) |fs| {
        if (fs.lookup(name) != null) return fs;
    }
    if (self.pflags) |pf| {
        if (pf.lookup(name) != null) return pf;
    }
    return null;
}

/// Mark a flag as required: cobra errors when the command is invoked without it,
/// and completion scripts prioritize suggesting it (Go: MarkFlagRequired).
pub fn markFlagRequired(self: *Command, gpa: std.mem.Allocator, name: []const u8) anyerror!void {
    self.mergePersistentFlags(gpa);
    const fs = localOrPersistentSet(self, name, false) orelse return error.NoSuchFlag;
    return fs.setAnnotation(name, completions_mod.bash_comp_one_required_flag, &.{"true"});
}

/// Mark a persistent flag as required (Go: MarkPersistentFlagRequired).
pub fn markPersistentFlagRequired(self: *Command, gpa: std.mem.Allocator, name: []const u8) anyerror!void {
    self.mergePersistentFlags(gpa);
    const fs = self.pflags orelse return error.NoSuchFlag;
    return fs.setAnnotation(name, completions_mod.bash_comp_one_required_flag, &.{"true"});
}

/// Mark a flag's value as filename(s), optionally restricted to the given
/// extensions (Go: MarkFlagFilename). `extensions` must outlive the command.
pub fn markFlagFilename(self: *Command, gpa: std.mem.Allocator, name: []const u8, extensions: []const []const u8) anyerror!void {
    self.mergePersistentFlags(gpa);
    const fs = localOrPersistentSet(self, name, false) orelse return error.NoSuchFlag;
    return fs.setAnnotation(name, completions_mod.bash_comp_filename_ext, extensions);
}

/// Mark a persistent flag's value as filename(s) (Go: MarkPersistentFlagFilename).
pub fn markPersistentFlagFilename(self: *Command, gpa: std.mem.Allocator, name: []const u8, extensions: []const []const u8) anyerror!void {
    self.mergePersistentFlags(gpa);
    const fs = self.pflags orelse return error.NoSuchFlag;
    return fs.setAnnotation(name, completions_mod.bash_comp_filename_ext, extensions);
}

/// Mark a flag with a custom bash completion function (Go: MarkFlagCustom — bash V1 only;
/// prefer registerFlagCompletionFunc which works across all shells).
pub fn markFlagCustom(self: *Command, gpa: std.mem.Allocator, name: []const u8, f: []const u8) anyerror!void {
    self.mergePersistentFlags(gpa);
    const fs = localOrPersistentSet(self, name, false) orelse return error.NoSuchFlag;
    const values = try gpa.alloc([]const u8, 1);
    values[0] = f;
    try fs.setAnnotation(name, completions_mod.bash_comp_custom, values);
    self.owned_annotation_values.append(gpa, values) catch {};
}

/// Mark a flag's value as a directory name (Go: MarkFlagDirname).
pub fn markFlagDirname(self: *Command, gpa: std.mem.Allocator, name: []const u8, dirname: []const u8) anyerror!void {
    self.mergePersistentFlags(gpa);
    const fs = localOrPersistentSet(self, name, false) orelse return error.NoSuchFlag;
    if (dirname.len == 0) {
        return fs.setAnnotation(name, completions_mod.bash_comp_subdirs_in_dir, &.{});
    }
    return fs.setAnnotation(name, completions_mod.bash_comp_subdirs_in_dir, &.{dirname});
}

/// Mark a persistent flag's value as a directory name (Go: MarkPersistentFlagDirname).
pub fn markPersistentFlagDirname(self: *Command, gpa: std.mem.Allocator, name: []const u8, dirname: []const u8) anyerror!void {
    self.mergePersistentFlags(gpa);
    const fs = self.pflags orelse return error.NoSuchFlag;
    if (dirname.len == 0) {
        return fs.setAnnotation(name, completions_mod.bash_comp_subdirs_in_dir, &.{});
    }
    return fs.setAnnotation(name, completions_mod.bash_comp_subdirs_in_dir, &.{dirname});
}
