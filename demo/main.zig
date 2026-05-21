//! Demo app using the zig-cobra framework.
//! Usage: zig build run-demo -- hello --name=join
const std = @import("std");
const cobra = @import("cobra");
const Command = cobra.Command;
const linux = std.os.linux;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var rootCmd = Command{
        .use = "demo",
        .short = "A CLI demo using zig-cobra framework",
    };

    var helloCmd = Command{
        .use = "hello",
        .short = "Say hello to someone",
        .run = helloRun,
        .disable_flag_parsing = true,
    };

    rootCmd.addCommand(gpa, &.{&helloCmd});
    defer rootCmd.deinit(gpa);

    const alloc = init.arena.allocator();
    const args_slice = try init.minimal.args.toSlice(alloc);
    const effective_args = if (args_slice.len > 1) args_slice[1..] else &.{};

    rootCmd.setArgs(effective_args);
    rootCmd.executeWrapper() catch {
        try std.Io.File.stderr().writeStreamingAll(io, "Error — try: demo hello --name=join\n");
        std.process.exit(1);
    };
}

/// hello 命令 — 输出 "hello <name>"
fn helloRun(cmd: *Command, args: [][]const u8) void {
    _ = cmd;
    var name: []const u8 = "world";

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.startsWith(u8, arg, "--name=")) {
            name = arg["--name=".len..];
        } else if (std.mem.eql(u8, arg, "--name") and i + 1 < args.len) {
            i += 1;
            name = args[i];
        }
    }

    var buf: [128]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "hello {s}\n", .{name}) catch return;
    _ = linux.write(1, msg.ptr, msg.len);
}
