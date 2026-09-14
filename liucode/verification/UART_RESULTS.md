# UART integration verification

## Configuration

- Device: `xc7a35tcsg324-1`
- Board clock: 100 MHz, T5
- Reset: active-low S8, P15
- UART RX/TX: N5/T4
- Serial format: 115200 baud, 8N1
- CPU: five-stage pipelined RV32I subset
- Program: `uart_sort_demo.mem`

## Automated checks

### UART peripheral

`tb_uart_mmio` checks receive sampling, transmit framing, MMIO read-to-clear,
busy-write rejection and sticky error clearing.

```text
PASS tb_uart_mmio: RX, TX, status and error handling verified
```

### Complete system

`tb_cpu_uart` models the PC serial connection, sends the line
`12 3 105 1<CR>`, decodes every byte transmitted by the FPGA, checks the four
sorted RAM words, and checks display playback `4, 1, 3, 12, 105`.

```text
PASS tb_cpu_uart: spaced multi-digit input, dynamic count, UART result and display sequence verified
```

The original display and performance regressions also remain valid:

```text
PASS tb_top: display changed during execution and finished at 3
PERF,TOTAL,CPI=1.444625,CPU_time_us=17.740000,clock_cycles=1774,IC=1228,T_clk_ns=10.000000,formula_check=PASS
PASS tb_cpu_performance
```

## Implementation result

- 100 MHz timing requirement: met
- Post-route WNS: `+0.152 ns`
- Post-route TNS: `0.000 ns`
- Unrouted nets: `0`
- Bitstream: `output/uart_sort_pipeline_100mhz.bit`
- Timing report: `output/uart_sort_pipeline_100mhz_timing.rpt`

The remaining required verification is the physical board demonstration using
the on-board USB serial port and a 115200/8N1 terminal.
