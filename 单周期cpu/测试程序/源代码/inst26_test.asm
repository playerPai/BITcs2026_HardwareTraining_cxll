# L1: inst26_test.asm
# 26-instruction exhaustive test for the pipelined CPU
# Instruction set: add sub slt and or xor sll srl sra / addi ori andi xori slti slli srli srai
#                  / lw sw lui / beq bne blt bge / jal jalr
# Rules: RV32I standard instructions ONLY. No pseudo-instructions, no ecall.
# Verification: run to completion, then compare registers with the expected table
# at the end of this file. x4 stays 0 if all branches behaved correctly.

# ================= control type: beq bne blt bge =================
addi x1, x0, 7          # x1 = 7
addi x2, x0, 7          # x2 = 7
addi x3, x0, 9          # x3 = 9

beq  x1, x2, ok_beq     # 7==7 -> must branch
addi x4, x0, 1          # error marker: must NOT execute
ok_beq:

bne  x1, x3, ok_bne     # 7!=9 -> must branch
addi x4, x0, 2          # error marker: must NOT execute
ok_bne:

blt  x1, x3, ok_blt     # 7<9  -> must branch
addi x4, x0, 3          # error marker: must NOT execute
ok_blt:

blt  x3, x1, fail       # 9<7  -> must NOT branch (signed compare)
bge  x3, x3, ok_bge     # 9>=9 -> must branch
addi x4, x0, 4          # error marker: must NOT execute
ok_bge:

bge  x1, x3, fail       # 7>=9 -> must NOT branch

# ================= R type: add sub slt and or xor sll srl sra =================
addi x31, x0, 30        # A = 30
addi x30, x0, 12        # B = 12
addi x29, x0, 2         # SH = 2

add  x10, x31, x30      # x10 = 30 + 12 = 42
sub  x11, x31, x30      # x11 = 30 - 12 = 18
slt  x12, x30, x31      # x12 = (12 < 30) = 1
slt  x13, x31, x30      # x13 = (30 < 12) = 0
and  x14, x31, x30      # x14 = 30 & 12 = 12
or   x15, x31, x30      # x15 = 30 | 12 = 30
xor  x16, x31, x30      # x16 = 30 ^ 12 = 18
sll  x17, x31, x29      # x17 = 30 << 2  = 120
srl  x18, x31, x29      # x18 = 30 >> 2  = 7  (logical)
sra  x19, x31, x29      # x19 = 30 >> 2  = 7  (arithmetic, positive)
sub  x20, x0, x31       # x20 = -30
sra  x21, x20, x29      # x21 = -30 >> 2 = -8 (arithmetic, sign-extended)
srl  x22, x20, x29      # x22 = -30 >>> 2 = 0x3FFFFFF8 (logical)
sll  x23, x20, x29      # x23 = -30 << 2  = -120

# ================= I type: addi ori andi xori slli srli srai slti =================
addi x28, x0, 13        # C = 13
addi x24, x28, 100      # x24 = 13 + 100 = 113
ori  x25, x28, 2        # x25 = 13 | 2 = 15
andi x26, x28, 10       # x26 = 13 & 10 = 8
xori x27, x28, 5        # x27 = 13 ^ 5 = 8
slli x29, x28, 4        # x29 = 13 << 4 = 208 (overwrites SH)
srli x30, x28, 2        # x30 = 13 >> 2 = 3  (overwrites B)
srai x31, x28, 2        # x31 = 13 >> 2 = 3  (overwrites A)
slti x28, x28, 10       # x28 = (13 < 10) = 0 (overwrites C)

# ================= lui / load-store =================
lui  x24, 0x12345       # x24 = 0x12345000 (overwrites addi result)
addi x28, x0, 0         # base = 0
addi x25, x0, 66
sw   x25, 0(x28)        # mem[0] = 66
addi x25, x0, -66
sw   x25, 4(x28)        # mem[1] = -66 (negative store)
lw   x26, 0(x28)        # x26 = 66
lw   x27, 4(x28)        # x27 = -66 (sign-extension through load)

# ================= jump/link: jal jalr =================
jal  x5, sub_ret        # x5 = return address, jump to sub_ret
addi x6, x0, 5          # return marker
pass:
beq  x0, x0, pass       # endless loop = test finished OK

sub_ret:
addi x7, x0, 20
jalr x0, 0(x5)          # jump back to the instruction after jal

fail:
beq  x0, x0, fail       # endless loop = test FAILED (should never be reached)

# =====================================================================
# Expected final register values:
#   x1=7  x2=7  x3=9  x4=0(no branch error)  x5=return addr  x6=5  x7=20
#   x10=42 x11=18 x12=1 x13=0 x14=12 x15=30 x16=18
#   x17=120 x18=7 x19=7 x20=-30 x21=-8 x22=0x3FFFFFF8 x23=-120
#   x24=0x12345000 x25=-66 x26=66 x27=-66 x28=0 x29=208 x30=3 x31=3
# Memory: mem[0]=66, mem[1]=-66
# =====================================================================