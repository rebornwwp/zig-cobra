//! Positional argument validators. Maps 1:1 from cobra/args.go
const std = @import("std");
const Command = @import("command.zig").Command;

pub const PositionalArgs = union(enum) {
    simple: *const fn (cmd: *Command, args: []const []const u8) anyerror!void,
    exact_n: usize,
    minimum_n: usize,
    maximum_n: usize,
    range: struct { min: usize, max: usize },
    match_all: []const PositionalArgs,

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

pub fn noArgs() PositionalArgs {
    return .{ .simple = noArgsInner };
}
pub fn onlyValidArgs() PositionalArgs {
    return .{ .simple = onlyValidArgsInner };
}
pub fn noDuplicateArgs() PositionalArgs {
    return .{ .simple = noDuplicateArgsInner };
}
pub fn arbitraryArgs() PositionalArgs {
    return .{ .simple = arbitraryArgsInner };
}
pub fn legacyArgs() PositionalArgs {
    return .{ .simple = legacyArgsInner };
}
pub fn exactArgs(n: usize) PositionalArgs {
    return .{ .exact_n = n };
}
pub fn minimumNArgs(n: usize) PositionalArgs {
    return .{ .minimum_n = n };
}
pub fn maximumNArgs(n: usize) PositionalArgs {
    return .{ .maximum_n = n };
}
pub fn rangeArgs(min_n: usize, max_n: usize) PositionalArgs {
    return .{ .range = .{ .min = min_n, .max = max_n } };
}
pub fn matchAll(validators: []const PositionalArgs) PositionalArgs {
    return .{ .match_all = validators };
}
pub fn exactValidArgs(n: usize) PositionalArgs {
    return matchAll(&.{ exactArgs(n), onlyValidArgs() });
}
