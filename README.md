# zig-cobra

A CLI framework for Zig 0.16.0, ported from Go's [spf13/cobra](https://github.com/spf13/cobra).

Built on [zig-pflag](https://github.com/your/zig-pflag) for POSIX/GNU-style flag parsing.

## Features

- Nested command tree (`addCommand`, aliases, groups)
- Flag parsing via zig‑pflag — all types, shorthand, `--help` auto‑generation
- Pre / Post run hooks — local + persistent with parent‑chain traversal
- Positional argument validators (`NoArgs`, `ExactArgs`, `MinimumNArgs`, `RangeArgs`, …)
- `--version` flag support
- Shell completion types, ActiveHelp
- Command deprecation, hidden commands, Levenshtein‑based suggestions

## Quick Start

```zig
const std = @import("std");
const cobra = @import("cobra");
const pflag = cobra.command_mod.pflag;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // ── Flag setup ──
    var flags = pflag.FlagSet.init(allocator, "hello");
    defer flags.deinit();
    var name: []const u8 = "world";
    flags.stringVarP(&name, "name", "n", "world", "your name") catch {};

    // ── Commands ──
    var helloCmd = cobra.Command{
        .use   = "hello",
        .short = "Say hello to someone",
        .long  = "Prints a greeting.\nDefaults to \"world\".",
        .run   = helloRun,
        .flags = &flags,
    };

    var rootCmd = cobra.Command{
        .use   = "myapp",
        .short = "A friendly CLI demo",
        .flags = &flags,
    };
    rootCmd.addCommand(allocator, &.{&helloCmd});
    defer rootCmd.deinit(allocator);

    // ── Parse args (skip program name) and execute ──
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    const effective = if (args.len > 1) args[1..] else &.{};
    rootCmd.setArgs(effective);
    rootCmd.executeWrapper() catch {};
}

fn helloRun(cmd: *cobra.Command, args: [][]const u8) void {
    _ = cmd;
    _ = args;
    // Flag values are already parsed — access them from shared state.
    std.debug.print("hello {s}\n", .{name});
}
```

## Command Tree Example

```zig
var appCmd       = cobra.Command{ .use = "app",        .short = "Application root" };
var serveCmd     = cobra.Command{ .use = "serve",      .short = "Start server",    .run = serveFn };
var serveHTTPCmd = cobra.Command{ .use = "http",       .short = "HTTP server",     .run = serveHTTPFn };
var serveGRPCCmd = cobra.Command{ .use = "grpc",       .short = "gRPC server",     .run = serveGRPCFn };

serveCmd.addCommand(allocator, &.{ &serveHTTPCmd, &serveGRPCCmd });
appCmd.addCommand(allocator, &.{ &serveCmd });
// nests:  app → serve → http / grpc
```

## Run Hooks

| Hook | Fires |
|------|-------|
| `pre_run` / `post_run` | Before / after this command's `run` |
| `persistent_pre_run` / `persistent_post_run` | On the whole path from root to this command |

```zig
var root = cobra.Command{
    .persistent_pre_run = setupLogging, // runs before any command
};
```

## Arg Validation

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

## Demos

| Demo | Run | Scope |
|------|-----|-------|
| `demo/` | `zig build run-demo -- hello --name=Sisyphus` | Minimal hello‑world |
| `dockr/` | `zig build run-dockr -- container run -d --name web -p 80:80 nginx` | Full Docker‑style CLI |

## Build

Requires **Zig 0.16.0**.

```bash
zig build              # Build library
zig build test         # Run 83 tests
zig build run-demo -- hello --name=Sisyphus
zig build run-dockr -- container run -d --name web -p 80:80 nginx
```

## License

MIT
