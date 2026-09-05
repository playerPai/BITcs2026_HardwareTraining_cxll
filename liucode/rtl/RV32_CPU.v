`timescale 1ns / 1ps

// Single-cycle RV32I CPU.
// Supported instructions:
// add/sub/slt/and/or/xor/sll/srl/sra,
// addi/ori/andi/xori/slti/slli/srli/srai,
// lw/sw/lui, beq/bne/blt/bge, jal/jalr.
module RV32_CPU #(
    parameter IMEM_FILE = "inst26_test.mem"
)(
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    output wire [31:0] x31_out
);
    wire [31:0] instr;
    wire [31:0] pc;
    wire [31:0] pc_plus4;
    wire [31:0] pc_next;
    wire [4:0] rs1 = instr[19:15];
    wire [4:0] rs2 = instr[24:20];
    wire [4:0] rd  = instr[11:7];
    wire reg_we;
    wire branch;
    wire dmem_we;
    wire alu_src;
    wire [2:0] imm_sel;
    wire [1:0] wb_sel;
    wire [3:0] alu_op;
    wire [31:0] rd1;
    wire [31:0] rd2;
    wire [31:0] imm;
    wire [31:0] br_off;
    wire [31:0] j_off;
    wire [31:0] imm_u;
    wire [31:0] alu_b;
    wire [31:0] alu_y;
    wire [31:0] dmem_rdata;
    wire [31:0] wb_data;
    wire take_branch;
    wire jump;
    wire [31:0] jmp_addr;
    reg [31:0] instruction_result;
    reg display_we;

    pc_reg u_pc (
        .clk(clk), .rst(reset), .en(enable), .pc_next(pc_next), .pc(pc)
    );
    assign pc_plus4 = pc + 32'd4;

    imem #(.IMEM_FILE(IMEM_FILE)) u_imem (
        .addr(pc), .instr(instr)
    );

    ctrl u_ctrl (
        .instr(instr), .dmem_we(dmem_we), .imm_sel(imm_sel),
        .alu_op(alu_op), .alu_src(alu_src), .branch(branch),
        .reg_we(reg_we), .wb_sel(wb_sel), .jump(jump)
    );

    imm_gen u_imm_gen (
        .instr(instr), .imm_sel(imm_sel), .imm(imm),
        .br_off(br_off), .j_off(j_off), .imm_u(imm_u)
    );

    regfile u_regfile (
        .clk(clk), .rst(reset), .en(enable), .we(reg_we),
        .ra1(rs1), .ra2(rs2), .rd1(rd1), .rd2(rd2),
        .wd(wb_data), .wa(rd),
        .display_we(display_we), .display_data(instruction_result),
        .x31_out(x31_out)
    );

    assign alu_b = alu_src ? imm : rd2;
    alu u_alu (
        .a(rd1), .b(alu_b), .alu_op(alu_op), .y(alu_y)
    );

    dmem u_dmem (
        .clk(clk), .addr(alu_y), .we(dmem_we & ~reset & enable),
        .rdata(dmem_rdata), .wdata(rd2)
    );

    br_unit u_br_unit (
        .branch(branch), .funct3(instr[14:12]),
        .rs1_val(rd1), .rs2_val(rd2), .take_branch(take_branch)
    );

    assign wb_data = (wb_sel == 2'b00) ? alu_y :
                     (wb_sel == 2'b01) ? dmem_rdata :
                     (wb_sel == 2'b10) ? pc_plus4 : imm_u;

    // JAL target is PC-relative. JALR target is (rs1 + imm) with bit 0 clear.
    assign jmp_addr = (instr[6:0] == 7'b1101111)
                    ? (pc + j_off) : (alu_y & 32'hfffffffe);
    assign pc_next = take_branch ? (pc + br_off)
                   : jump       ? jmp_addr
                                : pc_plus4;

    // x31 is reserved as an instruction-result monitor for the board display.
    // Arithmetic/load/LUI show their write-back value, store shows stored data,
    // branch shows 1/0 for taken/not-taken, and jumps show link/target values.
    // The terminal "beq x0,x0,0" hold instruction does not overwrite the last
    // useful result, so the final value remains visible.
    always @(*) begin
        instruction_result = 32'b0;
        display_we = 1'b1;
        case (instr[6:0])
            7'b0110011, // R-type
            7'b0010011, // I-type
            7'b0000011, // LW
            7'b0110111: instruction_result = wb_data; // LUI
            7'b0100011: instruction_result = rd2; // SW: stored word
            7'b1100011: instruction_result = {31'b0, take_branch};
            7'b1101111: instruction_result = pc_plus4; // JAL link value
            7'b1100111: instruction_result = (rd != 0) ? pc_plus4 : jmp_addr;
            default: begin
                instruction_result = x31_out;
                display_we = 1'b0;
            end
        endcase
        if (instr == 32'h00000063)
            display_we = 1'b0;
    end
endmodule

module pc_reg(
    input wire clk,
    input wire rst,
    input wire en,
    input wire [31:0] pc_next,
    output reg [31:0] pc
);
    always @(posedge clk or posedge rst) begin
        if (rst) pc <= 32'b0;
        else if (en) pc <= pc_next;
    end
endmodule

module imem #(
    parameter IMEM_FILE = "inst26_test.mem"
)(
    input wire [31:0] addr,
    output wire [31:0] instr
);
    reg [31:0] rom [0:255];
    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1)
            rom[i] = 32'h00000013;
        $readmemh(IMEM_FILE, rom);
    end
    assign instr = (addr[31:10] == 0 && addr[1:0] == 0)
                 ? rom[addr[9:2]] : 32'h00000013;
endmodule

module dmem(
    input wire clk,
    input wire we,
    input wire [31:0] addr,
    input wire [31:0] wdata,
    output wire [31:0] rdata
);
    reg [31:0] ram [0:511];
    integer i;
    initial begin
        for (i = 0; i < 512; i = i + 1)
            ram[i] = 32'b0;
    end
    always @(posedge clk) begin
        if (we) ram[addr[10:2]] <= wdata;
    end
    assign rdata = ram[addr[10:2]];
endmodule

module regfile(
    input wire clk,
    input wire rst,
    input wire en,
    input wire we,
    input wire [4:0] ra1,
    input wire [4:0] ra2,
    input wire [4:0] wa,
    input wire [31:0] wd,
    output wire [31:0] rd1,
    output wire [31:0] rd2,
    input wire display_we,
    input wire [31:0] display_data,
    output wire [31:0] x31_out
);
    reg [31:0] regs [0:31];
    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1)
            regs[i] = 32'b0;
    end
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'b0;
        end else if (en) begin
            // x31 is not a general-purpose destination in the board tests.
            if (we && (wa != 5'd0) && (wa != 5'd31))
                regs[wa] <= wd;
            if (display_we)
                regs[31] <= display_data;
        end
    end
    assign rd1 = (ra1 == 5'd0) ? 32'b0 : regs[ra1];
    assign rd2 = (ra2 == 5'd0) ? 32'b0 : regs[ra2];
    assign x31_out = regs[31];
endmodule

module alu(
    input wire [3:0] alu_op,
    input wire [31:0] a,
    input wire [31:0] b,
    output reg [31:0] y
);
    localparam ALU_ADD = 4'b0000;
    localparam ALU_SLL = 4'b0001;
    localparam ALU_SLT = 4'b0010;
    localparam ALU_XOR = 4'b0100;
    localparam ALU_SRL = 4'b0101;
    localparam ALU_OR  = 4'b0110;
    localparam ALU_AND = 4'b0111;
    localparam ALU_SUB = 4'b1000;
    localparam ALU_SRA = 4'b1101;
    always @(*) begin
        case (alu_op)
            ALU_ADD: y = a + b;
            ALU_SUB: y = a - b;
            ALU_SLL: y = a << b[4:0];
            ALU_SLT: y = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            ALU_XOR: y = a ^ b;
            ALU_SRL: y = a >> b[4:0];
            ALU_SRA: y = $signed(a) >>> b[4:0];
            ALU_OR:  y = a | b;
            ALU_AND: y = a & b;
            default: y = 32'b0;
        endcase
    end
endmodule

module imm_gen(
    input wire [31:0] instr,
    input wire [2:0] imm_sel,
    output reg [31:0] imm,
    output wire [31:0] br_off,
    output wire [31:0] j_off,
    output wire [31:0] imm_u
);
    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7],
                         instr[30:25], instr[11:8], 1'b0};
    wire [31:0] imm_j = {{12{instr[31]}}, instr[19:12], instr[20],
                         instr[30:21], 1'b0};
    assign imm_u = {instr[31:12], 12'b0};
    assign br_off = imm_b;
    assign j_off = imm_j;
    always @(*) begin
        case (imm_sel)
            3'b000: imm = imm_i;
            3'b001: imm = imm_s;
            3'b010: imm = imm_b;
            3'b011: imm = imm_u;
            3'b100: imm = imm_j;
            default: imm = 32'b0;
        endcase
    end
endmodule

module br_unit(
    input wire branch,
    input wire [2:0] funct3,
    input wire [31:0] rs1_val,
    input wire [31:0] rs2_val,
    output reg take_branch
);
    always @(*) begin
        take_branch = 1'b0;
        if (branch) begin
            case (funct3)
                3'b000: take_branch = (rs1_val == rs2_val);
                3'b001: take_branch = (rs1_val != rs2_val);
                3'b100: take_branch = ($signed(rs1_val) < $signed(rs2_val));
                3'b101: take_branch = ($signed(rs1_val) >= $signed(rs2_val));
                default: take_branch = 1'b0;
            endcase
        end
    end
endmodule

module ctrl(
    input wire [31:0] instr,
    output reg reg_we,
    output reg dmem_we,
    output reg alu_src,
    output reg branch,
    output reg jump,
    output reg [2:0] imm_sel,
    output reg [1:0] wb_sel,
    output reg [3:0] alu_op
);
    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];
    wire [6:0] funct7 = instr[31:25];
    localparam OPC_R    = 7'b0110011;
    localparam OPC_I    = 7'b0010011;
    localparam OPC_LW   = 7'b0000011;
    localparam OPC_SW   = 7'b0100011;
    localparam OPC_BR   = 7'b1100011;
    localparam OPC_JAL  = 7'b1101111;
    localparam OPC_JALR = 7'b1100111;
    localparam OPC_LUI  = 7'b0110111;
    localparam IMM_I = 3'b000, IMM_S = 3'b001, IMM_B = 3'b010,
               IMM_U = 3'b011, IMM_J = 3'b100;
    localparam WB_ALU = 2'b00, WB_MEM = 2'b01, WB_PC4 = 2'b10,
               WB_UIMM = 2'b11;
    localparam ALU_ADD = 4'b0000, ALU_SLL = 4'b0001,
               ALU_SLT = 4'b0010, ALU_XOR = 4'b0100,
               ALU_SRL = 4'b0101, ALU_OR  = 4'b0110,
               ALU_AND = 4'b0111, ALU_SUB = 4'b1000,
               ALU_SRA = 4'b1101;

    function [3:0] r_alu_func;
        input [9:0] fc;
        begin
            case (fc)
                10'b0000000_000: r_alu_func = ALU_ADD;
                10'b0100000_000: r_alu_func = ALU_SUB;
                10'b0000000_001: r_alu_func = ALU_SLL;
                10'b0000000_010: r_alu_func = ALU_SLT;
                10'b0000000_100: r_alu_func = ALU_XOR;
                10'b0000000_101: r_alu_func = ALU_SRL;
                10'b0100000_101: r_alu_func = ALU_SRA;
                10'b0000000_110: r_alu_func = ALU_OR;
                10'b0000000_111: r_alu_func = ALU_AND;
                default: r_alu_func = ALU_ADD;
            endcase
        end
    endfunction

    always @(*) begin
        reg_we = 1'b0;
        dmem_we = 1'b0;
        alu_src = 1'b0;
        branch = 1'b0;
        jump = 1'b0;
        imm_sel = IMM_I;
        wb_sel = WB_ALU;
        alu_op = ALU_ADD;
        case (opcode)
            OPC_R: begin
                reg_we = 1'b1;
                alu_op = r_alu_func({funct7, funct3});
            end
            OPC_I: begin
                reg_we = 1'b1;
                alu_src = 1'b1;
                case (funct3)
                    3'b000: alu_op = ALU_ADD;
                    3'b001: alu_op = ALU_SLL;
                    3'b010: alu_op = ALU_SLT;
                    3'b100: alu_op = ALU_XOR;
                    3'b101: alu_op = funct7[5] ? ALU_SRA : ALU_SRL;
                    3'b110: alu_op = ALU_OR;
                    3'b111: alu_op = ALU_AND;
                    default: alu_op = ALU_ADD;
                endcase
            end
            OPC_LW: begin
                reg_we = 1'b1;
                alu_src = 1'b1;
                wb_sel = WB_MEM;
            end
            OPC_SW: begin
                dmem_we = 1'b1;
                alu_src = 1'b1;
                imm_sel = IMM_S;
            end
            OPC_BR: begin
                branch = 1'b1;
                imm_sel = IMM_B;
                alu_op = ALU_SUB;
            end
            OPC_JAL: begin
                reg_we = 1'b1;
                wb_sel = WB_PC4;
                jump = 1'b1;
                imm_sel = IMM_J;
            end
            OPC_JALR: begin
                reg_we = 1'b1;
                wb_sel = WB_PC4;
                alu_src = 1'b1;
                jump = 1'b1;
            end
            OPC_LUI: begin
                reg_we = 1'b1;
                wb_sel = WB_UIMM;
                imm_sel = IMM_U;
            end
            default: begin end
        endcase
    end
endmodule
