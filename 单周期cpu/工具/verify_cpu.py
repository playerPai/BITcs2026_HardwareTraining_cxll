# -*- coding: utf-8 -*-
"""
verify_cpu.py — BITcs2026 单周期 CPU (RV32I 子集) 行为级校验器

1. 反汇编 .mem 机器码镜像（与 cpu_top/ctrl/imm_gen/alu/br_unit 一一对应）；
2. 按 CPU.v 的单周期语义逐周期仿真；
3. 核对寄存器堆与数据存储器的最终值是否与 .asm 头部注释中的期望表一致。

用法：
    python 工具\verify_cpu.py             # 验证 测试程序\机器代码\ 下全部 5 个 .mem
    python 工具\verify_cpu.py xxx.mem     # 只验证指定 .mem（未知程序则打印最终状态）

说明：
    - 源码 CPU.v 为 GBK 编码，本脚本为 UTF-8，两者无相互引用；
    - 校验结论见 仿真步骤指南.md 第 5 节（单周期基准数据：sort16 = 1064 周期）。
"""
import os
import sys

M = 0xFFFFFFFF

# ── opcode 常量（与 ctrl 模块一致）──────────────────────────
OPC_R, OPC_I, OPC_LW, OPC_SW, OPC_BR = 0x33, 0x13, 0x03, 0x23, 0x63
OPC_JAL, OPC_JALR, OPC_LUI = 0x6F, 0x67, 0x37

R_INST = {
    0b0000000_000: 'add', 0b0100000_000: 'sub', 0b0000000_001: 'sll',
    0b0000000_010: 'slt', 0b0000000_100: 'xor', 0b0000000_101: 'srl',
    0b0100000_101: 'sra', 0b0000000_110: 'or',  0b0000000_111: 'and',
}
I_INST = {0: 'addi', 1: 'slli', 2: 'slti', 4: 'xori', 5: 'srli/srai', 6: 'ori', 7: 'andi'}
BR_INST = {0: 'beq', 1: 'bne', 4: 'blt', 5: 'bge'}
LD_INST = {2: 'lw'}
ST_INST = {2: 'sw'}


def sext(v, bits):
    """把 bits 位二进制补码扩展为 Python 有符号整数。"""
    v &= (1 << bits) - 1
    return v - (1 << bits) if (v >> (bits - 1)) & 1 else v


def s32(v):
    v &= M
    return v - (1 << 32) if (v >> 31) & 1 else v


def u32(v):
    return v & M


def load_mem(path):
    """读取 .mem：容忍首行地址头（如 00400000）与空行。"""
    words = []
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        for ln in f:
            ln = ln.strip()
            if not ln:
                continue
            try:
                words.append(int(ln, 16))
            except ValueError:
                pass
    return words


def decode(instr, pc):
    """反汇编一条 32 位指令，返回 (助记符, rd, rs1, rs2, 立即数, 偏移)。"""
    opcode = instr & 0x7F
    rd = (instr >> 7) & 0x1F
    f3 = (instr >> 12) & 0x7
    rs1 = (instr >> 15) & 0x1F
    rs2 = (instr >> 20) & 0x1F
    f7 = (instr >> 25) & 0x7F
    if opcode == OPC_R:
        m = R_INST.get((f7 << 3) | f3)
        return (m, rd, rs1, rs2, None, None) if m else (None,) * 6
    if opcode == OPC_I:
        imm = sext((instr >> 20) & 0xFFF, 12)
        m = 'srai' if (f3 == 5 and (f7 & 0x20)) else ('srli' if f3 == 5 else I_INST.get(f3))
        return (m, rd, rs1, None, imm, None) if m else (None,) * 6
    if opcode == OPC_LW:
        m = LD_INST.get(f3)
        return (m, rd, rs1, None, sext((instr >> 20) & 0xFFF, 12), None) if m else (None,) * 6
    if opcode == OPC_SW:
        m = ST_INST.get(f3)
        s = sext((((instr >> 25) & 0x7F) << 5) | ((instr >> 7) & 0x1F), 12)
        return (m, None, rs1, rs2, s, None) if m else (None,) * 6
    if opcode == OPC_BR:
        imm = (sext((instr >> 31) & 1, 1) << 12) | (((instr >> 7) & 1) << 11) | \
              (((instr >> 25) & 0x3F) << 5) | (((instr >> 8) & 0xF) << 1)
        m = BR_INST.get(f3)
        return (m, None, rs1, rs2, None, sext(imm, 13)) if m else (None,) * 6
    if opcode == OPC_JAL:
        imm = (sext((instr >> 31) & 1, 1) << 20) | (((instr >> 12) & 0xFF) << 12) | \
              (((instr >> 20) & 1) << 11) | (((instr >> 21) & 0x3FF) << 1)
        return ('jal', rd, None, None, None, sext(imm, 21))
    if opcode == OPC_JALR:
        imm = sext((instr >> 20) & 0xFFF, 12)
        return ('jalr', rd, rs1, None, imm, None) if f3 == 0 else (None,) * 6
    if opcode == OPC_LUI:
        return ('lui', rd, None, None, None, None)
    return (None,) * 6


def alu(a, b, sel):
    """镜像 ALU：0000 ADD / 1000 SUB / 0001 SLL / 0010 SLT / 0100 XOR /
    0101 SRL / 1101 SRA / 0110 OR / 0111 AND。移位量取低 5 位。"""
    a, b = u32(a), u32(b)
    if sel == 0:  return u32(a + b)
    if sel == 8:  return u32(a - b)
    if sel == 1:  return u32(a << (b & 0x1F))
    if sel == 2:  return 1 if s32(a) < s32(b) else 0
    if sel == 4:  return a ^ b
    if sel == 5:  return a >> (b & 0x1F)
    if sel == 13: return u32(s32(a) >> (b & 0x1F))
    if sel == 6:  return a | b
    if sel == 7:  return a & b
    return 0


class CPU:
    """单周期 CPU 行为模型（与 CPU.v 一致：组合读、沿写、x0 恒零）。"""

    def __init__(self, words):
        self.imem = list(words)
        self.regs = [0] * 32
        self.ram = [0] * 512
        self.pc = 0

    def step(self):
        addr_w = self.pc >> 2
        if addr_w >= len(self.imem):
            return 'PC 超出指令存储器范围 @0x%04x' % self.pc
        instr = self.imem[addr_w]
        if instr > M:
            return '非法机器码 %08x @0x%04x' % (instr, self.pc)
        opcode = instr & 0x7F
        rd = (instr >> 7) & 0x1F
        f3 = (instr >> 12) & 0x7
        rs1 = (instr >> 15) & 0x1F
        rs2 = (instr >> 20) & 0x1F
        f7 = (instr >> 25) & 0x7F

        # ctrl 默认值
        reg_we = dmem_we = alu_src = branch = jump = 0
        imm_sel = wb_sel = alu_op = 0

        # imm_gen 五种立即数（连续赋值，全部现算）
        imm_i = sext((instr >> 20) & 0xFFF, 12)
        imm_s = sext((((instr >> 25) & 0x7F) << 5) | ((instr >> 7) & 0x1F), 12)
        imm_b = sext((sext((instr >> 31) & 1, 1) << 12) | (((instr >> 7) & 1) << 11) |
                     (((instr >> 25) & 0x3F) << 5) | (((instr >> 8) & 0xF) << 1), 13)
        imm_u = (instr & 0xFFFFF000) & M
        imm_j = sext((sext((instr >> 31) & 1, 1) << 20) | (((instr >> 12) & 0xFF) << 12) |
                     (((instr >> 20) & 1) << 11) | (((instr >> 21) & 0x3FF) << 1), 21)

        # ctrl 译码
        r_alu = {0b0000000000: 0, 0b0100000000: 8, 0b0000000001: 1, 0b0000000010: 2,
                 0b0000000100: 4, 0b0000000101: 5, 0b0100000101: 13,
                 0b0000000110: 6, 0b0000000111: 7}
        if opcode == OPC_R:
            reg_we, wb_sel, alu_src = 1, 0, 0
            alu_op = r_alu.get((f7 << 3) | f3, 0)
        elif opcode == OPC_I:
            reg_we, alu_src, imm_sel, wb_sel = 1, 1, 0, 0
            alu_op = {0: 0, 1: 1, 2: 2, 4: 4, 5: (13 if f7 & 0x20 else 5), 6: 6, 7: 7}.get(f3, 0)
        elif opcode == OPC_LW:
            reg_we, alu_src, imm_sel, wb_sel, alu_op = 1, 1, 0, 1, 0
        elif opcode == OPC_SW:
            dmem_we, alu_src, imm_sel, alu_op = 1, 1, 1, 0
        elif opcode == OPC_BR:
            branch, imm_sel, alu_op = 1, 2, 8
        elif opcode == OPC_JAL:
            reg_we, wb_sel, jump, imm_sel = 1, 2, 1, 4
        elif opcode == OPC_JALR:
            reg_we, wb_sel, alu_src, imm_sel, alu_op, jump = 1, 2, 1, 0, 0, 1
        elif opcode == OPC_LUI:
            reg_we, wb_sel, imm_sel = 1, 3, 3

        # 数据通路
        rd1 = 0 if rs1 == 0 else self.regs[rs1]
        rd2 = 0 if rs2 == 0 else self.regs[rs2]
        imm = (imm_i, imm_s, imm_b, imm_u, imm_j)[imm_sel]
        alu_y = alu(rd1, imm if alu_src else rd2, alu_op)
        rdata = self.ram[(alu_y >> 2) & 0x1FF]
        wb = (alu_y, rdata, u32(self.pc + 4), imm_u)[wb_sel]

        # br_unit（有符号比较，与 $signed 一致）
        take = 0
        if branch:
            take = {0: rd1 == rd2, 1: rd1 != rd2,
                    4: s32(rd1) < s32(rd2), 5: s32(rd1) >= s32(rd2)}.get(f3, 0)

        # pc_next：分支 > 跳转 > pc+4；jalr 目标 alu_y & ~1
        if opcode == OPC_JAL:
            jmp_addr = u32(self.pc + imm_j)
        elif opcode == OPC_JALR:
            jmp_addr = alu_y & 0xFFFFFFFE
        else:
            jmp_addr = 0
        pc_next = u32(self.pc + imm_b) if take else (jmp_addr if jump else u32(self.pc + 4))

        # 周期末尾沿写
        if reg_we and rd != 0:
            self.regs[rd] = u32(wb)
        if dmem_we:
            self.ram[(alu_y >> 2) & 0x1FF] = u32(rd2)
        self.pc = pc_next
        return None


def disasm_lines(words):
    lines = []
    for i, w in enumerate(words):
        pc = i * 4
        m, rd, rs1, rs2, imm, off = decode(w, pc)
        if m is None:
            lines.append('0x%04x: %08x  <未知指令 opcode=%02x funct3=%o>' % (pc, w, w & 0x7F, (w >> 12) & 7))
        elif m in ('lw', 'addi', 'xori', 'ori', 'andi', 'slti', 'jalr'):
            lines.append('0x%04x: %-7s x%-2d, %d(x%d)' % (pc, m, rd, imm, rs1))
        elif m in ('slli', 'srli', 'srai'):
            lines.append('0x%04x: %-7s x%-2d, x%-2d, %d' % (pc, m, rd, rs1, imm & 0x1F))
        elif m == 'sw':
            lines.append('0x%04x: %-7s x%-2d, %d(x%d)' % (pc, m, rs2, imm, rs1))
        elif m in ('beq', 'bne', 'blt', 'bge'):
            lines.append('0x%04x: %-7s x%-2d, x%-2d, 0x%04x' % (pc, m, rs1, rs2, u32(pc + off)))
        elif m == 'jal':
            lines.append('0x%04x: %-7s x%-2d, 0x%04x' % (pc, m, rd, u32(pc + off)))
        elif m == 'lui':
            lines.append('0x%04x: %-7s x%-2d, 0x%x' % (pc, m, rd, (w >> 12) & 0xFFFFF))
        elif m in ('add', 'sub', 'sll', 'slt', 'xor', 'srl', 'sra', 'or', 'and'):
            lines.append('0x%04x: %-7s x%-2d, x%-2d, x%-2d' % (pc, m, rd, rs1, rs2))
        else:
            lines.append('0x%04x: %s' % (pc, m))
    return lines


def run(words, max_steps=2000000):
    """跑到 pass 死循环（同一 PC 连续重复）为止，返回 (CPU, 周期数, 错误)。"""
    c = CPU(words)
    prev_pc, same = None, 0
    for steps in range(1, max_steps + 1):
        err = c.step()
        if err:
            return c, steps, err
        if c.pc == prev_pc:
            same += 1
            if same >= 2:
                return c, steps, None
        else:
            same = 0
        prev_pc = c.pc
    return c, max_steps, '超过 %d 周期未进入 pass 死循环' % max_steps


# ── 各测试程序的期望值（与 .asm 头部注释一致）──────────────────
EXPECT = {
    'inst26_test': (
        {1: 7, 2: 7, 3: 9, 4: 0, 5: 0xC0, 6: 5, 7: 20,
         10: 42, 11: 18, 12: 1, 13: 0, 14: 12, 15: 30, 16: 18,
         17: 120, 18: 7, 19: 7, 20: -30, 21: -8, 22: 0x3FFFFFF8, 23: -120,
         24: 0x12345000, 25: -66, 26: 66, 27: -66, 28: 0, 29: 208, 30: 3, 31: 3},
        {0: 66, 1: -66}),
    'raw_test': (
        {1: 1, 2: 2, 3: 3, 4: 4, 5: 7, 6: 11, 7: 18, 8: 29, 9: 47,
         10: 18, 11: 13, 12: 63, 13: 34, 14: 188, 15: 235, 16: 47, 17: 282,
         20: 0, 21: 100, 22: 100, 23: 200, 24: 200, 25: 300},
        {0: 100, 1: 200}),
    'loaduse_test': (
        {1: 10, 2: 20, 3: 33, 4: 33, 5: 10, 6: 1, 7: 7, 8: 10, 9: 17,
         10: 1, 11: 2, 12: 3, 13: 3, 14: 3, 15: 3, 16: 3, 17: 3, 18: 3, 19: 3},
        {0: 10, 1: 33, 2: 33, 3: 10, 4: 7}),
    'branch_test': (
        {1: 0x54, 2: 5, 3: 8, 4: -5, 10: 55, 11: 11, 12: 11, 15: 3, 16: 99, 17: 0, 19: 9},
        {}),
    'sort16': (
        {28: 0, 29: 15},
        {i: i for i in range(16)}),
}


def verify_one(path, verbose=True):
    """验证单个 .mem；未知程序只打印最终状态。返回是否通过。"""
    words = load_mem(path)
    name = os.path.splitext(os.path.basename(path))[0]
    print('=' * 72)
    print('[%s] %d 条指令' % (name, len(words)))
    c, steps, err = run(words)
    if err:
        print('  仿真错误: %s' % err)
        return False
    ok = True
    if name in EXPECT:
        exp_regs, exp_mem = EXPECT[name]
        for r, v in exp_regs.items():
            if u32(c.regs[r]) != u32(v):
                ok = False
                print('  不一致 x%-2d: 实际 0x%08x (%d)，期望 %d' % (r, c.regs[r], s32(c.regs[r]), v))
        for a, v in exp_mem.items():
            if c.ram[a] != u32(v):
                ok = False
                print('  不一致 mem[%d]: 实际 0x%08x (%d)，期望 %d' % (a, c.ram[a], s32(c.ram[a]), v))
        print('  %s：%d 周期到达 pass，寄存器/内存全部一致' % ('PASS' if ok else 'FAIL', steps))
    else:
        print('  （无内置期望表，已仿真 %d 周期，最终状态如下）' % steps)
        print('  寄存器: ' + ', '.join('x%d=%d' % (i, s32(c.regs[i])) for i in range(32)))
    return ok


def main(argv):
    here = os.path.dirname(os.path.abspath(__file__))
    default_dir = os.path.join(os.path.dirname(here), '测试程序', '机器代码')
    if argv:
        paths = argv if all(os.path.exists(a) for a in argv) else \
            [os.path.join(default_dir, a if a.endswith('.mem') else a + '.mem') for a in argv]
    else:
        paths = [os.path.join(default_dir, n)
                 for n in ('inst26_test.mem', 'raw_test.mem', 'loaduse_test.mem',
                           'branch_test.mem', 'sort16.mem')]
    ok = True
    for p in paths:
        if not os.path.exists(p):
            print('文件不存在: %s' % p)
            ok = False
            continue
        ok &= verify_one(p)
    print('=' * 72)
    print('ALL PASS' if ok else 'SOME CHECKS FAILED')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))