# int_test.asm
# 附加功能测试：中断（interrupt / mret）
# 布局：主程序 0x00-0x14，ISR 从 0x40（与 RV32_Pipeline/RV32_CPU 的
#       INT_VECTOR 参数默认值一致，imem 中 0x18-0x3C 为 NOP）。
# 机制：tb 在运行中把 int_req 拉高 -> CPU 跳 0x40 (ISR) -> ISR 写
#       mem[1]=0x55 -> mret 返回断点重执行 -> 主程序数到 5 写 mem[0]=5。
# x31 reserved by CPU monitor, never used here.
.text
.globl main
main:
    addi x1, x0, 0          # 0x00 计数器清零
    addi x2, x0, 5          # 0x04 循环上限
loop:
    addi x1, x1, 1          # 0x08 循环体：x1++（中断常在此处打断）
    blt  x1, x2, loop       # 0x0C x1<5 循环
    sw   x1, 0(x0)          # 0x10 主程序笔迹：mem[0]=5
pass:
    beq  x0, x0, pass       # 0x14 结束哨兵（自循环）

# ---- 中断服务程序 @ 0x40 ----
.org 0x40
isr:
    addi x3, x0, 0x55       # 0x40 ISR 标记值
    sw   x3, 4(x0)          # 0x44 ISR 笔迹：mem[1]=0x55
    mret                    # 0x48 返回：PC <- mepc，恢复可中断