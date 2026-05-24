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

// Shared state: place flag targets where the run function can reach them.
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
        .long  = "Prints a greeting.  Defaults to \"world\".",
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

## Command Tree

```zig
// Parent command
var serveCmd = cobra.Command{ .use = "serve", .short = "Start server" };

// Leaf commands — created outside parent scope so pointers stay alive
var httpCmd  = cobra.Command{ .use = "http",  .short = "HTTP server",  .run = serveHTTPFn };
var grpcCmd  = cobra.Command{ .use = "grpc",  .short = "gRPC server",  .run = serveGRPCFn };

serveCmd.addCommand(gpa, &.{ &httpCmd, &grpcCmd });
// nests:  serve → http / grpc
```

## Run Hooks

```zig
var root = cobra.Command{
    .persistent_pre_run = setupLogging,   // runs before ANY command in the tree
    .pre_run            = initDatabase,   // runs before this command's own run
    .post_run           = cleanup,        // runs after  this command's own run
};
// persistent_post_run at root runs after all commands complete
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

Apache License 2.0
