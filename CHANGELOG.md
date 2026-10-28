# Changelog

All notable changes to zig-cobra will be documented in this file.

## [0.3.0] - 2026-10-28

Reference baseline for this release: spf13/cobra v1.10.2 (vendored under `cobra/`).

### Added
- Go-parity execution flow in `execute()`: parse flags first, then initializers →
  ValidateArgs → nearest PersistentPreRun → PreRun → required-flag & flag-group
  validation → Run → PostRun → nearest PersistentPostRun; post hooks are skipped on error
- Real `find()`/`traverse()`: flag-aware argument stripping, unknown-command errors,
  working "Did you mean this?" suggestions, prefix matching and case-insensitive matching
  now actually take effect
- `legacyArgs` as the default positional validator (was `arbitraryArgs`)
- Automatic `help` subcommand (`initDefaultHelpCmd`) and `completion` command with
  bash/zsh/fish/powershell children plus `--no-descriptions` flags
- Hidden `__complete` command: full dynamic completion protocol (flag name/value
  completion, ValidArgs/ValidArgsFunction, directives, `:<int>` wire format)
- Shell completion script generators ported verbatim from cobra templates
  (`src/completions_templates.zig`): `genBashCompletionV2`, `genZshCompletion`,
  `genFishCompletion`, `genPowerShellCompletion`
- Flag groups implemented via cobra's annotation scheme with byte-identical error
  messages: `markFlagsMutuallyExclusive`, `markFlagsOneRequired`, `markFlagsRequiredTogether`,
  `enforceFlagGroupsForCompletion`
- `markFlagRequired` & friends implemented (`shell_completions.zig`); required-flag
  validation wired into `execute()` with Go-style error messages
- `registerFlagCompletionFunc` for flag value completions
- Persistent flag inheritance that actually works: ancestor persistent flags are merged
  (borrowed-pointer scheme, no double frees) for parsing and help rendering
  (`Flags:` / `Global Flags:` sections)
- Real doc generators: markdown (+tree), man pages (+tree), YAML (+tree), ReST (+tree)
- ActiveHelp: `getActiveHelpConfig` (COBRA_ACTIVE_HELP / <PROGRAM>_ACTIVE_HELP),
  `configEnvVar` sanitizing, `cobra.setEnviron()` for env-driven config
- `Command.user_data` field for application state (replaces the `iflags` pointer hack)
- `behavior_test.zig`: 17 behavior tests (hooks, inheritance, completion protocol, docs)
- CI smoke tests for both example apps (`scripts/smoke.sh`)

### Changed (breaking)
- `executeWrapper(gpa)` / `execute(io, gpa, args)` / `find(gpa, args)` /
  `parseFlags(io, gpa, args)` and lazy flag accessors (`flags(gpa)`,
  `persistentFlags(gpa)`, `localFlags(gpa)`, ...) now take an allocator
- `iflags` field restored to Go semantics (inherited flags view); raw nullable
  accessors renamed to `flagsPtr()` / `persistentFlagsPtr()`
- `errOrStderr(io)` / `outOrStdout(io)` / `inOrStdin(io)` take io and fall back to
  real stdout/stderr/stdin instead of returning undefined
- `printErr` family writes to stderr (was silently stdout)
- `CompletionFunc` is a `{ ctx, call }` struct with `.invoke()`;
  `completionWithDesc(gpa, choice, desc)` returns the Go `"choice\tdesc"` format
- `usageString(gpa)` renders the full usage block (was returning the `use` field);
  `calledAs()` returns "" when unset (Go parity)
- `argsLenAtDash()` returns `isize` (-1 when absent) from the flag parser
- `markFlags*` / `markFlag*` helpers take `gpa` and return errors
- `updateParentsPflags(gpa, rebuild)`; hook callbacks receive the executing command
  and flag-stripped args (Go parity)

### Fixed
- Dangling pointer: `--version` flag was bound to a stack temporary
- Undefined behavior: `validateRequiredFlags` reinterpreted an ArrayList pointer as an
  allocator (and was never called; `visitAll` arguments were also swapped)
- Subcommands silently sharing the parent FlagSet (`initDefaultHelpFlag` aliasing hack);
  FlagSets are now lazily owned per command
- `printHelp` double-written output, 4KB truncation, and writer bypass; help/usage are
  now rendered streaming to `errOrStderr` following cobra's default templates
- `commandPath()` had an empty `if` body (always returned the leaf name)
- Examples swallowed all errors and always exited 0; unknown commands now exit 1
- pflag's `exit_on_error` default killed the process on parse errors; cobra now forces
  `continue_on_error` on every FlagSet it parses
- `fixedCompletions` dropped its arguments and always returned an empty list
- `onlyValidArgs` used prefix matching; now exact match (Go parity)
- Help alignment: `__completeNoDesc` is an alias of `__complete` (Go parity), which
  also fixes `namePadding` distortion
- `removeCommand` O(n) rebuild replaced with in-place filtering

## [0.2.0] - 2026-10-21

### Changed
- Port from Zig 0.16.0 to Zig 0.17.0
- `build.zig`: `b.args` → `addPassthruArgs()` (Zig 0.17 build system breaking change)
- `build.zig.zon`: `minimum_zig_version` updated to `0.17.0`

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
