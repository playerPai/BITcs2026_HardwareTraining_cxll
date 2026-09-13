# overflow_test.asm
# 附加功能测试：溢出判断（signed overflow detection）
# 场景与期望（写内存，供 tb_overflow 断言）：
#   1) MAX_INT + 1    -> 正溢出     mem[0] = 0x80000000
#   2) MAX_INT + (-1) -> 不溢出     mem[1] = 0x7FFFFFFE
#   3) MIN_INT + (-1) -> 负溢出     mem[2] = 0x7FFFFFFF
#   4) 10 + 20        -> 不溢出     mem[3] = 30
#   5) MIN_INT - 10   -> 溢出       mem[4] = 0x7FFFFFF6
# x31 reserved by CPU monitor, never used here.
.text
.globl main
main:
    lui  x1, 0x80000        # x1 = 0x80000000 (MIN_INT)
    addi x1, x1, -1         # x1 = 0x7FFFFFFF (MAX_INT)
    addi x2, x0, 1          # x2 = 1
    add  x3, x1, x2         # MAX+1 -> overflow
    sw   x3, 0(x0)          # mem[0] = 0x80000000
    addi x2, x0, -1         # x2 = -1
    add  x3, x1, x2         # MAX+(-1) -> no overflow
    sw   x3, 4(x0)          # mem[1] = 0x7FFFFFFE
    lui  x2, 0x80000        # x2 = MIN_INT
    addi x3, x2, -1         # MIN+(-1) -> overflow
    sw   x3, 8(x0)          # mem[2] = 0x7FFFFFFF
    addi x4, x0, 10
    addi x5, x0, 20
    add  x6, x4, x5         # 10+20 -> no overflow
    sw   x6, 12(x0)         # mem[3] = 30
    sub  x7, x2, x4         # MIN-10 -> overflow
    sw   x7, 16(x0)         # mem[4] = 0x7FFFFFF6
pass:
    beq  x0, x0, pass       # terminal sentinel, never overflows