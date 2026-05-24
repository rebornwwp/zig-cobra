# zig-cobra

<div align="center">

[![Zig](https://img.shields.io/badge/Zig-0.16.0-orange?logo=zig&logoColor=white)](https://ziglang.org/)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Status](https://img.shields.io/badge/status-beta-yellow)](https://github.com/rebornwwp/zig-cobra)

</div>

面向 **Zig 0.16.0** 的 CLI 框架，从 Go 的 [spf13/cobra](https://github.com/spf13/cobra) 移植而来。

基于 [rebornwwp/zig-pflag](https://github.com/rebornwwp/zig-pflag) 实现 POSIX/GNU 风格的 flag 解析。

## 功能特性

- **嵌套命令树** — `addCommand`、别名、分组、拼写建议
- **Flag 解析** 基于 zig-pflag — 全部类型、短选项、`--help` 自动生成
- **运行钩子** — 前置/后置运行，本地 + 持久化，沿父命令链遍历
- **位置参数验证** — 10 种内置验证器（`NoArgs`、`ExactArgs`、`RangeArgs` 等）
- **`--version` flag** 支持
- **Shell 补全** — bash, zsh, fish, powershell，支持 `ShellCompDirective`
- **ActiveHelp** — 补全中的动态帮助文本
- **命令弃用**、隐藏命令、**基于 Levenshtein 的拼写建议**
- **Flag 分组** — 互斥、必须同时使用、至少一个必填
- **可定制** — 帮助模板、用法函数、错误函数、I/O 读写器

## 安装

将以下内容添加到你的 `build.zig.zon`：

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

然后在你的 `build.zig` 中：

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

## 快速开始

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

    // ── Flag 设置 ──
    var flags = pflag.FlagSet.init(gpa, "hello");
    defer flags.deinit();
    flags.stringVarP(&app.name, "name", "n", "world", "your name") catch {};

    // ── 命令 ──
    var helloCmd = cobra.Command{
        .use   = "hello",
        .short = "向某人问好",
        .long  = "打印问候语。默认问候 \"world\"。",
        .run   = helloRun,
        .flags = &flags,
    };
    helloCmd.iflags = @ptrCast(@alignCast(&app));

    var rootCmd = cobra.Command{
        .use   = "myapp",
        .short = "一个友好的 CLI 演示",
        .flags = &flags,
    };
    rootCmd.addCommand(gpa, &.{&helloCmd});
    defer rootCmd.deinit(gpa);

    // ── 解析参数并执行 ──
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

## API 参考

### Command 结构体

`Command` 是 cobra 的核心结构体。主要字段：

| 字段 | 类型 | 说明 |
|-------|------|------|
| `use` | `[]const u8` | 用法行，如 `"serve [flags]"`。第一个单词即命令名称 |
| `short` | `[]const u8` | 简短描述（显示在 help 中） |
| `long` | `[]const u8` | 长描述（显示在 `--help` 中） |
| `example` | `[]const u8` | 使用示例 |
| `aliases` | `[]const []const u8` | 命令别名 |
| `suggest_for` | `[]const []const u8` | 输入这些名称时建议当前命令 |
| `run` / `run_e` | `?RunFunc` / `?RunEFunc` | 主执行函数 |
| `pre_run` / `pre_run_e` | `?RunFunc` / `?RunEFunc` | 在本命令 run 之前执行 |
| `post_run` / `post_run_e` | `?RunFunc` / `?RunEFunc` | 在本命令 run 之后执行 |
| `persistent_pre_run[_e]` | `?RunFunc` / `?RunEFunc` | 在子树中所有命令 run 之前执行 |
| `persistent_post_run[_e]` | `?RunFunc` / `?RunEFunc` | 在子树中所有命令 run 之后执行 |
| `flags` | `*pflag.FlagSet` | 本命令的 flag 集合 |
| `iflags` | `?*anyopaque` | 传递给 run 函数的任意指针 |
| `args_validator` | `PositionalArgs` | 位置参数验证器 |
| `version` | `[]const u8` | 版本号（设置后自动启用 `--version` flag） |
| `deprecated` | `[]const u8` | 弃用信息 |
| `hidden` | `bool` | 在 help 中隐藏此命令 |
| `group_id` | `[]const u8` | 命令分组 ID（help 中归类显示） |
| `valid_args` | `[]const []const u8` | 有效参数值列表 |
| `arg_aliases` | `[]const []const u8` | 参数别名 |
| `completion_options` | `CompletionOptions` | 补全行为配置 |
| `silence_errors` | `bool` | 静默错误输出 |
| `silence_usage` | `bool` | 错误时静默用法输出 |
| `disable_flag_parsing` | `bool` | 原始参数直接传给 run 函数 |
| `disable_suggestions` | `bool` | 禁用 "你是想输入?" 建议 |
| `traverse_children` | `bool` | 在所有子命令上执行，而非仅匹配的命令 |
| `annotations` | `StringArrayHashMapUnmanaged` | 任意键值对元数据 |

### 关键方法

| 方法 | 说明 |
|--------|------|
| `addCommand(gpa, cmds)` | 添加子命令 |
| `executeWrapper()` | 解析 flag 并执行 |
| `setArgs(args)` | 在 execute 前设置参数 |
| `deinit(gpa)` | 释放所有已分配资源 |
| `root()` | 获取根命令 |
| `hasSubCommands()` | 检查是否有子命令 |
| `getCommands()` | 获取排序后的子命令列表 |
| `name()` | 获取命令名称 |
| `hasParent()` | 检查是否有父命令 |

### 全局配置（`cobra` 模块）

| 变量 | 默认值 | 说明 |
|----------|---------|------|
| `enable_prefix_matching` | `false` | 启用命令前缀匹配 |
| `enable_command_sorting` | `true` | 在 help 中按字母排序子命令 |
| `enable_case_insensitive` | `false` | 大小写不敏感的命令匹配 |
| `enable_traverse_run_hooks` | `false` | 在父命令链上执行运行钩子 |
| `mousetrap_help_text` | `"..."` | Windows cmd.exe 检测提示 |
| `mousetrap_display_duration_ns` | `5s` | mousetrap 提示显示时长 |

### 位置参数验证器

| 构造函数 | 行为 |
|-------------|------|
| `NoArgs()` | 有参数时拒绝 |
| `ArbitraryArgs()` | 接受任意数量的参数 |
| `ExactArgs(n)` | 要求恰好 `n` 个参数 |
| `MinimumNArgs(n)` | 要求至少 `n` 个参数 |
| `MaximumNArgs(n)` | 要求最多 `n` 个参数 |
| `RangeArgs(min, max)` | 要求参数数量在 `[min, max]` 内 |
| `ExactValidArgs(n)` | 恰好 n 个参数 + 必须在 `valid_args` 中 |
| `OnlyValidArgs()` | 所有参数必须在 `valid_args` 中 |
| `NoDuplicateArgs()` | 拒绝重复参数 |
| `LegacyArgs()` | 传统子命令行为 |
| `MatchAll(&.{...})` | 组合多个验证器 |

### Shell 补全指令

| 指令 | 效果 |
|-----------|------|
| `ShellCompDirective.error_flag` | 补全出错 |
| `ShellCompDirective.no_space` | 补全后不追加空格 |
| `ShellCompDirective.no_file_comp` | 不回退到文件补全 |
| `ShellCompDirective.filter_file_ext` | 按文件扩展名过滤 |
| `ShellCompDirective.filter_dirs` | 仅过滤目录 |
| `ShellCompDirective.keep_order` | 保持顺序，不排序 |

## 示例

### 命令树

```zig
var serveCmd = cobra.Command{ .use = "serve", .short = "启动服务器" };

var httpCmd = cobra.Command{ .use = "http", .short = "HTTP 服务器",  .run = serveHTTPFn };
var grpcCmd = cobra.Command{ .use = "grpc", .short = "gRPC 服务器", .run = serveGRPCFn };

serveCmd.addCommand(gpa, &.{ &httpCmd, &grpcCmd });
// 嵌套结构:  serve → http / grpc
```

### 运行钩子

```zig
var root = cobra.Command{
    .persistent_pre_run  = setupLogging,    // 在命令树中所有命令之前执行
    .persistent_post_run = teardownLogging, // 在所有命令完成后执行
    .pre_run             = initDatabase,    // 在本命令 run 之前执行
    .run                 = mainRun,
    .post_run            = cleanup,         // 在本命令 run 之后执行
};
```

### 参数验证

```zig
var cmd = cobra.Command{
    .use            = "deploy NAME [ENV]",
    .run            = deployFn,
    .args_validator = cobra.RangeArgs(1, 2),
};
// 合法:    deploy prod         (1 个参数)
//           deploy prod staging (2 个参数)
// 不合法:  deploy              (0 个参数)
//           deploy a b c       (3 个参数)
```

### 命令分组

```zig
var adminCmd = cobra.Command{ .use = "admin", .short = "管理命令", .group_id = "management" };
var listCmd  = cobra.Command{ .use = "list",  .short = "列出资源",  .group_id = "read" };
var getCmd   = cobra.Command{ .use = "get",   .short = "获取资源",  .group_id = "read" };

var lsmGroup = cobra.Group{ .id = "read",       .title = "读取操作" };
var mgmtGroup = cobra.Group{ .id = "management", .title = "管理" };

rootCmd.addCommand(gpa, &.{ &adminCmd, &listCmd, &getCmd });
rootCmd.groups = &.{ &lsmGroup, &mgmtGroup };
```

### 自定义帮助和错误输出

```zig
var cmd = cobra.Command{
    .use            = "mycmd",
    .silence_usage  = false,
    .silence_errors = false,
};
// 将输出重定向到自定义 writer
cmd.setOutWriter(&myWriter);
cmd.setErrWriter(&myErrWriter);
// 自定义帮助函数
cmd.setHelpFunc(myHelpFn);
```

### 版本 Flag

```zig
var rootCmd = cobra.Command{
    .use     = "myapp",
    .version = "1.2.3",
};
// 运行 `myapp --version` 输出: myapp version 1.2.3
```

### 隐藏和弃用命令

```zig
var oldCmd = cobra.Command{
    .use        = "old-feature",
    .short      = "旧功能",
    .deprecated = "请使用 'new-feature' 替代",
};

var internalCmd = cobra.Command{
    .use    = "internal-tool",
    .short  = "内部使用",
    .hidden = true,
};
```

### Flag 分组

```zig
const fg = @import("cobra").flag_groups_mod;

// 这些 flag 必须同时使用
fg.markFlagsRequiredTogether(&cmd, &.{ "username", "password" });

// 这些 flag 中至少有一个必填
fg.markFlagsOneRequired(&cmd, &.{ "file", "stdin" });

// 这些 flag 不能同时使用
fg.markFlagsMutuallyExclusive(&cmd, &.{ "verbose", "quiet" });
```

### Shell 补全

```zig
var cmd = cobra.Command{
    .use = "deploy",
    .valid_args_fn = cobra.FixedCompletions(
        &.{ "prod\t生产环境", "staging\t预发布环境" },
        cobra.ShellCompDirective.no_file_comp,
    ),
};
```

## 演示

| 演示 | 运行命令 | 说明 |
|------|-----|-------|
| `demo/` | `zig build run-demo -- hello --name=Sisyphus` | 最小 helloworld |
| `dockr/` | `zig build run-dockr -- container run -d --name web -p 80:80 nginx` | 完整 Docker 风格 CLI，含嵌套命令 |

## 构建

需要 **Zig 0.16.0**。

```bash
zig build                  # 构建库
zig build test             # 运行 83 个测试
zig build run-demo -- hello --name=Sisyphus
zig build run-dockr -- container ls
zig fmt src/ dockr/ demo/  # 格式化代码
```

## 许可证

[Apache License 2.0](LICENSE)

本项目是 [spf13/cobra](https://github.com/spf13/cobra)（Apache 2.0）的移植版本。
使用了 [zig-pflag](https://github.com/rebornwwp/zig-pflag)（BSD 3-Clause）。
