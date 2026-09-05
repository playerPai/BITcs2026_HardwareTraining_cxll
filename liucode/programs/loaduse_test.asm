# Load-use dependency test (also reusable by a future pipelined CPU).
# x31 is reserved by the CPU result monitor and is never used by this program.
# The final expected value x9 = 17 is re-emitted after the control group.
.text
.globl main
main:
    addi x20, x0, 0
    addi x1, x0, 10
    sw   x1, 0(x20)
    lw   x2, 0(x20)
    add  x2, x2, x2

    addi x3, x0, 33
    sw   x3, 4(x20)
    lw   x4, 4(x20)
    sw   x4, 8(x20)

    sw   x1, 12(x20)
    lw   x5, 12(x20)
    slti x6, x5, 100

    addi x7, x0, 7
    sw   x7, 16(x20)
    lw   x8, 16(x20)
    addi x8, x8, 3
    lw   x9, 12(x20)
    add  x9, x9, x8
    lw   x9, 16(x20)
    add  x9, x9, x8

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

    addi x9, x9, 0
pass:
    beq  x0, x0, pass
