# BITcs2026_HardwareTraining_cxll

北京理工大学计算机学院 2023 级本科《硬件训练》课程项目（CXLL 团队：陈、徐、刘、吕）。

当前仓库包含**单周期 CPU（RISC-V RV32I 子集，26 条指令）**的完整实现、5 个测试程序与行为级校验脚本。
组员克隆后即可在本地用 Vivado 复现全部仿真结果，无需安装额外工具。

## 目录结构

```text
BITcs2026_HardwareTraining_cxll/
├── README.md                          # 本文件：项目说明 + 快速复现
├── overall_scheme.docx                # 课程总体方案文档
└── 单周期cpu/
    ├── 指令集说明.md                   # 26 条指令的编码格式与语义定义
    ├── 仿真步骤指南.md                 # 从零复现仿真的完整步骤（换测试程序 / 重新生成机器码 / 常见问题）
    ├── SingleCycleCPU/
    │   └── project_1/
    │       ├── project_1.xpr          # Vivado 工程文件（打开即可运行仿真）
    │       └── project_1.srcs/
    │           ├── sources_1/new/     # CPU.v（单周期 CPU 实现）＋ CPU_8ins_backup.v（旧版备份）
    │           └── sim_1/new/         # testbench.v（周期计数器 + 寄存器/内存打印）＋ inst26_test.mem
    ├── 测试程序/
    │   ├── 源代码/                    # 5 个 .asm 测试程序（头部注释含期望值）
    │   └── 机器代码/                  # 与 .asm 一一对应的 .mem 机器码镜像
    └── 工具/
        └── verify_cpu.py              # 行为级校验脚本（Python 3）
```

## 环境要求

| 工具 | 用途 | 必需？ |
|---|---|---|
| Vivado | 行为级仿真（复现最终结果） | 必需 |
| Python 3 | 运行 `verify_cpu.py` 快速校验 | 推荐 |
| RARS + Java | 修改 `.asm` 后重新生成 `.mem` | 仅改程序时需要 |

> 机器码已全部生成在 `测试程序/机器代码/`，**只做仿真与测试不需要 RARS**。

## 快速复现（两种方式任选）

### 方式一：Vivado 行为级仿真（推荐，以仿真结果为准）

1. 打开工程 `单周期cpu/SingleCycleCPU/project_1/project_1.xpr`
2. `Flow Navigator → SIMULATION → Run Behavioral Simulation`
3. 仿真自动停在 `$stop`，Tcl 控制台打印周期数、全部 32 个寄存器与数据存储器内容
4. 与各 `.asm` 头部注释的期望值（或 `仿真步骤指南.md`「验收标准」表）核对

### 方式二：Python 行为级校验（秒级回归，开发期常用）

```bash
python 单周期cpu/工具/verify_cpu.py               # 校验全部 5 个程序
python 单周期cpu/工具/verify_cpu.py sort16.mem     # 只校验一个
```

输出 `ALL PASS` 即 5 个测试程序在 CPU.v 的单周期语义下全部符合预期。

## 测试程序与基准

| 程序 | 用途 | 到 pass 的执行指令数* |
|---|---|---|
| inst26_test | 26 条指令逐条验证 | 47 |
| raw_test | 数据相关（RAW）链验证 | 25 |
| loaduse_test | load-use 停顿场景验证 | 30 |
| branch_test | 分支/跳转（含 10 次循环、子程序调用返回） | 59 |
| sort16 | 16 元素排序（性能基准，报告用） | **1064** |

\* 从复位结束到程序末尾 `pass` 死循环的执行指令数；单周期设计 CPI=1，周期数即指令数。
testbench 的 `cyc` 计数器读数与此同口径，可作为报告对比数据。

## 更多操作

- **换一个测试程序跑**：见 `仿真步骤指南.md`「更换测试程序」——把想要的 `.mem` 复制为
  `project_1.srcs\sim_1\new\inst26_test.mem`（先备份原文件）再仿真。imem 默认加载
  `inst26_test.mem`（`CPU.v` 中 `$readmemh` 指定的文件名）。
- **修改测试程序**：改 `.asm` 后需用 RARS 重新生成 `.mem`，步骤见 `仿真步骤指南.md`「用 RARS 从 .asm 生成 .mem」。

## 常见问题

- 仿真时 imem 全为 x：`.mem` 未正确替换，或文件名与 `$readmemh` 不一致。
- 中文注释乱码：`CPU.v` 等源码注释为 GBK 编码，Windows 本地查看正常；GitHub 网页可能乱码，不影响编译与仿真。
- RARS 报 pseudo-instruction：测试程序禁止 `li/la/ecall` 等伪指令（未实现 `auipc` 与系统调用），见 `指令集说明.md`。