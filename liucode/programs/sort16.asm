# Sort 16 words in ascending order with bubble sort.
# x31 is reserved by the CPU result monitor and is never used by this program.
# The last useful instruction loads x29 = 15 (largest sorted element).
.text
.globl main
main:
    addi x20, x0, 0
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

    addi x22, x0, 15
outer:
    addi x23, x0, 0
    addi x24, x0, 0
inner:
    add  x25, x20, x23
    lw   x26, 0(x25)
    lw   x27, 4(x25)
    blt  x26, x27, noswap
    sw   x27, 0(x25)
    sw   x26, 4(x25)
noswap:
    addi x23, x23, 4
    addi x24, x24, 1
    blt  x24, x22, inner
    addi x22, x22, -1
    bne  x22, x0, outer

    lw   x28, 0(x20)
    lw   x29, 60(x20)
pass:
    beq  x0, x0, pass
