# BITcs2026_HardwareTraining_cxll

北京理工大学计算机学院 2023 级本科《硬件训练》课程项目（CXLL 团队：陈、徐、刘、吕）。

当前仓库包含**单周期 CPU** 与 **5 级流水线 CPU**（均为 RISC-V RV32I 子集，26 条指令）的完整实现、
5 个测试程序、行为级校验脚本，以及两个附加功能：**溢出判断** 与 **中断（interrupt/mret）**。
组员克隆后即可在本地用 Vivado 重建工程并复现全部仿真结果，无需安装额外工具。

## 目录结构

```text
BITcs2026_HardwareTraining_cxll/
├── README.md                          # 本文件：项目说明 + 快速复现
├── overall_scheme.docx                # 课程总体方案文档
├── docs/                              # 答辩与功能说明文档（推荐先读）
│   ├── 01_组长答辩稿.md                # 组长演讲逐字稿
│   ├── 02_答辩代码速览.md              # 答辩时对照代码的速览
│   ├── 05_溢出判断功能说明.md          # 附加功能一：溢出判断（设计+实现+亲跑指南）
│   ├── 06_亲手跑溢出仿真_操作指南.md    # 溢出仿真操作速查
│   └── 07_中断功能实现说明.md          # 附加功能二：中断（设计+实现+亲跑指南）
├── liucode/                           # ★ 最新统一开发目录（两个 CPU + 附加功能，推荐）
│   ├── rtl/
│   │   ├── RV32_CPU.v                 # 单周期 CPU（含溢出判断 + 中断）
│   │   ├── RV32_Pipeline.v            # 5 级流水线 CPU（含溢出判断 + 中断）
│   │   ├── LCD_controller.v           # 板级接口控制器
│   │   └── top.v                      # 顶层
│   ├── sim/
│   │   ├── tb_cpu_performance.v       # 性能对比 testbench（默认 top）
│   │   ├── tb_overflow.v / tb_overflow_sc.v   # 溢出功能测试（流水线/单周期）
│   │   ├── tb_int.v / tb_int_sc.v             # 中断功能测试（流水线/单周期）
│   │   └── …                           # 其他 testbench
│   ├── programs/                      # 汇编源 .asm 与机器码 .mem
│   │   ├── inst26_test.mem … sort16.mem      # 5 个基础测试程序
│   │   ├── overflow_test.asm/.mem            # 溢出测试程序
│   │   └── int_test.asm/.mem                 # 中断测试程序（ISR 位于 0x40）
│   ├── create_project.tcl             # 一键重建 Vivado 工程（克隆后必跑）
│   ├── sim_overflow.tcl               # 一键跑溢出仿真（流水线+单周期）
│   └── sim_int.tcl                    # 一键跑中断仿真（流水线+单周期）
├── 单周期cpu/                         # 早期开发目录（被 liucode 取代，仅参考）
│   ├── 指令集说明.md / 仿真步骤指南.md
│   ├── SingleCycleCPU/project_1/      # 旧单周期工程
│   ├── 测试程序/                      # .asm 与 .mem
│   └── 工具/verify_cpu.py             # Python 行为级校验
└── 流水线cpu/                         # 早期流水线目录（被 liucode 取代，仅参考）
    ├── PipelineCPU.v / tb_pipeline.v
    ├── create_project.tcl / 切换测试程序_流水线.ps1
    ├── 流水线CPU说明.md
    └── PipelineProject/pipeline_cpu.xpr
```

## 环境要求

| 工具 | 用途 | 必需？ |
|---|---|---|
| Vivado 2019.2+ | 行为级仿真（复现最终结果） | 必需 |
| Python 3 | 运行 `verify_cpu.py` 快速校验 | 推荐 |
| RARS + Java | 修改 `.asm` 后重新生成 `.mem` | 仅改程序时需要 |

## ★ 快速复现（liucode，小组推荐路径）

> 所有 `.mem` 均已生成在 `liucode/programs/`，**只做仿真与测试不需要 RARS**。

### 第 0 步：克隆仓库

```bash
git clone https://github.com/playerPai/BITcs2026_HardwareTraining_cxll.git
```

### 第 1 步：重建 Vivado 工程（唯一必须的一步）

工程文件（`.xpr`）含本机绝对路径，**不随仓库分发**；克隆后在 `liucode/` 目录执行：

```powershell
cd liucode
D:\vivado2019.2\Vivado\2019.2\bin\vivado.bat -mode batch -source create_project.tcl
```

生成 `liucode/project/liucode_project.xpr`，并自动把 `rtl/`、`sim/`、`programs/*.mem`
全部加入工程。

### 第 2 步：跑仿真（任选）

**一键跑溢出功能（流水线 + 单周期，全自动）：**

```powershell
D:\vivado2019.2\Vivado\2019.2\bin\vivado.bat -mode batch -source sim_overflow.tcl
```

**一键跑中断功能（流水线 + 单周期，全自动）：**

```powershell
D:\vivado2019.2\Vivado\2019.2\bin\vivado.bat -mode batch -source sim_int.tcl
```

> 若未先跑第 1 步，脚本会自动调用 `create_project.tcl` 重建工程，两个入口都可用。
> `run all` 后 TESTBENCH 打印 `PASS …` 即通过；脚本结束会恢复默认 top
> `tb_cpu_performance`。

**性能对比（PPT/报告数据来源，默认 top）：**

打开工程后在 `Flow Navigator → SIMULATION → Run Behavioral Simulation`，
点 **Run All（F3）** 跑完，参照 `docs/02_答辩代码速览.md` 核对：
单周期 1228 周期 / CPI 1.0；流水线 1774 周期 / CPI 1.444625。

### 附加功能一览

| 功能 | RTL | 测试 | 一键脚本 | 说明文档 |
|---|---|---|---|---|
| 溢出判断（ADD/SUB 饱和溢出，粘性标志） | `RV32_CPU.v` / `RV32_Pipeline.v` | `tb_overflow(_sc).v` | `sim_overflow.tcl` | `docs/05` |
| 中断（mepc + 中断向量 + mret，嵌套屏蔽） | 同上 | `tb_int(_sc).v` | `sim_int.tcl` | `docs/07` |

两种 CPU 的附加功能语义完全一致：**溢出** 在 ALU 检测、写回期生效、粘性保持；
**中断** 在指令边界响应、`mepc` 保存被推迟指令地址、`mret` 返回断点重新执行。

## 早期目录（单周期cpu / 流水线cpu）

`liucode/` 出现前的历史版本，保留作为代码演进记录与参考；新功能开发均以
`liucode/` 为准。若要在早期目录复现：分别见 `单周期cpu/仿真步骤指南.md` 与
`流水线cpu/流水线CPU说明.md`（工程 xpr 同样建议 `create_project.tcl` 重建）。

## 测试程序与基准（5 个基础程序）

| 程序 | 用途 | 到 pass 的执行指令数* |
|---|---|---|
| inst26_test | 26 条指令逐条验证 | 47 |
| raw_test | 数据相关（RAW）链验证 | 25 |
| loaduse_test | load-use 停顿场景验证 | 30 |
| branch_test | 分支/跳转（含 10 次循环、子程序调用返回） | 59 |
| sort16 | 16 元素排序（性能基准，报告用） | **1064** |

\* 从复位结束到程序末尾 `pass` 死循环的执行指令数；单周期设计 CPI=1，周期数即指令数。

## 常见问题

- 仿真时 imem 全为 x：先跑 `create_project.tcl` 重建工程，并确认 `.mem` 在
  `liucode/programs/`（脚本自动复制到 xsim 目录）。
- 中文注释乱码：旧目录源码注释为 GBK 编码，Windows 本地查看正常；GitHub 网页
  可能乱码，不影响编译与仿真。`liucode/` 下新文件均为 UTF-8。
- RARS 报 pseudo-instruction：测试程序禁止 `li/la/ecall` 等伪指令
  （未实现 `auipc` 与系统调用），见 `单周期cpu/指令集说明.md`。
- push 时 xpr/工程生成物变化：`.xpr`、`.cache/.runs/.sim/.hw` 均已加入
  `.gitignore`，不会再进入版本控制。