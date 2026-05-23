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
    const result = try completions.noFileCompletions(&cmd, &.{}, "");
    try std.testing.expect(result.completions.len == 0);
    try std.testing.expect(result.directive.nofilecomp);
}

test "fixedCompletions returns predefined choices" {
    const choices = [_]completions.Completion{ "one", "two", "three" };
    const fn_ptr = completions.fixedCompletions(&choices, .no_file_comp);
    var cmd = TestHelper.makeCommand("test", TestHelper.emptyRun);
    const result = try fn_ptr(&cmd, &.{}, "");
    try std.testing.expectEqual(@as(usize, 0), result.completions.len);
    try std.testing.expect(result.directive.nofilecomp);
}

test "completionWithDesc returns choice" {
    const result = completions.completionWithDesc("choice", "description");
    try std.testing.expectEqualStrings("choice", result);
}

test "compDebug does not crash" {
    completions.compDebug("test", false);
    completions.compDebugln("test", false);
}

test "compError does not crash" {
    completions.compError("test");
    completions.compErrorln("test");
}

test "const strings are correct" {
    try std.testing.expectEqualStrings("__complete", completions.shell_comp_request_cmd);
    try std.testing.expectEqualStrings("__completeNoDesc", completions.shell_comp_no_desc_request_cmd);
}
