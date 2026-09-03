# L4: raw_test.asm
# RAW (read-after-write) data hazard test for the pipelined CPU.
# Purpose: every ALU result is used by the very next instruction.
#          Without forwarding the pipeline must stall; with forwarding
#          it should run at full throughput. Count cycles and compare.
# Rules: RV32I standard instructions ONLY. No pseudo-instructions, no ecall.

# ---- part 1: pure ALU dependency chain ----
addi x1, x0, 1          # x1 = 1
addi x2, x0, 2          # x2 = 2
add  x3, x1, x2         # x3 = 3   (depends on x1,x2)
add  x4, x3, x1         # x4 = 4   (RAW on x3: written 1 cycle ago)
add  x5, x4, x3         # x5 = 7   (chain, both operands just written)
add  x6, x5, x4         # x6 = 11
add  x7, x6, x5         # x7 = 18
add  x8, x7, x6         # x8 = 29
add  x9, x8, x7         # x9 = 47
sub  x10, x9, x8        # x10 = 47 - 29 = 18    (RAW + subtract)
and  x11, x9, x8        # x11 = 47 & 29 = 13
or   x12, x9, x10       # x12 = 47 | 18 = 63
xor  x13, x9, x11       # x13 = 47 ^ 13 = 34
sll  x14, x9, x2        # x14 = 47 << 2 = 188   (shamt from x2)
add  x15, x14, x9       # x15 = 188 + 47 = 235
sub  x16, x15, x14      # x16 = 235 - 188 = 47
add  x17, x15, x16      # x17 = 235 + 47 = 282  (both operands are fresh results)

# ---- part 2: memory write -> read -> use chain ----
addi x20, x0, 0         # base = 0
addi x21, x0, 100
sw   x21, 0(x20)        # mem[0] = 100
lw   x22, 0(x20)        # x22 = 100      (RAW over memory)
add  x23, x22, x21      # x23 = 100+100 = 200  (uses lw result immediately)
sw   x23, 4(x20)        # mem[1] = 200
lw   x24, 4(x20)        # x24 = 200
add  x25, x24, x22      # x25 = 200+100 = 300

pass:
beq  x0, x0, pass       # endless loop = finish

# =====================================================================
# Expected final register values:
#   x3=3 x4=4 x5=7 x6=11 x7=18 x8=29 x9=47
#   x10=18 x11=13 x12=63 x13=34 x14=188 x15=235 x16=47 x17=282
#   x22=100 x23=200 x24=200 x25=300
# Memory: mem[0]=100, mem[1]=200
# =====================================================================
# Performance note: with full forwarding part 1 needs ~18 cycles
# (every instruction retires back-to-back). Count the cycles in the
# testbench waveform from reset release to `pass`.
# =====================================================================