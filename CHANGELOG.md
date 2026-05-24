# Changelog

All notable changes to zig-cobra will be documented in this file.

## [0.1.0] - 2026-05-24

### Added
- Core `Command` struct with 60+ fields matching Go cobra's API
- Nested command tree with `addCommand`, aliases, and parent-child traversal
- Flag parsing integration via [zig-pflag](https://github.com/rebornwwp/zig-pflag)
- Run hooks: `pre_run`, `post_run`, `persistent_pre_run`, `persistent_post_run` (with `_e` variants)
- 10 positional argument validators: `NoArgs`, `ExactArgs`, `MinimumNArgs`, `MaximumNArgs`, `RangeArgs`, `ArbitraryArgs`, `OnlyValidArgs`, `NoDuplicateArgs`, `LegacyArgs`, `ExactValidArgs`
- `MatchAll` combinator for chaining multiple validators
- `--version` flag support via `Command.version` field
- Automatic `--help` flag generation
- Shell completion system with `ShellCompDirective` (error, nospace, nofilecomp, filterfile, filterdirs, keeporder)
- `CompletionOptions` for configuring completion behavior
- `FixedCompletions`, `NoFileCompletions` for static completions
- ActiveHelp support: `appendActiveHelp`, `getActiveHelpConfig`
- Command deprecation with `deprecated` field
- Hidden commands with `hidden` field
- Levenshtein-based "did you mean?" suggestions on typos
- Global settings: `enable_prefix_matching`, `enable_command_sorting`, `enable_case_insensitive`, `enable_traverse_run_hooks`
- Windows mousetrap detection
- Flag error whitelist (`FParseErrWhitelist`)
- Command groups for help organization (`Group`, `group_id`)
- Template functions (`TmplFunc`)
- Customizable I/O: `setOutWriter`, `setErrWriter`, `setInReader`
- Customizable help/usage/error functions
- Flag groups: `markFlagsRequiredTogether`, `markFlagsOneRequired`, `markFlagsMutuallyExclusive`
- Shell completion helpers: `markFlagRequired`, `markFlagFilename`, `markFlagDirname`
- Utility functions: `levenshteinDistance`, `stringInSlice`, `trimRightSpace`, `rpad`
- Initializer/finalizer support: `onInitialize`, `onFinalize`
- 83 tests covering command tree, args validation, completions, active help, flag groups
- Hello-world demo (`demo/`)
- Docker-style CLI demo (`dockr/`) with container, image, volume subcommands
- Migration guide from Go cobra (`docs/migration-guide.md`)
- Apache 2.0 license with NOTICE file
