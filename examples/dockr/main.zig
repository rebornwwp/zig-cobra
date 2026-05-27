const std = @import("std");
const cobra = @import("cobra");
const pflag = cobra.command_mod.pflag;
const Command = cobra.Command;
const types = @import("types.zig");
const ctr = @import("container.zig");
const img = @import("image.zig");
const vol = @import("volume.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    var state = types.AppState{};

    // Root
    var root_flags = pflag.FlagSet.init(gpa, "dockr");
    defer root_flags.deinit();
    root_flags.stringVarP(&state.config, "config", "c", "/etc/dockr/config.toml", "config file path") catch {};
    var root_cmd = Command{ .use = "dockr", .short = "A self-sufficient runtime for containers", .long = "dockr is a CLI for managing containers, images, and volumes.\nUse 'dockr COMMAND --help' for more information on a command.", .flags = &root_flags, .persistent_pre_run = rootPersistentPreRun };
    root_cmd.iflags = @ptrCast(@alignCast(&state));

    // ── All commands are var in this scope (stack-lifetime) ──
    var ctr_cmd: Command = undefined;
    var cr_cmd: Command = undefined;
    var cr_flags: pflag.FlagSet = undefined;
    defer cr_flags.deinit();
    var cr_opts = types.ContainerRunOpts{};
    var cls_cmd: Command = undefined;
    var cls_flags: pflag.FlagSet = undefined;
    defer cls_flags.deinit();
    var cstart_cmd: Command = undefined;
    var cstop_cmd: Command = undefined;
    var crm_cmd: Command = undefined;
    var crm_flags: pflag.FlagSet = undefined;
    defer crm_flags.deinit();
    ctr.init_run(gpa, &cr_cmd, &cr_flags, &cr_opts);
    ctr.init_ls(gpa, &cls_cmd, &cls_flags);
    ctr.init_start(&cstart_cmd);
    ctr.init_stop(&cstop_cmd);
    ctr.init_rm(gpa, &crm_cmd, &crm_flags);
    ctr_cmd = Command{ .use = "container", .aliases = &.{"containers"}, .short = "Manage containers", .long = "Commands for creating, running, listing, and removing containers." };
    ctr_cmd.addCommand(gpa, &.{ &cr_cmd, &cls_cmd, &cstart_cmd, &cstop_cmd, &crm_cmd });

    var img_cmd: Command = undefined;
    var ils_cmd: Command = undefined;
    var ipull_cmd: Command = undefined;
    var ipush_cmd: Command = undefined;
    img.init(gpa, &img_cmd, &ils_cmd, &ipull_cmd, &ipush_cmd);

    var vol_cmd: Command = undefined;
    var vls_cmd: Command = undefined;
    var vcreate_cmd: Command = undefined;
    vol.init(gpa, &vol_cmd, &vls_cmd, &vcreate_cmd);

    // Wire
    root_cmd.addCommand(gpa, &.{ &ctr_cmd, &img_cmd, &vol_cmd });
    defer root_cmd.deinit(gpa);

    const alloc = init.arena.allocator();
    const args_slice = try init.minimal.args.toSlice(alloc);
    const effective_args = if (args_slice.len > 1) args_slice[1..] else &.{};
    root_cmd.setArgs(effective_args);
    root_cmd.executeWrapper() catch {};
}

fn rootPersistentPreRun(cmd: *Command, _: [][]const u8) void {
    const st: *types.AppState = @ptrCast(@alignCast(cmd.root().iflags.?));
    const io = @import("std").Io.Threaded.global_single_threaded.*.io();
    var buf: [256]u8 = undefined;
    var stderr_w = std.Io.File.Writer.init(std.Io.File.stderr(), io, &buf);
    const w = &stderr_w.interface;
    w.print("Loaded config: {s}\n", .{st.config}) catch {};
    stderr_w.flush() catch {};
}
