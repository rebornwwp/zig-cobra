# zig-cobra

[English](README.md) | [中文](README_cn.md)

<div align="center">

[![Zig](https://img.shields.io/badge/Zig-0.16.0-orange?logo=zig&logoColor=white)](https://ziglang.org/)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Status](https://img.shields.io/badge/status-beta-yellow)](https://github.com/rebornwwp/zig-cobra)

</div>

A CLI framework for **Zig 0.16.0**, ported from Go's [spf13/cobra](https://github.com/spf13/cobra).

Built on [rebornwwp/zig-pflag](https://github.com/rebornwwp/zig-pflag) for POSIX/GNU-style flag parsing.

## Features

- **Nested command tree** — `addCommand`, aliases, groups, suggestions
- **Flag parsing** via zig-pflag — all types, shorthand, `--help` auto-generation
- **Run hooks** — Pre/Post run, local + persistent with parent-chain traversal
- **Positional argument validation** — 10 built-in validators (`NoArgs`, `ExactArgs`, `RangeArgs`, …)
- **`--version` flag** support
- **Shell completion** — bash, zsh, fish, powershell with `ShellCompDirective`
- **ActiveHelp** — dynamic help text in completions
- **Command deprecation**, hidden commands, **Levenshtein-based suggestions**
- **Flag groups** — mutually exclusive, required together, one-required
- **Customizable** — help template, usage func, error func, I/O writers

## Installation

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .cobra = .{
        .url = "https://github.com/rebornwwp/zig-cobra/archive/refs/heads/main.tar.gz",
        .hash = "...",  // zig build 会提示正确值
    },
    .pflag = .{
        .url = "https://github.com/rebornwwp/zig-pflag/archive/refs/heads/main.tar.gz",
        .hash = "...",
    },
},
```

Then in your `build.zig`:

```zig
const cobra_dep = b.dependency("cobra", .{ .target = target, .optimize = optimize });
const pflag_dep = b.dependency("pflag", .{ .target = target, .optimize = optimize });
const cobra_mod = cobra_dep.module("cobra");
const pflag_mod = pflag_dep.module("pflag");

const exe = b.addExecutable(.{
    .name = "myapp",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "cobra", .module = cobra_mod },
            .{ .name = "pflag", .module = pflag_mod },
        },
    }),
});
```

## Quick Start

```zig
const std = @import("std");
const cobra = @import("cobra");
const pflag = cobra.command_mod.pflag;

const App = struct {
    name: []const u8 = "world",
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    var app = App{};

    // ── Flag setup ──
    var flags = pflag.FlagSet.init(gpa, "hello");
    defer flags.deinit();
    flags.stringVarP(&app.name, "name", "n", "world", "your name") catch {};

    // ── Commands ──
    var helloCmd = cobra.Command{
        .use   = "hello",
        .short = "Say hello to someone",
        .long  = "Prints a greeting. Defaults to \"world\".",
        .run   = helloRun,
        .flags = &flags,
    };
    helloCmd.iflags = @ptrCast(@alignCast(&app));

    var rootCmd = cobra.Command{
        .use   = "myapp",
        .short = "A friendly CLI demo",
        .flags = &flags,
    };
    rootCmd.addCommand(gpa, &.{&helloCmd});
    defer rootCmd.deinit(gpa);

    // ── Parse args and execute ──
    const alloc = init.arena.allocator();
    const raw = try init.minimal.args.toSlice(alloc);
    const effective = if (raw.len > 1) raw[1..] else &.{};
    rootCmd.setArgs(effective);
    rootCmd.executeWrapper() catch {};
}

fn helloRun(cmd: *cobra.Command, args: [][]const u8) void {
    _ = args;
    const app: *App = @ptrCast(@alignCast(cmd.iflags.?));
    std.debug.print("hello {s}\n", .{app.name});
}
```

## API Reference

### Command Struct

The `Command` struct is the core of cobra. Key fields:

| Field | Type | Description |
|-------|------|-------------|
| `use` | `[]const u8` | Usage line, e.g. `"serve [flags]`". First word = command name. |
| `short` | `[]const u8` | Short description shown in help |
| `long` | `[]const u8` | Long description shown in `--help` |
| `example` | `[]const u8` | Usage examples |
| `aliases` | `[]const []const u8` | Alternative command names |
| `suggest_for` | `[]const []const u8` | Names to suggest this command for on typos |
| `run` / `run_e` | `?RunFunc` / `?RunEFunc` | Main execution function |
| `pre_run` / `pre_run_e` | `?RunFunc` / `?RunEFunc` | Run before this command |
| `post_run` / `post_run_e` | `?RunFunc` / `?RunEFunc` | Run after this command |
| `persistent_pre_run[_e]` | `?RunFunc` / `?RunEFunc` | Run before ANY command in subtree |
| `persistent_post_run[_e]` | `?RunFunc` / `?RunEFunc` | Run after ANY command in subtree |
| `flags` | `*pflag.FlagSet` | Flag set for this command |
| `iflags` | `?*anyopaque` | Arbitrary pointer passed to run functions |
| `args_validator` | `PositionalArgs` | Positional argument validator |
| `version` | `[]const u8` | Version string (enables `--version` flag) |
| `deprecated` | `[]const u8` | Deprecation message |
| `hidden` | `bool` | Hide from help output |
| `group_id` | `[]const u8` | Group this command under in help |
| `valid_args` | `[]const []const u8` | Valid argument values |
| `arg_aliases` | `[]const []const u8` | Argument aliases |
| `completion_options` | `CompletionOptions` | Completion behavior config |
| `silence_errors` | `bool` | Suppress error output |
| `silence_usage` | `bool` | Suppress usage on errors |
| `disable_flag_parsing` | `bool` | Pass raw args to run function |
| `disable_suggestions` | `bool` | Disable "did you mean?" suggestions |
| `traverse_children` | `bool` | Run on all children, not just matched |
| `annotations` | `StringArrayHashMapUnmanaged` | Arbitrary metadata key-value pairs |

### Key Methods

| Method | Description |
|--------|-------------|
| `addCommand(gpa, cmds)` | Add subcommands |
| `executeWrapper()` | Parse flags and execute |
| `setArgs(args)` | Set arguments before execution |
| `deinit(gpa)` | Free all allocated resources |
| `root()` | Get root command |
| `hasSubCommands()` | Check for subcommands |
| `getCommands()` | Get sorted subcommand list |
| `name()` | Get command name |
| `hasParent()` | Check for parent command |

### Global Settings (`cobra` module)

| Variable | Default | Description |
|----------|---------|-------------|
| `enable_prefix_matching` | `false` | Enable prefix matching for commands |
| `enable_command_sorting` | `true` | Sort commands alphabetically in help |
| `enable_case_insensitive` | `false` | Case-insensitive command matching |
| `enable_traverse_run_hooks` | `false` | Run hooks on all parents, not just matched |
| `mousetrap_help_text` | `"..."` | Windows cmd.exe detection message |
| `mousetrap_display_duration_ns` | `5s` | How long to show mousetrap message |

### Positional Args Validators

| Constructor | Behavior |
|-------------|----------|
| `NoArgs()` | Reject if any args provided |
| `ArbitraryArgs()` | Accept any number of args |
| `ExactArgs(n)` | Require exactly `n` args |
| `MinimumNArgs(n)` | Require at least `n` args |
| `MaximumNArgs(n)` | Require at most `n` args |
| `RangeArgs(min, max)` | Require between `min` and `max` args |
| `ExactValidArgs(n)` | Exact count + from `valid_args` list |
| `OnlyValidArgs()` | All args must be in `valid_args` |
| `NoDuplicateArgs()` | Reject duplicate args |
| `LegacyArgs()` | Legacy subcommand behavior |
| `MatchAll(&.{...})` | Combine multiple validators |

### Shell Completion Directives

| Directive | Effect |
|-----------|--------|
| `ShellCompDirective.error_flag` | Completion error |
| `ShellCompDirective.no_space` | No space after completion |
| `ShellCompDirective.no_file_comp` | No file completion fallback |
| `ShellCompDirective.filter_file_ext` | Filter by file extension |
| `ShellCompDirective.filter_dirs` | Filter to directories only |
| `ShellCompDirective.keep_order` | Don't sort completions |

## Examples

### Command Tree

```zig
var serveCmd = cobra.Command{ .use = "serve", .short = "Start server" };

var httpCmd = cobra.Command{ .use = "http", .short = "HTTP server",  .run = serveHTTPFn };
var grpcCmd = cobra.Command{ .use = "grpc", .short = "gRPC server", .run = serveGRPCFn };

serveCmd.addCommand(gpa, &.{ &httpCmd, &grpcCmd });
// nests:  serve → http / grpc
```

### Run Hooks

```zig
var root = cobra.Command{
    .persistent_pre_run  = setupLogging,   // runs before ANY command in the tree
    .persistent_post_run = teardownLogging, // runs after ALL commands complete
    .pre_run             = initDatabase,    // runs before this command's own run
    .run                 = mainRun,
    .post_run            = cleanup,         // runs after this command's own run
};
```

### Arg Validation

```zig
var cmd = cobra.Command{
    .use            = "deploy NAME [ENV]",
    .run            = deployFn,
    .args_validator = cobra.RangeArgs(1, 2),
};
// Accepted:  deploy prod         (1 arg)
//            deploy prod staging (2 args)
// Rejected:  deploy              (0 args)
//            deploy a b c        (3 args)
```

### Command Groups

```zig
var adminCmd = cobra.Command{ .use = "admin", .short = "Admin commands", .group_id = "management" };
var listCmd  = cobra.Command{ .use = "list",  .short = "List resources",  .group_id = "read" };
var getCmd   = cobra.Command{ .use = "get",   .short = "Get a resource",  .group_id = "read" };

var lsmGroup = cobra.Group{ .id = "read",       .title = "Read Operations" };
var mgmtGroup = cobra.Group{ .id = "management", .title = "Management" };

rootCmd.addCommand(gpa, &.{ &adminCmd, &listCmd, &getCmd });
rootCmd.groups = &.{ &lsmGroup, &mgmtGroup };
```

### Custom Help & Error Output

```zig
var cmd = cobra.Command{
    .use            = "mycmd",
    .silence_usage  = false,
    .silence_errors = false,
};
// Redirect output to custom writer
cmd.setOutWriter(&myWriter);
cmd.setErrWriter(&myErrWriter);
// Custom help function
cmd.setHelpFunc(myHelpFn);
```

### Version Flag

```zig
var rootCmd = cobra.Command{
    .use     = "myapp",
    .version = "1.2.3",
};
// Running `myapp --version` prints: myapp version 1.2.3
```

### Hidden & Deprecated Commands

```zig
var oldCmd = cobra.Command{
    .use        = "old-feature",
    .short      = "Old feature",
    .deprecated = "use 'new-feature' instead",
};

var internalCmd = cobra.Command{
    .use    = "internal-tool",
    .short  = "Internal use only",
    .hidden = true,
};
```

### Flag Groups

```zig
const fg = @import("cobra").flag_groups_mod;

// These flags must be used together
fg.markFlagsRequiredTogether(&cmd, &.{ "username", "password" });

// At least one of these flags is required
fg.markFlagsOneRequired(&cmd, &.{ "file", "stdin" });

// These flags cannot be used together
fg.markFlagsMutuallyExclusive(&cmd, &.{ "verbose", "quiet" });
```

### Shell Completion

```zig
var cmd = cobra.Command{
    .use = "deploy",
    .valid_args_fn = cobra.FixedCompletions(
        &.{ "prod\tProduction environment", "staging\tStaging environment" },
        cobra.ShellCompDirective.no_file_comp,
    ),
};
```

## Demos

| Demo | Run | Scope |
|------|-----|-------|
| `demo/` | `zig build run-demo -- hello --name=Sisyphus` | Minimal hello-world |
| `dockr/` | `zig build run-dockr -- container run -d --name web -p 80:80 nginx` | Full Docker-style CLI with nested commands |

## Build

Requires **Zig 0.16.0**.

```bash
zig build                  # Build library
zig build test             # Run 83 tests
zig build run-demo -- hello --name=Sisyphus
zig build run-dockr -- container ls
zig fmt src/ dockr/ demo/  # Format code
```

## License

[Apache License 2.0](LICENSE)

This project is a port of [spf13/cobra](https://github.com/spf13/cobra) (Apache 2.0).
Uses [zig-pflag](https://github.com/rebornwwp/zig-pflag) (BSD 3-Clause).
