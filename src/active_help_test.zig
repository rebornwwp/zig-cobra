//! Tests for active_help. Maps from cobra/active_help_test.go
const std = @import("std");
const Command = @import("command.zig").Command;
const active_help = @import("active_help.zig");
const TestHelper = @import("test_helper.zig");
const Completion = @import("completions.zig").Completion;
const gpa = std.testing.allocator;

test "appendActiveHelp adds marker" {
    var comps = [2]Completion{ "option1", "option2" };
    const result = try active_help.appendActiveHelp(gpa, &comps, "help text");
    defer {
        // The last element is a heap-allocated active help string.
        // Elements 0..len-1 reference the input comps and must not be freed.
        gpa.free(result[result.len - 1]);
        gpa.free(result);
    }
    try std.testing.expect(result.len == 3);
    try std.testing.expectEqualStrings("option1", result[0]);
    try std.testing.expectEqualStrings("option2", result[1]);
    try std.testing.expect(std.mem.indexOf(u8, result[2], "_activeHelp_") != null);
}

test "appendActiveHelp with empty comps" {
    var comps: [0]Completion = .{};
    const result = try active_help.appendActiveHelp(gpa, &comps, "help");
    defer {
        // The last element is a heap-allocated active help string.
        gpa.free(result[result.len - 1]);
        gpa.free(result);
    }
    try std.testing.expect(result.len == 1);
}

test "getActiveHelpConfig returns empty without environ" {
    var buf: [64]u8 = undefined;
    const config = active_help.getActiveHelpConfig("test", &buf);
    try std.testing.expectEqualStrings("", config);
}

test "configEnvVar sanitizes and uppercases" {
    var buf: [64]u8 = undefined;
    const v = active_help.configEnvVar("my-app", "ACTIVE_HELP", &buf);
    try std.testing.expectEqualStrings("MY_APP_ACTIVE_HELP", v);
}

test "appendActiveHelp with multiple messages" {
    var comps: [0]Completion = .{};
    const result1 = try active_help.appendActiveHelp(gpa, &comps, "first message");
    defer {
        gpa.free(result1[result1.len - 1]);
        gpa.free(result1);
    }
    try std.testing.expect(result1.len == 1);

    // Add another active help message
    const result2 = try active_help.appendActiveHelp(gpa, result1, "second message");
    defer {
        gpa.free(result2[result2.len - 1]);
        gpa.free(result2);
    }
    try std.testing.expect(result2.len == 2);
    try std.testing.expect(std.mem.indexOf(u8, result2[0], "first message") != null);
    try std.testing.expect(std.mem.indexOf(u8, result2[1], "second message") != null);
}

test "appendActiveHelp preserves existing completions" {
    var comps = [3]Completion{ "opt1", "opt2", "opt3" };
    const result = try active_help.appendActiveHelp(gpa, &comps, "help text");
    defer {
        gpa.free(result[result.len - 1]);
        gpa.free(result);
    }
    try std.testing.expect(result.len == 4);
    try std.testing.expectEqualStrings("opt1", result[0]);
    try std.testing.expectEqualStrings("opt2", result[1]);
    try std.testing.expectEqualStrings("opt3", result[2]);
    try std.testing.expect(std.mem.indexOf(u8, result[3], "help text") != null);
}

test "activeHelp marker format is correct" {
    var comps: [0]Completion = .{};
    const result = try active_help.appendActiveHelp(gpa, &comps, "test message");
    defer {
        gpa.free(result[result.len - 1]);
        gpa.free(result);
    }
    try std.testing.expect(result.len == 1);
    // Verify the marker prefix is present
    try std.testing.expect(std.mem.startsWith(u8, result[0], active_help.active_help_marker));
    // Verify the message follows the marker
    try std.testing.expect(std.mem.indexOf(u8, result[0], "test message") != null);
}

test "getActiveHelpConfig with enabled env" {
    // Create a mock environment map
    var map = std.process.Environ.Map.init(gpa);
    defer map.deinit();

    var buf: [64]u8 = undefined;
    const var_name = active_help.configEnvVar("myapp", "ACTIVE_HELP", &buf);

    try map.put(var_name, "1");
    const old_environ = active_help.environ;
    active_help.environ = &map;
    defer active_help.environ = old_environ;

    var config_buf: [64]u8 = undefined;
    const config = active_help.getActiveHelpConfig("myapp", &config_buf);
    try std.testing.expectEqualStrings("1", config);
}

test "getActiveHelpConfig disabled with 0" {
    var map = std.process.Environ.Map.init(gpa);
    defer map.deinit();

    // Set COBRA_ACTIVE_HELP=0 to globally disable
    try map.put("COBRA_ACTIVE_HELP", "0");
    const old_environ = active_help.environ;
    active_help.environ = &map;
    defer active_help.environ = old_environ;

    var config_buf: [64]u8 = undefined;
    const config = active_help.getActiveHelpConfig("myapp", &config_buf);
    // When globally disabled, returns "0"
    try std.testing.expectEqualStrings("0", config);
}

test "getActiveHelpConfig global disable overrides program config" {
    var map = std.process.Environ.Map.init(gpa);
    defer map.deinit();

    // Set both global disable and program-specific enable
    try map.put("COBRA_ACTIVE_HELP", "0");
    try map.put("MYAPP_ACTIVE_HELP", "1");
    const old_environ = active_help.environ;
    active_help.environ = &map;
    defer active_help.environ = old_environ;

    var config_buf: [64]u8 = undefined;
    const config = active_help.getActiveHelpConfig("myapp", &config_buf);
    // Global disable takes precedence
    try std.testing.expectEqualStrings("0", config);
}
