# L5: sort16.asm
# 16-element bubble sort. Performance benchmark program.
# Same program must be run on BOTH the single-cycle CPU (last semester)
# and the pipelined CPU (this semester); count total cycles on each and
# compare CPI / MIPS in the report (required by the course task).
# This is the primary benchmark: ~120 swap-comparisons, ~1250+ executed
# instructions, dense memory access and branches.
# Rules: RV32I standard instructions ONLY. No pseudo-instructions, no ecall.

# ================= init: arr[0..15] = 15,0,14,1,13,2,12,3,11,4,10,5,9,6,8,7 =================
addi x20, x0, 0         # base = 0 (must be a small address; dmem is indexed by addr[31:2])
addi x21, x0, 15
sw   x21, 0(x20)
addi x21, x0, 0
sw   x21, 4(x20)
addi x21, x0, 14
sw   x21, 8(x20)
addi x21, x0, 1
sw   x21, 12(x20)
addi x21, x0, 13
sw   x21, 16(x20)
addi x21, x0, 2
sw   x21, 20(x20)
addi x21, x0, 12
sw   x21, 24(x20)
addi x21, x0, 3
sw   x21, 28(x20)
addi x21, x0, 11
sw   x21, 32(x20)
addi x21, x0, 4
sw   x21, 36(x20)
addi x21, x0, 10
sw   x21, 40(x20)
addi x21, x0, 5
sw   x21, 44(x20)
addi x21, x0, 9
sw   x21, 48(x20)
addi x21, x0, 6
sw   x21, 52(x20)
addi x21, x0, 8
sw   x21, 56(x20)
addi x21, x0, 7
sw   x21, 60(x20)

# ================= bubble sort =================
# x22 = outer counter i (15 .. 1), x24 = inner index (0 .. i-1), x23 = byte offset = i*4
addi x22, x0, 15        # i = n-1 = 15
outer:
  addi x23, x0, 0       # offset = 0
  addi x24, x0, 0       # index = 0
inner:
  add  x25, x20, x23    # addr = base + offset
  lw   x26, 0(x25)      # a = arr[j]
  lw   x27, 4(x25)      # b = arr[j+1]
  blt  x26, x27, noswap # if (a < b) no swap
  sw   x27, 0(x25)      # arr[j]   = b
  sw   x26, 4(x25)      # arr[j+1] = a
noswap:
  addi x23, x23, 4      # offset += 4
  addi x24, x24, 1      # index++
  blt  x24, x22, inner  # while (index < i)
  addi x22, x22, -1     # i--
  bne  x22, x0, outer   # while (i != 0)
                        # 15 outer rounds, 120 comparisons total

# ================= verify: read back smallest and largest =================
lw   x28, 0(x20)        # x28 = arr[0]   -> must be 0
lw   x29, 60(x20)       # x29 = arr[15]  -> must be 15

pass:
beq  x0, x0, pass       # endless loop = sort finished

# =====================================================================
# Expected results:
#   Memory arr[0..15] = 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
#   x28 = 0 (min)  x29 = 15 (max)
# =====================================================================
# Performance note (for the report):
#   static instructions ~48; executed instructions ~1250+
#   For the single-cycle CPU: cycles == executed instruction count (CPI=1)
#   For the pipelined CPU:   cycles = executed + stall cycles + flush cycles
#   Count both with the same testbench cycle counter and fill the CPI/MIPS
#   comparison table.
# =====================================================================