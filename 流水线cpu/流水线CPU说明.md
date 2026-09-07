# 流水线 CPU 说明（5 级：IF / ID / EX / MEM / WB）

> 本文档在 GitHub 仓库内，供全体组员使用。既是**原理复习**（流水线为什么这么做），也是**本设计的实现说明**（代码怎么读），
> 最后附**如何仿真验证**。对应代码：`PipelineCPU.v`，测试平台：`tb_pipeline.v`。

---

## 1. 为什么需要流水线

单周期 CPU：一条指令在一个时钟周期内完成取指 → 译码 → 执行 → 访存 → 写回，
所有逻辑串在**一个周期**里，主频被最长的路径（关键路径）卡死。
它的好处是简单（CPI = 1），坏处是快不起来。

流水线的思路：把一条指令的执行**切成 5 段**，每段用一个时钟周期，
让 5 条指令的不同阶段**同时在流水线上重叠执行**：

```
周期 →    1    2    3    4    5    6    7
指令1    IF   ID   EX   MEM  WB
指令2         IF   ID   EX   MEM  WB
指令3              IF   ID   EX   MEM  WB
```

理想情况下每个周期都能"完成"一条指令（吞吐率提升近 5 倍），
但单条指令仍要 5 个周期才走完（延迟不变）。
理想很丰满，前提是解决三类"冒险（hazard）"——见第 3 节。

## 2. 五级各做什么（对照单周期代码）

| 级 | 做什么 | 对应单周期 CPU.v 的部分 | 流水线里的模块 |
|---|---|---|---|
| IF 取指 | 按 PC 从指令存储器取指令 | pc_reg + imem | pc_reg、imem、if_id_reg |
| ID 译码 | 译出控制信号、生成立即数、读寄存器堆 | ctrl、imm_gen、regfile | 同名模块 + id_ex_reg |
| EX 执行 | ALU 运算；分支判断；算跳转目标 | alu、br_unit | 同名模块 + forwarding_unit |
| MEM 访存 | 读写数据存储器 | dmem | dmem + ex_mem_reg |
| WB 写回 | 把结果写回寄存器堆 | regfile 写端口 | mem_wb_reg |

**控制器 ctrl、立即数生成 imm_gen、ALU、分支单元 br_unit 的逻辑与单周期完全相同**，
只是各自搬到了对应的流水级——译码在 ID，ALU 和分支判断在 EX。

**流水寄存器**（if_id_reg / id_ex_reg / ex_mem_reg / mem_wb_reg）就是每级之间的"传送带"：
每个时钟上升沿把上一级的计算结果锁存给下一级。
其中 ID/EX 传的是：PC、两个寄存器读出值、立即数、rs1/rs2/rd 编号、funct3、全部控制信号。

## 3. 三类冒险与本设计的对策

### 3.1 结构冒险（结构资源冲突）
两条指令同时要抢同一个硬件。本设计**指令存储器和数据存储器分开**（imem/dmem），
寄存器堆读写端口也分开，所以天然不存在结构冒险，不需要处理。

### 3.2 数据冒险（RAW：后一条要用前一条还没写回的结果）

```
add x3, x1, x2     # x3 在 WB 级(第5拍)才写回
sub x4, x3, x1     # 却在 EX 级(第3拍)就要用 x3 → 读到旧值！
```

**对策一：前递/旁路（forwarding）—— 主力手段。**
x3 在第 3 拍末其实已经在 EX/MEM 流水寄存器里了！把"下一级的中间结果"
直接引一条线回来给 ALU 用，就不必等写回。`forwarding_unit` 做的事：

- 比较 EX 级指令的 rs1/rs2 与 **EX/MEM.rd**（上一条指令）→ 命中则前递 EX/MEM 的值
- 否则比较与 **MEM/WB.rd**（上上条指令）→ 命中则前递 MEM/WB 的值
- 都不命中 → 用寄存器堆原始读出值
- **x0 永远不前递**（它恒为零）

EX/MEM 里能前递的值是 `ex_wb_val`：ALU 结果 / lui 的立即数 / jal 的 PC+4，
在 EX 级就算好了；**lw 的数据要 MEM 级之后才存在**，所以它不走这条路（见下面停顿）。

**对策二：load-use 停顿（stall）—— 前递救不了的情况。**

```
lw  x5, 0(x20)    # 数据第 4 拍末才从 dmem 出来
add x6, x5, x1    # 第 3 拍就要用 → 前递也来不及，必须等一拍
```

`hazard_unit` 检测：EX 级是 lw（reg_we 且 wb_sel=内存），且 ID 级指令的
rs1/rs2 与 lw 的 rd 相同（rd≠0）→ 停 1 拍：

1. 冻结 PC（pc_reg 的 en=0）
2. IF/ID 保持原值（这条指令重取一次）
3. ID/EX 注入**气泡**（控制信号全零 → 什么都不做的一拍）

停完之后 lw 已到 MEM/WB，走前递通路交给用它的指令。
优化细节：hazard_unit 按指令真实用到的寄存器域判断
（jal/lui 不用 rs1 域、只有 R 型/分支/sw 用 rs2 域），避免无谓停顿。

**对策三（小补充）：寄存器堆写穿透。**
"上一条刚写回、这一条正在读"（WB 写与 ID 读同拍）时，
regfile 直接把写数据旁路给读出端：

```verilog
assign rd1 = (ra1 == 0) ? 0 :
             (we && wa == ra1) ? wd : regs[ra1];   // 写穿透
```

### 3.3 控制冒险（分支/跳转改变取指流向）
流水线每拍都默认取"PC+4"，但分支一旦成立，后面已取的指令全错了。
本设计选择**在 EX 级解决**（教科书 P&H 经典方案）：

- br_unit 在 EX 用**前递后**的操作数判断 beq/bne/blt/bge
- 分支目标 = PC(EX) + 立即数；jal 同理；jalr 目标 = (rs1+imm) & ~1
- 一旦成立（`ex_redirect`）：PC 装载目标地址，同时**冲刷** IF/ID、ID/EX
  （强制注入 NOP/气泡）——已取的两条错误指令作废，代价 **2 拍**

冲刷 vs 停顿的区别：停顿是"下一拍不许动"（保住指令），
冲刷是"下一拍变成 NOP"（丢弃指令）。

## 4. 数据通路总图

```
        ┌────────────────────────────────────────────────────────────┐
        │                     WB: 写回寄存器堆                        │
        │                wb_data = mem 或 ex_wb_val                  │
        └────────────────────────────────────────────────────────────┘
IF          ID               EX                MEM           WB
┌────┐  ┌───────┐  ┌──────────────┐  ┌──────────┐  ┌─────────┐
│ PC │→ │ctrl   │  │ 前递多路选择  │→ │ dmem R/W │→ │ 写回选择 │
│imem│  │imm_gen│→ │ ALU          │  └──────────┘  └─────────┘
└────┘  │regfile│  │ br_unit      │      ↑ store数据=fwd_b
  ↑     └───────┘  │ 分支目标加法器│      
  │          │         │         │
  │      IF/ID 寄存器  ID/EX 寄存器  EX/MEM 寄存器   MEM/WB 寄存器
  │
  └── EX 重定向：taken/jal/jalr → PC=目标，冲刷 IF/ID、ID/EX
  └── load-use：冻结 PC、IF/ID，ID/EX 注气泡

前递路径（虚线）：
  EX/MEM.ex_wb_val ──→ EX 段 ALU 操作数（上一条的结果）
  MEM/WB.wb_data  ──→ EX 段 ALU 操作数（上上条的结果）
```

## 5. 关键代码导读（PipelineCPU.v）

按模块顺序：

| 模块 | 要点 |
|---|---|
| `pipeline_top` | 把所有级连起来；`pc_next = ex_redirect ? ex_target : pc+4`；`pc_en = ~stall` |
| `if_id_reg` | flush 注 NOP（`32'h00000013`），stall 保持 |
| `id_ex_reg` | flush（冲刷或停顿）时**控制信号全清零** → 气泡不会产生任何副作用 |
| `forwarding_unit` | 两级比较，EX/MEM 优先（更新的值），排除 x0 |
| `hazard_unit` | 只管 load-use；`mem_read = reg_we && wb_sel==内存` |
| `ex_wb_val`（顶层 wire） | ALU/lui/PC+4 三选一；lw 不经此路（由停顿保证正确性） |
| `regfile` | 写穿透旁路 |
| `ctrl / imm_gen / alu / br_unit` | 与单周期完全一致 |

读代码建议顺序：先看 `pipeline_top` 的五段连接 → 再看 `forwarding_unit` +
EX 段的 `fwd_a/fwd_b` 选择 → 最后看 `hazard_unit` 与两个流水寄存器的
flush/stall 端口。

## 6. 如何仿真验证

### 6.1 建工程（一次性）

```powershell
cd <仓库根>\流水线cpu    # 例如：C:\Users\ASUS\Desktop\北京理工大学\大四上\小学期\BITcs2026_HardwareTraining_cxll\流水线cpu
# 方式 A：已生成工程，直接打开
#   PipelineProject\pipeline_cpu.xpr
# 方式 B：重建（Vivado Tcl 控制台或命令行）：
vivado -mode batch -source create_project.tcl
```

### 6.2 跑仿真

1. 打开 `pipeline_cpu.xpr`
2. `Flow Navigator → SIMULATION → Run Behavioral Simulation`
   （默认只跑 1000ns 弹出波形，点 **Run All**（F3）继续跑到 $stop）
3. 结束时 Tcl 控制台自动打印：总周期数、x0..x31、数据存储器非零项

### 6.3 切换测试程序

```powershell
cd <仓库根>\流水线cpu
powershell -ExecutionPolicy Bypass -File .\切换测试程序_流水线.ps1 inst26   # 默认
# 可选: inst26 / raw / loaduse / branch / sort16
```

然后在 Vivado 里 Stop 再重新 Run Behavioral Simulation。

### 6.4 每个测试验证什么

| 测试 | 验证的机制 | 核对要点（详见各 .asm 尾部注释） |
|---|---|---|
| inst26_test | 26 条指令语义全对 | x1..x31 全部与注释一致（x5=返回地址、mem[0]=66/mem[1]=-66） |
| raw_test | 前递 | x3..x17 依赖链全对（没有前递会读到旧值） |
| loaduse_test | load-use 停顿 + 前递 | x2=20, x4=33, x6=1, x8=10, x9=17 |
| branch_test | 分支判断 + 冲刷 + jal/jalr | x10=55, x11=11, x16=99（子程序正确返回）, x19=9 |
| sort16 | 整体数据通路 | 内存 arr[0..15]=0..15，x28=0, x29=15 |

本设计的以上 5 项**已全部通过仿真核对**（与单周期行为级模型结果一致）。

### 6.5 波形里看什么（理解流水线的关键）

- **看气泡**：跑 loaduse_test，加信号 `dut.u_id_ex/reg_we_out` 与 `dut/stall`，
  每次 load-use 后能看到一拍 reg_we_out=0（气泡）
- **看冲刷**：跑 branch_test，taken 分支后 `dut.u_if_id/instr_out` 变成
  `00000013`（NOP）
- **看前递**：跑 raw_test，观察 `dut/forward_a/forward_b` 在依赖指令
  到达 EX 时变成 2'b10 / 2'b01

## 7. 与单周期的对比（复习用）

| | 单周期 | 流水线 |
|---|---|---|
| CPI | 1 | 理想 1，实际 >1（停顿+冲刷的拍数摊到每条指令） |
| 时钟周期 | 一条指令的全部逻辑（长） | 最慢的一级（短得多）→ 主频可以更高 |
| 吞吐率 | 低 | 高（多条指令重叠执行） |
| 实现难点 | 无冒险问题 | 前递、停顿、冲刷 |
| 每条指令延迟 | 1 周期 | 仍是 5 周期（流水不缩短单条延迟） |

> 性能对比测试（周期数/CPI 表）本阶段暂不要求，需要时用 testbench 的
> cyc 计数器跑同一批测试即可。

## 8. 常见问题

| 现象 | 原因与对策 |
|---|---|
| imem 全为 x | 仿真目录没有 inst.mem：先跑一次 `切换测试程序_流水线.ps1`（它会自动建目录），再重新仿真 |
| 仿真只跑 1000ns 就停 | Vivado 默认行为，点工具栏 **Run All**（F3）继续 |
| 波形信号太多找不到 | Tcl：`add_wave /tb_pipeline/dut/*` 递归加；或 Scope 面板展开 dut |
| 分支后面执行了不该执行的指令 | 冲刷没生效：查 `ex_redirect` 与 `u_if_id/flush`、`u_id_ex/flush` |
| RAW 相关指令读到旧值 | 查 `forward_a/forward_b` 取值与 `exmem_rd/memwb_rd` 比较 |
| 改了 .v 没生效 | 先 Reset Behavioral Simulation（或关掉仿真窗口）再重新 Run |

## 9. 目录与文件

```
流水线cpu\（仓库根下）
├── PipelineCPU.v               # 流水线 CPU 全部 RTL（GBK 注释）
├── tb_pipeline.v               # 测试平台（GBK 注释）
├── create_project.tcl          # 一键建 Vivado 工程
├── 切换测试程序_流水线.ps1       # 一键切换 5 个测试程序
├── 流水线CPU说明.md             # 本文档
└── PipelineProject\            # Vivado 工程（已含 pipeline_cpu.xpr；cache/sim 等生成物不入库）
```

指令集定义、测试程序与期望值说明见：
`单周期cpu\仿真步骤指南.md`、`单周期cpu\指令集说明.md`、`单周期cpu\工具\verify_cpu.py`（参考答案）。