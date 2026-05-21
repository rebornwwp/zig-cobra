//! Cobra - global config + utility functions
const std = @import("std");

pub const command_mod = @import("command.zig");
pub const Command = command_mod.Command;
pub const Group = command_mod.Group;
pub const FParseErrWhitelist = command_mod.FParseErrWhitelist;
pub const TmplFunc = command_mod.TmplFunc;

pub const args_mod = @import("args.zig");
pub const PositionalArgs = args_mod.PositionalArgs;
pub const NoArgs = args_mod.noArgs;
pub const OnlyValidArgs = args_mod.onlyValidArgs;
pub const NoDuplicateArgs = args_mod.noDuplicateArgs;
pub const ArbitraryArgs = args_mod.arbitraryArgs;
pub const MinimumNArgs = args_mod.minimumNArgs;
pub const MaximumNArgs = args_mod.maximumNArgs;
pub const ExactArgs = args_mod.exactArgs;
pub const RangeArgs = args_mod.rangeArgs;
pub const MatchAll = args_mod.matchAll;
pub const ExactValidArgs = args_mod.exactValidArgs;
pub const LegacyArgs = args_mod.legacyArgs;

pub const completions_mod = @import("completions.zig");
pub const Completion = completions_mod.Completion;
pub const CompletionFunc = completions_mod.CompletionFunc;
pub const ShellCompDirective = completions_mod.ShellCompDirective;
pub const CompletionOptions = completions_mod.CompletionOptions;
pub const CompletionWithDesc = completions_mod.completionWithDesc;
pub const NoFileCompletions = completions_mod.noFileCompletions;
pub const FixedCompletions = completions_mod.fixedCompletions;

pub const active_help_mod = @import("active_help.zig");
pub const AppendActiveHelp = active_help_mod.appendActiveHelp;
pub const GetActiveHelpConfig = active_help_mod.getActiveHelpConfig;

pub const flag_groups_mod = @import("flag_groups.zig");
pub const shell_completions_mod = @import("shell_completions.zig");

pub const default_prefix_matching: bool = false;
pub const default_command_sorting: bool = true;
pub const default_case_insensitive: bool = false;
pub const default_traverse_run_hooks: bool = false;

pub var enable_prefix_matching: bool = default_prefix_matching;
pub var enable_command_sorting: bool = default_command_sorting;
pub var enable_case_insensitive: bool = default_case_insensitive;
pub var enable_traverse_run_hooks: bool = default_traverse_run_hooks;

pub var mousetrap_help_text: []const u8 =
    "This is a command line tool.\n\nYou need to open cmd.exe and run it from there.\n";

pub var mousetrap_display_duration_ns: i64 = 5 * std.time.ns_per_s;

var initializers: std.ArrayListUnmanaged(*const fn () void) = .empty;
var finalizers: std.ArrayListUnmanaged(*const fn () void) = .empty;

pub fn onInitialize(gpa: std.mem.Allocator, fns: []const *const fn () void) !void {
    try initializers.appendSlice(gpa, fns);
}

pub fn onFinalize(gpa: std.mem.Allocator, fns: []const *const fn () void) !void {
    try finalizers.appendSlice(gpa, fns);
}

pub fn runInitializers() void {
    for (initializers.items) |init_fn| init_fn();
}

pub fn runFinalizers() void {
    for (finalizers.items) |fin_fn| fin_fn();
}

pub fn trimRightSpace(s: []const u8) []const u8 {
    var end: usize = s.len;
    while (end > 0 and std.ascii.isWhitespace(s[end - 1])) : (end -= 1) {}
    return s[0..end];
}

pub fn appendIfNotPresent(gpa: std.mem.Allocator, s: []const u8, to_append: []const u8) ![]const u8 {
    if (std.mem.indexOf(u8, s, to_append) != null) return s;
    const result = try gpa.alloc(u8, s.len + 1 + to_append.len);
    @memcpy(result[0..s.len], s);
    result[s.len] = ' ';
    @memcpy(result[s.len + 1 ..], to_append);
    return result;
}

pub fn rpad(gpa: std.mem.Allocator, s: []const u8, padding: usize) ![]const u8 {
    if (s.len >= padding) return s;
    const result = try gpa.alloc(u8, padding);
    @memset(result, ' ');
    @memcpy(result[0..s.len], s);
    return result;
}

pub fn levenshteinDistance(s: []const u8, t: []const u8, ignore_case: bool) usize {
    var s_buf: [1024]u8 = undefined;
    var t_buf: [1024]u8 = undefined;
    const sn = if (ignore_case) blk: { _ = std.ascii.lowerString(&s_buf, s); break :blk s_buf[0..s.len]; } else s;
    const tn = if (ignore_case) blk: { _ = std.ascii.lowerString(&t_buf, t); break :blk t_buf[0..t.len]; } else t;
    const n = sn.len;
    const m = tn.len;
    var d: [1025][1025]usize = undefined;
    for (0..n + 1) |i| d[i][0] = i;
    for (0..m + 1) |j| d[0][j] = j;
    for (1..n + 1) |i| for (1..m + 1) |j| {
        d[i][j] = if (sn[i - 1] == tn[j - 1]) d[i - 1][j - 1] else @min(@min(d[i - 1][j], d[i][j - 1]), d[i - 1][j - 1]) + 1;
    };
    return d[n][m];
}

pub fn stringInSlice(needle: []const u8, haystack: []const []const u8) bool {
    for (haystack) |h| if (std.mem.eql(u8, needle, h)) return true;
    return false;
}

pub fn commandNameMatches(s: []const u8, t: []const u8) bool {
    if (enable_case_insensitive) return std.ascii.eqlIgnoreCase(s, t);
    return std.mem.eql(u8, s, t);
}
