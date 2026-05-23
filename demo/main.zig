//! Docker-style CLI demo using zig-cobra + zig-pflag.
//! Tests nested command trees, flags, help, hooks — production readiness.
//!
//! Usage: zig build run-demo -- container run --name web -d -p 80:80 nginx
//!        zig build run-demo -- container ls --all
//!        zig build run-demo -- --help
//!        zig build run-demo --

const std = @import("std");
const cobra = @import("cobra");
const pflag = cobra.command_mod.pflag;
const Command = cobra.Command;

// ─── State shared across commands (via iflags pointer) ───

const AppState = struct {
    config: []const u8 = "/etc/dockr/config.toml",
    verbose: bool = false,
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    var state = AppState{};

    // ── Root command ──
    var rootFlags = pflag.FlagSet.init(gpa, "dockr");
    defer rootFlags.deinit();
    rootFlags.stringVarP(&state.config, "config", "c", "/etc/dockr/config.toml", "config file path") catch {};

    var rootCmd = Command{
        .use = "dockr",
        .short = "A self-sufficient runtime for containers",
        .long = "dockr is a CLI for managing containers, images, and volumes.\nUse 'dockr COMMAND --help' for more information on a command.",
        .flags = &rootFlags, // wait, that's wrong
    };
    rootCmd.flags = &rootFlags;
    rootCmd.persistent_pre_run = rootPersistentPreRun;
    defer rootCmd.deinit(gpa);

    // ── container command group ──
    var containerCmd = Command{
        .use = "container",
        .aliases = &.{ "containers", "ctr" },
        .short = "Manage containers",
        .long = "Commands for creating, running, listing, and removing containers.",
    };

    // container run
    var runFlags = pflag.FlagSet.init(gpa, "container run");
    defer runFlags.deinit();
    var runOpts = ContainerRunOpts{};
    runFlags.stringVarP(&runOpts.name, "name", "", "", "assign a name to the container") catch {};
    runFlags.boolVarP(&runOpts.detach, "detach", "d", false, "run container in background and print container ID") catch {};
    runFlags.boolVarP(&runOpts.interactive, "interactive", "i", false, "keep STDIN open even if not attached") catch {};
    _ = &runOpts.interactive; // just defining it
    runFlags.boolVarP(&runOpts.tty, "tty", "t", false, "allocate a pseudo-TTY") catch {};
    runFlags.stringSliceVarP(&runOpts.publish, "publish", "p", &.{}, "publish a container's port(s) to the host") catch {};
    runFlags.stringSliceVarP(&runOpts.volume, "volume", "v", &.{}, "bind mount a volume") catch {};
    runFlags.stringSliceVarP(&runOpts.env, "env", "e", &.{}, "set environment variables") catch {};
    runFlags.boolVarP(&runOpts.rm, "rm", "", false, "automatically remove the container when it exits") catch {};

    var containerRunCmd = Command{
        .use = "run [OPTIONS] IMAGE [COMMAND] [ARG...]",
        .short = "Create and run a new container from an image",
        .long = "Creates a writeable container layer over the specified image\nand then starts it using the specified command.",
        .example = "  dockr container run -d --name web -p 80:80 nginx\n  dockr container run -it --rm ubuntu bash",
        .run = containerRunFn,
        .flags = &runFlags,
        .args_validator = cobra.MinimumNArgs(1),
    };
    containerRunCmd.iflags = @ptrCast(@alignCast(&runOpts));

    // container ls
    var lsFlags = pflag.FlagSet.init(gpa, "container ls");
    defer lsFlags.deinit();
    var lsAll: bool = false;
    var lsQuiet: bool = false;
    lsFlags.boolVarP(&lsAll, "all", "a", false, "show all containers (default shows just running)") catch {};
    lsFlags.boolVarP(&lsQuiet, "quiet", "q", false, "only display container IDs") catch {};

    var containerLsCmd = Command{
        .use = "ls [OPTIONS]",
        .short = "List containers",
        .run = containerLsFn,
        .flags = &lsFlags,
        .example = "  dockr container ls\n  dockr container ls --all",
    };

    // container start
    var containerStartCmd = Command{
        .use = "start [OPTIONS] CONTAINER [CONTAINER...]",
        .short = "Start one or more stopped containers",
        .run = containerStartFn,
        .args_validator = cobra.MinimumNArgs(1),
    };

    // container stop
    var containerStopCmd = Command{
        .use = "stop [OPTIONS] CONTAINER [CONTAINER...]",
        .short = "Stop one or more running containers",
        .run = containerStopFn,
        .args_validator = cobra.MinimumNArgs(1),
    };

    // container rm
    var rmFlags = pflag.FlagSet.init(gpa, "container rm");
    defer rmFlags.deinit();
    var rmForce: bool = false;
    rmFlags.boolVarP(&rmForce, "force", "f", false, "force removal of a running container") catch {};

    var containerRmCmd = Command{
        .use = "rm [OPTIONS] CONTAINER [CONTAINER...]",
        .short = "Remove one or more containers",
        .run = containerRmFn,
        .flags = &rmFlags,
        .args_validator = cobra.MinimumNArgs(1),
    };

    containerCmd.addCommand(gpa, &.{ &containerRunCmd, &containerLsCmd, &containerStartCmd, &containerStopCmd, &containerRmCmd });
    // handled by rootCmd.deinit

    // ── image command group ──
    var imageCmd = Command{
        .use = "image",
        .aliases = &.{ "images", "img" },
        .short = "Manage images",
        .long = "Commands for pulling, pushing, and listing images.",
    };

    var imageLsCmd = Command{
        .use = "ls [OPTIONS]",
        .short = "List images",
        .run = imageLsFn,
    };

    var imagePullCmd = Command{
        .use = "pull [OPTIONS] IMAGE",
        .short = "Download an image from a registry",
        .run = imagePullFn,
        .args_validator = cobra.MinimumNArgs(1),
    };

    var imagePushCmd = Command{
        .use = "push [OPTIONS] IMAGE",
        .short = "Upload an image to a registry",
        .run = imagePushFn,
        .args_validator = cobra.MinimumNArgs(1),
    };

    imageCmd.addCommand(gpa, &.{ &imageLsCmd, &imagePullCmd, &imagePushCmd });
    // handled by rootCmd.deinit

    // ── volume command group ──
    var volumeCmd = Command{
        .use = "volume",
        .short = "Manage volumes",
    };

    var volumeLsCmd = Command{
        .use = "ls [OPTIONS]",
        .short = "List volumes",
        .run = volumeLsFn,
    };

    var volumeCreateCmd = Command{
        .use = "create [OPTIONS] VOLUME",
        .short = "Create a volume",
        .run = volumeCreateFn,
        .args_validator = cobra.MinimumNArgs(1),
    };

    volumeCmd.addCommand(gpa, &.{ &volumeLsCmd, &volumeCreateCmd });
    // handled by rootCmd.deinit

    // ── Wire up the tree ──
    rootCmd.addCommand(gpa, &.{ &containerCmd, &imageCmd, &volumeCmd });

    // ── Dispatch ──
    const alloc = init.arena.allocator();
    const args_slice = try init.minimal.args.toSlice(alloc);
    const effective_args = if (args_slice.len > 1) args_slice[1..] else &.{};

    rootCmd.setArgs(effective_args);
    rootCmd.iflags = @ptrCast(@alignCast(&state));
    rootCmd.executeWrapper() catch {};
}

// ─── Persistent Pre-Run Hook (runs before every command) ───

fn rootPersistentPreRun(cmd: *Command, _: [][]const u8) void {
    const state: *AppState = @ptrCast(@alignCast(cmd.root().iflags.?));
    // Simulate loading config
    var buf: [256]u8 = undefined;
    _ = std.fmt.bufPrint(&buf, "[dockr] loaded config: {s}", .{state.config}) catch return;
    // In production: actually parse config, set up logging, etc.
}

// ─── Container Run Options ───

const ContainerRunOpts = struct {
    name: []const u8 = "",
    detach: bool = false,
    interactive: bool = false,
    tty: bool = false,
    rm: bool = false,
    publish: std.ArrayListUnmanaged([]const u8) = .empty,
    volume: std.ArrayListUnmanaged([]const u8) = .empty,
    env: std.ArrayListUnmanaged([]const u8) = .empty,
};

fn containerRunFn(cmd: *Command, args: [][]const u8) void {
    const opts: *ContainerRunOpts = @ptrCast(@alignCast(cmd.iflags.?));
    const image = if (args.len > 0) args[0] else "default-image";

    var cmdline: std.ArrayListUnmanaged(u8) = .empty;
    if (opts.detach) cmdline.appendSlice(std.heap.page_allocator, " -d") catch {};
    if (opts.interactive) cmdline.appendSlice(std.heap.page_allocator, " -i") catch {};
    if (opts.tty) cmdline.appendSlice(std.heap.page_allocator, " -t") catch {};
    if (opts.rm) cmdline.appendSlice(std.heap.page_allocator, " --rm") catch {};
    if (opts.name.len > 0) {
        cmdline.appendSlice(std.heap.page_allocator, " --name ") catch {};
        cmdline.appendSlice(std.heap.page_allocator, opts.name) catch {};
    }
    for (opts.publish.items) |p| {
        cmdline.appendSlice(std.heap.page_allocator, " -p ") catch {};
        cmdline.appendSlice(std.heap.page_allocator, p) catch {};
    }
    for (opts.volume.items) |v| {
        cmdline.appendSlice(std.heap.page_allocator, " -v ") catch {};
        cmdline.appendSlice(std.heap.page_allocator, v) catch {};
    }
    for (opts.env.items) |e| {
        cmdline.appendSlice(std.heap.page_allocator, " -e ") catch {};
        cmdline.appendSlice(std.heap.page_allocator, e) catch {};
    }

    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "[dockr] docker run{s} {s}\n", .{ cmdline.items, image }) catch return;
    _ = std.os.linux.write(1, msg.ptr, msg.len);
}

fn containerLsFn(cmd: *Command, _: [][]const u8) void {
    _ = cmd;
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "[dockr] CONTAINER ID   IMAGE     STATUS\n", .{}) catch return;
    _ = std.os.linux.write(1, msg.ptr, msg.len);
}

fn containerStartFn(_: *Command, args: [][]const u8) void {
    for (args) |name| {
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "[dockr] Started container '{s}'\n", .{name}) catch continue;
        _ = std.os.linux.write(1, msg.ptr, msg.len);
    }
}

fn containerStopFn(_: *Command, args: [][]const u8) void {
    for (args) |name| {
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "[dockr] Stopped container '{s}'\n", .{name}) catch continue;
        _ = std.os.linux.write(1, msg.ptr, msg.len);
    }
}

fn containerRmFn(_: *Command, args: [][]const u8) void {
    for (args) |name| {
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "[dockr] Removed container '{s}'\n", .{name}) catch continue;
        _ = std.os.linux.write(1, msg.ptr, msg.len);
    }
}

fn imageLsFn(_: *Command, _: [][]const u8) void {
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "[dockr] REPOSITORY   TAG       SIZE\n", .{}) catch return;
    _ = std.os.linux.write(1, msg.ptr, msg.len);
}

fn imagePullFn(_: *Command, args: [][]const u8) void {
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "[dockr] Pulling image '{s}'...\n", .{args[0]}) catch return;
    _ = std.os.linux.write(1, msg.ptr, msg.len);
}

fn imagePushFn(_: *Command, args: [][]const u8) void {
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "[dockr] Pushing image '{s}'...\n", .{args[0]}) catch return;
    _ = std.os.linux.write(1, msg.ptr, msg.len);
}

fn volumeLsFn(_: *Command, _: [][]const u8) void {
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "[dockr] VOLUME NAME\n", .{}) catch return;
    _ = std.os.linux.write(1, msg.ptr, msg.len);
}

fn volumeCreateFn(_: *Command, args: [][]const u8) void {
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "[dockr] Created volume '{s}'\n", .{args[0]}) catch return;
    _ = std.os.linux.write(1, msg.ptr, msg.len);
}
