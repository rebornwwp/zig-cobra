//! Command is the core of cobra - a command for your CLI application.
//! Maps 1:1 from cobra/command.go
const std = @import("std");

const Completion = @import("completions.zig").Completion;
const ShellCompDirective = @import("completions.zig").ShellCompDirective;
const CompletionFuncType = @import("completions.zig").CompletionFunc;
const CompletionOptions = @import("completions.zig").CompletionOptions;
const PositionalArgs = @import("args.zig").PositionalArgs;

pub const FlagSetByCobraAnnotation = "cobra_annotation_flag_set_by_cobra";
pub const CommandDisplayNameAnnotation = "cobra_annotation_command_display_name";
pub const help_flag_name = "help";
pub const help_command_name = "help";

pub const FParseErrWhitelist = struct {
    unknown_flag: bool = false,
    invalid_flag: bool = false,
    unknown_shorthand_flag: bool = false,
};

pub const Group = struct {
    id: []const u8,
    title: []const u8,
};

pub const TmplFunc = struct {
    tmpl: []const u8,
};

pub const RunFunc = *const fn (cmd: *Command, args: [][]const u8) void;
pub const RunEFunc = *const fn (cmd: *Command, args: [][]const u8) anyerror!void;
pub const HelpFuncType = *const fn (cmd: *Command, args: [][]const u8) void;
pub const UsageFuncType = *const fn (cmd: *Command) anyerror!void;
pub const FlagErrorFuncType = *const fn (cmd: *Command, err: anyerror) anyerror!void;

pub const Command = struct {
    use: []const u8,
    aliases: []const []const u8 = &.{},
    suggest_for: []const []const u8 = &.{},
    short: []const u8 = "",
    long: []const u8 = "",
    example: []const u8 = "",
    valid_args: []const []const u8 = &.{},
    arg_aliases: []const []const u8 = &.{},
    annotations: std.StringArrayHashMapUnmanaged([]const []const u8) = .{},
    version: []const u8 = "",
    deprecated: []const u8 = "",
    group_id: []const u8 = "",
    run: ?RunFunc = null,
    run_e: ?RunEFunc = null,
    pre_run: ?RunFunc = null,
    pre_run_e: ?RunEFunc = null,
    post_run: ?RunFunc = null,
    post_run_e: ?RunEFunc = null,
    persistent_pre_run: ?RunFunc = null,
    persistent_pre_run_e: ?RunEFunc = null,
    persistent_post_run: ?RunFunc = null,
    persistent_post_run_e: ?RunEFunc = null,
    fparse_err_whitelist: FParseErrWhitelist = .{},
    completion_options: CompletionOptions = .{},
    traverse_children: bool = false,
    hidden: bool = false,
    silence_errors: bool = false,
    silence_usage: bool = false,
    disable_flag_parsing: bool = false,
    disable_auto_gen_tag: bool = false,
    disable_flags_in_use_line: bool = false,
    disable_suggestions: bool = false,
    suggestions_minimum_distance: usize = 0,
    args_validator: ?PositionalArgs = null,
    valid_args_function: ?CompletionFuncType = null,
    commandgroups: std.ArrayListUnmanaged(*Group) = .empty,
    help_command_group_id: []const u8 = "",
    completion_command_group_id: []const u8 = "",
    usage_func: ?UsageFuncType = null,
    help_func: ?HelpFuncType = null,
    flag_error_func: ?FlagErrorFuncType = null,
    err_prefix: []const u8 = "",
    args_slice: []const []const u8 = &.{},
    commands: std.ArrayListUnmanaged(*Command) = .empty,
    parent: ?*Command = null,
    commands_are_sorted: bool = false,
    command_called_as: struct { name: []const u8 = "", called: bool = false } = .{},
    help_command: ?*Command = null,
    out_writer: ?*std.Io.Writer = null,
    err_writer: ?*std.Io.Writer = null,
    in_reader: ?*std.Io.Reader = null,
    flags: ?*FlagSet = null,
    pflags: ?*FlagSet = null,
    lflags: ?*FlagSet = null,
    iflags: ?*FlagSet = null,
    parents_pflags: ?*FlagSet = null,
    flag_error_buf: ?*std.ArrayListUnmanaged(u8) = null,
    commands_max_use_len: usize = 0,
    commands_max_command_path_len: usize = 0,
    commands_max_name_len: usize = 0,

    // ─── Methods ───
    pub fn setArgs(self: *Command, a: []const []const u8) void { self.args_slice = a; }
    pub fn setOut(self: *Command, w: *std.Io.Writer) void { self.out_writer = w; }
    pub fn setErr(self: *Command, w: *std.Io.Writer) void { self.err_writer = w; }
    pub fn setIn(self: *Command, r: *std.Io.Reader) void { self.in_reader = r; }
    pub fn setOutput(self: *Command, w: *std.Io.Writer) void { self.out_writer = w; self.err_writer = w; }
    pub fn setUsageFunc(self: *Command, f: UsageFuncType) void { self.usage_func = f; }
    pub fn setFlagErrorFunc(self: *Command, f: FlagErrorFuncType) void { self.flag_error_func = f; }
    pub fn setHelpFunc(self: *Command, f: HelpFuncType) void { self.help_func = f; }
    pub fn setHelpCommand(self: *Command, cmd: *Command) void { self.help_command = cmd; }
    pub fn setHelpCommandGroupID(self: *Command, gid: []const u8) void {
        if (self.help_command) |hc| hc.group_id = gid;
        self.help_command_group_id = gid;
    }
    pub fn setCompletionCommandGroupID(self: *Command, gid: []const u8) void {
        self.root().completion_command_group_id = gid;
    }
    pub fn setErrPrefix(self: *Command, s: []const u8) void { self.err_prefix = s; }

    pub fn errOrStderr(self: *Command) *std.Io.Writer {
        if (self.err_writer) |w| return w;
        if (self.parent) |p| return p.errOrStderr();
        return undefined;
    }
    pub fn outOrStdout(self: *Command) *std.Io.Writer {
        if (self.out_writer) |w| return w;
        if (self.parent) |p| return p.outOrStdout();
        return undefined;
    }
    pub fn inOrStdin(self: *Command) *std.Io.Reader {
        if (self.in_reader) |r| return r;
        if (self.parent) |p| return p.inOrStdin();
        return undefined;
    }
    pub fn hasParent(self: *const Command) bool { return self.parent != null; }
    pub fn getParent(self: *Command) ?*Command { return self.parent; }
    pub fn root(self: *Command) *Command {
        if (self.hasParent()) return self.parent.?.root();
        return self;
    }

    pub fn name(self: *const Command) []const u8 {
        if (std.mem.indexOfScalar(u8, self.use, ' ')) |i| return self.use[0..i];
        return self.use;
    }
    pub fn displayName(self: *const Command) []const u8 { return self.name(); }

    pub fn commandPath(self: *Command) []const u8 {
        if (self.hasParent()) {
            // parent path + " " + name (needs allocator for concat in full impl)
        }
        return self.displayName();
    }

    pub fn hasAlias(self: *const Command, s: []const u8) bool {
        const enable_case_insensitive = @import("cobra.zig").enable_case_insensitive;
        for (self.aliases) |a| {
            if (enable_case_insensitive) { if (std.ascii.eqlIgnoreCase(a, s)) return true; }
            else { if (std.mem.eql(u8, a, s)) return true; }
        }
        return false;
    }

    pub fn calledAs(self: *const Command) []const u8 {
        if (self.command_called_as.called) return self.command_called_as.name;
        return "";
    }

    pub fn runnable(self: *const Command) bool { return self.run != null or self.run_e != null; }
    pub fn hasSubCommands(self: *const Command) bool { return self.commands.items.len > 0; }
    pub fn hasExample(self: *const Command) bool { return self.example.len > 0; }

    pub fn isAvailableCommand(self: *const Command) bool {
        if (self.deprecated.len != 0 or self.hidden) return false;
        if (self.hasParent() and self.parent.?.help_command == self) return false;
        return self.runnable() or self.hasAvailableSubCommands();
    }
    pub fn hasAvailableSubCommands(self: *const Command) bool {
        for (self.commands.items) |sub| if (sub.isAvailableCommand()) return true;
        return false;
    }
    pub fn isAdditionalHelpTopicCommand(self: *const Command) bool {
        if (self.runnable() or self.deprecated.len != 0 or self.hidden) return false;
        for (self.commands.items) |sub| if (!sub.isAdditionalHelpTopicCommand()) return false;
        return true;
    }
    pub fn hasHelpSubCommands(self: *const Command) bool {
        for (self.commands.items) |sub| if (sub.isAdditionalHelpTopicCommand()) return true;
        return false;
    }

    pub fn getCommands(self: *Command) []*Command {
        const enable_command_sorting = @import("cobra.zig").enable_command_sorting;
        if (enable_command_sorting and !self.commands_are_sorted) {
            std.mem.sort(*Command, self.commands.items, {}, lessThanByName);
            self.commands_are_sorted = true;
        }
        return self.commands.items;
    }

    fn lessThanByName(_: void, a: *Command, b: *Command) bool {
        return std.ascii.lessThanIgnoreCase(a.name(), b.name());
    }

    pub fn addCommand(self: *Command, gpa: std.mem.Allocator, cmds: []const *Command) void {
        for (cmds) |cmd| {
            if (cmd == self) @panic("Command can't be a child of itself");
            cmd.parent = self;
            const ul = cmd.use.len;
            if (ul > self.commands_max_use_len) self.commands_max_use_len = ul;
            const cpl = cmd.commandPath().len;
            if (cpl > self.commands_max_command_path_len) self.commands_max_command_path_len = cpl;
            const nl = cmd.name().len;
            if (nl > self.commands_max_name_len) self.commands_max_name_len = nl;
            self.commands.append(gpa, cmd) catch @panic("OOM");
            self.commands_are_sorted = false;
        }
    }

    pub fn groups(self: *Command) []*Group { return self.commandgroups.items; }
    pub fn containsGroup(self: *const Command, gid: []const u8) bool {
        for (self.commandgroups.items) |g| if (std.mem.eql(u8, g.id, gid)) return true;
        return false;
    }
    pub fn allChildCommandsHaveGroup(self: *const Command) bool {
        for (self.commands.items) |sub| {
            if ((sub.isAvailableCommand() or sub == self.help_command) and sub.group_id.len == 0) return false;
        }
        return true;
    }
    pub fn addGroup(self: *Command, gpa: std.mem.Allocator, grp: []const *Group) void {
        self.commandgroups.appendSlice(gpa, grp) catch @panic("OOM");
    }
    pub fn removeCommand(self: *Command, gpa: std.mem.Allocator, cmds: []const *Command) void {
        var nc = std.ArrayList(*Command).initCapacity(gpa, 8) catch unreachable;
        defer nc.deinit(gpa);
        for (self.commands.items) |c| {
            var skip = false;
            for (cmds) |rc| if (c == rc) { c.parent = null; skip = true; break; };
            if (!skip) nc.append(gpa, c) catch unreachable;
        }
        self.commands.deinit(gpa);
        self.commands = .empty;
        for (nc.items) |cmd| {
            self.commands.append(gpa, cmd) catch unreachable;
        }
    }
    pub fn resetCommands(self: *Command, gpa: std.mem.Allocator) void {
        self.commands.deinit(gpa);
        self.parent = null; self.commands = .empty; self.help_command = null; self.parents_pflags = null;
    }
    pub fn deinit(self: *Command, gpa: std.mem.Allocator) void {
        for (self.commands.items) |c| c.deinit(gpa);
        self.commands.deinit(gpa);
        self.commandgroups.deinit(gpa);
    }
    pub fn findSuggestions(self: *const Command, typed_name: []const u8) []const u8 {
        const min_dist = if (self.suggestions_minimum_distance <= 0) 2 else self.suggestions_minimum_distance;
        const ld = @import("cobra.zig").levenshteinDistance;
        var count: usize = 0;
        for (self.commands.items) |cmd| {
            if (cmd.isAvailableCommand() and ld(typed_name, cmd.name(), true) <= min_dist) count += 1;
        }
        if (count == 0) return "";
        return "\n\nDid you mean this?";
    }

    pub fn suggestionsFor(self: *const Command, gpa: std.mem.Allocator, typed_name: []const u8) ![][]const u8 {
        var s = std.ArrayList([]const u8).initCapacity(gpa, 8) catch unreachable;
        const min_dist = if (self.suggestions_minimum_distance <= 0) 2 else self.suggestions_minimum_distance;
        const ld = @import("cobra.zig").levenshteinDistance;
        for (self.commands.items) |cmd| {
            if (cmd.isAvailableCommand()) {
                if (ld(typed_name, cmd.name(), true) <= min_dist or std.ascii.startsWithIgnoreCase(cmd.name(), typed_name))
                    try s.append(gpa, cmd.name());
            }
        }
        return try s.toOwnedSlice(gpa);
    }

    pub fn visitParents(self: *Command, fn_ptr: *const fn (*Command) void) void {
        if (self.hasParent()) { fn_ptr(self.parent.?); self.parent.?.visitParents(fn_ptr); }
    }

    pub fn errPrefix(self: *const Command) []const u8 {
        if (self.err_prefix.len > 0) return self.err_prefix;
        if (self.hasParent()) return self.parent.?.errPrefix();
        return "Error:";
    }

    pub fn print(self: *Command, io: std.Io, comptime fmt_str: []const u8, args: anytype) void { _ = self; _ = io; _ = fmt_str; _ = args; }
    pub fn println(self: *Command, io: std.Io, comptime fmt_str: []const u8, args: anytype) void { self.print(io, fmt_str ++ "\n", args); }
    pub fn printf(self: *Command, io: std.Io, comptime fmt_str: []const u8, args: anytype) void { self.print(io, fmt_str, args); }
    pub fn printErr(self: *Command, io: std.Io, comptime fmt_str: []const u8, args: anytype) void { self.print(io, fmt_str, args); }
    pub fn printErrln(self: *Command, io: std.Io, comptime fmt_str: []const u8, args: anytype) void { self.printErr(io, fmt_str ++ "\n", args); }
    pub fn printErrf(self: *Command, io: std.Io, comptime fmt_str: []const u8, args: anytype) void { self.printErr(io, fmt_str, args); }

    pub fn validateArgs(self: *Command, args: []const []const u8) anyerror!void {
        const arbitraryArgs = @import("args.zig").arbitraryArgs;
        if (self.args_validator) |a| return a.validate(self, args);
        try arbitraryArgs().validate(self, args);
    }

    pub fn execute(self: *Command, io: std.Io, a: []const []const u8) anyerror!void {
        if (self.deprecated.len > 0) self.printErr(io, "Command \"{s}\" is deprecated, {s}\n", .{ self.name(), self.deprecated });
        self.initDefaultHelpFlag();
        self.initDefaultVersionFlag();
        self.preRun();
        defer self.postRun();
        try self.validateArgs(a);
        if (self.run_e) |run_e| try run_e(self, @constCast(a))
        else if (self.run) |run| return run(self, @constCast(a));
    }

    fn preRun(_: *Command) void { @import("cobra.zig").runInitializers(); }
    fn postRun(_: *Command) void { @import("cobra.zig").runFinalizers(); }
    pub fn executeContext(self: *Command, io: std.Io) anyerror!void { const a = self.args_slice; return self.execute(io, a); }
    pub fn executeWrapper(self: *Command) anyerror!void {
        const io = @import("std").Io.Threaded.global_single_threaded.*.io();

        // 遍历 args，找到第一个匹配的子命令
        var cmd: *Command = self;
        var remaining: []const []const u8 = self.args_slice;

        while (remaining.len > 0) {
            const arg = remaining[0];
            // 遇到 flag 停止查找
            if (isFlagArg(arg)) break;

            var found: ?*Command = null;
            for (cmd.commands.items) |sub| {
                if (std.mem.eql(u8, sub.name(), arg) or sub.hasAlias(arg)) {
                    found = sub;
                    break;
                }
            }

            if (found) |next| {
                cmd = next;
                remaining = remaining[1..];
            } else {
                break;
            }
        }

        // 用剩余参数执行找到的命令
        return cmd.execute(io, remaining);
    }

    pub fn initDefaultHelpFlag(_: *Command) void {}
    pub fn initDefaultVersionFlag(_: *Command) void {}
    pub fn initDefaultHelpCmd(_: *Command) void {}
    pub fn initDefaultCompletionCmd(_: *Command, io: std.Io, args: [][]const u8) void { _ = io; _ = args; }
    pub fn initCompleteCmd(_: *Command, io: std.Io, args: [][]const u8) void { _ = io; _ = args; }
    pub fn usagePadding(self: *const Command) usize { return if (self.commands_max_use_len > 25) self.commands_max_use_len else 25; }
    pub fn commandPathPadding(self: *const Command) usize { return if (self.commands_max_command_path_len > 11) self.commands_max_command_path_len else 11; }
    pub fn namePadding(self: *const Command) usize { return if (self.commands_max_name_len > 11) self.commands_max_name_len else 11; }
    pub fn checkCommandGroups(_: *const Command) void {}

    pub fn isFlagArg(arg: []const u8) bool {
        return (arg.len >= 3 and std.mem.eql(u8, arg[0..2], "--")) or
            (arg.len >= 2 and arg[0] == '-' and arg[1] != '-');
    }
};

pub const FlagSet = struct {
    pub fn lookup(self: *FlagSet, lookup_name: []const u8) ?*Flag { _ = self; _ = lookup_name; return null; }
    pub fn shorthandLookup(self: *FlagSet, shorthand: []const u8) ?*Flag { _ = self; _ = shorthand; return null; }
    pub fn parse(self: *FlagSet, parse_args: [][]const u8) anyerror!void { _ = self; _ = parse_args; }
    pub fn nArg(self: *FlagSet) usize { _ = self; return 0; }
    pub fn args(self: *FlagSet) [][]const u8 { _ = self; return &.{}; }
};
pub const Flag = struct {
    name: []const u8 = "", shorthand: []const u8 = "", usage: []const u8 = "",
    def_value: []const u8 = "", changed: bool = false, hidden: bool = false,
    deprecated: []const u8 = "", no_opt_def_val: []const u8 = "",
};

pub const default_usage_template = "Usage:{{if .Runnable}}\n  {{.UseLine}}{{end}}\n";
pub const default_help_template = "{{with (or .Long .Short)}}{{.}}{{end}}";
pub const default_version_template = "{{.DisplayName}} version {{.Version}}\n";

pub fn defaultUsageFunc(writer: *std.Io.Writer, cmd: *Command) anyerror!void {
    writer.interface.print("Usage:", .{}) catch {};
    if (cmd.runnable()) writer.interface.print("\n  {s}", .{cmd.use}) catch {};
    if (cmd.hasAvailableSubCommands()) writer.interface.print("\n  {s} [command]", .{cmd.commandPath()}) catch {};
    if (cmd.aliases.len > 0) writer.interface.print("\n\nAliases:\n  {s}", .{cmd.name()}) catch {};
    writer.interface.print("\n", .{}) catch {};
}
pub fn defaultHelpFunc(writer: *std.Io.Writer, cmd: *Command) anyerror!void {
    var usage = cmd.long;
    if (usage.len == 0) usage = cmd.short;
    if (usage.len > 0) writer.interface.print("{s}\n\n", .{usage}) catch {};
}
