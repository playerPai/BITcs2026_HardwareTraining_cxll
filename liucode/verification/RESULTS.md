# Verification results

验证环境：RARS 1.6、Vivado/XSim 2019.2，日期 2026-09-04。

| Check | Result |
| --- | --- |
| RARS assemble all five programs | PASS; 54 / 26 / 32 / 31 / 50 words |
| XSim `tb_cpu_all` | PASS; first results follow 7 / 7 / 9 / branch=1; finals are 3 / 300 / 17 / 55 / 15 |
| XSim `tb_top` | PASS; intermediate result 7 is visibly scanned and final display is 3 |
| Vivado project creation | PASS; design top = `top`, simulation top = `tb_top` |
| Vivado synthesis | PASS; 0 errors, 0 critical warnings |

None of the five assembled programs reads or writes `x31`. The CPU reserves it as a hardware result monitor and updates it after each enabled instruction; the terminal self-branch preserves the final useful value. The board top retires one instruction every 5,000,000 input clocks (50 ms at 100 MHz) while the display scan remains at 100 MHz.

The synthesis run successfully read `inst26_test.mem` and inferred the data memory as a 512 x 32 distributed RAM. Expected warnings concern unused address/instruction bits, constant-off decimal points, and one trimmed internal BCD bit.
