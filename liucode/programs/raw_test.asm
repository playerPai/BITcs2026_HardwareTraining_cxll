# Read-after-write dependency-chain test.
# x31 is reserved by the CPU result monitor and is never used by this program.
# The last useful instruction produces x25 = 300.
.text
.globl main
main:
    addi x1, x0, 1
    addi x2, x0, 2
    add  x3, x1, x2
    add  x4, x3, x1
    add  x5, x4, x3
    add  x6, x5, x4
    add  x7, x6, x5
    add  x8, x7, x6
    add  x9, x8, x7
    sub  x10, x9, x8
    and  x11, x9, x8
    or   x12, x9, x10
    xor  x13, x9, x11
    sll  x14, x9, x2
    add  x15, x14, x9
    sub  x16, x15, x14
    add  x17, x15, x16

    addi x20, x0, 0
    addi x21, x0, 100
    sw   x21, 0(x20)
    lw   x22, 0(x20)
    add  x23, x22, x21
    sw   x23, 4(x20)
    lw   x24, 4(x20)
    add  x25, x24, x22

pass:
    beq  x0, x0, pass
