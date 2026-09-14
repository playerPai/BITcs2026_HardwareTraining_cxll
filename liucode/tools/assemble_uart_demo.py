#!/usr/bin/env python3
"""Tiny auditable assembler for uart_sort_demo.asm.

It intentionally supports only the RV32I instructions used by the demo.  The
course can therefore regenerate the .mem file without relying on an online
assembler or copied third-party program.
"""

from pathlib import Path
import re
import sys


def reg(token):
    match = re.fullmatch(r"x(\d+)", token.strip().lower())
    if not match or not 0 <= int(match.group(1)) <= 31:
        raise ValueError(f"invalid register: {token}")
    return int(match.group(1))


def signed(value, bits, what):
    lower = -(1 << (bits - 1))
    upper = (1 << (bits - 1)) - 1
    if not lower <= value <= upper:
        raise ValueError(f"{what} {value} does not fit signed {bits} bits")
    return value & ((1 << bits) - 1)


def encode_i(imm, rs1, funct3, rd, opcode):
    imm = signed(imm, 12, "I immediate")
    return (imm << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def encode_s(imm, rs2, rs1, funct3, opcode=0x23):
    imm = signed(imm, 12, "S immediate")
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | \
           (funct3 << 12) | ((imm & 0x1F) << 7) | opcode


def encode_b(offset, rs2, rs1, funct3, opcode=0x63):
    if offset & 1:
        raise ValueError("branch target must be two-byte aligned")
    imm = signed(offset, 13, "branch offset")
    return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3F) << 25) | \
           (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | \
           (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 1) << 7) | opcode


def encode_j(offset, rd, opcode=0x6F):
    if offset & 1:
        raise ValueError("jump target must be two-byte aligned")
    imm = signed(offset, 21, "jump offset")
    return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21) | \
           (((imm >> 11) & 1) << 20) | (((imm >> 12) & 0xFF) << 12) | \
           (rd << 7) | opcode


def memory_operand(token):
    match = re.fullmatch(r"([^()]+)\((x\d+)\)", token.replace(" ", ""))
    if not match:
        raise ValueError(f"invalid memory operand: {token}")
    return int(match.group(1), 0), reg(match.group(2))


def assemble_instruction(text, pc, labels):
    parts = text.replace(",", " ").split()
    op = parts[0].lower()
    args = parts[1:]

    if op == "lui":
        rd, imm = reg(args[0]), int(args[1], 0)
        if not 0 <= imm < (1 << 20):
            raise ValueError("LUI immediate must be an unsigned 20-bit value")
        return (imm << 12) | (rd << 7) | 0x37
    if op in ("add", "sub"):
        rd, rs1, rs2 = map(reg, args)
        funct7 = 0x20 if op == "sub" else 0x00
        return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | \
               (rd << 7) | 0x33
    if op in ("addi", "andi"):
        rd, rs1, imm = reg(args[0]), reg(args[1]), int(args[2], 0)
        funct3 = 0 if op == "addi" else 7
        return encode_i(imm, rs1, funct3, rd, 0x13)
    if op == "lw":
        rd = reg(args[0])
        imm, rs1 = memory_operand(args[1])
        return encode_i(imm, rs1, 2, rd, 0x03)
    if op == "sw":
        rs2 = reg(args[0])
        imm, rs1 = memory_operand(args[1])
        return encode_s(imm, rs2, rs1, 2)
    if op in ("beq", "bne", "blt", "bge"):
        rs1, rs2 = reg(args[0]), reg(args[1])
        funct3 = {"beq": 0, "bne": 1, "blt": 4, "bge": 5}[op]
        return encode_b(labels[args[2]] - pc, rs2, rs1, funct3)
    if op == "jal":
        return encode_j(labels[args[1]] - pc, reg(args[0]))
    if op == "jalr":
        rd = reg(args[0])
        imm, rs1 = memory_operand(args[1])
        return encode_i(imm, rs1, 0, rd, 0x67)
    raise ValueError(f"unsupported instruction: {text}")


def main():
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("programs/uart_sort_demo.asm")
    output = Path(sys.argv[2]) if len(sys.argv) > 2 else source.with_suffix(".mem")
    labels = {}
    instructions = []
    pc = 0

    for line_no, original in enumerate(source.read_text(encoding="utf-8").splitlines(), 1):
        line = original.split("#", 1)[0].strip()
        if not line:
            continue
        if line.endswith(":"):
            label = line[:-1].strip()
            if label in labels:
                raise ValueError(f"line {line_no}: duplicate label {label}")
            labels[label] = pc
            continue
        instructions.append((line_no, pc, line))
        pc += 4

    words = []
    for line_no, pc, instruction in instructions:
        try:
            words.append(assemble_instruction(instruction, pc, labels))
        except Exception as exc:
            raise ValueError(f"line {line_no}: {exc}") from exc

    output.write_text("".join(f"{word:08x}\n" for word in words), encoding="ascii")
    print(f"assembled {len(words)} instructions: {source} -> {output}")


if __name__ == "__main__":
    main()
