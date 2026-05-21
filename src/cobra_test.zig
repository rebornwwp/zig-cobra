//! Tests for cobra utility functions. Maps from cobra/cobra_test.go
const std = @import("std");
const cobra = @import("cobra.zig");
const Command = cobra.Command;
const TestHelper = @import("test_helper.zig");
const PositionalArgs = cobra.PositionalArgs;

test "Levenshtein distance - equal strings" {
    try std.testing.expectEqual(0, cobra.levenshteinDistance("hello", "hello", false));
}

test "Levenshtein distance - equal strings (case insensitive)" {
    try std.testing.expectEqual(0, cobra.levenshteinDistance("Hello", "hello", true));
}

test "Levenshtein distance - kitten/sitting" {
    try std.testing.expectEqual(3, cobra.levenshteinDistance("kitten", "sitting", false));
}

test "Levenshtein distance - case insensitive" {
    try std.testing.expectEqual(3, cobra.levenshteinDistance("Kitten", "Sitting", true));
}

test "Levenshtein distance - empty strings" {
    try std.testing.expectEqual(0, cobra.levenshteinDistance("", "", false));
}

test "Levenshtein distance - one empty" {
    try std.testing.expectEqual(3, cobra.levenshteinDistance("abc", "", false));
}

test "trimRightSpace" {
    try std.testing.expectEqualStrings("hello", cobra.trimRightSpace("hello   "));
    try std.testing.expectEqualStrings("hello", cobra.trimRightSpace("hello"));
    try std.testing.expectEqualStrings("", cobra.trimRightSpace("   "));
    try std.testing.expectEqualStrings("", cobra.trimRightSpace(""));
}

test "stringInSlice" {
    const items = [_][]const u8{ "apple", "banana", "cherry" };
    try std.testing.expect(cobra.stringInSlice("apple", &items));
    try std.testing.expect(cobra.stringInSlice("cherry", &items));
    try std.testing.expect(!cobra.stringInSlice("grape", &items));
    try std.testing.expect(!cobra.stringInSlice("", &items));
}

test "commandNameMatches - case sensitive" {
    try std.testing.expect(cobra.commandNameMatches("root", "root"));
    try std.testing.expect(!cobra.commandNameMatches("root", "ROOT"));
}
