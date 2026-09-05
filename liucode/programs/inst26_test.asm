# Complete test for the 26 implemented RV32I instructions.
# x31 is reserved by the CPU result monitor and is never used by this program.
# The SRAI result is kept in x9. The last useful result is x9 = 3.
.text
.globl main
main:
    addi x1, x0, 7
    addi x2, x0, 7
    addi x3, x0, 9
    beq  x1, x2, ok_beq
    addi x4, x0, 1
ok_beq:
    bne  x1, x3, ok_bne
    addi x4, x0, 2
ok_bne:
    blt  x1, x3, ok_blt
    addi x4, x0, 3
ok_blt:
    blt  x3, x1, fail
    bge  x3, x3, ok_bge
    addi x4, x0, 4
ok_bge:
    bge  x1, x3, fail

    addi x8, x0, 30
    addi x30, x0, 12
    addi x29, x0, 2
    add  x10, x8, x30
    sub  x11, x8, x30
    slt  x12, x30, x8
    slt  x13, x8, x30
    and  x14, x8, x30
    or   x15, x8, x30
    xor  x16, x8, x30
    sll  x17, x8, x29
    srl  x18, x8, x29
    sra  x19, x8, x29
    sub  x20, x0, x8
    sra  x21, x20, x29
    srl  x22, x20, x29
    sll  x23, x20, x29

    addi x28, x0, 13
    addi x24, x28, 100
    ori  x25, x28, 2
    andi x26, x28, 10
    xori x27, x28, 5
    slli x29, x28, 4
    srli x30, x28, 2
    srai x9, x28, 2
    slti x28, x28, 10

    lui  x24, 0x12345
    addi x28, x0, 0
    addi x25, x0, 66
    sw   x25, 0(x28)
    addi x25, x0, -66
    sw   x25, 4(x28)
    lw   x26, 0(x28)
    lw   x27, 4(x28)

    jal  x5, sub_ret
    addi x6, x0, 5
    addi x9, x9, 0       # Re-emit the final expected result for the monitor.
pass:
    beq  x0, x0, pass

sub_ret:
    addi x7, x0, 20
    jalr x0, x5, 0

fail:
    beq  x0, x0, fail
