# Single-cycle / pipelined CPU board project

本目录将 26 条指令的单周期 CPU 与五级流水线 CPU、五套测试程序、
MMIO UART 外设，以及已验证的 EES-338 管脚和八位七段数码管控制器
整合在同一个 Vivado 工程中。原单周期 RTL 保持不变；流水线实现使用
独立的 `pipe_*` 模块名，不会与单周期内部模块冲突。

## Layout

| Path | Purpose |
| --- | --- |
| `rtl/RV32_CPU.v` | 新单周期 CPU，保留 `x31` 作为逐指令结果监视器 |
| `rtl/RV32_Pipeline.v` | 五级流水线 CPU，含前递、load-use 停顿、控制冲刷、退休接口和板级步进使能 |
| `rtl/top.v` | 流水线 CPU、MMIO UART 与八位数码管的 SoC 下板顶层 |
| `rtl/uart_mmio.v` | 115200/8N1 UART 收发器及 MMIO 寄存器 |
| `rtl/display_sequence_mmio.v` | 数码管显示队列：先显示数量，再循环显示排序结果 |
| `rtl/LCD_controller.v` | 八位七段数码管控制器（历史文件名，并非液晶屏） |
| `constraints/ees338.xdc` | 100 MHz 时钟、复位、数码管及 UART 管脚 |
| `programs/*.asm` | 测试程序源代码，完全不使用保留的 `x31` |
| `programs/*.mem` | 用 RARS 1.6 重新生成的机器码 |
| `sim/tb_cpu_all.v` | 五套程序并行自检 |
| `sim/tb_cpu_performance.v` | 单周期/流水线的周期数、IC、CPI 与 CPU 时间对比 |
| `sim/tb_top.v` | CPU 到八位数码管的端到端自检 |
| `sim/tb_uart_mmio.v` | UART IP 收发、状态与错误标志自动比对 |
| `sim/tb_cpu_uart.v` | 电脑串口到 CPU 排序再返回串口的端到端自动比对 |
| `programs/uart_sort_demo.asm` | UART 接收空格分隔的多位数并排序返回的汇编程序 |
| `create_project.tcl` | 创建独立 Vivado 2019.2 工程 |

## UART integrated demonstration

最终下板顶层默认使用流水线 CPU、100 MHz 主时钟、115200 波特率、
8 数据位、无校验、1 停止位。EES-338 串口管脚为：

| Signal | Direction | FPGA pin |
| --- | --- | --- |
| `I_rs232_rxd` | PC/USB-UART -> FPGA | N5 |
| `O_rs232_txd` | FPGA -> PC/USB-UART | T4 |

UART 使用如下存储器映射：

| Address | Access | Meaning |
| --- | --- | --- |
| `0x40000000` | W | TXDATA，低 8 位写入发送器 |
| `0x40000004` | R | RXDATA，读取后清除 RX_VALID |
| `0x40000008` | R | STATUS：RX_VALID、TX_READY、TX_BUSY 和错误标志 |
| `0x4000000c` | W | CONTROL：bit0 清除粘滞错误标志 |
| `0x40000010` | W | DISPLAY_CONTROL：bit0 清队列，bit1 开始轮播 |
| `0x40000014` | W | DISPLAY_DATA：向显示队列追加一个数值 |

打开串口助手后按 S8 复位，终端首先收到：

```text
READY
```

以文本方式输入最多 16 个非负整数，用空格分隔，并以 CR 或 LF 结束：

```text
12 3 105 1
```

流水线 CPU 通过 MMIO 接收字符，在数据 RAM 中执行冒泡排序并返回：

```text
COUNT:4
SORTED:1 3 12 105
```

允许连续空格；支持的演示数值范围为 `0..99999999`。完成后数码管先显示
数量 `4`，再依次显示 `1`、`3`、`12`、`105`，随后循环播放。默认每项
停留 1 秒。UART 演示必须保持
`CPU_STEP_CYCLES=1`，否则慢速演示使能会来不及接收连续串口数据。

等待输入期间数码管固定显示 `0`，不再显示 CPU 轮询 UART 时快速变化的
内部监视值。S8 复位采用异步置位、同步释放，并要求按键释放连续稳定约
20 ms 后才启动 CPU，避免机械抖动截断 `READY` 的首字节。

自动验证命令：

```powershell
D:\Xilinx\Vivado\2019.2\bin\vivado.bat -mode batch -source sim_check.tcl -tclargs tb_uart_mmio
D:\Xilinx\Vivado\2019.2\bin\vivado.bat -mode batch -source sim_check.tcl -tclargs tb_cpu_uart
```

已验证结果：`tb_uart_mmio` 通过；`tb_cpu_uart` 自动确认
`12 3 105 1 -> SORTED:1 3 12 105`，并逐项检查排序后的 RAM 和
`4, 1, 3, 12, 105` 显示序列。加入 UART 后的
完整顶层在 100 MHz 下实现通过，布线后 WNS 为 `+0.152 ns`。

## Board display results

普通 CPU 测试时数码管显示 `x31` 的无符号十进制值。UART 排序完成后，
显示队列接管数码管。UART 集成版默认程序为
`uart_sort_demo.mem`；原CPU回归仍可选择下表中的测试程序。

| Program | Final monitored result | Final display |
| --- | --- | --- |
| `inst26_test.mem` | `x9`（`srai` 的结果） | `3` |
| `raw_test.mem` | `x25` | `300` |
| `loaduse_test.mem` | `x9` | `17` |
| `branch_test.mem` | `x10` | `55` |
| `sort16.mem` | `x29`（排序后最大值） | `15` |

CPU 每完成一条有效指令就自动更新 `x31`，所以程序运行期间显示值会持续变化：算术、逻辑、移位、`lw`、`lui` 显示写回值；`sw` 显示写入内存的数据；条件分支显示是否跳转（`1`/`0`）；`jal` 显示链接地址；`jalr x0` 显示跳转目标。程序结束使用的 `beq x0,x0,0` 保持循环不会覆盖最后结果。

五个测试程序的机器指令均不读写 `x31`。`inst26_test` 原先使用 `x31` 的普通计算已分别改用 `x8` 和 `x9`，关键结果保持不变。

为保证肉眼能看到变化，`top` 使用 `CPU_STEP_CYCLES` 对 CPU 做时钟使能步进，同时数码管控制器始终使用 100 MHz 扫描。默认值为 `100000000`，即每秒推进一个 CPU 周期；设为 `1` 表示每个时钟推进一个 CPU 周期。

## Create and use the Vivado project

在 `liucode` 目录执行：

```powershell
C:\Xilinx\Vivado\2019.2\bin\vivado.bat -mode batch -source create_project.tcl
```

然后打开 `project/liucode_project.xpr`。工程默认设置如下：

- `sources_1` 综合顶层：`top`，默认 `CPU_TYPE="pipeline"`，用于综合、实现和生成 bitstream。
- UART 更新后的 `sim_1` 仿真顶层为 `tb_cpu_uart`；性能对比仍可手动选择 `tb_cpu_performance`。

### 性能测试切换

打开 `sim/tb_cpu_performance.v`，在 `USER SETTING` 处只改这一行：

```verilog
localparam CPU_TYPE = "single_cycle"; // 或 "pipeline"
```

然后将 `tb_cpu_performance` 设为 Simulation Top，运行 Behavioral Simulation 并点 `Run All`。控制台会打印每个程序和总计的 `clock_cycles`、`IC`、`CPI`、`CPU_time_us`。两种 CPU 的默认频率都按 100 MHz 计算；如果要比较综合后的真实性能，请把同一区域内的 `SINGLE_CYCLE_CLOCK_FREQ_HZ` 与 `PIPELINE_CLOCK_FREQ_HZ` 改为各自时序报告所得频率。

当前同为 100 MHz 的回归结果：

| CPU | Total cycles | IC | CPI |
| --- | ---: | ---: | ---: |
| `single_cycle` | 1228 | 1228 | 1.000000 |
| `pipeline` | 1774 | 1228 | 1.444625 |

### 下板与 tb_top

将 `tb_top` 设为 **Simulation Top** 可先验证“流水线 CPU → x31 监视值 → 数码管扫描”的完整下板数据通路。生成 bitstream 时必须保持 **Design Sources 的综合顶层为 `top`**；`tb_top` 含仿真时钟和 `$fatal/$finish`，不能作为 FPGA 综合顶层。默认上板程序为 `inst26_test.mem`，最终显示 `3`。

若要把原单周期 CPU 下板，将 `rtl/top.v` 的默认参数改为：

```verilog
parameter CPU_TYPE = "single_cycle"
```

可选的命令行综合检查：

```powershell
C:\Xilinx\Vivado\2019.2\bin\vivado.bat -mode batch -source synth_check.tcl
```

一键完成综合、实现和 bitstream 生成：

```powershell
C:\Xilinx\Vivado\2019.2\bin\vivado.bat -mode batch -source build_bitstream.tcl
```

生成文件位于 `project/liucode_project.runs/impl_1/top.bit`，另有稳定副本
`output/uart_sort_pipeline_100mhz.bit`。加入 UART 和
MMIO 后的流水线 SoC 已在 100 MHz 下通过实现时序（WNS = 0.188 ns）。

运行工程默认的性能测试：

```powershell
C:\Xilinx\Vivado\2019.2\bin\vivado.bat -mode batch -source sim_check.tcl
```

运行流水线下板数据通路仿真：

```powershell
C:\Xilinx\Vivado\2019.2\bin\vivado.bat -mode batch -source sim_check.tcl -tclargs tb_top
```

同时运行五套程序的 CPU 自检：

```powershell
C:\Xilinx\Vivado\2019.2\bin\vivado.bat -mode batch -source sim_all_check.tcl
```

切换上板程序时，修改 `rtl/top.v` 中 `IMEM_FILE` 的默认值，例如改成 `"sort16.mem"`，再重新执行综合、实现和 Generate Bitstream。仅替换磁盘上的 `.mem` 不会改变已经生成的 `.bit`。

器件默认沿用原工程的 `xc7a35tcsg324-1`。如果已验证板卡工程的实际 Project Device 不同，应以板卡工程为准修改 `create_project.tcl` 中的 `-part`。

## Reset and pins

`I_rst_n` 为低电平有效，顶层采用异步置位复位、同步释放。时钟为 T5 / 100 MHz，复位为 P15；段选和位选完全沿用原工程 `ees338.xdc`。
