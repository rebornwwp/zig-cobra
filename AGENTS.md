# AGENTS.md - zig-cobra

Zig 0.17.0 CLI framework ported from Go's spf13/cobra. Depends on zig-pflag for flag parsing.

## Commands

```bash
zig build                    # Build library
zig build test               # Run all tests (139 tests)
zig build run-demo -- --help # Run simple demo
zig build run-dockr -- --help # Run Docker-style demo
zig fmt --check src/ examples/ build.zig  # Check formatting
zig fmt src/ examples/       # Format code
```

## Dependencies

Install with `zig fetch --save`:
```bash
zig fetch --save git+https://github.com/rebornwwp/zig-pflag.git
```

Do NOT use `.path` or tarball URLs. Only `git+https://` format works correctly with Zig 0.17.0's module system.

## Architecture

- `src/cobra.zig` - Main entry point, re-exports all public APIs
- `src/command.zig` - Command struct and core logic
- `src/args.zig` - Positional argument validators (NoArgs, ExactArgs, etc.)
- `src/completions.zig` - Shell completion (bash, zsh, fish, powershell)
- `src/flag_groups.zig` - Flag grouping (mutually exclusive, required together)
- `src/completions_templates.zig` - Shell completion script templates (verbatim port from spf13/cobra)
- `src/active_help.zig` - Dynamic help text in completions
- `src/doc/` - Documentation generators (markdown, man, yaml, rest)
- `examples/` - Demo applications (demo.zig, dockr/)
- `*_test.zig` - Test files co-located with source

## Critical Constraints

- **Zig 0.17.0 only** - Uses new build system (configurer/maker separation), `@backingInt`/`@fromBackingInt`, `SafeAllocator`
- **Stack-lifetime Commands** - User Command instances must not be heap-allocated (exception: library-internal `help`/`completion`/`__complete` commands are heap-allocated via gpa and freed in `deinit(gpa)`)
- **Test pattern** - Tests use `std.testing.allocator`, not custom allocators
- **Module exposure** - Library uses `b.addModule()` in build.zig, dependencies access via `dep.module()`

## CI Checks

Before committing:
1. `zig build test --summary all` - All tests pass
2. `zig fmt --check src/ examples/ build.zig` - Formatting correct
3. `zig build` - Library builds cleanly

## Git Conventions

- Author: `reborn <rebornwwp@gmail.com>`
- Commit style: conventional commits (feat:, fix:, docs:, chore:, style:, refactor:)
- Branch: main (default)
- CI runs on push/PR to main
