const std = @import("std");
const cobra = @import("cobra");
const Command = cobra.Command;

pub fn init(gpa: std.mem.Allocator, cmd: *Command, ls_cmd: *Command, pull_cmd: *Command, push_cmd: *Command) void {
    ls_cmd.* = Command{ .use = "ls [OPTIONS]", .short = "List images", .run = lsFn };
    pull_cmd.* = Command{ .use = "pull [OPTIONS] IMAGE", .short = "Download an image from a registry", .run = pullFn, .args_validator = cobra.MinimumNArgs(1) };
    push_cmd.* = Command{ .use = "push [OPTIONS] IMAGE", .short = "Upload an image to a registry", .run = pushFn, .args_validator = cobra.MinimumNArgs(1) };
    cmd.* = Command{ .use = "image", .aliases = &.{ "images", "img" }, .short = "Manage images", .long = "Commands for pulling, pushing, and listing images." };
    cmd.addCommand(gpa, &.{ ls_cmd, pull_cmd, push_cmd });
}
fn lsFn(_: *Command, _: [][]const u8) void {
    const io = std.Io.Threaded.global_single_threaded.*.io(); std.Io.File.stdout().writeStreamingAll(io, "REPOSITORY   TAG       SIZE\n") catch {};
}
fn pullFn(_: *Command, args: [][]const u8) void {
    var b: [128]u8 = undefined;
    const m = std.fmt.bufPrint(&b, "Pulling '{s}'...\n", .{args[0]}) catch return;
    const io = std.Io.Threaded.global_single_threaded.*.io(); std.Io.File.stdout().writeStreamingAll(io, m) catch {};
}
fn pushFn(_: *Command, args: [][]const u8) void {
    var b: [128]u8 = undefined;
    const m = std.fmt.bufPrint(&b, "Pushing '{s}'...\n", .{args[0]}) catch return;
    const io = std.Io.Threaded.global_single_threaded.*.io(); std.Io.File.stdout().writeStreamingAll(io, m) catch {};
}
