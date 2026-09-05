# Single-cycle CPU board project

本目录将新版 26 条指令单周期 CPU、五套测试程序，与已验证的 EES-338 管脚和八位七段数码管控制器整合在一起。目录和文件名均为英文，工程不依赖原来的中文路径。

## Layout

| Path | Purpose |
| --- | --- |
| `rtl/RV32_CPU.v` | 新单周期 CPU，保留 `x31` 作为逐指令结果监视器 |
| `rtl/top.v` | CPU 与八位数码管的下板顶层，包含可配置的指令步进使能 |
| `rtl/LCD_controller.v` | 已验证的 32 位无符号十进制显示控制器 |
| `constraints/ees338.xdc` | 已验证的 100 MHz 时钟、复位、段选和位选管脚 |
| `programs/*.asm` | 测试程序源代码，完全不使用保留的 `x31` |
| `programs/*.mem` | 用 RARS 1.6 重新生成的机器码 |
| `sim/tb_cpu_all.v` | 五套程序并行自检 |
| `sim/tb_top.v` | CPU 到八位数码管的端到端自检 |
| `create_project.tcl` | 创建独立 Vivado 2019.2 工程 |

## Board display results

数码管显示 `x31` 的无符号十进制值。默认程序是 `inst26_test.mem`。

| Program | Final monitored result | Final display |
| --- | --- | --- |
| `inst26_test.mem` | `x9`（`srai` 的结果） | `3` |
| `raw_test.mem` | `x25` | `300` |
| `loaduse_test.mem` | `x9` | `17` |
| `branch_test.mem` | `x10` | `55` |
| `sort16.mem` | `x29`（排序后最大值） | `15` |

CPU 每完成一条有效指令就自动更新 `x31`，所以程序运行期间显示值会持续变化：算术、逻辑、移位、`lw`、`lui` 显示写回值；`sw` 显示写入内存的数据；条件分支显示是否跳转（`1`/`0`）；`jal` 显示链接地址；`jalr x0` 显示跳转目标。程序结束使用的 `beq x0,x0,0` 保持循环不会覆盖最后结果。

五个测试程序的机器指令均不读写 `x31`。`inst26_test` 原先使用 `x31` 的普通计算已分别改用 `x8` 和 `x9`，关键结果保持不变。

为保证肉眼能看到变化，`top` 默认设置 `CPU_STEP_CYCLES=5000000`：100 MHz 下每 50 ms 执行一条指令，同时数码管控制器继续使用 100 MHz 扫描。需要更快或更慢时可修改该参数；设为 `1` 表示每个时钟执行一条指令。

## Create and use the Vivado project

在 `liucode` 目录执行：

```powershell
C:\Xilinx\Vivado\2019.2\bin\vivado.bat -mode batch -source create_project.tcl
```

然后打开 `project/liucode_project.xpr`。综合顶层为 `top`，仿真顶层为 `tb_top`，默认上板应显示 `3`。

可选的命令行综合检查：

```powershell
C:\Xilinx\Vivado\2019.2\bin\vivado.bat -mode batch -source synth_check.tcl
```

默认端到端仿真可执行：

```powershell
C:\Xilinx\Vivado\2019.2\bin\vivado.bat -mode batch -source sim_check.tcl
```

同时运行五套程序的 CPU 自检：

```powershell
C:\Xilinx\Vivado\2019.2\bin\vivado.bat -mode batch -source sim_all_check.tcl
```

切换上板程序时，修改 `rtl/top.v` 中 `IMEM_FILE` 的默认值，例如改成 `"sort16.mem"`，再重新执行综合、实现和 Generate Bitstream。仅替换磁盘上的 `.mem` 不会改变已经生成的 `.bit`。

器件默认沿用原工程的 `xc7a35tcsg324-1`。如果已验证板卡工程的实际 Project Device 不同，应以板卡工程为准修改 `create_project.tcl` 中的 `-part`。

## Reset and pins

`I_rst_n` 为低电平有效，顶层采用异步置位复位、同步释放。时钟为 T5 / 100 MHz，复位为 P15；段选和位选完全沿用原工程 `ees338.xdc`。
