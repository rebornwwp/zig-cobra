//! Command is the core of cobra — a command abstraction for your CLI application.
//! Maps 1:1 from cobra/command.go
const std = @import("std");
pub const pflag = @import("pflag");

const Completion = @import("completions.zig").Completion;
const ShellCompDirective = @import("completions.zig").ShellCompDirective;
const CompletionFuncType = @import("completions.zig").CompletionFunc;
const CompletionOptions = @import("completions.zig").CompletionOptions;
const PositionalArgs = @import("args.zig").PositionalArgs;

/// Annotation key for flags set internally by cobra
pub const FlagSetByCobraAnnotation = "cobra_annotation_flag_set_by_cobra";
/// Annotation key for custom command display name
pub const CommandDisplayNameAnnotation = "cobra_annotation_command_display_name";
/// Standard name for the help flag
pub const help_flag_name = "help";
/// Standard name for the help command
pub const help_command_name = "help";

/// Flag parse error whitelist: controls which parse errors are silently ignored.
pub const FParseErrWhitelist = struct {
    /// Ignore unknown flag errors
    unknown_flag: bool = false,
    /// Ignore invalid flag errors
    invalid_flag: bool = false,
    /// Ignore unknown shorthand flag errors
    unknown_shorthand_flag: bool = false,
};

/// Command group: used to categorize subcommands in help output.
pub const Group = struct {
    /// Group identifier
    id: []const u8,
    /// Group title (displayed in help)
    title: []const u8,
};

/// Template function: used for custom help output templates.
pub const TmplFunc = struct {
    /// Go template string
    tmpl: []const u8,
};

/// Command run function signature: (cmd, args) -> void
pub const RunFunc = *const fn (cmd: *Command, args: [][]const u8) void;
/// Fallible run function signature: (cmd, args) -> error!void
pub const RunEFunc = *const fn (cmd: *Command, args: [][]const u8) anyerror!void;
/// Custom help function signature: (cmd, args) -> void
pub const HelpFuncType = *const fn (cmd: *Command, args: [][]const u8) void;
/// Custom usage function signature: (cmd) -> error!void
pub const UsageFuncType = *const fn (cmd: *Command) anyerror!void;
/// Custom flag error handler signature: (cmd, err) -> error!void
pub const FlagErrorFuncType = *const fn (cmd: *Command, err: anyerror) anyerror!void;

/// Command is the core struct of cobra, representing a single CLI command.
/// All fields are public and can be set during initialization.
/// Important: Command instances should have stack lifetime; avoid heap allocation.
pub const Command = struct {
    /// Usage line, e.g. "serve [flags] [args]". The first word is the command name.
    use: []const u8,
    /// Alternative command names
    aliases: []const []const u8 = &.{},
    /// Names that, when typed, will suggest this command
    suggest_for: []const []const u8 = &.{},
    /// Short description (shown in parent command's help)
    short: []const u8 = "",
    /// Long description (shown in this command's help)
    long: []const u8 = "",
    /// Usage examples
    example: []const u8 = "",
    /// Valid argument values (used with OnlyValidArgs validator)
    valid_args: []const []const u8 = &.{},
    /// Argument aliases
    arg_aliases: []const []const u8 = &.{},
    /// Arbitrary key-value metadata
    annotations: std.StringArrayHashMapUnmanaged([]const []const u8) = .{},
    /// Version string: when set, --version flag is automatically enabled
    version: []const u8 = "",
    /// Deprecation message: non-empty means this command is deprecated
    deprecated: []const u8 = "",
    /// Command group ID (for grouping subcommands in help output)
    group_id: []const u8 = "",
    /// Main execution function
    run: ?RunFunc = null,
    /// Main execution function (fallible)
    run_e: ?RunEFunc = null,
    /// Pre-run hook: executed before this command's run
    pre_run: ?RunFunc = null,
    /// Pre-run hook (fallible)
    pre_run_e: ?RunEFunc = null,
    /// Post-run hook: executed after this command's run
    post_run: ?RunFunc = null,
    /// Post-run hook (fallible)
    post_run_e: ?RunEFunc = null,
    /// Persistent pre-run hook: executed before run for all commands in the subtree
    persistent_pre_run: ?RunFunc = null,
    /// Persistent pre-run hook (fallible)
    persistent_pre_run_e: ?RunEFunc = null,
    /// Persistent post-run hook: executed after run for all commands in the subtree
    persistent_post_run: ?RunFunc = null,
    /// Persistent post-run hook (fallible)
    persistent_post_run_e: ?RunEFunc = null,
    /// Flag parse error whitelist
    fparse_err_whitelist: FParseErrWhitelist = .{},
    /// Completion behavior configuration
    completion_options: CompletionOptions = .{},
    /// Run on all child commands, not just the matched one
    traverse_children: bool = false,
    /// Hide this command from help output
    hidden: bool = false,
    /// Suppress error output
    silence_errors: bool = false,
    /// Suppress usage output on errors
    silence_usage: bool = false,
    /// Disable flag parsing (raw args passed directly to run)
    disable_flag_parsing: bool = false,
    /// Disable automatic flag tag generation
    disable_auto_gen_tag: bool = false,
    /// Hide flag info in the usage line
    disable_flags_in_use_line: bool = false,
    /// Disable "Did you mean?" suggestions
    disable_suggestions: bool = false,
    /// Minimum Levenshtein distance for suggestions (0 = use default of 2)
    suggestions_minimum_distance: usize = 0,
    /// Positional argument validator
    args_validator: ?PositionalArgs = null,
    /// Dynamic argument completion function
    valid_args_function: ?CompletionFuncType = null,
    /// Command group list
    commandgroups: std.ArrayListUnmanaged(*Group) = .empty,
    /// Group ID for the help command
    help_command_group_id: []const u8 = "",
    /// Group ID for the completion command
    completion_command_group_id: []const u8 = "",
    /// Custom usage output function
    usage_func: ?UsageFuncType = null,
    /// Custom help output function
    help_func: ?HelpFuncType = null,
    /// Custom flag error handler
    flag_error_func: ?FlagErrorFuncType = null,
    /// Error output prefix
    err_prefix: []const u8 = "",
    /// Parsed command-line arguments
    args_slice: []const []const u8 = &.{},
    /// Subcommand list (internal use)
    commands: std.ArrayListUnmanaged(*Command) = .empty,
    /// Parent command pointer (internal use, set automatically by addCommand)
    parent: ?*Command = null,
    /// Whether subcommands have been sorted alphabetically
    commands_are_sorted: bool = false,
    /// Name the command was called as
    command_called_as: struct { name: []const u8 = "", called: bool = false } = .{},
    /// Associated help command
    help_command: ?*Command = null,
    /// Custom stdout writer
    out_writer: ?*std.Io.Writer = null,
    /// Custom stderr writer
    err_writer: ?*std.Io.Writer = null,
    /// Custom stdin reader
    in_reader: ?*std.Io.Reader = null,
    /// Local flag set
    flags: ?*pflag.FlagSet = null,
    /// Persistent flag set (automatically inherited by subcommands)
    pflags: ?*pflag.FlagSet = null,
    /// Local flags inherited from parent only
    lflags: ?*pflag.FlagSet = null,
    /// Flags inherited from parent (can be cast to arbitrary pointer type to pass user data)
    iflags: ?*pflag.FlagSet = null,
    /// Union of all parent persistent flag sets
    parents_pflags: ?*pflag.FlagSet = null,
    /// Flag error buffer
    flag_error_buf: ?*std.ArrayListUnmanaged(u8) = null,
    /// Maximum use field length among subcommands (for alignment)
    commands_max_use_len: usize = 0,
    /// Maximum command path length among subcommands
    commands_max_command_path_len: usize = 0,
    /// Maximum command name length among subcommands
    commands_max_name_len: usize = 0,

    // ─── Methods ───
    pub fn setArgs(self: *Command, a: []const []const u8) void {
        self.args_slice = a;
    }
    pub fn setOut(self: *Command, w: *std.Io.Writer) void {
        self.out_writer = w;
    }
    pub fn setErr(self: *Command, w: *std.Io.Writer) void {
        self.err_writer = w;
    }
    pub fn setIn(self: *Command, r: *std.Io.Reader) void {
        self.in_reader = r;
    }
    pub fn setOutput(self: *Command, w: *std.Io.Writer) void {
        self.out_writer = w;
        self.err_writer = w;
    }
    pub fn setUsageFunc(self: *Command, f: UsageFuncType) void {
        self.usage_func = f;
    }
    pub fn setFlagErrorFunc(self: *Command, f: FlagErrorFuncType) void {
        self.flag_error_func = f;
    }
    pub fn setHelpFunc(self: *Command, f: HelpFuncType) void {
        self.help_func = f;
    }
    pub fn setHelpCommand(self: *Command, cmd: *Command) void {
        self.help_command = cmd;
    }
    pub fn setHelpCommandGroupID(self: *Command, gid: []const u8) void {
        if (self.help_command) |hc| hc.group_id = gid;
        self.help_command_group_id = gid;
    }
    pub fn setCompletionCommandGroupID(self: *Command, gid: []const u8) void {
        self.root().completion_command_group_id = gid;
    }
    pub fn setErrPrefix(self: *Command, s: []const u8) void {
        self.err_prefix = s;
    }

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
    pub fn hasParent(self: *const Command) bool {
        return self.parent != null;
    }
    pub fn getParent(self: *Command) ?*Command {
        return self.parent;
    }
    pub fn root(self: *Command) *Command {
        if (self.hasParent()) return self.parent.?.root();
        return self;
    }

    pub fn name(self: *const Command) []const u8 {
        if (std.mem.indexOfScalar(u8, self.use, ' ')) |i| return self.use[0..i];
        return self.use;
    }
    pub fn displayName(self: *const Command) []const u8 {
        return self.name();
    }

    pub fn commandPath(self: *Command) []const u8 {
        if (self.hasParent()) {
            // parent path + " " + name (needs allocator for concat in full impl)
        }
        return self.displayName();
    }

    pub fn hasAlias(self: *const Command, s: []const u8) bool {
        const enable_case_insensitive = @import("cobra.zig").enable_case_insensitive;
        for (self.aliases) |a| {
            if (enable_case_insensitive) {
                if (std.ascii.eqlIgnoreCase(a, s)) return true;
            } else {
                if (std.mem.eql(u8, a, s)) return true;
            }
        }
        return false;
    }

    pub fn calledAs(self: *const Command) []const u8 {
        if (self.command_called_as.called) return self.command_called_as.name;
        return "";
    }

    pub fn runnable(self: *const Command) bool {
        return self.run != null or self.run_e != null;
    }
    pub fn hasSubCommands(self: *const Command) bool {
        return self.commands.items.len > 0;
    }
    pub fn hasExample(self: *const Command) bool {
        return self.example.len > 0;
    }

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

    pub fn groups(self: *Command) []*Group {
        return self.commandgroups.items;
    }
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
            for (cmds) |rc| if (c == rc) {
                c.parent = null;
                skip = true;
                break;
            };
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
        self.parent = null;
        self.commands = .empty;
        self.help_command = null;
        self.parents_pflags = null;
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
        if (self.hasParent()) {
            fn_ptr(self.parent.?);
            self.parent.?.visitParents(fn_ptr);
        }
    }

    pub fn errPrefix(self: *const Command) []const u8 {
        if (self.err_prefix.len > 0) return self.err_prefix;
        if (self.hasParent()) return self.parent.?.errPrefix();
        return "Error:";
    }

    pub fn print(self: *Command, io: std.Io, comptime fmt_str: []const u8, args: anytype) void {
        if (self.out_writer) |w| {
            w.print(fmt_str, args) catch {};
        }
        _ = io;
    }
    pub fn println(self: *Command, io: std.Io, comptime fmt_str: []const u8, args: anytype) void {
        self.print(io, fmt_str ++ "\n", args);
    }
    pub fn printf(self: *Command, io: std.Io, comptime fmt_str: []const u8, args: anytype) void {
        self.print(io, fmt_str, args);
    }
    pub fn printErr(self: *Command, io: std.Io, comptime fmt_str: []const u8, args: anytype) void {
        self.print(io, fmt_str, args);
    }
    pub fn printErrln(self: *Command, io: std.Io, comptime fmt_str: []const u8, args: anytype) void {
        self.printErr(io, fmt_str ++ "\n", args);
    }
    pub fn printErrf(self: *Command, io: std.Io, comptime fmt_str: []const u8, args: anytype) void {
        self.printErr(io, fmt_str, args);
    }

    pub fn validateArgs(self: *Command, args: []const []const u8) anyerror!void {
        const arbitraryArgs = @import("args.zig").arbitraryArgs;
        if (self.args_validator) |a| return a.validate(self, args);
        try arbitraryArgs().validate(self, args);
    }

    pub fn execute(self: *Command, io: std.Io, a: []const []const u8) anyerror!void {
        if (self.deprecated.len > 0) self.printErr(io, "Command \"{s}\" is deprecated, {s}\n", .{ self.name(), self.deprecated });

        // ── Run hooks: persistent_pre_run (parent chain) → pre_run → persistent_post_run (defer) → post_run
        @import("cobra.zig").runInitializers();
        self.executePersistentPreRun();
        if (self.pre_run) |f| f(self, @constCast(a));
        defer {
            if (self.post_run) |f| f(self, @constCast(a));
            self.executePersistentPostRun();
            @import("cobra.zig").runFinalizers();
        }

        self.initDefaultHelpFlag();
        self.initDefaultVersionFlag();

        // ── Setup --help flag
        var help_requested: bool = false;
        if (self.flags != null and self.flags.?.lookup("help") == null) {
            self.flags.?.boolVarP(&help_requested, "help", "h", false, "help for this command") catch {};
        }

        // ── Parse flags
        var remaining = a;
        if (self.flags != null and !self.disable_flag_parsing and remaining.len > 0) {
            // Pass FParseErrWhitelist to pflag
            self.flags.?.parse_errors_allowlist.unknown_flags = self.fparse_err_whitelist.unknown_flag;
            self.flags.?.parse(remaining) catch |err| {
                if (err == error.Help) {
                    self.printHelp(io);
                    return;
                }
                if (!self.silence_errors) {
                    self.printErr(io, "{s} {s}\n", .{ self.errPrefix(), @errorName(err) });
                }
                if (!self.silence_usage) self.printHelp(io);
                return err;
            };
            remaining = self.flags.?.argList();
        }

        // Show help if requested
        if (help_requested) {
            self.printHelp(io);
            return;
        }

        // ── Version flag
        if (self.version.len > 0 and self.flags != null) {
            if (self.flags.?.lookup("version")) |vf| {
                if (vf.changed) {
                    self.print(io, "{s} version {s}\n", .{ self.displayName(), self.version });
                    return;
                }
            }
        }

        try self.validateArgs(remaining);
        if (self.run_e) |run_e| try run_e(self, @constCast(remaining)) else if (self.run) |run| return run(self, @constCast(remaining));
    }

    fn executePersistentPreRun(self: *Command) void {
        var cmd: ?*Command = self;
        while (cmd) |c| : (cmd = c.parent) {
            if (c.persistent_pre_run) |f| f(c, @constCast(c.args_slice));
        }
    }
    fn executePersistentPostRun(self: *Command) void {
        var cmd: ?*Command = self;
        while (cmd) |c| : (cmd = c.parent) {
            if (c.persistent_post_run) |f| f(c, @constCast(c.args_slice));
        }
    }

    /// Print formatted help including description, usage, flags, and subcommands.
    pub fn printHelp(self: *Command, io: std.Io) void {
        // Try to get a writer: prefer configured out_writer, fall back to stderr
        var buf: [4096]u8 = undefined;
        var help_writer = std.Io.Writer.fixed(&buf);
        if (self.out_writer) |ow| {
            help_writer = ow.*;
        }

        // Description
        if (self.long.len > 0) {
            help_writer.print("{s}\n\n", .{self.long}) catch {};
        } else if (self.short.len > 0) {
            help_writer.print("{s}\n\n", .{self.short}) catch {};
        }

        // Usage
        help_writer.print("Usage:\n", .{}) catch {};
        if (self.runnable()) {
            help_writer.print("  {s} [flags]", .{self.commandPath()}) catch {};
        } else {
            help_writer.print("  {s} [command]", .{self.commandPath()}) catch {};
        }
        help_writer.print("\n", .{}) catch {};

        // Subcommands
        const subs = self.getCommands();
        if (subs.len > 0) {
            help_writer.print("\nAvailable Commands:\n", .{}) catch {};
            for (subs) |sub| {
                if (!sub.isAvailableCommand() and !sub.isAdditionalHelpTopicCommand()) continue;
                help_writer.print("  {s}\t{s}\n", .{ sub.name(), sub.short }) catch {};
            }
        }

        // Flags
        if (self.flags != null) {
            help_writer.print("\nFlags:\n", .{}) catch {};
            var flag_buf: [4096]u8 = undefined;
            var fw = std.Io.Writer.fixed(&flag_buf);
            const saved = self.flags.?.out_writer;
            self.flags.?.out_writer = &fw;
            self.flags.?.printDefaults();
            self.flags.?.out_writer = saved;
            const flag_out = std.Io.Writer.buffered(&fw);
            if (flag_out.len > 0) {
                help_writer.print("{s}\n", .{flag_out}) catch {};
            }
        }

        if (self.example.len > 0) {
            help_writer.print("\nExamples:\n  {s}\n", .{self.example}) catch {};
        }

        // Flush to stderr
        const output = std.Io.Writer.buffered(&help_writer);
        var stderr_buf: [256]u8 = undefined;
        var stderr_w = std.Io.File.Writer.init(std.Io.File.stderr(), io, &stderr_buf);
        const se = &stderr_w.interface;
        se.print("{s}", .{output}) catch {};
        stderr_w.flush() catch {};
    }

    pub fn executeContext(self: *Command, io: std.Io) anyerror!void {
        const a = self.args_slice;
        return self.execute(io, a);
    }
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

    pub fn initDefaultHelpFlag(self: *Command) void {
        // Lazy init: if no flags set, check parent
        if (self.flags == null and self.parent != null) {
            self.flags = self.parent.?.flags;
        }
    }
    fn _hasHelpFlag(self: *Command) bool {
        if (self.flags != null and self.flags.?.lookup("help") != null) return true;
        if (self.parent) |p| return p._hasHelpFlag();
        return false;
    }
    pub fn initDefaultVersionFlag(self: *Command) void {
        if (self.version.len == 0) return;
        if (self.flags != null and self.flags.?.lookup("version") != null) return;
        if (self._hasVersionFlag()) return;
        if (self.flags == null) return;
        var _v: bool = false;
        self.flags.?.boolVarP(&_v, "version", "", false, "print the version") catch {};
    }
    fn _hasVersionFlag(self: *Command) bool {
        if (self.flags != null and self.flags.?.lookup("version") != null) return true;
        if (self.parent) |p| return p._hasVersionFlag();
        return false;
    }
    pub fn initDefaultHelpCmd(_: *Command) void {}
    pub fn initDefaultCompletionCmd(_: *Command, io: std.Io, args: [][]const u8) void {
        _ = io;
        _ = args;
    }
    pub fn initCompleteCmd(_: *Command, io: std.Io, args: [][]const u8) void {
        _ = io;
        _ = args;
    }
    pub fn usagePadding(self: *const Command) usize {
        return if (self.commands_max_use_len > 25) self.commands_max_use_len else 25;
    }
    pub fn commandPathPadding(self: *const Command) usize {
        return if (self.commands_max_command_path_len > 11) self.commands_max_command_path_len else 11;
    }
    pub fn namePadding(self: *const Command) usize {
        return if (self.commands_max_name_len > 11) self.commands_max_name_len else 11;
    }
    pub fn checkCommandGroups(_: *const Command) void {}

    pub fn isFlagArg(arg: []const u8) bool {
        return (arg.len >= 3 and std.mem.eql(u8, arg[0..2], "--")) or
            (arg.len >= 2 and arg[0] == '-' and arg[1] != '-');
    }
};
pub const FlagSet = pflag.FlagSet;
pub const Flag = pflag.Flag;

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
