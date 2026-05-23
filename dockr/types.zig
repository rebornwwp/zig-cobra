const std = @import("std");
const cobra = @import("cobra");
pub const Command = cobra.Command;
pub const AppState = struct { config: []const u8 = "/etc/dockr/config.toml" };
pub const ContainerRunOpts = struct {
    name: []const u8 = "",
    detach: bool = false,
    interactive: bool = false,
    tty: bool = false,
    rm: bool = false,
    publish: std.ArrayListUnmanaged([]const u8) = .empty,
    volume: std.ArrayListUnmanaged([]const u8) = .empty,
    env: std.ArrayListUnmanaged([]const u8) = .empty,
};
pub fn formatRun(opts: *const ContainerRunOpts, image: []const u8, buf: []u8) []const u8 {
    var w = std.Io.Writer.fixed(buf);
    w.print("docker run", .{}) catch {};
    if (opts.detach) w.print(" -d", .{}) catch {};
    if (opts.interactive) w.print(" -i", .{}) catch {};
    if (opts.tty) w.print(" -t", .{}) catch {};
    if (opts.rm) w.print(" --rm", .{}) catch {};
    if (opts.name.len > 0) w.print(" --name {s}", .{opts.name}) catch {};
    for (opts.publish.items) |p| w.print(" -p {s}", .{p}) catch {};
    for (opts.volume.items) |v| w.print(" -v {s}", .{v}) catch {};
    for (opts.env.items) |e| w.print(" -e {s}", .{e}) catch {};
    w.print(" {s}\n", .{image}) catch {};
    return std.Io.Writer.buffered(&w);
}
