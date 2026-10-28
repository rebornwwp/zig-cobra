const std = @import("std");
const cobra = @import("cobra");
const pflag = cobra.command_mod.pflag;

const HelloState = struct { name: []const u8 = "world" };

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    cobra.setEnviron(init.environ_map);
    var state = HelloState{};

    var hello_flags = pflag.FlagSet.init(gpa, "hello");
    defer hello_flags.deinit();
    hello_flags.stringVarP(&state.name, "name", "n", "world", "your name") catch {};

    var helloCmd = cobra.Command{
        .use = "hello",
        .short = "Say hello to someone",
        .run = helloRun,
        .flags_ptr = &hello_flags,
    };
    helloCmd.user_data = @ptrCast(@alignCast(&state));

    var rootCmd = cobra.Command{
        .use = "demo",
        .short = "A friendly CLI demo",
    };
    rootCmd.addCommand(gpa, &.{&helloCmd});
    defer rootCmd.deinit(gpa);

    const alloc = init.arena.allocator();
    const raw = try init.minimal.args.toSlice(alloc);
    const effective = if (raw.len > 1) @as([]const []const u8, @ptrCast(raw[1..])) else &.{};
    rootCmd.setArgs(effective);
    rootCmd.executeWrapper(gpa) catch {
        std.process.exit(1);
    };
}

fn helloRun(cmd: *cobra.Command, args: [][]const u8) void {
    _ = args;
    const state: *HelloState = @ptrCast(@alignCast(cmd.user_data.?));
    const io = @import("std").Io.Threaded.global_single_threaded.*.io();
    var buf: [128]u8 = undefined;
    var stdout_w = std.Io.File.Writer.init(std.Io.File.stdout(), io, &buf);
    const w = &stdout_w.interface;
    w.print("hello {s}\n", .{state.name}) catch {};
    stdout_w.flush() catch {};
}
