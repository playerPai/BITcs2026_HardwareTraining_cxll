# L4: branch_test.asm
# Control hazard test: dense branches and jumps for the pipelined CPU.
# Purpose:
#   - verify beq/bne/blt/bge both taken and not-taken paths
#   - verify jal/jalr (subroutine call and return, saved return address)
#   - the loop and subroutine give measurable branch-penalty data:
#     every wrong prediction / flush costs cycles, count them.
# Rules: RV32I standard instructions ONLY. No pseudo-instructions, no ecall.

# ---- part 1: dense independent branches, alternating directions ----
addi x1, x0, 5          # 5
addi x2, x0, 5          # 5
addi x3, x0, 8          # 8

beq  x1, x2, L1         # 5==5  -> taken
beq  x1, x3, fail       # 5==8  -> NOT taken
L1:
bne  x1, x3, L2         # 5!=8  -> taken
bne  x1, x2, fail       # 5!=5  -> NOT taken
L2:
blt  x3, x1, fail       # 8<5   -> NOT taken
blt  x1, x3, L3         # 5<8   -> taken
L3:
bge  x3, x3, L4         # 8>=8  -> taken (equality edge)
L4:
bge  x1, x3, fail       # 5>=8  -> NOT taken

# signed negative compare edge
sub  x4, x0, x1         # x4 = -5
blt  x4, x1, L5         # -5<5  -> taken (signed!)
L5:

# ---- part 2: loop with a branch inside (branch prediction stress) ----
addi x10, x0, 0         # sum = 0
addi x11, x0, 1         # i = 1
addi x12, x0, 11        # limit = 11
loop:
  add  x10, x10, x11    # sum += i
  addi x11, x11, 1      # i++
  blt  x11, x12, loop   # while (i < 11)  -> loop body runs 10 times,
                        # branch NOT taken exactly once at the end:
                        # 10 mis-predictions / flushes to measure
# after loop: sum = 55, i = 11

# ---- part 3: subroutine call and return (jal / jalr) ----
addi x15, x0, 3         # argument n = 3
jal  x1, sq             # x1 = return address, call sq(n)
addi x16, x0, 99        # return marker: reached only after jalr returns

pass:
beq  x0, x0, pass       # endless loop = finish OK

# subroutine: x19 = n * n (repeated addition, no pseudo-instructions)
sq:
  addi x17, x15, 0      # counter = n
  addi x19, x0, 0       # result = 0
sq_loop:
  add  x19, x19, x15    # result += n
  addi x17, x17, -1
  bne  x17, x0, sq_loop
  jalr x0, 0(x1)        # return to caller

fail:
beq  x0, x0, fail       # endless loop = FAILED (should never be reached)

# =====================================================================
# Expected final register values:
#   x10=55 (1+..+10)  x11=11  x16=99 (subroutine returned)  x19=9 (3*3)
# =====================================================================
# Performance note: 10 loop iterations + 1 branch miss at loop exit;
# the whole program has 6 taken branches + 7 not-taken + 1 jal + 1 jalr.
# Report: cycles from reset to `pass` minus the ideal instruction count
# = total branch penalty. Divide by the number of taken branches to get
# the average cost of a taken branch in your pipeline.
# =====================================================================