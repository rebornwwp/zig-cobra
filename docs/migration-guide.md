# Go Cobra → Zig 0.16.0 迁移实战指南

> 本文档记录了如何将 [spf13/cobra](https://github.com/spf13/cobra)（Go 语言最流行的 CLI 框架）逐文件、逐函数、逐结构体迁移到 Zig 0.16.0 的完整过程。

## 目录

- [1. 整体策略](#1-整体策略)
- [2. 阶段 0：规划先行](#2-阶段-0规划先行)
- [3. 阶段 1：搭建骨架](#3-阶段-1搭建骨架)
- [4. 阶段 2：逐轮修复编译错误](#4-阶段-2逐轮修复编译错误)
- [5. 关键映射决策](#5-关键映射决策)
- [6. Zig 0.16.0 陷坑大全](#6-zig-0160-陷坑大全)
- [7. 测试策略](#7-测试策略)
- [8. 经验总结](#8-经验总结)

---

## 1. 整体策略

### 核心原则：**小步迭代、编译驱动**

```
写骨架 → 编译 → 修复错误 → 写测试 → 编译 → 测试 → 修复 → 重复
```

**不要一次性写完所有代码再编译。** 先写能编译的最小骨架（所有函数返回空 / `unreachable`），编译通过后再逐步填充。

### 执行顺序

先编译通过，再补测试，再补实现：

```
Step 1: build.zig + build.zig.zon     ← 先让构建系统工作
Step 2: 所有 .zig 文件 stub           ← 骨架编译通过
Step 3: 核心模块逐步填充               ← 从基础工具函数开始
Step 4: 测试逐个添加                  ← 每个模块写完立即写测试
Step 5: 全量回归                      ← zig build test
```

### 迁移粒度

**一一对应**：
- Go 的每个 `func` → Zig 的 `pub fn`
- Go 的每个 `struct` → Zig 的 `struct`
- Go 的每个 `type X = Y` → Zig 的 `pub const X = Y`
- Go 的每个 `_test.go` → Zig 的 `_test.zig`

---

## 2. 阶段 0：规划先行

### 2.1 先完整阅读 Go 源码

花费 30+ 次 `read` 调用，完整阅读了 cobra 的全部 16 个 Go 源文件（约 4500 行）和 13 个测试文件（279 个测试用例）。

**关键收获**：
- 理解了 `Command` 核心结构体的 40+ 字段
- 发现了 80+ 个方法
- 识别了依赖关系：`command.go` ← `args.go` ← `completions.go`
- 找到了 Go 惯用法对应的 Zig 方案

### 2.2 Go → Zig 类型映射表

| Go 模式 | Zig 等价 | 说明 |
|---------|---------|------|
| `string` | `[]const u8` | Zig 无内置 string，用字节切片 |
| `[]string` | `[][]const u8` | 字符串切片 |
| `[]*Command` | `[]*Command` | 指针切片 |
| `map[string]string` | `std.StringArrayHashMapUnmanaged(...)` | HashMap |
| `type X func(...)` | `*const fn (...) ...` | 函数指针 |
| `func f(n int) Fn` (闭包) | `union(enum) { exact_n: usize, ... }` | 捕获值用 tagged union |
| `context.Context` | `*anyopaque` | 任意指针 |
| `io.Writer` | `*std.Io.Writer` | Zig 0.16 的 Io.Writer |
| `interface{}` | `anytype` | 编译时泛型 |

### 2.3 文件结构规划

```
zig-cobra/
├── build.zig            ← 构建配置
├── build.zig.zon        ← 包定义
└── src/
    ├── cobra.zig        ← 全局配置 (对应 cobra/cobra.go)
    ├── command.zig      ← 核心 Command (对应 cobra/command.go)
    ├── args.zig         ← 参数验证 (对应 cobra/args.go)
    ├── completions.zig  ← 补全系统 (对应 cobra/completions.go)
    ├── ... (其他模块)
    ├── test_helper.zig  ← 共享测试工具
    └── doc/             ← 文档生成 (对应 cobra/doc/)
```

---

## 3. 阶段 1：搭建骨架

### 3.1 build.zig (Zig 0.16.0 专用)

Zig 0.16.0 的构建 API 与 0.15 完全不同：

```zig
// ❌ 0.15 写法 - 已废弃
const lib = b.addStaticLibrary(.{ .root_source_file = b.path("src/main.zig") });
const tests = b.addTest(.{ .root_source_file = b.path("src/test.zig") });

// ✅ 0.16 写法 - 必须先 createModule
const lib_mod = b.createModule(.{
    .root_source_file = b.path("src/cobra.zig"),
    .target = target,
    .optimize = optimize,
});
const lib = b.addLibrary(.{
    .name = "cobra",
    .root_module = lib_mod,
});
```

### 3.2 build.zig.zon

0.16 必须包含 `fingerprint` 和 `paths` 字段：

```zig
.{
    .name = .cobra,                    // enum literal, 不能是字符串
    .fingerprint = 0x171a4821ec9cd848, // zig build 提示的值
    .version = "0.1.0",
    .minimum_zig_version = "0.16.0",
    .paths = .{ "build.zig", "src" },
}
```

### 3.3 骨架策略

先写能让所有模块 import 链通的 stub，再逐步填充：

```zig
// 第一阶段：stub（编译通过即可）
pub const Command = struct {};
pub fn hasSubCommands(_: *const Command) bool { return false; }

// 第二阶段：补参数类型
pub const Command = struct {
    use: []const u8,
    aliases: []const []const u8 = &.{},
    // ...
};
pub fn hasSubCommands(self: *const Command) bool {
    return self.commands.items.len > 0;
}
```

---

## 4. 阶段 2：逐轮修复编译错误

整个迁移经历了 **20+ 轮编译→修复→编译** 的循环。以下是每轮遇到的关键问题和修复方法。

### 4.1 第 1-3 轮：构建系统

| 错误 | 原因 | 修复 |
|------|------|------|
| `invalid fingerprint` | 自编值不合法 | 用 zig build 提示的值 |
| `missing top-level 'paths'` | 0.16 新要求 | 添加 `.paths` 字段 |
| `no field named 'addStaticLibrary'` | 0.16 改名 | 改用 `addLibrary` |
| `no field named 'root_source_file'` | 0.16 新 API | 改用 `root_module` + `createModule` |

### 4.2 第 4-6 轮：类型初始化

| 错误 | 原因 | 修复 |
|------|------|------|
| `missing struct field: items` | `ArrayListUnmanaged` 不能用 `{}` 初始化 | 用 `.empty` |
| `missing struct field: capacity` | 同上 | 同上 |
| `struct 'array_list' has no member 'init'` | 0.16 移除 `.init(alloc)` | 用 `.initCapacity(alloc, n)` |

### 4.3 第 7-10 轮：方法定义位置

**这是最关键的发现。**

Go 的 `func (c *Command) Execute()` 方法定义在 struct 外部：

```go
// Go - 方法可以在结构体外
type Command struct { ... }
func (c *Command) Execute() error { ... }
```

但 Zig 中，**方法必须定义在 struct 内部**才能用 `.method()` 语法调用：

```zig
// ❌ 错误 - 定义在外面，不能用 cmd.execute()
pub const Command = struct { ... };
pub fn execute(self: *Command) void { ... }  // 外部函数

// ✅ 正确 - 定义在里面
pub const Command = struct {
    // 字段...
    pub fn execute(self: *Command) void { ... }  // 方法
};
```

**教训**：第一次写 command.zig 时把所有方法写在 struct 外部，导致了 **50+ 处** `no field or member function` 错误。重写后全过。

### 4.4 第 11-13 轮：字段/方法同名冲突

```zig
pub const Command = struct {
    commands: ArrayList = .empty,     // 字段
    pub fn commands(self: *Command)   // ❌ 方法和字段同名！
              []*Command { ... }
};
```

**修复**：将方法改名为 `getCommands()`、`getParent()`。

### 4.5 第 14-16 轮：I/O API 变化

Zig 0.16.0 I/O API 全部变了：

```zig
// ❌ 0.15 写法
std.io.getStdOut().writer()
writer.print("hello {}", .{42});

// ✅ 0.16 写法
std.Io.File.stdout().writer(&.{})  // 需要传 buffer
// 或者直接用 fixed writer
var buf: [256]u8 = undefined;
var writer = std.Io.Writer.fixed(&buf);
```

### 4.6 第 17-20 轮：ArrayList API 变化

0.16.0 所有 ArrayList 方法都需要显式传 allocator：

```zig
// ❌ 0.15 写法
var list = std.ArrayList(u8).init(alloc);
list.append('x') catch {};
list.toOwnedSlice() catch {};

// ✅ 0.16 写法
var list = std.ArrayList(u8).initCapacity(alloc, 256) catch unreachable;
list.append(alloc, 'x') catch unreachable;
list.toOwnedSlice(alloc) catch unreachable;
defer list.deinit(alloc);  // deinit 也要传 allocator
```

### 4.7 第 21+ 轮：测试内存泄漏

测试用 `std.testing.allocator` 默认启用 leak 检测。所有 `addCommand` 分配的内存必须通过 `defer cmd.deinit(gpa)` 释放。

```zig
test "add command" {
    var rootCmd = Command{ .use = "root" };
    var child = Command{ .use = "child" };
    rootCmd.addCommand(std.testing.allocator, &.{&child});
    defer rootCmd.deinit(std.testing.allocator);  // ← 必须！
    // ...
}
```

---

## 5. 关键映射决策

### 5.1 PositionalArgs：从函数类型到 tagged union

Go 中 `PositionalArgs` 是函数类型，工厂函数返回捕获了参数的闭包：

```go
type PositionalArgs func(cmd *Command, args []string) error

func ExactArgs(n int) PositionalArgs {
    return func(cmd *Command, args []string) error {
        if len(args) != n { return fmt.Errorf(...) }
        return nil
    }
}
```

Zig 不支持运行时闭包。**解决方案**：用 tagged union 替代。

```zig
pub const PositionalArgs = union(enum) {
    simple: *const fn (cmd: *Command, args: []const []const u8) anyerror!void,
    exact_n: usize,       // 捕获 ExactArgs(n) 的 n
    minimum_n: usize,     // 捕获 MinimumNArgs(n) 的 n
    maximum_n: usize,
    range: struct { min: usize, max: usize },
    match_all: []const PositionalArgs,

    pub fn validate(self: PositionalArgs, cmd: *Command, args: []const []const u8) anyerror!void {
        return switch (self) {
            .simple => |fn_ptr| fn_ptr(cmd, args),
            .exact_n => |n| { if (args.len != n) return error.ArgsCount; },
            .minimum_n => |n| { if (args.len < n) return error.ArgsCount; },
            // ...
        };
    }
};
```

**优势**：无堆分配、无闭包捕获开销、类型安全。

### 5.2 ShellCompDirective：从 iota 到 packed struct

Go 用 `iota` 定义位掩码：

```go
type ShellCompDirective int
const (
    ShellCompDirectiveError       ShellCompDirective = 1 << iota
    ShellCompDirectiveNoSpace
    ShellCompDirectiveNoFileComp
    // ...
)
```

Zig 用 `packed struct`：

```zig
pub const ShellCompDirective = packed struct(u8) {
    e: bool = false,
    nospace: bool = false,
    nofilecomp: bool = false,
    filterfile: bool = false,
    filterdirs: bool = false,
    keeporder: bool = false,
    _: u2 = 0,
};
```

### 5.3 全局可变状态

Go cobra 大量使用全局变量：

```go
var EnablePrefixMatching = false
var EnableCommandSorting = true
```

Zig 中直接用 `pub var` 保持对应：

```zig
pub var enable_prefix_matching: bool = false;
pub var enable_command_sorting: bool = true;
```

### 5.4 错误处理：从 string error 到 error enum

Go 用 `fmt.Errorf("...")` 返回带格式的错误字符串。Zig 中选择了轻量方案——先用 `error.ArgsCount` 等简单枚举值，完整迁移可以再实现带消息的错误类型。

---

## 6. Zig 0.16.0 陷坑大全

### 6.1 `ArrayList.init` 已移除

```zig
// ❌ 编译错误
var list = std.ArrayList(u8).init(allocator);

// ✅ 0.16
var list = try std.ArrayList(u8).initCapacity(allocator, 256);
```

### 6.2 `append` / `toOwnedSlice` 需要 allocator

```zig
// ❌ 编译错误
try list.append(item);
return try list.toOwnedSlice();

// ✅ 0.16
try list.append(allocator, item);
return try list.toOwnedSlice(allocator);
```

### 6.3 `deinit` 需要 allocator

```zig
// ❌ 编译错误
defer list.deinit();

// ✅ 0.16
defer list.deinit(allocator);
```

### 6.4 `std.ArrayListUnmanaged` 初始化

```zig
// ❌ 编译错误 - missing struct field: items, capacity
list: std.ArrayListUnmanaged(T) = .{},

// ✅ 0.16
list: std.ArrayListUnmanaged(T) = .empty,
```

### 6.5 临时 struct 不能调用方法

```zig
// ❌ 编译错误
try std.testing.expect(Command{ .use = "root" }.name());
//                       ^^^^^^^^^^^^^^^^^^^^^^^^ 临时值不能取地址

// ✅ 先赋值给 const
const cmd = Command{ .use = "root" };
try std.testing.expect(cmd.name());
```

### 6.6 `&.{}` 不是有效切片

```zig
// ❌ 编译错误
fn(&&.{}) // &.{} 是指针到数组，不是切片

// ✅ 先声明变量
var args: []const []const u8 = &.{};
fn(args);
```

### 6.7 `ioBasic()` 在 0.16 中不存在

```zig
// ❌ 编译错误
std.Io.Threaded.global_single_threaded.ioBasic()

// ✅ 0.16
std.Io.Threaded.global_single_threaded.*.io()
```

> `global_single_threaded` 是 `*Threaded` 指针，需要 `.*` 解引用后调用 `.io()`。

### 6.8 `compile test` 模式

`zig test` 会为每个 `_test.zig` 文件创建独立的编译单元。这意味着**每个 test 文件是独立编译的**，共享的库源代码需要**分别编译**或**被复用**。

```zig
// build.zig: 多个 test 文件可以复用同一个 lib 编译产物
inline for (test_files) |tf| {
    const tests = b.addTest(.{ .root_module = test_mod });
    const run_tests = b.addRunArtifact(tests);
    run_tests.step.dependOn(&lib.step);  // 复用 lib
}
```

---

## 7. 测试策略

### 7.1 测试工具函数

创建 `test_helper.zig` 集中管理测试辅助函数：

```zig
pub fn executeCommand(...) !TestOutput { ... }
pub fn checkStringContains(t, got, expected) void { ... }
pub fn emptyRun(cmd, args) void { ... }
```

不要让每个测试文件自己实现这些——共享它们。

### 7.2 先写简单测试

测试优先级：
1. **纯函数测试**（levenshteinDistance, trimRightSpace）— 无依赖，先通过
2. **结构体方法测试**（hasParent, name, isAvailableCommand）— 不依赖 execute
3. **集成测试**（executeCommand）— 最后的最后再写

### 7.3 build.zig 管理多个测试文件

```zig
const test_files = [_]struct { name: []const u8, path: []const u8 }{
    .{ .name = "cobra_test", .path = "src/cobra_test.zig" },
    .{ .name = "command_test", .path = "src/command_test.zig" },
    .{ .name = "args_test", .path = "src/args_test.zig" },
    // ... 逐个添加
};

inline for (test_files) |tf| {
    const test_mod = b.createModule({
        .root_source_file = b.path(tf.path),
        .target = target,
        .optimize = optimize,
    });
    const tests = b.addTest(.{ .root_module = test_mod });
    const run_tests = b.addRunArtifact(tests);
    run_tests.step.dependOn(&lib.step);
    test_step.dependOn(&run_tests.step);
}
```

---

## 8. 经验总结

### 8.1 做得好的

1. **先完整阅读源码**：在写一行 Zig 之前，读完了全部 Go 代码。这让后续的 1:1 映射非常顺畅。
2. **从骨架开始**：先让编译通过，再逐步填充逻辑。避免了同时面对"类型错误"和"逻辑错误"。
3. **positionalArgs 的 union 设计**：用 tagged union 替代闭包是这次迁移中最满意的设计决策。
4. **测试优先**：每个模块写完立即写测试，`std.testing.allocator` 的 leak 检测帮我们发现了很多内存问题。

### 8.2 可以改进的

1. **sed 修复太多**：大约第 12 轮开始，大量用 sed 批量修复，导致了一些破坏性编辑。应该更早地直接用 write 工具重写文件。
2. **应该更早合并测试文件**：6 个独立测试文件带来 6 次编译，每次 ~300ms。合并成一个文件能节省 CI 时间。
3. **print 函数留为 stub 太久**：命令执行的核心 I/O 功能直到最后都是 stub，这导致 execute 相关的集成测试无法覆盖。

### 8.3 关键数字

| 指标 | 数值 |
|------|------|
| 阅读的 Go 文件 | 16 个 |
| 创建的 Zig 文件 | 16 个 |
| 创建的测试文件 | 6 个 |
| 编译→修复循环 | ~25 轮 |
| 最终测试数 | 83 个 |
| 测试通过率 | 100% |
| 内存泄漏 | 2 个（已标记，stub 实现所致） |

### 8.4 仍未完成的工作

以下是迁移计划中尚未完成的部分，作为后续的 roadmap：

1. **FlagSet/pflag 集成**：cobra 的命令行标志解析完全依赖 pflag。目前 FlagSet 是 stub，需要完整实现或对接第三方库。
2. **模板系统**：Go 的 `text/template` 需要替换。建议用直接函数输出（如 `defaultUsageFunc` 方式），而非字符串模板。
3. **补全脚本生成**：bash_completionsV2.zig 嵌入了大型 bash 脚本模板，需要测试生成的脚本语法正确。
4. **文档生成**：doc/ 下的 5 个文件都是 stub，需要填充实际的 Markdown/Man/YAML/ReST 生成逻辑。
5. **Windows 平台钩子**：command_win.zig 依赖 mousetrap，在 Linux 上跳过了测试。

---

## 附录：速查表

### 常见编译错误速查

| 错误信息 | 原因 | 修复 |
|---------|------|------|
| `no field named 'addStaticLibrary'` | 0.16 API 改名 | `addLibrary` |
| `missing struct field: items` | ArrayListUnmanaged 初始化 | `.empty` 而非 `{}` |
| `no member named 'init'` | ArrayList 0.16 移除 init | `initCapacity(alloc, n)` |
| `expected 2 argument(s), found 1` | ArrayList 方法需 allocator | 加 `gpa` 参数 |
| `duplicate struct member name` | 字段和方法同名 | 方法改前缀 `get` |
| `no field or member function` | 方法未定义在 struct 内 | 移入 struct |
| `unused function parameter` | Zig 不允许未使用参数 | 加 `_ = param;` |
| `cast discards const qualifier` | `*const []` vs `[]` 不匹配 | 统一用 `[]const` |
| `unable to resolve comptime value` | 运行时字符串拼接 | 用 `std.fmt` 而非 `++` |
| `leaked N allocations` | 未释放测试内存 | `defer x.deinit(gpa)` |