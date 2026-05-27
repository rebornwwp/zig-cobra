# zig-cobra 常用命令
#
# 运行: just <command>
# 安装: https://github.com/casey/just

default:
    @just --list

# 编译库并运行所有测试
test:
    zig build test --summary all

# 编译库
build:
    zig build

# 运行 hello-world demo
demo *args:
    zig build run-demo -- {{args}}

# 运行 Docker 风格 demo
dockr *args:
    zig build run-dockr -- {{args}}

# 格式化代码
fmt:
    zig fmt src/ examples/

# 检查格式（不修改）
fmt-check:
    zig fmt --check src/ examples/

# 清理构建产物
clean:
    rm -rf zig-out .zig-cache
