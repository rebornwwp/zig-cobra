//! Command is the core of cobra — a command abstraction for your CLI application.
//! Maps 1:1 from cobra/command.go
//!
//! Memory model notes (Zig-specific):
//! - Command instances should have stack lifetime; user commands must not be heap-allocated.
//!   EXCEPTION: internal helper commands (help, completion, __complete) created by this module
//!   are heap-allocated via the gpa passed to executeWrapper/execute and freed in deinit().
//! - Persistent flags are merged into a command's own flagset as *borrowed* pointers for the
//!   duration of flag parsing and removed afterwards, so no Flag is ever freed twice. Display
//!   views (localFlags/inheritedFlags) are built the same way and cleared in deinit().
const std = @import("std");
pub const pflag = @import("pflag");

const completions_mod = @import("completions.zig");
const Completion = completions_mod.Completion;
const ShellCompDirective = completions_mod.ShellCompDirective;
const CompletionFuncType = completions_mod.CompletionFunc;
const CompletionOptions = completions_mod.CompletionOptions;
const PositionalArgs = @import("args.zig").PositionalArgs;

/// Annotation key for flags set internally by cobra
pub const FlagSetByCobraAnnotation = "cobra_annotation_flag_set_by_cobra";
/// Annotation key for custom command display name
pub const CommandDisplayNameAnnotation = "cobra_annotation_command_display_name";
/// Standard name for the help flag
pub const help_flag_name = "help";
/// Standard name for the help command
pub const help_command_name = "help";
/// Standard name for the version flag
pub const version_flag_name = "version";

/// Annotation key (pflag-compatible) marking a flag as required.
pub const bash_comp_one_required_flag = "__cobra_bash_comp_one_required_flag";

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

/// Template function descriptor. NOTE: custom templates are currently stored verbatim but
/// NOT rendered — help/usage output is produced by the built-in renderer. Kept for API parity.
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

/// Execution state shared with library-internal commands (help, completion).
/// Zig has no closures, so io/gpa for internal command callbacks are staged here by
/// execute()/executeWrapper() before dispatch. Single-threaded CLI use only.
var exec_state: struct {
    io: ?std.Io = null,
    gpa: ?std.mem.Allocator = null,
} = .{};

/// Fallback stdout writer used when no out_writer is configured.
var fallback_out: ?std.Io.File.Writer = null;
var fallback_out_buf: [8192]u8 = undefined;
/// Fallback stderr writer used when no err_writer is configured.
var fallback_err: ?std.Io.File.Writer = null;
var fallback_err_buf: [8192]u8 = undefined;
/// Fallback stdin reader used when no in_reader is configured.
var fallback_in: ?std.Io.File.Reader = null;
var fallback_in_buf: [4096]u8 = undefined;

pub fn defaultStdout(io: std.Io) *std.Io.Writer {
    if (fallback_out == null) {
        fallback_out = std.Io.File.Writer.init(std.Io.File.stdout(), io, &fallback_out_buf);
    }
    return &fallback_out.?.interface;
}

pub fn defaultStderr(io: std.Io) *std.Io.Writer {
    if (fallback_err == null) {
        fallback_err = std.Io.File.Writer.init(std.Io.File.stderr(), io, &fallback_err_buf);
    }
    return &fallback_err.?.interface;
}

fn defaultStdin(io: std.Io) *std.Io.Reader {
    if (fallback_in == null) {
        fallback_in = std.Io.File.Reader.init(std.Io.File.stdin(), io, &fallback_in_buf);
    }
    return &fallback_in.?.interface;
}

/// Command is the core struct of cobra, representing a single CLI command.
/// All fields are public and can be set during initialization.
/// Important: user Command instances should have stack lifetime; avoid heap allocation
/// (library-internal helper commands are the documented exception, freed in deinit).
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
    /// Post-run hook: executed after this command's run (only when run succeeds)
    post_run: ?RunFunc = null,
    /// Post-run hook (fallible)
    post_run_e: ?RunEFunc = null,
    /// Persistent pre-run hook: executed before run (nearest in chain wins,
    /// unless cobra.enable_traverse_run_hooks is true)
    persistent_pre_run: ?RunFunc = null,
    /// Persistent pre-run hook (fallible)
    persistent_pre_run_e: ?RunEFunc = null,
    /// Persistent post-run hook: executed after run (nearest in chain wins,
    /// unless cobra.enable_traverse_run_hooks is true)
    persistent_post_run: ?RunFunc = null,
    /// Persistent post-run hook (fallible)
    persistent_post_run_e: ?RunEFunc = null,
    /// Flag parse error whitelist
    fparse_err_whitelist: FParseErrWhitelist = .{},
    /// Completion behavior configuration
    completion_options: CompletionOptions = .{},
    /// Resolve commands with Traverse semantics (parse flags at every level)
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
    /// Command group list (groups shown in help under their titles)
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
    /// Custom usage template (stored for API parity; not rendered — see TmplFunc note)
    usage_template: []const u8 = "",
    /// Custom help template (stored for API parity; not rendered — see TmplFunc note)
    help_template: []const u8 = "",
    /// Custom version template (stored for API parity; not rendered — see TmplFunc note)
    version_template: []const u8 = "",
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
    /// Local flag set (pointer to external FlagSet; owned_* variants are library-allocated)
    flags_ptr: ?*pflag.FlagSet = null,
    /// Persistent flag set (automatically inherited by subcommands)
    pflags: ?*pflag.FlagSet = null,
    /// Local flags view (own flags + own persistent, excluding inherited) — borrowed, library-owned
    lflags: ?*pflag.FlagSet = null,
    /// Inherited flags view (persistent flags of ancestors) — borrowed, library-owned
    iflags: ?*pflag.FlagSet = null,
    /// Union of all parent persistent flag sets — borrowed, library-owned
    parents_pflags: ?*pflag.FlagSet = null,
    /// Local non-persistent flags view — borrowed, library-owned
    lnpflags: ?*pflag.FlagSet = null,
    /// Opaque user data (e.g. pointer to application state)
    user_data: ?*anyopaque = null,

    // ─── Library-owned storage (do not set manually) ───
    owned_flags: ?pflag.FlagSet = null,
    owned_pflags: ?pflag.FlagSet = null,
    lflags_storage: ?pflag.FlagSet = null,
    iflags_storage: ?pflag.FlagSet = null,
    parents_pflags_storage: ?pflag.FlagSet = null,
    lnpflags_storage: ?pflag.FlagSet = null,
    /// Persistent storage for the auto-registered --help flag value
    help_flag_value: bool = false,
    /// Persistent storage for the auto-registered --version flag value
    version_flag_value: bool = false,
    /// Internal heap-allocated helper commands (help/completion/__complete), freed in deinit
    owned_internal_cmds: std.ArrayListUnmanaged(*Command) = .empty,
    /// Flag completion function registry (RegisterFlagCompletionFunc)
    flag_completions: std.StringHashMapUnmanaged(CompletionFuncType) = .empty,
    /// Allocated annotation value slices (flag groups), freed in deinit
    owned_annotation_values: std.ArrayListUnmanaged([]const []const u8) = .empty,
    /// Allocated flag-group key strings, freed in deinit
    owned_group_keys: std.ArrayListUnmanaged([]u8) = .empty,
    /// Boolean storage for library-internal flags (e.g. completion --no-descriptions)
    internal_flag_bool: bool = false,
    /// Detailed error message buffer (validation messages mirror Go's error strings)
    err_msg_buf: [2048]u8 = undefined,
    err_msg_len: usize = 0,
    /// Scratch buffers for computed strings
    path_buf: [512]u8 = undefined,
    use_line_buf: [640]u8 = undefined,
    alias_buf: [768]u8 = undefined,
    help_usage_buf: [128]u8 = undefined,
    version_usage_buf: [160]u8 = undefined,
    /// Flag error buffer (legacy field)
    flag_error_buf: ?*std.ArrayListUnmanaged(u8) = null,
    /// Maximum use field length among subcommands (for alignment)
    commands_max_use_len: usize = 0,
    /// Maximum command path length among subcommands
    commands_max_command_path_len: usize = 0,
    /// Maximum command name length among subcommands
    commands_max_name_len: usize = 0,

    // ─── Setters (Go API parity) ───

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
    pub fn setUsageTemplate(self: *Command, tmpl: []const u8) void {
        self.usage_template = tmpl;
    }
    pub fn setHelpTemplate(self: *Command, tmpl: []const u8) void {
        self.help_template = tmpl;
    }
    pub fn setVersionTemplate(self: *Command, tmpl: []const u8) void {
        self.version_template = tmpl;
    }

    // ─── IO resolution (never returns undefined) ───

    pub fn errOrStderr(self: *const Command, io: std.Io) *std.Io.Writer {
        if (self.err_writer) |w| return w;
        if (self.parent) |p| return p.errOrStderr(io);
        return defaultStderr(io);
    }
    pub fn outOrStdout(self: *const Command, io: std.Io) *std.Io.Writer {
        if (self.out_writer) |w| return w;
        if (self.parent) |p| return p.outOrStdout(io);
        return defaultStdout(io);
    }
    pub fn inOrStdin(self: *const Command, io: std.Io) *std.Io.Reader {
        if (self.in_reader) |r| return r;
        if (self.parent) |p| return p.inOrStdin(io);
        return defaultStdin(io);
    }

    pub fn hasParent(self: *const Command) bool {
        return self.parent != null;
    }
    pub fn getParent(self: *Command) ?*Command {
        return self.parent;
    }
    pub fn root(self: *Command) *Command {
        var c: *Command = self;
        while (c.parent) |p| : (c = p) {}
        return c;
    }

    // ─── Name/path helpers ───

    pub fn name(self: *const Command) []const u8 {
        if (std.mem.indexOfScalar(u8, self.use, ' ')) |i| return self.use[0..i];
        return self.use;
    }

    /// Returns the annotation-provided display name, or name() when unset (Go parity).
    pub fn displayName(self: *const Command) []const u8 {
        if (self.annotations.get(CommandDisplayNameAnnotation)) |vals| {
            if (vals.len > 0) return vals[0];
        }
        return self.name();
    }

    /// Full command path, e.g. "root sub leaf". Rendered into an internal buffer;
    /// valid until the next commandPath() call on the same Command.
    pub fn commandPath(self: *Command) []const u8 {
        var w = std.Io.Writer.fixed(&self.path_buf);
        self.writeCommandPath(&w);
        return self.path_buf[0..w.end];
    }

    fn writeCommandPath(self: *Command, w: *std.Io.Writer) void {
        if (self.parent) |p| {
            p.writeCommandPath(w);
            w.print(" {s}", .{self.displayName()}) catch {};
        } else {
            w.print("{s}", .{self.displayName()}) catch {};
        }
    }

    pub fn hasAlias(self: *const Command, s: []const u8) bool {
        for (self.aliases) |a| {
            if (@import("cobra.zig").commandNameMatches(a, s)) return true;
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
        for (self.commands.items) |sub| {
            if (sub.isAvailableCommand()) return true;
            if (sub == self.help_command) return true;
        }
        return false;
    }
    pub fn isAdditionalHelpTopicCommand(self: *const Command) bool {
        // Go parity: a non-runnable, non-hidden, non-deprecated command is a help
        // topic when ALL of its subcommands (if any) are help topics too.
        if (self.runnable() or self.deprecated.len != 0 or self.hidden) return false;
        for (self.commands.items) |sub| {
            if (!sub.isAdditionalHelpTopicCommand()) return false;
        }
        return true;
    }
    pub fn hasHelpSubCommands(self: *const Command) bool {
        for (self.commands.items) |sub| {
            if (sub.isAdditionalHelpTopicCommand()) return true;
        }
        return false;
    }

    pub fn getCommands(self: *Command) []*Command {
        if (@import("cobra.zig").enable_command_sorting and !self.commands_are_sorted) {
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
            if (cmd == self) @panic("cobra: command can't be a child of itself");
            cmd.parent = self;
            if (cmd.use.len > self.commands_max_use_len) self.commands_max_use_len = cmd.use.len;
            const cpl = cmd.commandPath().len;
            if (cpl > self.commands_max_command_path_len) self.commands_max_command_path_len = cpl;
            if (cmd.name().len > self.commands_max_name_len) self.commands_max_name_len = cmd.name().len;
            self.commands.append(gpa, cmd) catch @panic("cobra: OOM in addCommand");
            self.commands_are_sorted = false;
        }
    }

    pub fn groups(self: *Command) []*Group {
        return self.commandgroups.items;
    }
    pub fn containsGroup(self: *const Command, gid: []const u8) bool {
        for (self.commandgroups.items) |g| {
            if (std.mem.eql(u8, g.id, gid)) return true;
        }
        return false;
    }
    pub fn allChildCommandsHaveGroup(self: *const Command) bool {
        for (self.commands.items) |sub| {
            const considered = sub.isAvailableCommand() or sub == self.help_command;
            if (considered and sub.group_id.len == 0) return false;
        }
        return true;
    }
    pub fn addGroup(self: *Command, gpa: std.mem.Allocator, grp: []const *Group) void {
        self.commandgroups.appendSlice(gpa, grp) catch @panic("cobra: OOM in addGroup");
    }

    pub fn removeCommand(self: *Command, gpa: std.mem.Allocator, cmds: []const *Command) void {
        _ = gpa;
        var write: usize = 0;
        for (self.commands.items) |c| {
            var skip = false;
            for (cmds) |rc| {
                if (c == rc) {
                    c.parent = null;
                    skip = true;
                    break;
                }
            }
            if (!skip) {
                self.commands.items[write] = c;
                write += 1;
            }
        }
        self.commands.shrinkRetainingCapacity(write);
        self.commands_are_sorted = false;
        // Go parity: recompute all display lengths after removal.
        self.commands_max_use_len = 0;
        self.commands_max_command_path_len = 0;
        self.commands_max_name_len = 0;
        for (self.commands.items) |c| {
            if (c.use.len > self.commands_max_use_len) self.commands_max_use_len = c.use.len;
            const cpl = c.commandPath().len;
            if (cpl > self.commands_max_command_path_len) self.commands_max_command_path_len = cpl;
            if (c.name().len > self.commands_max_name_len) self.commands_max_name_len = c.name().len;
        }
    }

    pub fn resetCommands(self: *Command, gpa: std.mem.Allocator) void {
        for (self.commands.items) |c| c.parent = null;
        self.commands.clearRetainingCapacity();
        _ = gpa;
        self.parent = null;
        self.commands_are_sorted = false;
        self.help_command = null;
        self.parents_pflags = null;
    }

    pub fn deinit(self: *Command, gpa: std.mem.Allocator) void {
        for (self.commands.items) |c| c.deinit(gpa);
        self.commands.deinit(gpa);
        self.commandgroups.deinit(gpa);
        for (self.owned_internal_cmds.items) |c| {
            gpa.destroy(c);
        }
        self.owned_internal_cmds.deinit(gpa);
        self.flag_completions.deinit(gpa);
        for (self.owned_annotation_values.items) |vals| gpa.free(vals);
        self.owned_annotation_values.deinit(gpa);
        for (self.owned_group_keys.items) |k| gpa.free(k);
        self.owned_group_keys.deinit(gpa);
        // Owned flag storage: clear borrowed flags first so nothing is double-freed,
        // then release the FlagSet's own maps.
        if (self.owned_flags) |*fs| fs.deinit();
        self.owned_flags = null;
        self.flags_ptr = null;
        if (self.owned_pflags) |*fs| fs.deinit();
        self.owned_pflags = null;
        self.pflags = null;
        clearBorrowed(&self.parents_pflags_storage);
        if (self.parents_pflags_storage) |*fs| fs.deinit();
        self.parents_pflags_storage = null;
        self.parents_pflags = null;
        clearBorrowed(&self.lflags_storage);
        if (self.lflags_storage) |*fs| fs.deinit();
        self.lflags_storage = null;
        self.lflags = null;
        clearBorrowed(&self.iflags_storage);
        if (self.iflags_storage) |*fs| fs.deinit();
        self.iflags_storage = null;
        self.iflags = null;
        clearBorrowed(&self.lnpflags_storage);
        if (self.lnpflags_storage) |*fs| fs.deinit();
        self.lnpflags_storage = null;
        self.lnpflags = null;
    }

    // ─── Suggestions ───

    fn suggestionsMinDistance(self: *const Command) usize {
        return if (self.suggestions_minimum_distance == 0) 2 else self.suggestions_minimum_distance;
    }

    /// Go's SuggestionsFor: names within Levenshtein distance or having typed_name as prefix.
    pub fn suggestionsFor(self: *const Command, gpa: std.mem.Allocator, typed_name: []const u8) ![][]const u8 {
        var s: std.ArrayListUnmanaged([]const u8) = .empty;
        const min_dist = self.suggestionsMinDistance();
        const ld = @import("cobra.zig").levenshteinDistance;
        for (self.commands.items) |cmd| {
            if (!cmd.isAvailableCommand() and cmd != self.help_command) continue;
            if (ld(typed_name, cmd.name(), true) <= min_dist or
                (typed_name.len > 0 and std.ascii.startsWithIgnoreCase(cmd.name(), typed_name)))
            {
                try s.append(gpa, cmd.name());
            }
        }
        return try s.toOwnedSlice(gpa);
    }

    /// Renders Go's "\n\nDid you mean this?\n\t<suggestion>\n" block into an internal buffer.
    pub fn findSuggestions(self: *Command, typed_name: []const u8) []const u8 {
        if (self.disable_suggestions) return "";
        const min_dist = self.suggestionsMinDistance();
        const ld = @import("cobra.zig").levenshteinDistance;
        var buf = std.Io.Writer.fixed(self.err_msg_buf[self.err_msg_len..]);
        buf.print("\n\nDid you mean this?\n", .{}) catch return self.err_msg_buf[0..self.err_msg_len];
        var count: usize = 0;
        for (self.commands.items) |cmd| {
            if (!cmd.isAvailableCommand() and cmd != self.help_command) continue;
            const near = ld(typed_name, cmd.name(), true) <= min_dist;
            const prefixed = typed_name.len > 0 and std.ascii.startsWithIgnoreCase(cmd.name(), typed_name);
            if (near or prefixed) {
                buf.print("\t{s}\n", .{cmd.name()}) catch break;
                count += 1;
                if (count >= 8) break;
            }
        }
        if (count == 0) {
            // roll back the header
            return self.err_msg_buf[0..self.err_msg_len];
        }
        self.err_msg_len += buf.end;
        return self.err_msg_buf[0..self.err_msg_len];
    }

    pub fn visitParents(self: *Command, fn_ptr: *const fn (*Command) void) void {
        var c: ?*Command = self.parent;
        while (c) |p| : (c = p.parent) fn_ptr(p);
    }

    pub fn errPrefix(self: *const Command) []const u8 {
        if (self.err_prefix.len > 0) return self.err_prefix;
        if (self.hasParent()) return self.parent.?.errPrefix();
        return "Error:";
    }

    // ─── Output ───

    pub fn print(self: *Command, io: std.Io, comptime fmt_str: []const u8, args: anytype) void {
        const w = self.outOrStdout(io);
        w.print(fmt_str, args) catch {};
        w.flush() catch {};
    }
    pub fn println(self: *Command, io: std.Io, comptime fmt_str: []const u8, args: anytype) void {
        self.print(io, fmt_str ++ "\n", args);
    }
    pub fn printf(self: *Command, io: std.Io, comptime fmt_str: []const u8, args: anytype) void {
        self.print(io, fmt_str, args);
    }
    pub fn printErr(self: *Command, io: std.Io, comptime fmt_str: []const u8, args: anytype) void {
        const w = self.errOrStderr(io);
        w.print(fmt_str, args) catch {};
        w.flush() catch {};
    }
    pub fn printErrln(self: *Command, io: std.Io, comptime fmt_str: []const u8, args: anytype) void {
        self.printErr(io, fmt_str ++ "\n", args);
    }
    pub fn printErrf(self: *Command, io: std.Io, comptime fmt_str: []const u8, args: anytype) void {
        self.printErr(io, fmt_str, args);
    }

    // ─── Args validation ───

    pub fn validateArgs(self: *Command, args: []const []const u8) anyerror!void {
        if (self.args_validator) |a| {
            return a.validate(self, args);
        }
        // Go parity: default validator is legacyArgs.
        return @import("args.zig").legacyArgs().validate(self, args);
    }

    // ─── Execution (Go command.go execute() order) ───

    pub fn execute(self: *Command, io: std.Io, gpa: std.mem.Allocator, a: []const []const u8) anyerror!void {
        exec_state = .{ .io = io, .gpa = gpa };
        if (self.deprecated.len > 0) {
            self.printErr(io, "Command \"{s}\" is deprecated, {s}\n", .{ self.name(), self.deprecated });
        }

        self.initDefaultHelpFlag(gpa);
        self.initDefaultVersionFlag(gpa);

        var arg_wo_flags: []const []const u8 = a;
        if (!self.disable_flag_parsing) {
            // Build merged views (used by validators and help rendering), then parse.
            self.mergePersistentFlags(gpa);
            self.parseArgs(gpa, a) catch |err| {
                if (err == error.Help) {
                    self.printHelp(io);
                    return;
                }
                if (self.flag_error_func) |f| {
                    f(self, err) catch {};
                }
                try self.handleExecError(io, err);
                return err;
            };
            arg_wo_flags = self.flags_ptr.?.argList();
        }

        // --help: our registered flag or a user-provided help flag
        const help_requested = self.help_flag_value or
            (if (self.flags_ptr) |fs| (fs.getBool(help_flag_name) catch false) else false);
        if (help_requested) {
            self.printHelp(io);
            return;
        }

        // --version: our registered flag or a user-provided version flag
        if (self.version.len > 0) {
            const version_requested = self.version_flag_value or
                (if (self.flags_ptr) |fs| (fs.getBool(version_flag_name) catch false) else false);
            if (version_requested) {
                const w = self.outOrStdout(io);
                w.print("{s} version {s}\n", .{ self.displayName(), self.version }) catch {};
                w.flush() catch {};
                return;
            }
        }

        // Go parity: non-runnable command invocation prints help and skips
        // initializers/hooks/validation entirely (Go's execute() returns flag.ErrHelp here).
        if (!self.runnable()) {
            self.printHelp(io);
            return;
        }

        @import("cobra.zig").runInitializers();
        defer @import("cobra.zig").runFinalizers();

        self.validateArgs(arg_wo_flags) catch |err| {
            try self.handleExecError(io, err);
            return err;
        };

        const hook_args: [][]const u8 = @constCast(arg_wo_flags);

        self.execPersistentPreRun(hook_args) catch |err| {
            try self.handleExecError(io, err);
            return err;
        };
        if (self.pre_run_e) |f| {
            f(self, hook_args) catch |err| {
                try self.handleExecError(io, err);
                return err;
            };
        } else if (self.pre_run) |f| {
            f(self, hook_args);
        }

        self.validateRequiredFlags() catch |err| {
            try self.handleExecError(io, err);
            return err;
        };
        self.validateFlagGroups() catch |err| {
            try self.handleExecError(io, err);
            return err;
        };

        if (self.run_e) |f| {
            f(self, hook_args) catch |err| {
                try self.handleExecError(io, err);
                return err;
            };
        } else if (self.run) |f| {
            f(self, hook_args);
        } else {
            // Unreachable: the runnable() gate above guarantees run or run_e is set.
            @panic("cobra: execute() reached dispatch with non-runnable command");
        }

        if (self.post_run_e) |f| {
            f(self, hook_args) catch |err| {
                try self.handleExecError(io, err);
                return err;
            };
        } else if (self.post_run) |f| {
            f(self, hook_args);
        }
        self.execPersistentPostRun(hook_args) catch |err| {
            try self.handleExecError(io, err);
            return err;
        };
    }

    /// Trims trailing whitespace (std.mem.trimRight was removed in Zig 0.17).
    fn trimEnd(s: []const u8) []const u8 {
        var end = s.len;
        while (end > 0) {
            const c = s[end - 1];
            if (c != ' ' and c != '\t' and c != '\n' and c != '\r') break;
            end -= 1;
        }
        return s[0..end];
    }

    /// Prints "Error: <msg>" (unless silenced) and usage (unless silenced),
    /// preferring the detailed message staged in err_msg_buf.
    fn handleExecError(self: *Command, io: std.Io, err: anyerror) anyerror!void {
        if (!self.silence_errors) {
            if (self.err_msg_len > 0) {
                self.printErr(io, "{s} {s}\n", .{ self.errPrefix(), self.err_msg_buf[0..self.err_msg_len] });
            } else {
                self.printErr(io, "{s} {s}\n", .{ self.errPrefix(), @errorName(err) });
            }
        }
        self.err_msg_len = 0;
        if (!self.silence_usage) self.printUsage(io);
    }

    /// Stages a detailed error message (Go-style error text) into err_msg_buf.
    /// handleExecError prefers this over the bare error name. Custom argument
    /// validators may use it to provide richer messages.
    pub fn setErrMsg(self: *Command, comptime fmt_str: []const u8, args: anytype) void {
        var w = std.Io.Writer.fixed(&self.err_msg_buf);
        w.print(fmt_str, args) catch {};
        self.err_msg_len = w.end;
    }

    /// Go parity: only the NEAREST command defining a persistent run hook executes it,
    /// unless cobra.enable_traverse_run_hooks is enabled (then the whole chain runs).
    /// Hooks receive the executing command (self), like Go does.
    fn execPersistentPreRun(self: *Command, args: [][]const u8) anyerror!void {
        const traverse_hooks = @import("cobra.zig").enable_traverse_run_hooks;
        var c: ?*Command = self;
        while (c) |p| : (c = p.parent) {
            if (p.persistent_pre_run_e) |f| {
                try f(self, args);
                if (!traverse_hooks) return;
            } else if (p.persistent_pre_run) |f| {
                f(self, args);
                if (!traverse_hooks) return;
            }
        }
    }
    fn execPersistentPostRun(self: *Command, args: [][]const u8) anyerror!void {
        const traverse_hooks = @import("cobra.zig").enable_traverse_run_hooks;
        var c: ?*Command = self;
        while (c) |p| : (c = p.parent) {
            if (p.persistent_post_run_e) |f| {
                try f(self, args);
                if (!traverse_hooks) return;
            } else if (p.persistent_post_run) |f| {
                f(self, args);
                if (!traverse_hooks) return;
            }
        }
    }

    // ─── Help / Usage rendering (Go template output parity) ───

    /// Displays the help for this command (Go: Help()).
    pub fn help(self: *Command, io: std.Io) anyerror!void {
        if (self.helpFunc()) |f| {
            f(self, &.{});
            return;
        }
        self.printHelp(io);
    }

    /// Renders full help (description + usage) to errOrStderr (Go: Help() writes to OutOrStderr).
    pub fn printHelp(self: *Command, io: std.Io) void {
        if (self.help_func) |f| {
            f(self, &.{});
            return;
        }
        const w = self.errOrStderr(io);
        const desc = self.description();
        if (desc.len > 0) {
            const trimmed = trimEnd(desc);
            w.print("{s}\n\n", .{trimmed}) catch {};
        }
        if (self.runnable() or self.hasSubCommands()) {
            self.renderUsage(w);
        }
        w.flush() catch {};
    }

    /// Long description if set, else short (Go template: or .Long .Short).
    pub fn description(self: *const Command) []const u8 {
        if (self.long.len > 0) return self.long;
        return self.short;
    }

    /// Renders the usage block (Go's default usage template output).
    pub fn printUsage(self: *Command, io: std.Io) void {
        if (self.usage_func) |f| {
            f(self) catch {};
            return;
        }
        const w = self.errOrStderr(io);
        self.renderUsage(w);
        w.flush() catch {};
    }

    fn renderUsage(self: *Command, w: *std.Io.Writer) void {
        w.print("Usage:", .{}) catch {};
        if (self.runnable()) w.print("\n  {s}", .{self.useLine()}) catch {};
        if (self.hasAvailableSubCommands()) w.print("\n  {s} [command]", .{self.commandPath()}) catch {};

        if (self.aliases.len > 0) {
            w.print("\n\nAliases:\n  {s}", .{self.nameAndAliases()}) catch {};
        }

        if (self.hasExample()) {
            w.print("\n\nExamples:\n{s}", .{self.example}) catch {};
        }

        if (self.hasAvailableSubCommands()) {
            const pad = self.subCommandNamePad();
            if (self.commandgroups.items.len == 0) {
                w.print("\n\nAvailable Commands:", .{}) catch {};
                for (self.getCommands()) |sub| {
                    if (!sub.isAvailableCommand() and sub != self.help_command) continue;
                    writePaddedName(w, sub.name(), pad);
                    w.print(" {s}", .{sub.short}) catch {};
                }
            } else {
                for (self.commandgroups.items) |group| {
                    w.print("\n\n{s}", .{group.title}) catch {};
                    for (self.getCommands()) |sub| {
                        if (!std.mem.eql(u8, sub.group_id, group.id)) continue;
                        if (!sub.isAvailableCommand() and sub != self.help_command) continue;
                        writePaddedName(w, sub.name(), pad);
                        w.print(" {s}", .{sub.short}) catch {};
                    }
                }
                if (!self.allChildCommandsHaveGroup()) {
                    w.print("\n\nAdditional Commands:", .{}) catch {};
                    for (self.getCommands()) |sub| {
                        if (!sub.isAvailableCommand() and sub != self.help_command) continue;
                        if (sub.group_id.len > 0) continue;
                        writePaddedName(w, sub.name(), pad);
                        w.print(" {s}", .{sub.short}) catch {};
                    }
                }
            }
        }

        // Build merged local/inherited views when an allocator is available.
        if (exec_state.gpa) |g| self.mergePersistentFlags(g);

        // Flags: (local = own flags + own persistent, excluding inherited)
        if (self.hasAvailableLocalFlags()) {
            w.print("\n\nFlags:\n", .{}) catch {};
            const local = self.lflags orelse self.flags_ptr;
            self.renderFlagSetDefaults(w, local, true);
            // When no merged view exists, still show own persistent flags.
            if (self.lflags == null) {
                if (self.pflags) |pf| self.renderFlagSetDefaults(w, pf, true);
            }
        }

        // Global Flags: (inherited persistent flags from ancestors)
        if (self.hasAvailableInheritedFlags()) {
            w.print("\n\nGlobal Flags:\n", .{}) catch {};
            self.renderFlagSetDefaults(w, self.inheritedFlagsView(), true);
        }

        if (self.hasHelpSubCommands()) {
            w.print("\n\nAdditional help topics:", .{}) catch {};
            for (self.getCommands()) |sub| {
                if (!sub.isAdditionalHelpTopicCommand()) continue;
                w.print("\n  {s} {s}", .{ sub.name(), sub.short }) catch {};
            }
        }

        if (self.hasAvailableSubCommands()) {
            w.print("\n\nUse \"{s} [command] --help\" for more information about a command.", .{self.commandPath()}) catch {};
        }
        w.print("\n", .{}) catch {};
    }

    fn subCommandNamePad(self: *const Command) usize {
        return self.namePadding();
    }

    /// Prints "\n  <name>" followed by spaces up to `pad` columns (Go's rpad behavior).
    fn writePaddedName(w: *std.Io.Writer, name_str: []const u8, pad: usize) void {
        w.print("\n  {s}", .{name_str}) catch {};
        var i: usize = name_str.len;
        while (i < pad) : (i += 1) {
            w.print(" ", .{}) catch {};
        }
    }

    /// Renders a flagset's defaults into w by temporarily redirecting its out_writer.
    fn renderFlagSetDefaults(self: *Command, w: *std.Io.Writer, fs_opt: ?*pflag.FlagSet, trim: bool) void {
        _ = self;
        _ = trim;
        const fs = fs_opt orelse return;
        const saved = fs.out_writer;
        fs.out_writer = w;
        fs.printDefaults();
        fs.out_writer = saved;
    }

    /// Full usage text as an owned, allocated string (Go: UsageString()). Caller frees with gpa.
    pub fn usageString(self: *Command, gpa: std.mem.Allocator) ![]u8 {
        var buf: [8192]u8 = undefined;
        var w = std.Io.Writer.fixed(&buf);
        self.renderUsage(&w);
        return gpa.dupe(u8, buf[0..w.end]);
    }

    pub fn helpFunc(self: *const Command) ?HelpFuncType {
        if (self.help_func) |f| return f;
        if (self.hasParent()) return self.parent.?.helpFunc();
        return null;
    }
    pub fn flagErrorFunc(self: *const Command) ?FlagErrorFuncType {
        if (self.flag_error_func) |f| return f;
        if (self.hasParent()) return self.parent.?.flagErrorFunc();
        return null;
    }
    pub fn usageFunc(self: *const Command) ?UsageFuncType {
        if (self.usage_func) |f| return f;
        if (self.hasParent()) return self.parent.?.usageFunc();
        return null;
    }
    pub fn usageTemplate(self: *const Command) []const u8 {
        if (self.usage_template.len > 0) return self.usage_template;
        if (self.hasParent()) return self.parent.?.usageTemplate();
        return default_usage_template;
    }
    pub fn helpTemplate(self: *const Command) []const u8 {
        if (self.help_template.len > 0) return self.help_template;
        if (self.hasParent()) return self.parent.?.helpTemplate();
        return default_help_template;
    }
    pub fn versionTemplate(self: *const Command) []const u8 {
        if (self.version_template.len > 0) return self.version_template;
        if (self.hasParent()) return self.parent.?.versionTemplate();
        return default_version_template;
    }

    // ─── ExecuteC equivalent ───

    /// Executes with the args previously set via setArgs() (Go: Execute()).
    pub fn executeContext(self: *Command, io: std.Io, gpa: std.mem.Allocator) anyerror!void {
        const a = self.args_slice;
        return self.execute(io, gpa, a);
    }

    /// Top-level entry point (Go: ExecuteC()). Resolves the target command, wires default
    /// help/completion commands, reports errors with usage, and executes.
    pub fn executeWrapper(self: *Command, gpa: std.mem.Allocator) anyerror!void {
        const io = std.Io.Threaded.global_single_threaded.*.io();
        exec_state = .{ .io = io, .gpa = gpa };

        self.initDefaultHelpCmd(gpa);
        self.initDefaultCompletionCmd(gpa);
        self.initCompleteCmd(gpa);
        self.checkCommandGroups();

        const found = self.findForExec(gpa, self.args_slice);
        defer if (found.owned_args) |a| gpa.free(a);
        const cmd = found.cmd;
        if (found.err) |e| {
            if (!cmd.silence_errors) {
                if (cmd.err_msg_len > 0) {
                    cmd.printErr(io, "{s} {s}\n", .{ cmd.errPrefix(), cmd.err_msg_buf[0..cmd.err_msg_len] });
                } else {
                    cmd.printErr(io, "{s} {s}\n", .{ cmd.errPrefix(), @errorName(e) });
                }
            }
            cmd.err_msg_len = 0;
            if (!cmd.silence_usage) cmd.printUsage(io);
            return e;
        }
        return cmd.execute(io, gpa, found.args);
    }

    fn findForExec(self: *Command, gpa: std.mem.Allocator, args: []const []const u8) FindResult {
        if (self.traverse_children) return self.traverse(gpa, args);
        const found = self.find(gpa, args);
        if (found.err) |e| {
            if (e == error.UnknownCommand and !self.disable_suggestions and found.unknown_arg.len > 0) {
                var msg_cmd = found.cmd;
                msg_cmd.setErrMsg("unknown command \"{s}\" for \"{s}\"", .{ found.unknown_arg, msg_cmd.commandPath() });
                _ = msg_cmd.findSuggestions(found.unknown_arg);
            } else if (found.cmd.err_msg_len == 0) {
                found.cmd.setErrMsg("{s}", .{@errorName(e)});
            }
        }
        return found;
    }

    // ─── Default flags ───

    /// Ensures this command owns (or references) a FlagSet (Go parity: Flags() never nil).
    pub fn ensureFlags(self: *Command, gpa: std.mem.Allocator) *pflag.FlagSet {
        if (self.flags_ptr) |fs| return fs;
        if (self.owned_flags == null) {
            var fs = pflag.FlagSet.init(gpa, self.name());
            fs.error_handling = .continue_on_error;
            self.owned_flags = fs;
        }
        self.flags_ptr = &self.owned_flags.?;
        return self.flags_ptr.?;
    }

    pub fn ensurePersistentFlags(self: *Command, gpa: std.mem.Allocator) *pflag.FlagSet {
        if (self.pflags) |fs| return fs;
        if (self.owned_pflags == null) {
            var fs = pflag.FlagSet.init(gpa, self.name());
            fs.error_handling = .continue_on_error;
            self.owned_pflags = fs;
        }
        self.pflags = &self.owned_pflags.?;
        return self.pflags.?;
    }

    /// Registers --help if not already defined (Go: InitDefaultHelpFlag).
    pub fn initDefaultHelpFlag(self: *Command, gpa: std.mem.Allocator) void {
        const fs = self.ensureFlags(gpa);
        if (fs.lookup(help_flag_name) != null) return;
        var usage_w = std.Io.Writer.fixed(&self.help_usage_buf);
        if (self.displayName().len > 0) {
            usage_w.print("help for {s}", .{self.displayName()}) catch {};
        } else {
            usage_w.print("help for this command", .{}) catch {};
        }
        const usage_w_end = usage_w.end;
        const usage = self.help_usage_buf[0..usage_w_end];
        if (fs.shorthandLookup('h') == null) {
            fs.boolVarP(&self.help_flag_value, help_flag_name, "h", false, usage) catch {
                fs.boolVar(&self.help_flag_value, help_flag_name, false, usage) catch @panic("cobra: failed to register default --help flag");
            };
        } else {
            fs.boolVar(&self.help_flag_value, help_flag_name, false, usage) catch @panic("cobra: failed to register default --help flag");
        }
        if (fs.lookup(help_flag_name)) |f| {
            f.annotations.put(gpa, FlagSetByCobraAnnotation, &.{"true"}) catch @panic("cobra: OOM annotating --help flag");
        }
    }

    /// Registers --version when version is set (Go: InitDefaultVersionFlag).
    pub fn initDefaultVersionFlag(self: *Command, gpa: std.mem.Allocator) void {
        if (self.version.len == 0) return;
        const fs = self.ensureFlags(gpa);
        if (fs.lookup(version_flag_name) != null) return;
        var usage_w = std.Io.Writer.fixed(&self.version_usage_buf);
        if (self.displayName().len > 0) {
            usage_w.print("version for {s}", .{self.displayName()}) catch {};
        } else {
            usage_w.print("version for this command", .{}) catch {};
        }
        const usage_w_end = usage_w.end;
        const usage = self.version_usage_buf[0..usage_w_end];
        if (fs.shorthandLookup('v') == null) {
            fs.boolVarP(&self.version_flag_value, version_flag_name, "v", false, usage) catch {
                fs.boolVar(&self.version_flag_value, version_flag_name, false, usage) catch @panic("cobra: failed to register default --version flag");
            };
        } else {
            fs.boolVar(&self.version_flag_value, version_flag_name, false, usage) catch @panic("cobra: failed to register default --version flag");
        }
    }

    // ─── Default commands ───

    fn trackInternal(self: *Command, gpa: std.mem.Allocator, cmd: *Command) void {
        // MUST NOT swallow: an untracked internal command would leak in deinit.
        self.root().owned_internal_cmds.append(gpa, cmd) catch @panic("cobra: OOM tracking internal command");
    }

    /// Creates the default `help` subcommand (Go: InitDefaultHelpCmd).
    pub fn initDefaultHelpCmd(self: *Command, gpa: std.mem.Allocator) void {
        if (!self.hasSubCommands()) return;
        if (self.help_command == null) {
            const hc = gpa.create(Command) catch @panic("cobra: OOM creating help command");
            hc.* = .{
                .use = "help [command]",
                .short = "Help about any command",
                .run_e = helpCommandRun,
                .hidden = false,
            };
            // `long` needs stable storage — render into the heap-owned command's own buffer.
            var lw = std.Io.Writer.fixed(&hc.alias_buf);
            lw.print(
                "Help provides help for any command in the application.\nSimply type {s} help [path to command] for full details.",
                .{self.displayName()},
            ) catch {};
            hc.long = hc.alias_buf[0..lw.end];
            if (self.help_command_group_id.len > 0) hc.group_id = self.help_command_group_id;
            self.help_command = hc;
            self.trackInternal(gpa, hc);
        }
        if (!self.hasHelpCommand()) {
            self.addCommand(gpa, &.{self.help_command.?});
        }
    }

    fn hasHelpCommand(self: *const Command) bool {
        for (self.commands.items) |c| {
            if (c == self.help_command) return true;
        }
        return false;
    }

    fn helpCommandRun(cmd: *Command, args: [][]const u8) anyerror!void {
        const io = exec_state.io orelse return error.NoIoState;
        const gpa = exec_state.gpa orelse return error.NoGpaState;
        const r = cmd.root();
        const found = r.find(gpa, args);
        defer if (found.owned_args) |a| gpa.free(a);
        if (found.err != null) {
            var joined: [256]u8 = undefined;
            var jw = std.Io.Writer.fixed(&joined);
            for (args, 0..) |a, i| {
                if (i > 0) jw.print(" ", .{}) catch {};
                jw.print("{s}", .{a}) catch {};
            }
            cmd.print(io, "Unknown help command \"{s}\"\n", .{joined[0..jw.end]});
            return;
        }
        found.cmd.initDefaultHelpFlag(gpa);
        found.cmd.printHelp(io);
    }

    /// Creates the default `completion` command with bash/zsh/fish/powershell children
    /// (Go: InitDefaultCompletionCmd).
    pub fn initDefaultCompletionCmd(self: *Command, gpa: std.mem.Allocator) void {
        const opts = self.root().completion_options;
        if (opts.disable_default_cmd) return;
        if (!self.hasSubCommands()) return;
        // Idempotence: don't add twice; respect a user-provided `completion` command.
        for (self.commands.items) |c| {
            if (std.mem.eql(u8, c.name(), completions_mod.completion_command_name)) return;
            if (c.hasAlias(completions_mod.completion_command_name)) return;
        }

        const have_no_desc_flag = !opts.disable_no_desc_flag and !opts.disable_descriptions;

        const parent = gpa.create(Command) catch @panic("cobra: OOM creating completion command");
        parent.* = .{
            .use = completions_mod.completion_command_name,
            .short = "Generate the autocompletion script for the specified shell",
            .args_validator = @import("args.zig").noArgs(),
            .hidden = opts.hidden_default_cmd,
            .valid_args_function = completions_mod.noFileCompletions(),
        };
        parent.long =
            \\Generate the autocompletion script for this application, to load it into your shell.
            \\See each sub-command's help for details on how to use the generated script.
        ;
        if (self.completion_command_group_id.len > 0) parent.group_id = self.completion_command_group_id;
        self.trackInternal(gpa, parent);

        const defs = [_]struct { use: []const u8, short: []const u8, f: RunFunc, no_desc_flag: bool }{
            .{ .use = "bash", .short = "Generate the autocompletion script for bash", .f = completionBashRun, .no_desc_flag = true },
            .{ .use = "zsh", .short = "Generate the autocompletion script for zsh", .f = completionZshRun, .no_desc_flag = true },
            .{ .use = "fish", .short = "Generate the autocompletion script for fish", .f = completionFishRun, .no_desc_flag = true },
            .{ .use = "powershell", .short = "Generate the autocompletion script for powershell", .f = completionPowerShellRun, .no_desc_flag = true },
        };
        for (defs) |d| {
            const c = gpa.create(Command) catch @panic("cobra: OOM creating completion command");
            c.* = .{
                .use = d.use,
                .short = d.short,
                .run = d.f,
                .args_validator = @import("args.zig").noArgs(),
                .valid_args_function = completions_mod.noFileCompletions(),
            };
            if (have_no_desc_flag and d.no_desc_flag) {
                const fs = c.ensureFlags(gpa);
                fs.boolVar(&c.internal_flag_bool, completions_mod.comp_cmd_no_desc_flag_name, completions_mod.comp_cmd_no_desc_flag_default, completions_mod.comp_cmd_no_desc_flag_desc) catch @panic("cobra: failed to register completion --no-descriptions flag");
            }
            parent.addCommand(gpa, &.{c});
            self.trackInternal(gpa, c);
        }
        self.addCommand(gpa, &.{parent});
    }

    /// Effective include-descriptions for a completion subcommand run.
    fn completionIncludeDesc(cmd: *Command) bool {
        return !cmd.internal_flag_bool and !cmd.root().completion_options.disable_descriptions;
    }

    fn completionBashRun(cmd: *Command, args: [][]const u8) void {
        _ = args;
        const io = exec_state.io orelse return;
        const w = cmd.outOrStdout(io);
        completions_mod.genBashCompletionV2(cmd.root(), w, completionIncludeDesc(cmd)) catch {};
        w.flush() catch {};
    }
    fn completionZshRun(cmd: *Command, args: [][]const u8) void {
        _ = args;
        const io = exec_state.io orelse return;
        const w = cmd.outOrStdout(io);
        completions_mod.genZshCompletion(cmd.root(), w, completionIncludeDesc(cmd)) catch {};
        w.flush() catch {};
    }
    fn completionFishRun(cmd: *Command, args: [][]const u8) void {
        _ = args;
        const io = exec_state.io orelse return;
        const w = cmd.outOrStdout(io);
        completions_mod.genFishCompletion(cmd.root(), w, completionIncludeDesc(cmd)) catch {};
        w.flush() catch {};
    }
    fn completionPowerShellRun(cmd: *Command, args: [][]const u8) void {
        _ = args;
        const io = exec_state.io orelse return;
        const w = cmd.outOrStdout(io);
        completions_mod.genPowerShellCompletion(cmd.root(), w, completionIncludeDesc(cmd)) catch {};
        w.flush() catch {};
    }

    /// Creates the hidden __complete machinery (Go: initCompleteCmd).
    /// __completeNoDesc is an ALIAS (Go parity); the run distinguishes via calledAs().
    pub fn initCompleteCmd(self: *Command, gpa: std.mem.Allocator) void {
        if (!self.hasSubCommands()) return;
        for (self.commands.items) |c| {
            if (std.mem.eql(u8, c.name(), completions_mod.shell_comp_request_cmd)) return;
        }
        const complete = gpa.create(Command) catch @panic("cobra: OOM creating __complete command");
        complete.* = .{
            .use = completions_mod.shell_comp_request_cmd,
            .aliases = &.{completions_mod.shell_comp_no_desc_request_cmd},
            .short = "Request shell completion choices for the specified command-line",
            .long = completions_mod.shell_comp_request_cmd ++
                " is a special command used by the shell completion logic to request completion choices.",
            .hidden = true,
            .disable_flag_parsing = true,
            .args_validator = @import("args.zig").minimumNArgs(1),
            .run_e = completeCmdRun,
        };
        self.trackInternal(gpa, complete);
        self.addCommand(gpa, &.{complete});
    }

    fn completeCmdRun(cmd: *Command, args: [][]const u8) anyerror!void {
        const with_desc = !std.mem.eql(u8, cmd.calledAs(), completions_mod.shell_comp_no_desc_request_cmd);
        try runCompletionRequest(cmd, args, with_desc);
    }
    fn runCompletionRequest(cmd: *Command, args: [][]const u8, with_desc: bool) anyerror!void {
        const io = exec_state.io orelse return error.NoIoState;
        const gpa = exec_state.gpa orelse return error.NoGpaState;
        try completions_mod.getCompletions(cmd.root(), io, gpa, args, with_desc);
    }

    /// Validates that every child command's group_id is a registered group (Go panics on misuse).
    pub fn checkCommandGroups(self: *const Command) void {
        for (self.commands.items) |sub| {
            const considered = sub.isAvailableCommand() or sub == self.help_command;
            if (!considered) continue;
            sub.checkCommandGroups();
            if (sub.group_id.len > 0 and !self.containsGroup(sub.group_id)) {
                @panic("cobra: group id of command is not defined");
            }
        }
    }

    pub fn isFlagArg(arg: []const u8) bool {
        return (arg.len >= 3 and std.mem.eql(u8, arg[0..2], "--")) or
            (arg.len >= 2 and arg[0] == '-' and arg[1] != '-');
    }

    // ─── Flag accessors ───

    /// Returns this command's own FlagSet, lazily creating an owned one (Go: Flags()).
    pub fn flags(self: *Command, gpa: std.mem.Allocator) *pflag.FlagSet {
        return self.ensureFlags(gpa);
    }
    /// Raw accessor without lazy creation (may be null).
    pub fn flagsPtr(self: *const Command) ?*pflag.FlagSet {
        return self.flags_ptr;
    }

    /// Returns this command's persistent FlagSet, lazily creating an owned one.
    pub fn persistentFlags(self: *Command, gpa: std.mem.Allocator) *pflag.FlagSet {
        return self.ensurePersistentFlags(gpa);
    }
    pub fn persistentFlagsPtr(self: *const Command) ?*pflag.FlagSet {
        return self.pflags;
    }

    /// Builds the borrowed parents_pflags view (union of ancestors' persistent flags).
    /// When `rebuild` is true the view is refreshed (flags may have been added since).
    pub fn updateParentsPflags(self: *Command, gpa: std.mem.Allocator, rebuild: bool) void {
        if (self.parents_pflags != null and !rebuild) return;
        if (!self.hasParent()) {
            self.parents_pflags = null;
            return;
        }
        if (self.parents_pflags_storage == null) {
            var fs = pflag.FlagSet.init(gpa, "parents");
            fs.error_handling = .continue_on_error;
            self.parents_pflags_storage = fs;
        }
        const view = &self.parents_pflags_storage.?;
        clearBorrowed(&self.parents_pflags_storage);
        var p: ?*Command = self.parent;
        // Farthest ancestor first so nearest flags win name conflicts.
        var chain: [32]*Command = undefined;
        var n: usize = 0;
        while (p) |cur| {
            if (n >= chain.len) @panic("cobra: command tree deeper than 32 levels");
            chain[n] = cur;
            n += 1;
            p = cur.parent;
        }
        while (n > 0) {
            n -= 1;
            if (chain[n].pflags) |pf| addBorrowedFlags(view, pf);
        }
        self.parents_pflags = view;
    }

    /// Builds local/inherited views and ensures flags exist (Go: MergePersistentFlags()).
    /// Views hold borrowed flag pointers and are rebuilt on every call so that flags
    /// registered later (e.g. the implicit --help) are always reflected.
    pub fn mergePersistentFlags(self: *Command, gpa: std.mem.Allocator) void {
        _ = self.ensureFlags(gpa);
        self.updateParentsPflags(gpa, true);

        // Local flags = own flags + own persistent, minus inherited (Go: LocalFlags).
        if (self.lflags_storage == null) {
            var fs = pflag.FlagSet.init(gpa, "local");
            fs.error_handling = .continue_on_error;
            self.lflags_storage = fs;
        }
        {
            const view = &self.lflags_storage.?;
            clearBorrowed(&self.lflags_storage);
            if (self.flags_ptr) |f| addBorrowedFlags(view, f);
            if (self.pflags) |pf| addBorrowedFlags(view, pf);
            if (self.parents_pflags) |pp| removeFlagsPresent(view, pp);
            self.lflags = view;
        }

        // Inherited = ancestors' persistent flags (null when there is no parent chain).
        if (self.parents_pflags) |pp| {
            if (self.iflags_storage == null) {
                var fs = pflag.FlagSet.init(gpa, "inherited");
                fs.error_handling = .continue_on_error;
                self.iflags_storage = fs;
            }
            const view = &self.iflags_storage.?;
            clearBorrowed(&self.iflags_storage);
            addBorrowedFlags(view, pp);
            self.iflags = view;
        } else {
            self.iflags = null;
        }

        // Local non-persistent = own flags minus own persistent (Go: LocalNonPersistentFlags).
        if (self.lnpflags_storage == null) {
            var fs = pflag.FlagSet.init(gpa, "localNonPersistent");
            fs.error_handling = .continue_on_error;
            self.lnpflags_storage = fs;
        }
        {
            const view = &self.lnpflags_storage.?;
            clearBorrowed(&self.lnpflags_storage);
            if (self.flags_ptr) |f| addBorrowedFlags(view, f);
            if (self.pflags) |pf| removeFlagsPresent(view, pf);
            self.lnpflags = view;
        }
    }

    /// Local flags view (own + own persistent). Requires mergePersistentFlags first.
    pub fn localFlagsView(self: *const Command) ?*pflag.FlagSet {
        return self.lflags;
    }
    /// Inherited flags view. Requires mergePersistentFlags first.
    pub fn inheritedFlagsView(self: *const Command) ?*pflag.FlagSet {
        return self.iflags;
    }

    pub fn localFlags(self: *Command, gpa: std.mem.Allocator) ?*pflag.FlagSet {
        self.mergePersistentFlags(gpa);
        return self.lflags;
    }
    pub fn inheritedFlags(self: *Command, gpa: std.mem.Allocator) ?*pflag.FlagSet {
        self.mergePersistentFlags(gpa);
        return self.iflags;
    }
    pub fn parentsPflags(self: *Command, gpa: std.mem.Allocator) ?*pflag.FlagSet {
        self.updateParentsPflags(gpa, false);
        return self.parents_pflags;
    }
    pub fn nonInheritedFlags(self: *Command, gpa: std.mem.Allocator) ?*pflag.FlagSet {
        return self.localFlags(gpa);
    }
    pub fn localNonPersistentFlags(self: *Command, gpa: std.mem.Allocator) ?*pflag.FlagSet {
        self.mergePersistentFlags(gpa);
        return self.lnpflags;
    }

    /// Lookup a flag by name across this command and its ancestors (Go: Flag()).
    pub fn flag(self: *const Command, flag_name: []const u8) ?*pflag.Flag {
        if (self.flags_ptr) |fs| {
            if (fs.lookup(flag_name)) |f| return f;
        }
        if (self.pflags) |pf| {
            if (pf.lookup(flag_name)) |f| return f;
        }
        if (self.parent) |p| return p.flag(flag_name);
        return null;
    }

    // ─── Flag queries ───

    fn setHasAvailableFlags(fs: ?*pflag.FlagSet) bool {
        const f = fs orelse return false;
        for (f.ordered_formal.items) |fl| {
            if (!fl.hidden) return true;
        }
        return false;
    }

    pub fn hasFlags(self: *const Command) bool {
        if (self.flags_ptr != null or self.pflags != null) return true;
        return self.hasInheritedFlags();
    }
    pub fn hasLocalFlags(self: *const Command) bool {
        return setHasAvailableFlags(self.flags_ptr) or setHasAvailableFlags(self.pflags);
    }
    pub fn hasInheritedFlags(self: *const Command) bool {
        var p: ?*const Command = self.parent;
        while (p) |cur| : (p = cur.parent) {
            if (setHasAvailableFlags(cur.pflags)) return true;
        }
        return false;
    }
    pub fn hasPersistentFlags(self: *const Command) bool {
        return setHasAvailableFlags(self.pflags);
    }
    pub fn hasAvailableFlags(self: *const Command) bool {
        return setHasAvailableFlags(self.flags_ptr) or self.hasAvailablePersistentFlags() or self.hasAvailableInheritedFlags();
    }
    pub fn hasAvailableLocalFlags(self: *const Command) bool {
        return setHasAvailableFlags(self.lflags) or setHasAvailableFlags(self.flags_ptr) or setHasAvailableFlags(self.pflags);
    }
    pub fn hasAvailableInheritedFlags(self: *const Command) bool {
        return setHasAvailableFlags(self.iflags) or self.hasInheritedFlags();
    }
    pub fn hasAvailablePersistentFlags(self: *const Command) bool {
        return setHasAvailableFlags(self.pflags);
    }

    // ─── Required flags & flag groups (Go: ValidateRequiredFlags / ValidateFlagGroups) ───

    const RequiredCtx = struct {
        names: *[32][]const u8,
        count: *usize,
    };

    /// Validates that all flags annotated as required were set. Stages a Go-parity message
    /// in err_msg_buf and returns error.RequiredFlagsMissing on failure.
    pub fn validateRequiredFlags(self: *const Command) anyerror!void {
        if (self.disable_flag_parsing) return;
        const fs = self.flags_ptr orelse return;
        var names: [32][]const u8 = undefined;
        var count: usize = 0;
        const ctx = RequiredCtx{ .names = &names, .count = &count };
        fs.visitAll(ctx, struct {
            fn cb(c: RequiredCtx, f: *pflag.Flag) void {
                const ann = f.annotations.get(bash_comp_one_required_flag) orelse return;
                if (ann.len == 0) return;
                if (!std.mem.eql(u8, ann[0], "true")) return;
                if (f.changed) return;
                if (c.count.* >= c.names.len) return;
                c.names[c.count.*] = f.name;
                c.count.* += 1;
            }
        }.cb);
        if (count == 0) return;

        const this = @constCast(self);
        var w = std.Io.Writer.fixed(&this.err_msg_buf);
        w.print("required flag(s) ", .{}) catch {};
        for (names[0..count], 0..) |n, i| {
            if (i + 1 == count) {
                w.print("\"{s}\"", .{n}) catch {};
            } else {
                w.print("\"{s}\", ", .{n}) catch {};
            }
        }
        w.print(" not set", .{}) catch {};
        this.err_msg_len = w.end;
        return error.RequiredFlagsMissing;
    }

    /// Flag group annotation keys (Go: flag_groups.go).
    pub const required_as_group_annotation = "cobra_annotation_required_if_others_set";
    pub const one_required_annotation = "cobra_annotation_one_required";
    pub const mutually_exclusive_annotation = "cobra_annotation_mutually_exclusive";

    /// Finds the FlagSet (own, persistent, or ancestor) owning `flag_name`.
    pub fn owningFlagSet(self: *Command, flag_name: []const u8) ?*pflag.FlagSet {
        if (self.flags_ptr) |fs| {
            if (fs.lookup(flag_name) != null) return fs;
        }
        if (self.pflags) |pf| {
            if (pf.lookup(flag_name) != null) return pf;
        }
        if (self.parent) |p| return p.owningFlagSet(flag_name);
        return null;
    }

    /// Validates flag groups (Go: ValidateFlagGroups). Groups are stored as flag
    /// annotations; messages and ordering match Go exactly.
    pub fn validateFlagGroups(self: *const Command) anyerror!void {
        if (self.disable_flag_parsing) return;
        const this = @constCast(self);
        const local = this.lflags orelse this.flags_ptr orelse return;
        if (this.validateFlagGroupKind(local, this.iflags, required_as_group_annotation, .required_together)) return error.FlagGroupViolation;
        if (this.validateFlagGroupKind(local, this.iflags, one_required_annotation, .one_required)) return error.FlagGroupViolation;
        if (this.validateFlagGroupKind(local, this.iflags, mutually_exclusive_annotation, .mutually_exclusive)) return error.FlagGroupViolation;
    }

    const GroupKind = enum { required_together, one_required, mutually_exclusive };

    fn lookupAcross(a: ?*pflag.FlagSet, b: ?*pflag.FlagSet, n: []const u8) ?*pflag.Flag {
        if (a) |s| {
            if (s.lookup(n)) |f| return f;
        }
        if (b) |s| {
            if (s.lookup(n)) |f| return f;
        }
        return null;
    }

    fn lessThanString(_: void, a: []const u8, b: []const u8) bool {
        return std.mem.order(u8, a, b) == .lt;
    }

    /// Splits a space-joined group key into names. Returns count, or null if it overflows.
    fn splitGroupKey(key: []const u8, out: *[16][]const u8) ?usize {
        var n: usize = 0;
        var it = std.mem.splitScalar(u8, key, ' ');
        while (it.next()) |part| {
            if (part.len == 0) continue;
            if (n >= out.len) return null;
            out[n] = part;
            n += 1;
        }
        return n;
    }

    /// Returns true when a violation was found (message staged in err_msg_buf).
    fn validateFlagGroupKind(self: *Command, local: *pflag.FlagSet, inherited: ?*pflag.FlagSet, annotation: []const u8, kind: GroupKind) bool {
        var keys: [32][]const u8 = undefined;
        var n_keys: usize = 0;
        const scan = struct {
            fn inner(fs: ?*pflag.FlagSet, ann: []const u8, keys_arr: *[32][]const u8, count: *usize) void {
                const s = fs orelse return;
                for (s.ordered_formal.items) |f| {
                    const group_list = f.annotations.get(ann) orelse continue;
                    for (group_list) |g| {
                        var dup = false;
                        for (keys_arr[0..count.*]) |k| {
                            if (std.mem.eql(u8, k, g)) {
                                dup = true;
                                break;
                            }
                        }
                        if (!dup and count.* < keys_arr.len) {
                            keys_arr[count.*] = g;
                            count.* += 1;
                        }
                    }
                }
            }
        }.inner;
        scan(local, annotation, &keys, &n_keys);
        scan(inherited, annotation, &keys, &n_keys);
        if (n_keys > 1) std.mem.sort([]const u8, keys[0..n_keys], {}, lessThanString);

        for (keys[0..n_keys]) |group_key| {
            var names: [16][]const u8 = undefined;
            const n_names = splitGroupKey(group_key, &names) orelse continue;
            if (n_names == 0) continue;

            var all_present = true;
            for (names[0..n_names]) |n| {
                if (lookupAcross(local, inherited, n) == null) {
                    all_present = false;
                    break;
                }
            }
            if (!all_present) continue;

            var set: [16][]const u8 = undefined;
            var n_set: usize = 0;
            var unset: [16][]const u8 = undefined;
            var n_unset: usize = 0;
            for (names[0..n_names]) |n| {
                const f = lookupAcross(local, inherited, n).?;
                if (f.changed) {
                    if (n_set < set.len) {
                        set[n_set] = n;
                        n_set += 1;
                    }
                } else {
                    if (n_unset < unset.len) {
                        unset[n_unset] = n;
                        n_unset += 1;
                    }
                }
            }

            switch (kind) {
                .required_together => {
                    if (n_set > 0 and n_unset > 0) {
                        if (n_unset > 1) std.mem.sort([]const u8, unset[0..n_unset], {}, lessThanString);
                        var w = std.Io.Writer.fixed(&self.err_msg_buf);
                        w.print("if any flags in the group [{s}] are set they must all be set; missing [", .{group_key}) catch {};
                        for (unset[0..n_unset], 0..) |u, i| {
                            if (i > 0) w.print(" ", .{}) catch {};
                            w.print("{s}", .{u}) catch {};
                        }
                        w.print("]", .{}) catch {};
                        self.err_msg_len = w.end;
                        return true;
                    }
                },
                .one_required => {
                    if (n_set == 0) {
                        var w = std.Io.Writer.fixed(&self.err_msg_buf);
                        w.print("at least one of the flags in the group [{s}] is required", .{group_key}) catch {};
                        self.err_msg_len = w.end;
                        return true;
                    }
                },
                .mutually_exclusive => {
                    if (n_set > 1) {
                        if (n_set > 1) std.mem.sort([]const u8, set[0..n_set], {}, lessThanString);
                        var w = std.Io.Writer.fixed(&self.err_msg_buf);
                        w.print("if any flags in the group [{s}] are set none of the others can be; [", .{group_key}) catch {};
                        for (set[0..n_set], 0..) |s, i| {
                            if (i > 0) w.print(" ", .{}) catch {};
                            w.print("{s}", .{s}) catch {};
                        }
                        w.print("] were all set", .{}) catch {};
                        self.err_msg_len = w.end;
                        return true;
                    }
                },
            }
        }
        return false;
    }

    /// Go parity: adjusts required/hidden flag state so completion proposals
    /// respect flag groups. Called during __complete handling only.
    pub fn enforceFlagGroupsForCompletion(self: *const Command) void {
        if (self.disable_flag_parsing) return;
        const this = @constCast(self);
        const local = this.lflags orelse this.flags_ptr orelse return;

        const enforceKind = struct {
            fn inner(local_set: *pflag.FlagSet, inherited: ?*pflag.FlagSet, ann: []const u8, mode: u8) void {
                var keys: [32][]const u8 = undefined;
                var n_keys: usize = 0;
                const scanSets = [_]?*pflag.FlagSet{ local_set, inherited };
                for (scanSets) |maybe| {
                    const s = maybe orelse continue;
                    for (s.ordered_formal.items) |f| {
                        const group_list = f.annotations.get(ann) orelse continue;
                        for (group_list) |g| {
                            var dup = false;
                            for (keys[0..n_keys]) |k| {
                                if (std.mem.eql(u8, k, g)) {
                                    dup = true;
                                    break;
                                }
                            }
                            if (!dup and n_keys < keys.len) {
                                keys[n_keys] = g;
                                n_keys += 1;
                            }
                        }
                    }
                }
                for (keys[0..n_keys]) |group_key| {
                    var names: [16][]const u8 = undefined;
                    const n_names = splitGroupKey(group_key, &names) orelse continue;
                    var n_set: usize = 0;
                    for (names[0..n_names]) |n| {
                        const f = lookupAcross(local_set, inherited, n) orelse continue;
                        if (f.changed) n_set += 1;
                    }
                    switch (mode) {
                        // required-together: any set -> all become required
                        // one-required: none set -> all become required
                        0, 1 => {
                            const act = (mode == 0 and n_set > 0) or (mode == 1 and n_set == 0);
                            if (act) {
                                for (names[0..n_names]) |n| {
                                    if (lookupAcross(local_set, inherited, n)) |f| {
                                        f.annotations.put(local_set.gpa, bash_comp_one_required_flag, &.{"true"}) catch @panic("cobra: OOM enforcing flag groups for completion");
                                    }
                                }
                            }
                        },
                        // mutually exclusive: any set -> hide the others
                        else => {
                            if (n_set > 0) {
                                for (names[0..n_names]) |n| {
                                    const f = lookupAcross(local_set, inherited, n) orelse continue;
                                    if (!f.changed) f.hidden = true;
                                }
                            }
                        },
                    }
                }
            }
        }.inner;

        enforceKind(local, this.iflags, required_as_group_annotation, 0);
        enforceKind(local, this.iflags, one_required_annotation, 1);
        enforceKind(local, this.iflags, mutually_exclusive_annotation, 2);
    }

    // ─── Parsing ───

    /// Parses args with inherited persistent flags temporarily merged in (borrowed).
    pub fn parseArgs(self: *Command, gpa: std.mem.Allocator, a: []const []const u8) anyerror!void {
        const fs = self.flags_ptr orelse return;
        fs.error_handling = .continue_on_error;
        fs.parse_errors_allowlist.unknown_flags =
            self.fparse_err_whitelist.unknown_flag or self.fparse_err_whitelist.unknown_shorthand_flag;

        // Temporarily borrow own-persistent + ancestor-persistent flags into fs.
        // Unbounded tracking (gpa-backed): every successfully added flag MUST be
        // recorded, otherwise it would leak into fs permanently as a dangling pointer.
        var borrowed: std.ArrayListUnmanaged(*pflag.Flag) = .empty;
        const start_formal = fs.ordered_formal.items.len;
        defer {
            removeBorrowedFlags(fs, borrowed.items, start_formal);
            borrowed.deinit(gpa);
        }

        const borrowFrom = struct {
            fn inner(dst: *pflag.FlagSet, src: ?*pflag.FlagSet, list: *std.ArrayListUnmanaged(*pflag.Flag), alloc: std.mem.Allocator) !void {
                const s = src orelse return;
                for (s.ordered_formal.items) |f| {
                    if (dst.lookup(f.name) != null) continue;
                    if (f.shorthand.len > 0) {
                        if (dst.shorthandLookup(f.shorthand[0]) != null) continue;
                    }
                    // Track first: if addFlag refuses the flag, roll the tracking back.
                    try list.append(alloc, f);
                    dst.addFlag(f) catch {
                        _ = list.pop();
                        continue;
                    };
                }
            }
        }.inner;
        try borrowFrom(fs, self.pflags, &borrowed, gpa);
        // Ancestors' persistent flags
        var p: ?*Command = self.parent;
        while (p) |cur| : (p = cur.parent) {
            try borrowFrom(fs, cur.pflags, &borrowed, gpa);
        }

        return fs.parse(a);
    }

    /// Public parse entry point (Go: ParseFlags()).
    pub fn parseFlags(self: *Command, io: std.Io, gpa: std.mem.Allocator, a: []const []const u8) anyerror!void {
        _ = io;
        if (self.disable_flag_parsing) {
            self.args_slice = a;
            return;
        }
        self.mergePersistentFlags(gpa);
        return self.parseArgs(gpa, a);
    }

    // ─── Command resolution (Go: Find/Traverse) ───

    pub const FindResult = struct {
        cmd: *Command,
        args: []const []const u8,
        err: ?anyerror = null,
        /// First unrecognized positional arg (for error messages/suggestions)
        unknown_arg: []const u8 = "",
        /// Heap slice backing `args` when find() had to copy during descent (command name
        /// not at index 0). Caller owns it and must free with the same gpa (null when `args`
        /// borrows from the input or was produced by traverse()).
        owned_args: ?[]const []const u8 = null,
    };

    /// Strips flags (honoring value-consuming flags) and returns positional args only.
    /// Mirrors Go's stripFlags.
    fn stripFlags(self: *Command, args: []const []const u8, out: *std.ArrayListUnmanaged([]const u8), gpa: std.mem.Allocator) void {
        const fs = self.flags_ptr;
        var i: usize = 0;
        while (i < args.len) {
            const s = args[i];
            i += 1;
            if (std.mem.eql(u8, s, "--")) break;
            if (std.mem.startsWith(u8, s, "--")) {
                if (std.mem.indexOfScalar(u8, s, '=') != null) continue;
                const fname = s[2..];
                const takes_value = if (fs) |f| flagTakesValue(f.lookup(fname)) else false;
                if (takes_value) {
                    if (i >= args.len) break;
                    i += 1; // consume value
                }
                continue;
            }
            if (s.len >= 2 and s[0] == '-' and s[1] != '-') {
                if (std.mem.indexOfScalar(u8, s, '=') != null) continue;
                if (s.len == 2) {
                    const takes_value = if (fs) |f| flagTakesValue(f.shorthandLookup(s[1])) else false;
                    if (takes_value) {
                        if (i >= args.len) break;
                        i += 1;
                    }
                }
                continue;
            }
            if (s.len > 0) {
                out.append(gpa, s) catch @panic("cobra: OOM in stripFlags");
            }
        }
    }

    fn flagTakesValue(f: ?*pflag.Flag) bool {
        const fl = f orelse return false; // Unknown flag: Go assumes it takes no value.
        return fl.no_opt_def_val.len == 0;
    }

    /// Resolves the target command and remaining args (Go: Find()).
    /// Returns err=error.UnknownCommand when legacyArgs rejects trailing positional args.
    pub fn find(self: *Command, gpa: std.mem.Allocator, args: []const []const u8) FindResult {
        // stripFlags must see inherited persistent flags to know which consume values.
        _ = self.ensureFlags(gpa);
        self.mergePersistentFlags(gpa);
        var cmd: *Command = self;
        var remaining: []const []const u8 = args;
        // Ownership of the argsMinusFirstX copy (if any). Intermediate copies are freed as
        // we descend; the final one is handed to the caller via FindResult.owned_args.
        var owned_remaining: ?[]const []const u8 = null;

        var positional: std.ArrayListUnmanaged([]const u8) = .empty;
        defer positional.deinit(gpa);

        while (true) {
            positional.clearRetainingCapacity();
            cmd.stripFlags(remaining, &positional, gpa);
            if (positional.items.len == 0) break;
            const next_name = positional.items[0];
            const next = cmd.findNext(next_name) orelse break;
            const minus = argsMinusFirstX(gpa, remaining, next_name) orelse break;
            if (owned_remaining) |a| gpa.free(a);
            remaining = minus.args;
            owned_remaining = minus.owned;
            cmd = next;
        }

        // Go parity: legacyArgs check only when the found command has no custom validator.
        if (cmd.args_validator == null) {
            positional.clearRetainingCapacity();
            cmd.stripFlags(remaining, &positional, gpa);
            if (cmd.hasSubCommands() and !cmd.hasParent() and positional.items.len > 0) {
                return .{ .cmd = cmd, .args = remaining, .err = error.UnknownCommand, .unknown_arg = positional.items[0], .owned_args = owned_remaining };
            }
        }
        return .{ .cmd = cmd, .args = remaining, .err = null, .owned_args = owned_remaining };
    }

    pub fn findNext(self: *Command, next_name: []const u8) ?*Command {
        const name_matches = @import("cobra.zig").commandNameMatches;
        for (self.commands.items) |c| {
            if (name_matches(c.name(), next_name) or c.hasAlias(next_name)) {
                c.command_called_as = .{ .name = next_name, .called = true };
                return c;
            }
        }
        if (@import("cobra.zig").enable_prefix_matching) {
            // Go parity: hidden/deprecated commands still participate in prefix matching.
            var match: ?*Command = null;
            var n: usize = 0;
            for (self.commands.items) |c| {
                if (c.hasNameOrAliasPrefix(next_name)) {
                    n += 1;
                    if (n == 1) match = c;
                    if (n > 1) break; // ambiguous prefix → no match (Go: len(matches) != 1)
                }
            }
            if (n == 1) {
                if (match) |m| {
                    m.command_called_as = .{ .name = next_name, .called = true };
                    return m;
                }
            }
        }
        return null;
    }

    /// Traverses the command tree parsing flags at every level (Go: Traverse()).
    /// Unlike find(), flags may appear between subcommand names.
    pub fn traverse(self: *Command, gpa: std.mem.Allocator, args: []const []const u8) FindResult {
        var cmd: *Command = self;
        var remaining = args;
        while (remaining.len > 0) {
            const s = remaining[0];
            if (std.mem.eql(u8, s, "--")) break;
            if (!std.mem.startsWith(u8, s, "-") and s.len > 0) {
                const next = cmd.findNext(s) orelse {
                    return .{ .cmd = cmd, .args = remaining, .err = error.UnknownCommand, .unknown_arg = s };
                };
                cmd = next;
                remaining = remaining[1..];
                continue;
            }
            // Flag token: consume it plus its value if the flag requires one at this level.
            const fs = cmd.flags_ptr;
            var skip: usize = 1;
            if (std.mem.startsWith(u8, s, "--")) {
                if (std.mem.indexOfScalar(u8, s, '=') == null) {
                    const fname = s[2..];
                    if (fs) |f| {
                        if (flagTakesValue(f.lookup(fname))) skip = 2;
                    }
                }
            } else if (s.len == 2) {
                if (fs) |f| {
                    if (flagTakesValue(f.shorthandLookup(s[1]))) skip = 2;
                }
            }
            if (skip > remaining.len) break;
            remaining = remaining[skip..];
        }
        _ = gpa;
        return .{ .cmd = cmd, .args = remaining, .err = null };
    }

    /// Number of CLI args before the '--' separator, or -1 if absent (Go: ArgsLenAtDash()).
    pub fn argsLenAtDash(self: *const Command) isize {
        if (self.flags_ptr) |fs| return fs.args_len_at_dash;
        return -1;
    }

    // ─── Utility ───

    /// "name, alias1, alias2" rendered into an internal buffer (Go: NameAndAliases()).
    pub fn nameAndAliases(self: *Command) []const u8 {
        var w = std.Io.Writer.fixed(&self.alias_buf);
        w.print("{s}", .{self.name()}) catch {};
        for (self.aliases) |a| {
            w.print(", {s}", .{a}) catch {};
        }
        return self.alias_buf[0..w.end];
    }

    /// Parent path + use line (Go: UseLine()). Rendered into an internal buffer.
    pub fn useLine(self: *Command) []const u8 {
        var w = std.Io.Writer.fixed(&self.use_line_buf);
        if (self.parent) |p| {
            w.print("{s} ", .{p.commandPath()}) catch {};
        }
        const use = self.use;
        w.print("{s}", .{use}) catch {};
        if (!self.disable_flags_in_use_line) {
            // Go appends " [flags]" when the command has available flags and use doesn't already end with it.
            if (self.hasAvailableFlags() and !std.mem.endsWith(u8, use, "[flags]")) {
                w.print(" [flags]", .{}) catch {};
            }
        }
        return self.use_line_buf[0..w.end];
    }

    pub fn resetFlags(self: *Command) void {
        self.flags_ptr = null;
        self.pflags = null;
        self.lflags = null;
        self.iflags = null;
        self.parents_pflags = null;
        self.lnpflags = null;
        self.help_flag_value = false;
        self.version_flag_value = false;
    }

    pub fn hasNameOrAliasPrefix(self: *const Command, prefix: []const u8) bool {
        if (prefix.len == 0) return false;
        if (std.mem.startsWith(u8, self.name(), prefix)) return true;
        for (self.aliases) |a| {
            if (std.mem.startsWith(u8, a, prefix)) return true;
        }
        return false;
    }

    /// Registers a completion function for a flag's values (Go: RegisterFlagCompletionFunc).
    pub fn registerFlagCompletionFunc(self: *Command, gpa: std.mem.Allocator, flag_name: []const u8, f: CompletionFuncType) anyerror!void {
        if (self.flag(flag_name) == null) return error.NoSuchFlag;
        if (self.flag_completions.contains(flag_name)) return error.FlagCompletionAlreadyRegistered;
        try self.flag_completions.put(gpa, flag_name, f);
    }

    /// Looks up a registered flag completion function.
    pub fn getFlagCompletionFunc(self: *const Command, flag_name: []const u8) ?CompletionFuncType {
        return self.flag_completions.get(flag_name);
    }

    // ─── Flag group marking (Go: MarkFlags*) ───

    /// Adds the group annotation to every flag of the group. The group key is the
    /// space-joined flag names, stored with stable (library-owned) allocation.
    fn markFlagGroupAnnotation(self: *Command, gpa: std.mem.Allocator, flag_names: []const []const u8, annotation: []const u8) anyerror!void {
        if (flag_names.len < 2) return; // groups of size < 2 have no observable effect

        // Go parity: unknown flags abort the whole mark (Go panics; we return an error).
        for (flag_names) |n| {
            if (self.owningFlagSet(n) == null) {
                self.setErrMsg("Failed to find flag \"{s}\" and mark it as being in a flag group", .{n});
                return error.NoSuchFlag;
            }
        }

        var key_buf: [512]u8 = undefined;
        var kw = std.Io.Writer.fixed(&key_buf);
        for (flag_names, 0..) |n, i| {
            if (i > 0) kw.print(" ", .{}) catch {};
            kw.print("{s}", .{n}) catch {};
        }
        const key = try gpa.dupe(u8, key_buf[0..kw.end]);

        for (flag_names) |n| {
            const fs = self.owningFlagSet(n) orelse {
                self.setErrMsg("Failed to find flag \"{s}\" and mark it as being in a flag group", .{n});
                return error.NoSuchFlag;
            };
            const existing: []const []const u8 = if (fs.lookup(n)) |f|
                (f.annotations.get(annotation) orelse &.{})
            else
                &.{};
            const vals = try gpa.alloc([]const u8, existing.len + 1);
            @memcpy(vals[0..existing.len], existing);
            vals[existing.len] = key;
            fs.setAnnotation(n, annotation, vals) catch {
                gpa.free(vals);
                return error.NoSuchFlag;
            };
            try self.owned_annotation_values.append(gpa, vals);
        }
        try self.owned_group_keys.append(gpa, key);
    }

    pub fn markFlagsMutuallyExclusive(self: *Command, gpa: std.mem.Allocator, flag_names: []const []const u8) anyerror!void {
        self.mergePersistentFlags(gpa);
        try self.markFlagGroupAnnotation(gpa, flag_names, mutually_exclusive_annotation);
    }
    pub fn markFlagsOneRequired(self: *Command, gpa: std.mem.Allocator, flag_names: []const []const u8) anyerror!void {
        self.mergePersistentFlags(gpa);
        try self.markFlagGroupAnnotation(gpa, flag_names, one_required_annotation);
    }
    pub fn markFlagsRequiredTogether(self: *Command, gpa: std.mem.Allocator, flag_names: []const []const u8) anyerror!void {
        self.mergePersistentFlags(gpa);
        try self.markFlagGroupAnnotation(gpa, flag_names, required_as_group_annotation);
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

    /// Debug helper: writes the resolved flagset contents to the writer (Go: DebugFlags()).
    pub fn debugFlags(self: *Command, io: std.Io) void {
        const w = self.errOrStderr(io);
        if (self.flags_ptr) |fs| {
            for (fs.ordered_formal.items) |f| {
                if (f.value.string(fs.gpa)) |val| {
                    defer fs.gpa.free(val);
                    w.print("--{s}: {s}\n", .{ f.name, val }) catch {};
                } else |_| {
                    w.print("--{s}: ?\n", .{f.name}) catch {};
                }
            }
        }
        w.flush() catch {};
    }
};

/// Removes a borrowed flag (by pointer identity) from the destination set.
fn removeBorrowedFlags(fs: *pflag.FlagSet, borrowed: []const *pflag.Flag, start_formal: usize) void {
    for (borrowed) |f| {
        _ = fs.formal.remove(f.name);
        if (f.shorthand.len > 0) {
            if (fs.shorthandLookup(f.shorthand[0]) == f) {
                _ = fs.shorthands.remove(f.shorthand[0]);
            }
        }
    }
    // Restore ordered_formal to pre-merge contents (borrowed flags were appended at the end).
    if (fs.ordered_formal.items.len > start_formal) {
        fs.ordered_formal.shrinkRetainingCapacity(start_formal);
    }
}

/// Adds every flag from src into dst as a *borrowed* pointer (no cloning, no ownership).
fn addBorrowedFlags(dst: *pflag.FlagSet, src: *pflag.FlagSet) void {
    for (src.ordered_formal.items) |f| {
        if (dst.lookup(f.name) != null) continue;
        if (f.shorthand.len > 0 and dst.shorthandLookup(f.shorthand[0]) != null) continue;
        dst.addFlag(f) catch continue;
    }
}

/// Drops borrowed flags from dst that also exist in other (used to compute "local" views).
fn removeFlagsPresent(dst: *pflag.FlagSet, other: *pflag.FlagSet) void {
    var i: usize = 0;
    while (i < dst.ordered_formal.items.len) {
        const f = dst.ordered_formal.items[i];
        if (other.lookup(f.name) != null) {
            _ = dst.formal.remove(f.name);
            if (f.shorthand.len > 0) {
                _ = dst.shorthands.remove(f.shorthand[0]);
            }
            _ = dst.ordered_formal.orderedRemove(i);
        } else {
            i += 1;
        }
    }
}

/// Clears a FlagSet's flag registries WITHOUT freeing Flag storage (borrowed views only).
fn clearBorrowed(fs_opt: *?pflag.FlagSet) void {
    if (fs_opt.* == null) return;
    const fs = &fs_opt.*.?;
    fs.formal.clearRetainingCapacity();
    fs.shorthands.clearRetainingCapacity();
    fs.ordered_formal.clearRetainingCapacity();
}

/// Copy of args with the first occurrence of x removed. Returned slice may reference a
/// gpa allocation (caller-scoped); the common index-0 case allocates nothing.
/// Returns `args` with the first element equal to `x` removed. When `x` is not at
/// index 0 a copy is allocated; `owned` then reports the allocation so callers can
/// free it (null when the result borrows from `args`).
fn argsMinusFirstX(gpa: std.mem.Allocator, args: []const []const u8, x: []const u8) ?struct { args: []const []const u8, owned: ?[]const []const u8 } {
    for (args, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, x)) {
            if (i == 0) return .{ .args = args[1..], .owned = null };
            const out = gpa.alloc(@TypeOf(args[0]), args.len - 1) catch return null;
            @memcpy(out[0..i], args[0..i]);
            @memcpy(out[i..], args[i + 1 ..]);
            return .{ .args = out, .owned = out };
        }
    }
    return null;
}

pub const FlagSet = pflag.FlagSet;
pub const Flag = pflag.Flag;

/// Go's default usage template (stored for parity; rendering is built-in).
pub const default_usage_template = "Usage:{{if .Runnable}}\n  {{.UseLine}}{{end}}\n";
/// Go's default help template (stored for parity; rendering is built-in).
pub const default_help_template = "{{with (or .Long .Short)}}{{.}}{{end}}";
/// Go's default version template (stored for parity; rendering is built-in).
pub const default_version_template = "{{.DisplayName}} version {{.Version}}\n";
