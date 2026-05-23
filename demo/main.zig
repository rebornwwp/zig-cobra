//! Simple hello-world CLI using zig-cobra + zig-pflag.
//! zig build run-demo -- hello --name=Sisyphus
//! zig build run-demo -- hello                 # defaults to "world"

const std = @import("std");
const cobra = @import("cobra");
const pflag = cobra.command_mod.pflag;

const HelloState = struct { name: []const u8 = "world" };

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    var state = HelloState{};

    var flags = pflag.FlagSet.init(gpa, "hello");
    defer flags.deinit();
    flags.stringVarP(&state.name, "name", "n", "world", "your name") catch {};

    var helloCmd = cobra.Command{
        .use   = "hello",
        .short = "Say hello to someone",
        .run   = helloRun,
        .flags = &flags,
    };
    helloCmd.iflags = @ptrCast(@alignCast(&state));

    var rootCmd = cobra.Command{
        .use   = "demo",
        .short = "A friendly CLI demo",
        .flags = &flags,
    };
    rootCmd.addCommand(gpa, &.{&helloCmd});
    defer rootCmd.deinit(gpa);

    const alloc = init.arena.allocator();
    const raw = try init.minimal.args.toSlice(alloc);
    const effective = if (raw.len > 1) raw[1..] else &.{};
    rootCmd.setArgs(@as([]const []const u8, @ptrCast(effective)));
    rootCmd.executeWrapper() catch {};
}

fn helloRun(cmd: *cobra.Command, args: [][]const u8) void {
    _ = args;
    const state: *HelloState = @ptrCast(@alignCast(cmd.iflags.?));
    var buf: [128]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "hello {s}\n", .{state.name}) catch return;
    _ = std.os.linux.write(1, msg.ptr, msg.len);
}
