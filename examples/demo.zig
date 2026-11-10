const std = @import("std");
const cobra = @import("cobra");
const pflag = cobra.command_mod.pflag;

const HelloState = struct { name: []const u8 = "world", age: i32 = 0 };

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    cobra.setEnviron(init.environ_map);
    var state = HelloState{};

    var hello_flags = pflag.FlagSet.init(gpa, "hello");
    defer hello_flags.deinit();
    hello_flags.stringVarP(&state.name, "name", "n", "world", "your name") catch {};
    hello_flags.intVarP(i32, &state.age, "age", "a", 0, "your age") catch {};

    var helloCmd = cobra.Command{
        .use = "hello",
        .short = "Say hello to someone",
        // Zig-native Exec channel: run callbacks receive the execution
        // environment (io + allocator) that execute() threaded from main —
        // the explicit-parameter form of what Go expresses with closures.
        // Output goes through cmd.print so setOut()/redirected writers keep
        // working; no global Io fetch, no File.Writer boilerplate, no manual
        // flush, and the callback can propagate errors.
        .run_e = helloRun,
        .flags_ptr = &hello_flags,
    };
    // helloCmd.flags(gpa).boolVar(p: *bool, name: []const u8, value: bool, usage: []const u8)
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

fn helloRun(ev: cobra.Exec, cmd: *cobra.Command, args: [][]const u8) anyerror!void {
    _ = args;
    const state: *HelloState = @ptrCast(@alignCast(cmd.user_data.?));
    cmd.print(ev.io, "hello {s}\n", .{state.name});
    if (state.age != 0) {
        cmd.print(ev.io, "you are {d} years old\n", .{state.age});
    }
}
