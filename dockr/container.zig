const std = @import("std");
const cobra = @import("cobra");
const pflag = cobra.command_mod.pflag;
const Command = cobra.Command;
const types = @import("types.zig");

pub fn init_run(gpa: std.mem.Allocator, cmd: *Command, flags: *pflag.FlagSet, opts: *types.ContainerRunOpts) void {
    flags.* = pflag.FlagSet.init(gpa, "container run");
    flags.stringVarP(&opts.name, "name", "", "", "assign a name") catch {};
    flags.boolVarP(&opts.detach, "detach", "d", false, "run in background") catch {};
    flags.boolVarP(&opts.interactive, "interactive", "i", false, "keep STDIN open") catch {};
    flags.boolVarP(&opts.tty, "tty", "t", false, "allocate a pseudo-TTY") catch {};
    flags.stringSliceVarP(&opts.publish, "publish", "p", &.{}, "publish container ports") catch {};
    flags.stringSliceVarP(&opts.volume, "volume", "v", &.{}, "bind mount a volume") catch {};
    flags.stringSliceVarP(&opts.env, "env", "e", &.{}, "set environment variables") catch {};
    flags.boolVarP(&opts.rm, "rm", "", false, "auto-remove on exit") catch {};
    cmd.* = Command{ .use = "run [OPTIONS] IMAGE [COMMAND] [ARG...]", .short = "Create and run a new container from an image", .long = "Creates a writeable container layer over the specified image\nand then starts it using the specified command.", .example = "  dockr container run -d --name web -p 80:80 nginx\n  dockr container run -it --rm ubuntu bash", .run = runFn, .flags = flags, .args_validator = cobra.MinimumNArgs(1) };
    cmd.iflags = @ptrCast(@alignCast(opts));
}

pub fn init_ls(gpa: std.mem.Allocator, cmd: *Command, flags: *pflag.FlagSet) void {
    flags.* = pflag.FlagSet.init(gpa, "container ls");
    var a: bool = false;
    var q: bool = false;
    flags.boolVarP(&a, "all", "a", false, "show all containers") catch {};
    flags.boolVarP(&q, "quiet", "q", false, "only display IDs") catch {};
    cmd.* = Command{ .use = "ls [OPTIONS]", .short = "List containers", .run = lsFn, .flags = flags };
}

pub fn init_rm(gpa: std.mem.Allocator, cmd: *Command, flags: *pflag.FlagSet) void {
    flags.* = pflag.FlagSet.init(gpa, "container rm");
    var f: bool = false;
    flags.boolVarP(&f, "force", "f", false, "force removal") catch {};
    cmd.* = Command{ .use = "rm [OPTIONS] CONTAINER [CONTAINER...]", .short = "Remove one or more containers", .run = rmFn, .flags = flags, .args_validator = cobra.MinimumNArgs(1) };
}

pub fn init_start(cmd: *Command) void {
    cmd.* = Command{ .use = "start [OPTIONS] CONTAINER [CONTAINER...]", .short = "Start one or more stopped containers", .run = startFn, .args_validator = cobra.MinimumNArgs(1) };
}
pub fn init_stop(cmd: *Command) void {
    cmd.* = Command{ .use = "stop [OPTIONS] CONTAINER [CONTAINER...]", .short = "Stop one or more running containers", .run = stopFn, .args_validator = cobra.MinimumNArgs(1) };
}

fn runFn(cmd: *Command, args: [][]const u8) void {
    const opts: *types.ContainerRunOpts = @ptrCast(@alignCast(cmd.iflags.?));
    var buf: [512]u8 = undefined;
    _ = std.os.linux.write(1, types.formatRun(opts, if (args.len > 0) args[0] else "image", &buf).ptr, types.formatRun(opts, if (args.len > 0) args[0] else "image", &buf).len);
}
fn lsFn(_: *Command, _: [][]const u8) void {
    const io = std.Io.Threaded.global_single_threaded.*.io(); std.Io.File.stdout().writeStreamingAll(io, "CONTAINER ID   IMAGE     STATUS\n") catch {};
}
fn startFn(_: *Command, args: [][]const u8) void {
    for (args) |n| {
        var b: [128]u8 = undefined;
        const m = std.fmt.bufPrint(&b, "Started container '{s}'\n", .{n}) catch continue;
        const io = std.Io.Threaded.global_single_threaded.*.io(); std.Io.File.stdout().writeStreamingAll(io, m) catch {};
    }
}
fn stopFn(_: *Command, args: [][]const u8) void {
    for (args) |n| {
        var b: [128]u8 = undefined;
        const m = std.fmt.bufPrint(&b, "Stopped container '{s}'\n", .{n}) catch continue;
        const io = std.Io.Threaded.global_single_threaded.*.io(); std.Io.File.stdout().writeStreamingAll(io, m) catch {};
    }
}
fn rmFn(_: *Command, args: [][]const u8) void {
    for (args) |n| {
        var b: [128]u8 = undefined;
        const m = std.fmt.bufPrint(&b, "Removed container '{s}'\n", .{n}) catch continue;
        const io = std.Io.Threaded.global_single_threaded.*.io(); std.Io.File.stdout().writeStreamingAll(io, m) catch {};
    }
}
