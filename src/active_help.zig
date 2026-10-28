//! ActiveHelp support. Maps from cobra/active_help.go
//!
//! ActiveHelp enables dynamic help text display during shell completions,
//! guiding users through interactive workflows.
const std = @import("std");
const Completion = @import("completions.zig").Completion;

/// Marker prefix for ActiveHelp entries in completion output.
/// This value must not change: shell scripts rely on it.
pub const active_help_marker = "_activeHelp_ ";
/// Suffix of the program-specific ActiveHelp env var (<PROGRAM>_ACTIVE_HELP).
pub const active_help_env_var_suffix = "ACTIVE_HELP";
/// Global ActiveHelp env var (COBRA_ACTIVE_HELP).
pub const active_help_global_env_var = "COBRA_ACTIVE_HELP";
/// Value that globally disables ActiveHelp.
pub const active_help_global_disable = "0";
/// Global prefix used for COBRA_<SUFFIX> fallback env vars.
pub const config_env_var_global_prefix = "COBRA";

/// Environment variable storage. Set this from main() (e.g. `cobra.environ = init.environ_map;`)
/// to enable env-driven configuration (ActiveHelp gating, completion descriptions).
/// When null, all env lookups report "not set".
pub var environ: ?*const std.process.Environ.Map = null;

/// Uppercases `name`, joins "<NAME>_<SUFFIX>" and sanitizes it into a valid env var
/// name (Go: configEnvVar — all non-ASCII-alphanumeric chars become '_').
/// Renders into `buf` and returns the result slice.
pub fn configEnvVar(name: []const u8, suffix: []const u8, buf: []u8) []const u8 {
    var w = std.Io.Writer.fixed(buf);
    const write_sanitized = struct {
        fn inner(wr: *std.Io.Writer, s: []const u8) void {
            for (s) |c| {
                const out: u8 = if (c >= 'a' and c <= 'z')
                    c - 32
                else if ((c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_')
                    c
                else
                    '_';
                wr.print("{c}", .{out}) catch {};
            }
        }
    }.inner;
    write_sanitized(&w, name);
    w.print("_", .{}) catch {};
    write_sanitized(&w, suffix);
    return buf[0..w.end];
}

fn getEnv(name: []const u8) ?[]const u8 {
    const env = environ orelse return null;
    const val = env.get(name) orelse return null;
    if (val.len == 0) return null;
    return val;
}

/// getEnvConfig returns the value of <PROGRAM>_<SUFFIX>; when empty/unset it falls
/// back to COBRA_<SUFFIX> (Go: getEnvConfig).
pub fn getEnvConfig(program_name: []const u8, suffix: []const u8, buf: []u8) ?[]const u8 {
    const var_name = configEnvVar(program_name, suffix, buf);
    if (getEnv(var_name)) |v| return v;
    var global_buf: [64]u8 = undefined;
    const global_name = configEnvVar(config_env_var_global_prefix, suffix, &global_buf);
    return getEnv(global_name);
}

/// Returns the ActiveHelp configuration for a program (Go: GetActiveHelpConfig).
/// COBRA_ACTIVE_HELP=0 disables ActiveHelp globally; otherwise the program-specific
/// <PROGRAM>_ACTIVE_HELP value is returned (empty slice means "not configured").
/// `buf` provides storage for the computed env var name.
pub fn getActiveHelpConfig(root_name: []const u8, buf: []u8) []const u8 {
    const global = getEnv(active_help_global_env_var);
    if (global != null and std.mem.eql(u8, global.?, active_help_global_disable)) {
        return active_help_global_disable;
    }
    const var_name = configEnvVar(root_name, active_help_env_var_suffix, buf);
    return getEnv(var_name) orelse "";
}

/// Append an ActiveHelp entry to the end of a completion array.
/// Returns a newly allocated owned slice; caller is responsible for cleanup.
/// The active_help_str is displayed to the user with the "_activeHelp_ " prefix.
pub fn appendActiveHelp(gpa: std.mem.Allocator, comp_array: []const Completion, active_help_str: []const u8) ![]Completion {
    var result: std.ArrayListUnmanaged(Completion) = .empty;
    try result.ensureTotalCapacity(gpa, @intCast(comp_array.len + 1));
    errdefer result.deinit(gpa);
    try result.appendSlice(gpa, comp_array);
    const entry = try gpa.alloc(u8, active_help_marker.len + active_help_str.len);
    @memcpy(entry[0..active_help_marker.len], active_help_marker);
    @memcpy(entry[active_help_marker.len..], active_help_str);
    try result.append(gpa, entry);
    return try result.toOwnedSlice(gpa);
}
