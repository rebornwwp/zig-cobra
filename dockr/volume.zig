const std = @import("std");
const cobra = @import("cobra");
const Command = cobra.Command;

pub fn init(gpa: std.mem.Allocator, cmd: *Command, ls_cmd: *Command, create_cmd: *Command) void {
    ls_cmd.* = Command{ .use = "ls [OPTIONS]", .short = "List volumes", .run = lsFn };
    create_cmd.* = Command{ .use = "create [OPTIONS] VOLUME", .short = "Create a volume", .run = createFn, .args_validator = cobra.MinimumNArgs(1) };
    cmd.* = Command{ .use = "volume", .short = "Manage volumes" };
    cmd.addCommand(gpa, &.{ ls_cmd, create_cmd });
}
fn io() std.Io {
    return @import("std").Io.Threaded.global_single_threaded.*.io();
}
fn lsFn(_: *Command, _: [][]const u8) void {
    var b: [256]u8 = undefined;
    var ow = std.Io.File.Writer.init(std.Io.File.stdout(), io(), &b);
    const w = &ow.interface;
    w.print("VOLUME NAME\n", .{}) catch {};
    ow.flush() catch {};
}
fn createFn(_: *Command, args: [][]const u8) void {
    var b: [256]u8 = undefined;
    var ow = std.Io.File.Writer.init(std.Io.File.stdout(), io(), &b);
    const w = &ow.interface;
    w.print("Created volume '{s}'\n", .{args[0]}) catch {};
    ow.flush() catch {};
}
