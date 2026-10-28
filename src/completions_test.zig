//! Tests for completions. Maps from cobra/completions_test.go
const std = @import("std");
const Command = @import("command.zig").Command;
const completions = @import("completions.zig");
const TestHelper = @import("test_helper.zig");
const gpa = std.testing.allocator;

test "ShellCompDirective default is zero" {
    const d = completions.ShellCompDirective.default;
    try std.testing.expect(!d.e);
    try std.testing.expect(!d.nospace);
    try std.testing.expect(!d.nofilecomp);
}

test "ShellCompDirective no_file_comp" {
    const d = completions.ShellCompDirective.no_file_comp;
    try std.testing.expect(d.nofilecomp);
    try std.testing.expect(!d.nospace);
}

test "ShellCompDirective no_space" {
    const d = completions.ShellCompDirective.no_space;
    try std.testing.expect(d.nospace);
    try std.testing.expect(!d.e);
}

test "ShellCompDirective filter_file_ext" {
    const d = completions.ShellCompDirective.filter_file_ext;
    try std.testing.expect(d.filterfile);
}

test "ShellCompDirective filter_dirs" {
    const d = completions.ShellCompDirective.filter_dirs;
    try std.testing.expect(d.filterdirs);
}

test "ShellCompDirective keep_order" {
    const d = completions.ShellCompDirective.keep_order;
    try std.testing.expect(d.keeporder);
}

test "CompletionOptions default values" {
    const opts = completions.CompletionOptions{};
    try std.testing.expect(!opts.disable_default_cmd);
    try std.testing.expect(!opts.disable_no_desc_flag);
    try std.testing.expect(!opts.disable_descriptions);
    try std.testing.expect(!opts.hidden_default_cmd);
    try std.testing.expect(opts.default_shell_comp_directive == null);
}

test "noFileCompletions returns no_file_comp directive" {
    var cmd = TestHelper.makeCommand("test", TestHelper.emptyRun);
    const cf = completions.noFileCompletions();
    const result = try cf.invoke(&cmd, &.{}, "");
    try std.testing.expect(result.completions.len == 0);
    try std.testing.expect(result.directive.nofilecomp);
}

test "fixedCompletions returns predefined choices" {
    const cf = completions.fixedCompletions(&.{ "one", "two", "three" }, .no_file_comp);
    var cmd = TestHelper.makeCommand("test", TestHelper.emptyRun);
    const result = try cf.invoke(&cmd, &.{}, "");
    try std.testing.expectEqual(@as(usize, 3), result.completions.len);
    try std.testing.expectEqualStrings("one", result.completions[0]);
    try std.testing.expectEqualStrings("three", result.completions[2]);
    try std.testing.expect(result.directive.nofilecomp);
}

test "completionWithDesc joins with tab" {
    const result = try completions.completionWithDesc(gpa, "choice", "description");
    defer gpa.free(result);
    try std.testing.expectEqualStrings("choice\tdescription", result);
}

test "directive int encoding matches Go" {
    try std.testing.expectEqual(@as(u8, 0), completions.ShellCompDirective.default.toInt());
    try std.testing.expectEqual(@as(u8, 1), completions.ShellCompDirective.error_flag.toInt());
    try std.testing.expectEqual(@as(u8, 2), completions.ShellCompDirective.no_space.toInt());
    try std.testing.expectEqual(@as(u8, 4), completions.ShellCompDirective.no_file_comp.toInt());
    try std.testing.expectEqual(@as(u8, 8), completions.ShellCompDirective.filter_file_ext.toInt());
    try std.testing.expectEqual(@as(u8, 16), completions.ShellCompDirective.filter_dirs.toInt());
    try std.testing.expectEqual(@as(u8, 32), completions.ShellCompDirective.keep_order.toInt());
}

test "compDebug does not crash" {
    const io = std.Io.Threaded.global_single_threaded.*.io();
    completions.compDebug(io, "test", false);
    completions.compDebugln(io, "test", false);
}

test "compError does not crash" {
    const io = std.Io.Threaded.global_single_threaded.*.io();
    completions.compError(io, "test");
    completions.compErrorln(io, "test");
}

test "const strings are correct" {
    try std.testing.expectEqualStrings("__complete", completions.shell_comp_request_cmd);
    try std.testing.expectEqualStrings("__completeNoDesc", completions.shell_comp_no_desc_request_cmd);
}
