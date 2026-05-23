# zig-cobra

A CLI framework for Zig, ported from Go's [spf13/cobra](https://github.com/spf13/cobra).

Built on [zig-pflag](https://github.com/your/zig-pflag) for POSIX/GNU-style flag parsing.

## Features

- Nested command tree with addCommand, aliases, groups
- Flag parsing via zig-pflag (bool, int, uint, float, string, count, duration, slices, maps)
- Auto-generated --help / -h at every command level
- Pre/Post run hooks (local + persistent with parent chain traversal)
- Positional argument validators (NoArgs, ExactArgs, MinimumNArgs, RangeArgs, etc.)
- Shell completion types, ActiveHelp support
- Command deprecation, hidden commands, suggestions (Levenshtein distance)

## Usage

```zig
const cobra = @import("cobra");
const pflag = cobra.command_mod.pflag;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    var flags = pflag.FlagSet.init(alloc, "myapp");
    defer flags.deinit();
    var name: []const u8 = "world";
    flags.stringVarP(&name, "name", "n", "world", "your name") catch {};

    var helloCmd = cobra.Command{
        .use = "hello",
        .short = "Say hello",
        .run = helloRun,
        .flags = &flags,
    };

    var rootCmd = cobra.Command{
        .use = "myapp",
        .short = "A friendly CLI",
        .flags = &flags,
    };
    rootCmd.addCommand(alloc, &.{&helloCmd});
    defer rootCmd.deinit(alloc);

    rootCmd.setArgs(args);
    rootCmd.executeWrapper() catch {};
}

fn helloRun(cmd: *cobra.Command, args: [][]const u8) void {
    // flags already parsed by execute(), read values from shared state
    std.debug.print("hello {s}\n", .{name});
}
```

## Demos

- `demo/` — Simple hello-world CLI
- `dockr/` — Full Docker-style CLI (3-tier command tree, 12 commands, persistent hooks)

## Build

Requires Zig 0.16.0.

```bash
zig build              # build library
zig build test         # run 83 tests
zig build run-demo -- hello --name=Sisyphus
zig build run-dockr -- container run -d --name web -p 80:80 nginx
```

## License

MIT
