//! Shell completion types and logic. Maps from cobra/completions.go (spf13/cobra v1.10+).
//!
//! Completion strings follow the Go format: either the bare choice, or
//! "choice<TAB>description" (see completionWithDesc).
const std = @import("std");
const command_mod = @import("command.zig");
const Command = command_mod.Command;
const pflag = command_mod.pflag;
const templates = @import("completions_templates.zig");
const active_help = @import("active_help.zig");

/// Command name used by the shell to request completions
pub const shell_comp_request_cmd = "__complete";
/// Command name (alias) used to request completions without descriptions
pub const shell_comp_no_desc_request_cmd = "__completeNoDesc";
/// Name of the generated `completion` command
pub const completion_command_name = "completion";
/// `--no-descriptions` flag on completion subcommands
pub const comp_cmd_no_desc_flag_name = "no-descriptions";
pub const comp_cmd_no_desc_flag_desc = "disable completion descriptions";
pub const comp_cmd_no_desc_flag_default = false;
/// Suffix for the COMPLETION_DESCRIPTIONS env config var
pub const config_env_var_suffix_descriptions = "COMPLETION_DESCRIPTIONS";

// Annotation keys (Go: bash_completions.go)
pub const bash_comp_filename_ext = "__cobra_bash_comp_filename_ext";
pub const bash_comp_custom = "__cobra_bash_comp_custom";
pub const bash_comp_one_required_flag = command_mod.bash_comp_one_required_flag;
pub const bash_comp_subdirs_in_dir = "__cobra_bash_comp_subdirs_in_dir";

/// A single completion item (Go: `type Completion = string`).
/// Two formats: "choice" or "choice<TAB>description".
pub const Completion = []const u8;

/// Return type for CompletionFunc: completion list + directive.
pub const CompResult = struct {
    completions: []const Completion = &.{},
    directive: ShellCompDirective = .{},
};

/// Completion function (Go: `func(cmd, args, toComplete) ([]Completion, ShellCompDirective)`).
/// Zig equivalent of a Go closure: a function pointer plus an optional context pointer.
pub const CompletionFunc = struct {
    ctx: ?*anyopaque = null,
    call: *const fn (
        ctx: ?*anyopaque,
        cmd: *Command,
        args: [][]const u8,
        to_complete: []const u8,
    ) anyerror!CompResult,

    pub fn invoke(self: CompletionFunc, cmd: *Command, args: [][]const u8, to_complete: []const u8) anyerror!CompResult {
        return self.call(self.ctx, cmd, args, to_complete);
    }
};

/// Configuration for shell completion behavior.
pub const CompletionOptions = struct {
    /// Disable creation of the default `completion` command
    disable_default_cmd: bool = false,
    /// Disable creation of the `--no-descriptions` flag on completion subcommands
    disable_no_desc_flag: bool = false,
    /// Turn off all completion descriptions
    disable_descriptions: bool = false,
    /// Hide the default `completion` command
    hidden_default_cmd: bool = false,
    /// Default ShellCompDirective (null means use the zero directive)
    default_shell_comp_directive: ?ShellCompDirective = null,
};

/// Shell completion directive: controls the shell's behavior after a completion.
/// Bit values match Go's ShellCompDirective constants exactly.
pub const ShellCompDirective = packed struct(u8) {
    /// Indicates a completion error occurred
    e: bool = false,
    /// Do not append a space after the completion
    nospace: bool = false,
    /// Disable file completion fallback
    nofilecomp: bool = false,
    /// Completions are file extensions to filter by
    filterfile: bool = false,
    /// Filter to directories only
    filterdirs: bool = false,
    /// Preserve the order of provided completions (don't sort)
    keeporder: bool = false,
    _: u2 = 0,

    pub const error_flag = ShellCompDirective{ .e = true };
    pub const no_space = ShellCompDirective{ .nospace = true };
    pub const no_file_comp = ShellCompDirective{ .nofilecomp = true };
    pub const filter_file_ext = ShellCompDirective{ .filterfile = true };
    pub const filter_dirs = ShellCompDirective{ .filterdirs = true };
    pub const keep_order = ShellCompDirective{ .keeporder = true };
    pub const default = ShellCompDirective{};

    /// Integer wire value (matches Go's directive ints).
    pub fn toInt(self: ShellCompDirective) u8 {
        return @bitCast(self);
    }

    /// Human-readable names (Go: ShellCompDirective.string()). Rendered into `buf`.
    pub fn string(self: ShellCompDirective, buf: []u8) []const u8 {
        var w = std.Io.Writer.fixed(buf);
        var any = false;
        const names = [_]struct { bit: bool, name: []const u8 }{
            .{ .bit = self.e, .name = "ShellCompDirectiveError" },
            .{ .bit = self.nospace, .name = "ShellCompDirectiveNoSpace" },
            .{ .bit = self.nofilecomp, .name = "ShellCompDirectiveNoFileComp" },
            .{ .bit = self.filterfile, .name = "ShellCompDirectiveFilterFileExt" },
            .{ .bit = self.filterdirs, .name = "ShellCompDirectiveFilterDirs" },
            .{ .bit = self.keeporder, .name = "ShellCompDirectiveKeepOrder" },
        };
        for (names) |n| {
            if (!n.bit) continue;
            if (any) w.print(", ", .{}) catch {};
            w.print("{s}", .{n.name}) catch {};
            any = true;
        }
        if (!any) {
            w.print("ShellCompDirectiveDefault", .{}) catch {};
        }
        return buf[0..w.end];
    }
};

/// Builds a completion string with a TAB-separated description (Go: CompletionWithDesc).
/// The returned slice is allocated with `gpa`; caller owns it.
pub fn completionWithDesc(gpa: std.mem.Allocator, choice: []const u8, description: []const u8) !Completion {
    const out = try gpa.alloc(u8, choice.len + 1 + description.len);
    @memcpy(out[0..choice.len], choice);
    out[choice.len] = '\t';
    @memcpy(out[choice.len + 1 ..], description);
    return out;
}

/// Completion function that returns no completions and disables file fallback.
pub fn noFileCompletions() CompletionFunc {
    const S = struct {
        fn call(_: ?*anyopaque, _: *Command, _: [][]const u8, _: []const u8) anyerror!CompResult {
            return .{ .completions = &.{}, .directive = .no_file_comp };
        }
    };
    return .{ .call = S.call };
}

/// Builds a completion function returning a fixed choice list (Go: FixedCompletions).
/// `choices` and `directive` must be comptime-known (typical for static lists).
pub fn fixedCompletions(comptime choices: []const Completion, comptime directive: ShellCompDirective) CompletionFunc {
    const S = struct {
        fn call(_: ?*anyopaque, _: *Command, _: [][]const u8, _: []const u8) anyerror!CompResult {
            return .{ .completions = choices, .directive = directive };
        }
    };
    return .{ .call = S.call };
}

/// Debug logging for completion scripts (Go: CompDebug). Writes to stderr when
/// BASH_COMP_DEBUG_FILE-style debugging is enabled; otherwise a no-op.
pub fn compDebug(_: std.Io, msg: []const u8, print_to_stderr: bool) void {
    if (print_to_stderr) {
        std.debug.print("[Debug] {s}", .{msg});
    }
}
pub fn compDebugln(io: std.Io, msg: []const u8, print_to_stderr: bool) void {
    compDebug(io, msg, print_to_stderr);
    if (print_to_stderr) std.debug.print("\n", .{});
}
/// Completion error output (Go: CompError / CompErrorln) — always to stderr.
pub fn compError(io: std.Io, msg: []const u8) void {
    const w = command_mod.defaultStderr(io);
    w.print("[Error] {s}", .{msg}) catch {};
    w.flush() catch {};
}
pub fn compErrorln(io: std.Io, msg: []const u8) void {
    const w = command_mod.defaultStderr(io);
    w.print("[Error] {s}\n", .{msg}) catch {};
    w.flush() catch {};
}

// ─────────────────────────────────────────────────────────────────────────────
// __complete machinery (Go: getCompletions and friends)
// ─────────────────────────────────────────────────────────────────────────────

const FlagCompletionCheck = struct {
    flag: ?*pflag.Flag = null,
    args: []const []const u8,
    to_complete: []const u8,
    err: ?anyerror = null,
};

fn nonCompletableFlag(flag: *const pflag.Flag) bool {
    return flag.hidden or flag.deprecated.len > 0;
}

fn flagAcceptsMultiple(flag: *const pflag.Flag) bool {
    const tn = flag.value.typeName();
    if (std.mem.indexOf(u8, tn, "Slice") != null) return true;
    if (std.mem.indexOf(u8, tn, "Array") != null) return true;
    if (std.mem.startsWith(u8, tn, "stringTo")) return true;
    return false;
}

/// Go: helpOrVersionFlagPresent — only considers flags registered by cobra itself.
fn helpOrVersionFlagPresent(cmd: *Command) bool {
    const fs = cmd.flags_ptr orelse return false;
    const names = [_][]const u8{ "version", command_mod.help_flag_name };
    for (names) |n| {
        const f = fs.lookup(n) orelse continue;
        const ann = f.annotations.get(command_mod.FlagSetByCobraAnnotation) orelse continue;
        if (ann.len > 0 and f.changed) return true;
    }
    return false;
}

/// Go: findFlag — resolves a (possibly shorthand) flag name across local+inherited sets.
fn findFlagCmd(cmd: *Command, gpa: std.mem.Allocator, flag_name: []const u8) ?*pflag.Flag {
    cmd.mergePersistentFlags(gpa);
    var resolved: []const u8 = flag_name;
    if (flag_name.len == 1) {
        var ok = false;
        if (cmd.flags_ptr) |fs| {
            if (fs.shorthandLookup(flag_name[0])) |f| {
                resolved = f.name;
                ok = true;
            }
        }
        if (!ok) {
            if (cmd.iflags) |inh| {
                if (inh.shorthandLookup(flag_name[0])) |f| {
                    resolved = f.name;
                    ok = true;
                }
            }
        }
        if (!ok) return null;
    }
    return cmd.flag(resolved);
}

/// Go: checkIfFlagCompletion — determines whether toComplete is a flag VALUE completion.
fn checkIfFlagCompletion(final_cmd: *Command, gpa: std.mem.Allocator, args: []const []const u8, last_arg: []const u8) FlagCompletionCheck {
    if (final_cmd.disable_flag_parsing) {
        // The command wants to handle completion of all flags itself.
        return .{ .args = args, .to_complete = last_arg };
    }

    var flag_name: []const u8 = "";
    var trimmed_args = args;
    var new_last = last_arg;
    var flag_with_equal = false;
    const org_last_arg = last_arg;

    if (new_last.len > 0 and new_last[0] == '-') {
        if (std.mem.indexOfScalar(u8, new_last, '=')) |idx| {
            if (std.mem.startsWith(u8, new_last[0..idx], "--")) {
                flag_name = new_last[2..idx];
            } else if (idx > 0) {
                // Shorthand group: the LAST char is the flag whose value we complete.
                flag_name = new_last[idx - 1 .. idx];
            }
            new_last = new_last[idx + 1 ..];
            flag_with_equal = true;
        }
    }

    if (flag_name.len == 0 and args.len > 0) {
        const prev_arg = args[args.len - 1];
        if (Command.isFlagArg(prev_arg) and std.mem.indexOfScalar(u8, prev_arg, '=') == null) {
            if (std.mem.startsWith(u8, prev_arg, "--")) {
                flag_name = prev_arg[2..];
            } else {
                flag_name = prev_arg[prev_arg.len - 1 ..];
            }
            // Drop the incomplete flag token so parsing doesn't fail on it.
            trimmed_args = args[0 .. args.len - 1];
        }
    }

    if (flag_name.len == 0) {
        // Not completing a flag value.
        return .{ .args = trimmed_args, .to_complete = new_last };
    }

    const flag = findFlagCmd(final_cmd, gpa, flag_name) orelse {
        // Unknown flag: callers may ignore this (like Go's flagCompError).
        return .{ .args = args, .to_complete = org_last_arg, .err = error.FlagCompError };
    };

    if (!flag_with_equal and flag.no_opt_def_val.len != 0) {
        // Two-word boolean flag: there is no value to complete; reset to noun completion.
        return .{ .args = args, .to_complete = org_last_arg };
    }

    return .{ .flag = flag, .args = trimmed_args, .to_complete = new_last };
}

/// Go: getFlagNameCompletions — "--name<TAB>usage" / "-x<TAB>usage" matches.
fn getFlagNameCompletions(gpa: std.mem.Allocator, list: *std.ArrayListUnmanaged(Completion), flag: *pflag.Flag, to_complete: []const u8) !void {
    if (nonCompletableFlag(flag)) return;

    if (std.mem.startsWith(u8, "--", to_complete) or to_complete.len == 0) {
        var buf = try gpa.alloc(u8, flag.name.len + 2);
        buf[0] = '-';
        buf[1] = '-';
        @memcpy(buf[2..], flag.name);
        try list.append(gpa, try completionWithDesc(gpa, buf, flag.usage));
    }
    if (flag.shorthand.len > 0) {
        const short_name = try gpa.alloc(u8, 2);
        short_name[0] = '-';
        short_name[1] = flag.shorthand[0];
        if (std.mem.startsWith(u8, short_name, to_complete) or to_complete.len == 0) {
            try list.append(gpa, try completionWithDesc(gpa, short_name, flag.usage));
        }
    }
}

/// Go: completeRequireFlags — suggests required-but-unset flags even without '-' prefix.
fn completeRequireFlags(gpa: std.mem.Allocator, list: *std.ArrayListUnmanaged(Completion), final_cmd: *Command, to_complete: []const u8) !void {
    const views = [_]?*pflag.FlagSet{ final_cmd.iflags, final_cmd.lflags };
    for (views) |maybe| {
        const fs = maybe orelse continue;
        for (fs.ordered_formal.items) |f| {
            const ann = f.annotations.get(bash_comp_one_required_flag) orelse continue;
            if (ann.len == 0) continue;
            if (f.changed) continue;
            try getFlagNameCompletions(gpa, list, f, to_complete);
        }
    }
}

fn findFlagCompletionFunc(cmd: *const Command, flag_name: []const u8) ?CompletionFunc {
    var c: ?*const Command = cmd;
    while (c) |cur| : (c = cur.parent) {
        if (cur.flag_completions.get(flag_name)) |f| return f;
    }
    return null;
}

fn printCompletions(
    io: std.Io,
    final_cmd: *Command,
    root_name: []const u8,
    comps: []const Completion,
    directive: ShellCompDirective,
    no_descriptions_requested: bool,
) void {
    var no_desc = no_descriptions_requested;
    var env_buf: [64]u8 = undefined;
    if (!no_desc) {
        if (active_help.getEnvConfig(root_name, config_env_var_suffix_descriptions, &env_buf)) |v| {
            no_desc = std.mem.eql(u8, v, "false") or std.mem.eql(u8, v, "0");
        }
    }

    const no_active_help = blk: {
        var ah_buf: [64]u8 = undefined;
        break :blk std.mem.eql(u8, active_help.getActiveHelpConfig(root_name, &ah_buf), active_help.active_help_global_disable);
    };

    const w = final_cmd.outOrStdout(io);
    for (comps) |comp| {
        var c = comp;
        if (no_active_help and std.mem.startsWith(u8, c, active_help.active_help_marker)) continue;
        if (no_desc) {
            if (std.mem.indexOfScalar(u8, c, '\t')) |idx| c = c[0..idx];
        }
        // Only the first line of a completion is emitted (a description could
        // otherwise inject newlines into the shell protocol).
        if (std.mem.indexOfScalar(u8, c, '\n')) |idx| c = c[0..idx];
        c = std.mem.trim(u8, c, " \t");
        w.print("{s}\n", .{c}) catch {};
    }
    // The directive must be the final line: ":<int>"
    w.print(":{d}\n", .{directive.toInt()}) catch {};
    w.flush() catch {};

    var dir_buf: [256]u8 = undefined;
    const we = final_cmd.errOrStderr(io);
    we.print("Completion ended with directive: {s}\n", .{directive.string(&dir_buf)}) catch {};
    we.flush() catch {};
}

/// Handles a `__complete` request (Go: getCompletions + the Run body of initCompleteCmd).
/// `args` are the raw command-line tokens; the last one is the word being completed.
/// Completion results and the final ":<directive>" line are written to stdout.
pub fn getCompletions(root_self: *Command, io: std.Io, gpa: std.mem.Allocator, args: [][]const u8, include_desc: bool) anyerror!void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const aa = arena.allocator();

    const root = root_self.root();
    const root_name = root.name();

    if (args.len == 0) {
        printCompletions(io, root, root_name, &.{}, .default, !include_desc);
        return;
    }

    const to_complete_raw = args[args.len - 1];
    const trimmed_args = args[0 .. args.len - 1];

    var completions: std.ArrayListUnmanaged(Completion) = .empty;
    var directive: ShellCompDirective = .default;

    // Find the real command for which completion is requested.
    // NOTE: find() persists flag views via `gpa` (must outlive the arena), so scratch
    // ownership comes back in found.owned_args and is freed explicitly here.
    const found = if (root.traverse_children) root.traverse(gpa, trimmed_args) else root.find(gpa, trimmed_args);
    defer if (found.owned_args) |a| gpa.free(a);
    const final_cmd = found.cmd;
    var final_args = found.args;
    if (found.err != null) {
        compErrorln(io, "unable to find a command for arguments");
        printCompletions(io, final_cmd, root_name, &.{}, .default, !include_desc);
        return;
    }

    if (!final_cmd.disable_flag_parsing) {
        final_cmd.initDefaultHelpFlag(gpa);
        final_cmd.initDefaultVersionFlag(gpa);
        final_cmd.mergePersistentFlags(gpa);
    }

    const fc = checkIfFlagCompletion(final_cmd, gpa, final_args, to_complete_raw);
    final_args = fc.args;
    const to_complete = fc.to_complete;

    // Detect interspersed '--' state (Go: parse args plus a trailing "--" and compare NArg).
    var flag_completion = true;
    if (!final_cmd.disable_flag_parsing) {
        const fs = final_cmd.flags_ptr orelse return;
        const with_dash = try aa.alloc([]const u8, final_args.len + 1);
        @memcpy(with_dash[0..final_args.len], final_args);
        with_dash[final_args.len] = "--";
        final_cmd.parseArgs(aa, with_dash) catch {};
        const new_arg_count = fs.nArg();
        final_cmd.parseArgs(aa, final_args) catch {
            compErrorln(io, "error while parsing flags");
            printCompletions(io, final_cmd, root_name, &.{}, .default, !include_desc);
            return;
        };
        if (new_arg_count > fs.nArg()) flag_completion = false;
    }

    if (fc.err) |e| {
        if (e != error.FlagCompError or flag_completion) {
            compErrorln(io, "unknown flag being completed");
            printCompletions(io, final_cmd, root_name, &.{}, .default, !include_desc);
            return;
        }
    }

    // --help/--version present: no further completions.
    if (helpOrVersionFlagPresent(final_cmd)) {
        printCompletions(io, final_cmd, root_name, &.{}, .no_file_comp, !include_desc);
        return;
    }

    if (!final_cmd.disable_flag_parsing) {
        if (final_cmd.flags_ptr) |fs| final_args = fs.argList();
    }

    // Flag VALUE completion driven by annotations.
    if (fc.flag) |flag| {
        if (flag_completion) {
            if (flag.annotations.get(bash_comp_filename_ext)) |exts| {
                if (exts.len != 0) {
                    printCompletions(io, final_cmd, root_name, exts, .filter_file_ext, !include_desc);
                    return;
                }
                // Empty extension list == plain file completion == default behavior.
            }
            if (flag.annotations.get(bash_comp_subdirs_in_dir)) |sub| {
                if (sub.len == 1) {
                    printCompletions(io, final_cmd, root_name, sub, .filter_dirs, !include_desc);
                } else {
                    printCompletions(io, final_cmd, root_name, &.{}, .filter_dirs, !include_desc);
                }
                return;
            }
        }
    }

    final_cmd.enforceFlagGroupsForCompletion();

    const completing_flag_name = fc.flag == null and to_complete.len > 0 and
        to_complete[0] == '-' and std.mem.indexOfScalar(u8, to_complete, '=') == null and flag_completion;

    if (completing_flag_name) {
        try completeRequireFlags(aa, &completions, final_cmd, to_complete);
        if (completions.items.len == 0) {
            const views = [_]?*pflag.FlagSet{ final_cmd.iflags, final_cmd.lflags };
            for (views) |maybe| {
                const fs = maybe orelse continue;
                for (fs.ordered_formal.items) |f| {
                    if (f.changed and !flagAcceptsMultiple(f)) continue;
                    try getFlagNameCompletions(aa, &completions, f, to_complete);
                }
            }
        }
        directive = .no_file_comp;

        if (!final_cmd.disable_flag_parsing) {
            printCompletions(io, final_cmd, root_name, completions.items, directive, !include_desc);
            return;
        }
        // DisableFlagParsing: fall through so ValidArgsFunction can still apply.
    } else {
        // Walk the chain for a custom DefaultShellCompDirective.
        var cc: ?*const Command = final_cmd;
        while (cc) |c2| : (cc = c2.parent) {
            if (c2.completion_options.default_shell_comp_directive) |d| {
                directive = d;
                break;
            }
        }

        if (fc.flag == null) {
            var found_local_non_persistent = false;
            if (!root.traverse_children) {
                if (final_cmd.lflags) |lf| {
                    for (lf.ordered_formal.items) |f| {
                        if (!f.changed) continue;
                        if (final_cmd.lnpflags) |lnp| {
                            if (lnp.lookup(f.name) != null) {
                                found_local_non_persistent = true;
                                break;
                            }
                        }
                    }
                }
            }

            // Complete subcommand names (including the help command).
            if (final_args.len == 0 and !found_local_non_persistent) {
                for (final_cmd.getCommands()) |sub| {
                    if (sub.isAvailableCommand() or sub == final_cmd.help_command) {
                        if (std.mem.startsWith(u8, sub.name(), to_complete)) {
                            try completions.append(aa, try completionWithDesc(aa, sub.name(), sub.short));
                        }
                        directive = .no_file_comp;
                    }
                }
            }

            // Required flags are suggested even without a '-' prefix.
            try completeRequireFlags(aa, &completions, final_cmd, to_complete);

            // ValidArgs: exclusive source of positional completions.
            if (final_cmd.valid_args.len > 0) {
                if (final_args.len == 0) {
                    for (final_cmd.valid_args) |va| {
                        if (std.mem.startsWith(u8, va, to_complete)) {
                            try completions.append(aa, va);
                        }
                    }
                    directive = .no_file_comp;
                    if (completions.items.len == 0) {
                        for (final_cmd.arg_aliases) |va| {
                            if (std.mem.startsWith(u8, va, to_complete)) {
                                try completions.append(aa, va);
                            }
                        }
                    }
                }
                printCompletions(io, final_cmd, root_name, completions.items, directive, !include_desc);
                return;
            }
        }
    }

    // User-provided completion function (flag-specific or ValidArgsFunction).
    var maybe_fn: ?CompletionFunc = null;
    if (fc.flag) |flag| {
        if (flag_completion) maybe_fn = findFlagCompletionFunc(final_cmd, flag.name);
    } else {
        maybe_fn = final_cmd.valid_args_function;
    }
    if (maybe_fn) |cf| {
        const res = try cf.invoke(final_cmd, @constCast(final_args), to_complete);
        try completions.appendSlice(aa, res.completions);
        directive = res.directive;
    }

    printCompletions(io, final_cmd, root_name, completions.items, directive, !include_desc);
}

// ─────────────────────────────────────────────────────────────────────────────
// Script generation (Go: GenBashCompletionV2 / GenZshCompletion /
// GenFishCompletion / GenPowerShellCompletion)
// ─────────────────────────────────────────────────────────────────────────────

fn nameForVar(root_name: []const u8, buf: []u8) []const u8 {
    @memcpy(buf[0..root_name.len], root_name);
    for (buf[0..root_name.len]) |*c| {
        if (c.* == '-' or c.* == ':') c.* = '_';
    }
    return buf[0..root_name.len];
}

/// Renders a Go-fmt-style template (%[N]s, %[N]d, %s, %d, %%, optional
/// '-' left-align width like %-36s / %-36[1]s) against string arguments.
pub fn writeFormattedTemplate(w: *std.Io.Writer, tmpl: []const u8, args: []const []const u8) void {
    var i: usize = 0;
    var sequential: usize = 0;
    while (i < tmpl.len) {
        const pct = std.mem.indexOfScalarPos(u8, tmpl, i, '%') orelse {
            w.print("{s}", .{tmpl[i..]}) catch {};
            return;
        };
        if (pct > i) w.print("{s}", .{tmpl[i..pct]}) catch {};
        if (pct + 1 >= tmpl.len) return;
        var j = pct + 1;
        if (tmpl[j] == '%') {
            w.print("%", .{}) catch {};
            i = j + 1;
            continue;
        }
        var pad: usize = 0;
        if (tmpl[j] == '-') j += 1; // left-align is our default behavior
        while (j < tmpl.len and tmpl[j] >= '0' and tmpl[j] <= '9') {
            pad = pad * 10 + (tmpl[j] - '0');
            j += 1;
        }
        var idx: usize = 0;
        if (j < tmpl.len and tmpl[j] == '[') {
            const close = std.mem.indexOfScalarPos(u8, tmpl, j, ']') orelse {
                i = j;
                continue;
            };
            idx = std.fmt.parseInt(usize, tmpl[j + 1 .. close], 10) catch {
                i = j;
                continue;
            };
            sequential = idx; // Go numbering continues from the explicit index
            j = close + 1;
        } else {
            sequential += 1;
            idx = sequential;
        }
        if (j >= tmpl.len or (tmpl[j] != 's' and tmpl[j] != 'd' and tmpl[j] != 'v')) {
            i = j;
            continue;
        }
        j += 1;
        if (idx >= 1 and idx <= args.len) {
            const s = args[idx - 1];
            w.print("{s}", .{s}) catch {};
            var k: usize = s.len;
            while (k < pad) : (k += 1) w.print(" ", .{}) catch {};
        }
        i = j;
    }
}

const directive_args = [_][]const u8{ "1", "2", "4", "8", "16", "32" };

/// Generates the bash completion V2 script (Go: GenBashCompletionV2).
pub fn genBashCompletionV2(root: *Command, w: *std.Io.Writer, include_desc: bool) !void {
    const comp_cmd = if (include_desc) shell_comp_request_cmd else shell_comp_no_desc_request_cmd;
    var args_storage: [9][]const u8 = undefined;
    args_storage[0] = root.name();
    args_storage[1] = comp_cmd;
    @memcpy(args_storage[2..8], &directive_args);
    args_storage[8] = active_help.active_help_marker;
    writeFormattedTemplate(w, templates.bash_v2_template, &args_storage);
}

/// Generates the zsh completion script (Go: GenZshCompletion / GenZshCompletionNoDesc).
pub fn genZshCompletion(root: *Command, w: *std.Io.Writer, include_desc: bool) !void {
    const comp_cmd = if (include_desc) shell_comp_request_cmd else shell_comp_no_desc_request_cmd;
    var args_storage: [9][]const u8 = undefined;
    args_storage[0] = root.name();
    args_storage[1] = comp_cmd;
    @memcpy(args_storage[2..8], &directive_args);
    args_storage[8] = active_help.active_help_marker;
    writeFormattedTemplate(w, templates.zsh_template, &args_storage);
}

/// Generates the fish completion script (Go: GenFishCompletion).
pub fn genFishCompletion(root: *Command, w: *std.Io.Writer, include_desc: bool) !void {
    const comp_cmd = if (include_desc) shell_comp_request_cmd else shell_comp_no_desc_request_cmd;
    var nfv_buf: [128]u8 = undefined;
    var env_buf: [160]u8 = undefined;
    var args_storage: [10][]const u8 = undefined;
    args_storage[0] = nameForVar(root.name(), &nfv_buf);
    args_storage[1] = root.name();
    args_storage[2] = comp_cmd;
    @memcpy(args_storage[3..9], &directive_args);
    args_storage[9] = active_help.configEnvVar(root.name(), active_help.active_help_env_var_suffix, &env_buf);
    // fish header line is rendered separately in the Go source.
    writeFormattedTemplate(w, templates.fish_header_template, args_storage[1..2]);
    writeFormattedTemplate(w, templates.fish_template, &args_storage);
}

/// Generates the powershell completion script
/// (Go: GenPowerShellCompletionWithDesc / GenPowerShellCompletion).
pub fn genPowerShellCompletion(root: *Command, w: *std.Io.Writer, include_desc: bool) !void {
    const comp_cmd = if (include_desc) shell_comp_request_cmd else shell_comp_no_desc_request_cmd;
    var nfv_buf: [128]u8 = undefined;
    var env_buf: [160]u8 = undefined;
    var args_storage: [10][]const u8 = undefined;
    args_storage[0] = root.name();
    args_storage[1] = nameForVar(root.name(), &nfv_buf);
    args_storage[2] = comp_cmd;
    @memcpy(args_storage[3..9], &directive_args);
    args_storage[9] = active_help.configEnvVar(root.name(), active_help.active_help_env_var_suffix, &env_buf);
    writeFormattedTemplate(w, templates.powershell_template, &args_storage);
}
