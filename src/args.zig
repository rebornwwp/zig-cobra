//! Positional argument validators. Maps 1:1 from cobra/args.go
const std = @import("std");
const Command = @import("command.zig").Command;

/// PositionalArgs: a tagged union representing argument count and content validation strategies.
pub const PositionalArgs = union(enum) {
    /// Custom validation function with signature (cmd, args) -> error!void
    simple: *const fn (cmd: *Command, args: []const []const u8) anyerror!void,
    /// Exactly n arguments required
    exact_n: usize,
    /// At least n arguments required
    minimum_n: usize,
    /// At most n arguments allowed
    maximum_n: usize,
    /// Argument count must be within [min, max]
    range: struct { min: usize, max: usize },
    /// Combine multiple validators; all must pass
    match_all: []const PositionalArgs,

    /// Validate positional args against this strategy. Returns error.ArgsCount or error.InvalidArg on failure.
    pub fn validate(self: PositionalArgs, cmd: *Command, args: []const []const u8) anyerror!void {
        return switch (self) {
            .simple => |fn_ptr| fn_ptr(cmd, args),
            .exact_n => |n| {
                if (args.len != n) return error.ArgsCount;
            },
            .minimum_n => |n| {
                if (args.len < n) return error.ArgsCount;
            },
            .maximum_n => |n| {
                if (args.len > n) return error.ArgsCount;
            },
            .range => |r| {
                if (args.len < r.min or args.len > r.max) return error.ArgsCount;
            },
            .match_all => |validators| {
                for (validators) |v| try v.validate(cmd, args);
            },
        };
    }
};

fn noArgsInner(cmd: *Command, args: []const []const u8) anyerror!void {
    _ = cmd;
    if (args.len > 0) return error.UnknownCommand;
}

fn onlyValidArgsInner(cmd: *Command, args: []const []const u8) anyerror!void {
    if (cmd.valid_args.len == 0) return;
    for (args) |arg| {
        var found = false;
        for (cmd.valid_args) |valid| {
            if (std.mem.startsWith(u8, valid, arg)) {
                found = true;
                break;
            }
        }
        if (!found) return error.InvalidArg;
    }
}

fn noDuplicateArgsInner(cmd: *Command, args: []const []const u8) anyerror!void {
    _ = cmd;
    for (args, 0..) |a, i| {
        for (args[i + 1 ..]) |b| {
            if (std.mem.eql(u8, a, b)) return error.DuplicateArg;
        }
    }
}

fn arbitraryArgsInner(cmd: *Command, args: []const []const u8) anyerror!void {
    _ = cmd;
    _ = args;
}

fn legacyArgsInner(cmd: *Command, args: []const []const u8) anyerror!void {
    if (!cmd.hasSubCommands()) return;
    if (!cmd.hasParent() and args.len > 0) return error.UnknownCommand;
}

/// Reject any positional args. Returns error.UnknownCommand if args are present.
pub fn noArgs() PositionalArgs {
    return .{ .simple = noArgsInner };
}
/// All args must be present in Command.valid_args (prefix match).
pub fn onlyValidArgs() PositionalArgs {
    return .{ .simple = onlyValidArgsInner };
}
/// Reject duplicate positional args.
pub fn noDuplicateArgs() PositionalArgs {
    return .{ .simple = noDuplicateArgsInner };
}
/// Accept any number of args (no count restriction).
pub fn arbitraryArgs() PositionalArgs {
    return .{ .simple = arbitraryArgsInner };
}
/// Legacy mode: reject positional args when subcommands exist.
pub fn legacyArgs() PositionalArgs {
    return .{ .simple = legacyArgsInner };
}
/// Require exactly n positional args.
pub fn exactArgs(n: usize) PositionalArgs {
    return .{ .exact_n = n };
}
/// Require at least n positional args.
pub fn minimumNArgs(n: usize) PositionalArgs {
    return .{ .minimum_n = n };
}
/// Allow at most n positional args.
pub fn maximumNArgs(n: usize) PositionalArgs {
    return .{ .maximum_n = n };
}
/// Require positional arg count within [min, max].
pub fn rangeArgs(min_n: usize, max_n: usize) PositionalArgs {
    return .{ .range = .{ .min = min_n, .max = max_n } };
}
/// Combine multiple validators; all must pass.
pub fn matchAll(validators: []const PositionalArgs) PositionalArgs {
    return .{ .match_all = validators };
}
/// Exactly n args, and all must be in valid_args. Equivalent to matchAll(exactArgs(n), onlyValidArgs()).
pub fn exactValidArgs(n: usize) PositionalArgs {
    return matchAll(&.{ exactArgs(n), onlyValidArgs() });
}
