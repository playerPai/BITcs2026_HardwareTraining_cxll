# Dense branch, loop, JAL and JALR test.
# x31 is reserved by the CPU result monitor and is never used by this program.
# The final expected value x10 = 55 is re-emitted after the subroutine returns.
.text
.globl main
main:
    addi x1, x0, 5
    addi x2, x0, 5
    addi x3, x0, 8
    beq  x1, x2, L1
    beq  x1, x3, fail
L1:
    bne  x1, x3, L2
    bne  x1, x2, fail
L2:
    blt  x3, x1, fail
    blt  x1, x3, L3
L3:
    bge  x3, x3, L4
L4:
    bge  x1, x3, fail
    sub  x4, x0, x1
    blt  x4, x1, L5
L5:
    addi x10, x0, 0
    addi x11, x0, 1
    addi x12, x0, 11
loop:
    add  x10, x10, x11
    addi x11, x11, 1
    blt  x11, x12, loop

    addi x15, x0, 3
    jal  x1, sq
    addi x16, x0, 99
    addi x10, x10, 0
pass:
    beq  x0, x0, pass

sq:
    addi x17, x15, 0
    addi x19, x0, 0
sq_loop:
    add  x19, x19, x15
    addi x17, x17, -1
    bne  x17, x0, sq_loop
    jalr x0, x1, 0

fail:
    beq  x0, x0, fail
