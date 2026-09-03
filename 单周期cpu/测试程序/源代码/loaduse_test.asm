# L4: loaduse_test.asm
# Load-use hazard (load data needed in the very next instruction) test.
# Purpose: verify the pipeline inserts a stall (bubble) for every load-use,
# while independent ALU instructions keep full throughput. By counting
# cycles between fixed points the cost of each load-use hazard can be
# measured (usually 1 extra cycle per load-use without data forwarding
# from the memory stage, 0 if forwarded with stall only for the use).
# Rules: RV32I standard instructions ONLY. No pseudo-instructions, no ecall.

addi x20, x0, 0         # base = 0 (data area: mem[0..19])

# ---- scene 1: lw followed immediately by ALU use ----
addi x1, x0, 10
sw   x1, 0(x20)         # mem[0] = 10
lw   x2, 0(x20)         # x2 = 10
add  x2, x2, x2         # x2 = 20   <-- load-use: x2 needed next cycle

# ---- scene 2: lw result used as store data right away ----
addi x3, x0, 33
sw   x3, 4(x20)         # mem[1] = 33
lw   x4, 4(x20)         # x4 = 33
sw   x4, 8(x20)         # mem[2] = 33  <-- load-use: lw -> sw chain

# ---- scene 3: lw result feeds a compare ----
sw   x1, 12(x20)        # mem[3] = 10
lw   x5, 12(x20)        # x5 = 10
slti x6, x5, 100        # x6 = 1   <-- load-use: x5 in comparator

# ---- scene 4: two load-uses back to back ----
addi x7, x0, 7
sw   x7, 16(x20)        # mem[4] = 7
lw   x8, 16(x20)        # x8 = 7
addi x8, x8, 3          # x8 = 10  <-- load-use
lw   x9, 12(x20)        # x9 = 10
add  x9, x9, x8         # x9 = 20  <-- x8 is an ALU result (normal RAW)
lw   x9, 16(x20)        # x9 = 7
add  x9, x9, x8         # x9 = 17  <-- load-use again

# ---- scene 5: control group, NO load-use (full throughput) ----
addi x10, x0, 1
addi x11, x0, 2
add  x12, x10, x11
add  x13, x10, x11
add  x14, x10, x11
add  x15, x10, x11
add  x16, x10, x11
add  x17, x10, x11
add  x18, x10, x11
add  x19, x10, x11

pass:
beq  x0, x0, pass       # endless loop = finish

# =====================================================================
# Expected final register values:
#   x2=20, x4=33, x6=1, x8=10, x9=17
#   x10..x19 = 1,2,3,3,3,3,3,3,3,3
# Memory: mem[0]=10, mem[1]=33, mem[2]=33, mem[3]=10, mem[4]=7
# =====================================================================
# Performance note: scenes 1-4 contain 4 load-use hazards (each needs a
# stall). Scene 5 has none. Compare the retire rate of the two parts:
# the whole program above scene 5 should take (number of instr + 4)
# cycles if each load-use costs exactly 1 bubble.
# =====================================================================