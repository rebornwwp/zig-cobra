# Contributing to zig-cobra

## License

By contributing to this project, you agree that your contributions will be
licensed under the Apache License 2.0 that covers this project.

## Development

```bash
zig build test           # Run 83 tests
zig build run-demo       # Run simple demo
zig build run-dockr      # Run Docker-style demo  
zig fmt src/ dockr/ demo/
```

## Code Style

- Zig 0.16.0 standard library conventions
- `zig fmt` for formatting
- All Command instances must have stack-lifetime; avoid heap-allocated Commands
