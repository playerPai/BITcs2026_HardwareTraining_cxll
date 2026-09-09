`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 工程名 : 流水线 CPU（5 级：IF / ID / EX / MEM / WB）
// 文件   : PipelineCPU.v
// 说明   : 在单周期 CPU（CPU.v）基础上改造的五级流水线，指令集不变
//          （RV32I 子集 26 条）。相对单周期新增：
//            1) 四组流水寄存器：IF/ID、ID/EX、EX/MEM、MEM/WB
//            2) pipe_forwarding_unit：EX/MEM、MEM/WB 两级前递，解决 RAW 数据冒险
//            3) pipe_hazard_unit    ：load-use 检测，冻结 PC 与 IF/ID，向 ID/EX 注气泡
//            4) 分支/跳转在 EX 级解决：taken 或 jal/jalr 时重定向 PC，
//               并冲刷 IF/ID、ID/EX（taken 代价 2 拍）
//            5) pipe_regfile 增加写穿透旁路（WB 写回与 ID 读取同拍时直接返回写数据）
//          指令存储器从 inst.mem 加载，配合 切换测试程序_流水线.ps1 一键切换测试。
//////////////////////////////////////////////////////////////////////////////////

// ================================ 顶层 ================================
// 工程统一接口：与单周期 RV32_CPU 使用相同的参数和板级端口，并额外
// 暴露退休级信息，供 tb_cpu_performance 准确区分有效指令、停顿和气泡。
module RV32_Pipeline #(
    parameter IMEM_FILE = "inst26_test.mem"
)(
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    output reg  [31:0] x31_out,
    output wire        retire_valid,
    output wire [31:0] retire_pc,
    output wire [31:0] retire_instr
    );
    // ---------------- 取指 IF ----------------
    wire [31:0] pc_f;                 // 当前取指地址
    wire [31:0] pc_plus4_f = pc_f + 32'd4;
    wire [31:0] instr_f;              // 指令存储器取出的指令
    wire        ex_redirect;          // EX 级要求重定向 PC（分支 taken / jal / jalr）
    wire [31:0] ex_target;            // 重定向目标地址
    wire        stall;                // load-use 停顿标志
    wire        pc_en = enable && ~stall; // 板级步进关闭或冒险停顿时冻结 PC
    wire [31:0] pc_next = ex_redirect ? ex_target : pc_plus4_f;

    // 跨级连线（统一提前声明，供各流水段实例引用）
    wire [31:0] pc4_d;                    // ID 段的 PC+4
    wire [31:0] pc4_e;                    // EX 段的 PC+4（jal/jalr 的写回值）
    wire [31:0] exmem_alu_y, exmem_store_data, exmem_wb_val;
    wire [4:0]  exmem_rd, wb_rd;
    wire        exmem_reg_we, exmem_dmem_we, wb_reg_we;
    wire [1:0]  exmem_wb_sel;
    wire [31:0] wb_data;

    pipe_pc_reg u_pc(
        .clk(clk), .rst(reset),
        .en(pc_en),
        .pc_next(pc_next),
        .pc(pc_f)
    );

    pipe_imem #(.IMEM_FILE(IMEM_FILE)) u_imem(
        .addr(pc_f),
        .instr(instr_f)
    );

    // ---------------- IF/ID 流水寄存器 ----------------
    wire [31:0] pc_d;
    wire [31:0] instr_d;
    pipe_if_id_reg u_if_id(
        .clk(clk), .rst(reset), .enable(enable),
        .flush(ex_redirect),          // 冲刷：注入 NOP
        .stall(stall),                // 停顿：保持原值
        .pc_in(pc_f),  .instr_in(instr_f),
        .pc_out(pc_d), .instr_out(instr_d)
    );

    // ---------------- 译码 ID ----------------
    assign pc4_d = pc_d + 32'd4;          // jal/jalr 的写回值 PC+4（随流水带下去）
    // 控制器 / 立即数生成与单周期完全相同，只是位置移到 ID 级
    wire        reg_we_d, dmem_we_d, alu_src_d, branch_d, jump_d;
    wire [2:0]  imm_sel_d;
    wire [1:0]  wb_sel_d;
    wire [3:0]  alu_op_d;
    wire [31:0] imm_d;                // 按 imm_sel 选出的立即数：
                                      //   分支指令=>B型偏移，jal=>J型偏移，jalr=>I型
    pipe_ctrl u_ctrl(
        .instr(instr_d),
        .reg_we(reg_we_d), .dmem_we(dmem_we_d), .alu_src(alu_src_d),
        .branch(branch_d), .jump(jump_d),
        .imm_sel(imm_sel_d), .wb_sel(wb_sel_d), .alu_op(alu_op_d)
    );
    pipe_imm_gen u_imm_gen(
        .instr(instr_d), .imm_sel(imm_sel_d), .imm(imm_d)
    );

    // 读寄存器堆（写端口来自 WB 级，模块内部带写穿透旁路）
    wire [31:0] rd1_d, rd2_d;
    pipe_regfile u_regfile(
        .clk(clk), .rst(reset),
        .we(wb_reg_we && enable), .wa(wb_rd), .wd(wb_data), // 写：来自 WB 级
        .ra1(instr_d[19:15]), .ra2(instr_d[24:20]), // 读：当前指令的 rs1/rs2
        .rd1(rd1_d), .rd2(rd2_d)
    );

    wire        jal_sel_d = (instr_d[6:0] == 7'b1101111); // 是否 jal（EX 区分跳转目标）

    // ---------------- ID/EX 流水寄存器 ----------------
    wire [31:0] pc_e, rd1_e, rd2_e, imm_e;
    wire [4:0]  rs1_e, rs2_e, rd_e;
    wire [2:0]  funct3_e;
    wire        reg_we_e, dmem_we_e, alu_src_e, branch_e, jump_e, jal_sel_e;
    wire [1:0]  wb_sel_e;
    wire [3:0]  alu_op_e;
    pipe_id_ex_reg u_id_ex(
        .clk(clk), .rst(reset), .enable(enable),
        .flush(ex_redirect || stall),   // 冲刷或停顿都注入气泡（控制信号清零）
        // 透传数据
        .pc_in(pc_d),      .pc_out(pc_e),
        .pc4_in(pc4_d),    .pc4_out(pc4_e),
        .rd1_in(rd1_d),    .rd1_out(rd1_e),
        .rd2_in(rd2_d),    .rd2_out(rd2_e),
        .imm_in(imm_d),    .imm_out(imm_e),
        .rs1_in(instr_d[19:15]), .rs1_out(rs1_e),
        .rs2_in(instr_d[24:20]), .rs2_out(rs2_e),
        .rd_in(instr_d[11:7]),   .rd_out(rd_e),
        .funct3_in(instr_d[14:12]), .funct3_out(funct3_e),
        .jal_sel_in(jal_sel_d),     .jal_sel_out(jal_sel_e),
        // 控制信号
        .reg_we_in(reg_we_d),   .reg_we_out(reg_we_e),
        .dmem_we_in(dmem_we_d), .dmem_we_out(dmem_we_e),
        .alu_src_in(alu_src_d), .alu_src_out(alu_src_e),
        .branch_in(branch_d),   .branch_out(branch_e),
        .jump_in(jump_d),       .jump_out(jump_e),
        .wb_sel_in(wb_sel_d),   .wb_sel_out(wb_sel_e),
        .alu_op_in(alu_op_d),   .alu_op_out(alu_op_e)
    );

    // ---------------- 执行 EX ----------------
    // 前递多路选择：10=来自 EX/MEM（上一条），01=来自 MEM/WB（上上条），00=寄存器堆
    wire [1:0]  forward_a, forward_b;
    pipe_forwarding_unit u_forwarding(
        .id_ex_rs1(rs1_e), .id_ex_rs2(rs2_e),
        .exmem_reg_we(exmem_reg_we), .exmem_rd(exmem_rd),
        .memwb_reg_we(wb_reg_we),    .memwb_rd(wb_rd),
        .forward_a(forward_a), .forward_b(forward_b)
    );
    wire [31:0] fwd_a = (forward_a == 2'b10) ? exmem_wb_val  :
                        (forward_a == 2'b01) ? wb_data       : rd1_e;
    wire [31:0] fwd_b = (forward_b == 2'b10) ? exmem_wb_val  :
                        (forward_b == 2'b01) ? wb_data       : rd2_e;

    wire [31:0] alu_b = alu_src_e ? imm_e : fwd_b;   // I 型/S 型/lw/sw 用立即数
    wire [31:0] alu_y_e;
    pipe_alu u_alu(
        .alu_op(alu_op_e),
        .a(fwd_a), .b(alu_b),
        .y(alu_y_e)
    );

    // 分支条件判断：操作数用前递后的值（紧随其后的相关分支也能正确判断）
    wire take_branch;
    pipe_br_unit u_br_unit(
        .branch(branch_e),
        .funct3(funct3_e),
        .rs1_val(fwd_a), .rs2_val(fwd_b),
        .take_branch(take_branch)
    );

    // EX 级重定向：条件分支 taken，或无条件跳转
    assign ex_redirect = take_branch | jump_e;
    // 目标地址：分支与 jal 都是 PC + 立即数（imm_d 在 ID 级已按类型选好）；
    // jalr 目标 = (rs1 + imm) 且 bit0 清零
    wire [31:0] branch_target = pc_e + imm_e;
    // Keep the JALR target adder independent of the general ALU.  Reusing
    // alu_y_e makes the PC path pass through ALU-operation and operand-B
    // selection even though JALR always computes rs1 + imm.
    wire [31:0] jalr_target   = (fwd_a + imm_e) & 32'hFFFFFFFE;
    assign ex_target = jump_e ? (jal_sel_e ? branch_target : jalr_target)
                              : branch_target;

    // EX 段就能确定的写回值：ALU 结果 / U 型立即数 / PC+4
    // （lw 的数据要 MEM 级之后才有；load-use 停顿保证它不会从 EX/MEM 被前递）
    wire [31:0] ex_wb_val = (wb_sel_e == 2'b11) ? imm_e :
                            (wb_sel_e == 2'b10) ? pc4_e : alu_y_e;

    // ---------------- EX/MEM 流水寄存器 ----------------
    pipe_ex_mem_reg u_ex_mem(
        .clk(clk), .rst(reset), .enable(enable),
        .alu_y_in(alu_y_e),        .alu_y_out(exmem_alu_y),
        .store_in(fwd_b),          .store_out(exmem_store_data), // sw 的写入数据
        .wb_val_in(ex_wb_val),     .wb_val_out(exmem_wb_val),    // 可前递的写回值
        .rd_in(rd_e),              .rd_out(exmem_rd),
        .reg_we_in(reg_we_e),      .reg_we_out(exmem_reg_we),
        .dmem_we_in(dmem_we_e),    .dmem_we_out(exmem_dmem_we),
        .wb_sel_in(wb_sel_e),      .wb_sel_out(exmem_wb_sel)
    );

    // ---------------- 访存 MEM ----------------
    wire [31:0] mem_rdata;
    pipe_dmem u_dmem(
        .clk(clk),
        .we(exmem_dmem_we && enable),
        .addr(exmem_alu_y),
        .wdata(exmem_store_data),
        .rdata(mem_rdata)
    );

    // ---------------- MEM/WB 流水寄存器 ----------------
    pipe_mem_wb_reg u_mem_wb(
        .clk(clk), .rst(reset), .enable(enable),
        .wb_val_in(exmem_wb_val),  // ALU / U 型立即数 / PC+4
        .mem_in(mem_rdata),        // lw 读出的数据
        .wb_sel_in(exmem_wb_sel),
        .rd_in(exmem_rd),
        .reg_we_in(exmem_reg_we),
        .wb_data_out(wb_data),     // 写回值在这里做最终选择
        .rd_out(wb_rd),
        .reg_we_out(wb_reg_we)
    );
    // WB：regfile 写端口已在上面连接（we=wb_reg_we, wa=wb_rd, wd=wb_data）

    // ---------------- 冒险检测 ----------------
    pipe_hazard_unit u_hazard(
        .id_ex_reg_we(reg_we_e),
        .id_ex_wb_sel(wb_sel_e),
        .id_ex_rd(rd_e),
        .if_id_instr(instr_d),
        .stall(stall)
    );

    // ---------------- 退休跟踪与板级显示 ----------------
    // 原始流水线没有有效位；仅靠 NOP 无法区分真实 NOP 与停顿/冲刷气泡。
    // 这里单独流水化 valid、PC 和 instruction，不改变原数据通路。
    reg        valid_d, valid_e, valid_m, valid_w;
    reg [31:0] instr_e, instr_m, instr_w;
    reg [31:0] pc_m, pc_w;
    reg [31:0] monitor_value_m, monitor_value_w;
    reg        monitor_we_m, monitor_we_w;
    reg        monitor_use_wb_m, monitor_use_wb_w;

    reg [31:0] monitor_value_e;
    reg        monitor_we_e;
    reg        monitor_use_wb_e;

    always @(*) begin
        monitor_value_e  = 32'b0;
        monitor_we_e     = 1'b1;
        monitor_use_wb_e = 1'b0;
        case (instr_e[6:0])
            7'b0110011, // R-type
            7'b0010011, // I-type
            7'b0000011, // LW: wb_data 在 WB 级才包含访存结果
            7'b0110111, // LUI
            7'b1101111: monitor_use_wb_e = 1'b1; // JAL link
            7'b0100011: monitor_value_e = fwd_b; // SW data
            7'b1100011: monitor_value_e = {31'b0, take_branch};
            7'b1100111: begin
                if (rd_e != 5'd0)
                    monitor_use_wb_e = 1'b1;
                else
                    monitor_value_e = jalr_target;
            end
            default: monitor_we_e = 1'b0;
        endcase
        // 终止哨兵只保持 PC，不覆盖最后一个有用结果。
        if (instr_e == 32'h00000063)
            monitor_we_e = 1'b0;
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            valid_d <= 1'b0;
            valid_e <= 1'b0;
            valid_m <= 1'b0;
            valid_w <= 1'b0;
            instr_e <= 32'h00000013;
            instr_m <= 32'h00000013;
            instr_w <= 32'h00000013;
            pc_m <= 32'b0;
            pc_w <= 32'b0;
            monitor_value_m <= 32'b0;
            monitor_value_w <= 32'b0;
            monitor_we_m <= 1'b0;
            monitor_we_w <= 1'b0;
            monitor_use_wb_m <= 1'b0;
            monitor_use_wb_w <= 1'b0;
            x31_out <= 32'b0;
        end else if (enable) begin
            if (ex_redirect) begin
                valid_d <= 1'b0;
            end else if (!stall) begin
                valid_d <= 1'b1;
            end

            if (ex_redirect || stall) begin
                valid_e <= 1'b0;
                instr_e <= 32'h00000013;
            end else begin
                valid_e <= valid_d;
                instr_e <= instr_d;
            end

            valid_m <= valid_e;
            instr_m <= instr_e;
            pc_m <= pc_e;
            monitor_value_m <= monitor_value_e;
            monitor_we_m <= monitor_we_e;
            monitor_use_wb_m <= monitor_use_wb_e;

            valid_w <= valid_m;
            instr_w <= instr_m;
            pc_w <= pc_m;
            monitor_value_w <= monitor_value_m;
            monitor_we_w <= monitor_we_m;
            monitor_use_wb_w <= monitor_use_wb_m;

            if (valid_w && monitor_we_w)
                x31_out <= monitor_use_wb_w ? wb_data : monitor_value_w;
        end
    end

    assign retire_valid = enable && valid_w;
    assign retire_pc    = pc_w;
    assign retire_instr = instr_w;

endmodule

// ============================ PC 寄存器 ============================
// 与单周期版差别：增加 en 使能，load-use 停顿时冻结
module pipe_pc_reg(
    input wire clk,
    input wire rst,
    input wire en,
    input wire [31:0] pc_next,
    output reg [31:0] pc
    );
    always @(posedge clk or posedge rst) begin
        if (rst)          pc <= 32'b0;
        else if (en)      pc <= pc_next;   // en=0 时保持原值（停顿）
    end
endmodule

// ============================ 指令存储器 ============================
module pipe_imem #(
    parameter IMEM_FILE = "inst26_test.mem"
)(
    input wire [31:0] addr,
    output wire [31:0] instr
    );
    reg [31:0] rom [0:255];
    initial begin
        $readmemh(IMEM_FILE, rom);
    end
    assign instr = rom[addr[9:2]];    // 256 words, word addressed
endmodule

// ============================ 数据存储器 ============================
module pipe_dmem(
    input wire clk,
    input wire we,
    input wire [31:0] addr,
    input wire [31:0] wdata,
    output wire [31:0] rdata
    );
    reg [31:0] ram [0:511];           // 512 字（sort16 需要 16 字以上）
    integer i;
    initial begin
        for (i = 0; i < 512; i = i + 1)
            ram[i] = 32'b0;
    end
    always @(posedge clk) begin      // MEM 级上升沿写入
        if (we)
            ram[addr[10:2]] <= wdata;
    end
    assign rdata = ram[addr[10:2]];  // 异步读（组合逻辑）
endmodule

// ============================ 寄存器堆 ============================
// 与单周期版差别：增加写穿透旁路——
//   WB 级正在写的寄存器如果恰好是 ID 级要读的寄存器，
//   直接把写数据旁路给读出端（否则读到旧值，流水线会差一拍）
module pipe_regfile(
    input wire clk,
    input wire rst,
    input wire we,
    input wire [4:0] ra1,
    input wire [4:0] ra2,
    input wire [4:0] wa,
    input wire [31:0] wd,
    output wire [31:0] rd1,
    output wire [31:0] rd2
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
        end else if (we && (wa != 5'd0)) begin
            regs[wa] <= wd;
        end
    end
    // x0 恒零；写穿透：同拍写入的寄存器读出写数据
    assign rd1 = (ra1 == 5'd0) ? 32'b0 :
                 (we && (wa == ra1)) ? wd : regs[ra1];
    assign rd2 = (ra2 == 5'd0) ? 32'b0 :
                 (we && (wa == ra2)) ? wd : regs[ra2];
endmodule

// ============================ ALU ============================
// 与单周期完全一致：4 位函数码，9 种运算
module pipe_alu(
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
            ALU_OR : y = a | b;
            ALU_AND: y = a & b;
            default: y = 32'b0;
        endcase
    end
endmodule

// ============================ 立即数生成器 ============================
// 与单周期完全一致：五种立即数（I/S/B/U/J），imm 端口按 imm_sel 输出
module pipe_imm_gen(
    input wire [31:0] instr,
    input wire [2:0] imm_sel,
    output reg [31:0] imm,
    output wire [31:0] br_off,   // 保留端口（与单周期一致），本设计未用
    output wire [31:0] j_off,
    output wire [31:0] imm_u
    );
    wire [31:0] imm_i;
    wire [31:0] imm_s;
    wire [31:0] imm_b;
    wire [31:0] imm_j;
    assign imm_i = {{20{instr[31]}}, instr[31:20]};
    assign imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    assign imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
    assign imm_u = {instr[31:12], 12'b0};
    assign imm_j = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};
    assign br_off = imm_b;
    assign j_off = imm_j;
    always @(*) begin
        case (imm_sel)
            3'b000:  imm = imm_i;
            3'b001:  imm = imm_s;
            3'b010:  imm = imm_b;
            3'b011:  imm = imm_u;
            3'b100:  imm = imm_j;
            default: imm = 32'b0;
        endcase
    end
endmodule

// ============================ 分支单元 ============================
// 与单周期完全一致，位置移到 EX 级，操作数用前递后的值
module pipe_br_unit(
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
                3'b000:  take_branch = (rs1_val == rs2_val);                    // beq
                3'b001:  take_branch = (rs1_val != rs2_val);                    // bne
                3'b100:  take_branch = ($signed(rs1_val) <  $signed(rs2_val));  // blt
                3'b101:  take_branch = ($signed(rs1_val) >= $signed(rs2_val));  // bge
                default: take_branch = 1'b0;
            endcase
        end
    end
endmodule

// ============================ 控制器 ============================
// 与单周期完全一致，位置移到 ID 级
module pipe_ctrl(
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
    wire [6:0] opcode;
    wire [2:0] funct3;
    wire [6:0] funct7;
    assign opcode = instr[6:0];
    assign funct3 = instr[14:12];
    assign funct7 = instr[31:25];
    localparam OPC_R    = 7'b0110011;
    localparam OPC_I    = 7'b0010011;
    localparam OPC_LW   = 7'b0000011;
    localparam OPC_SW   = 7'b0100011;
    localparam OPC_BR   = 7'b1100011;
    localparam OPC_JAL  = 7'b1101111;
    localparam OPC_JALR = 7'b1100111;
    localparam OPC_LUI  = 7'b0110111;
    localparam IMM_I   = 3'b000;
    localparam IMM_S   = 3'b001;
    localparam IMM_B   = 3'b010;
    localparam IMM_U   = 3'b011;
    localparam IMM_J   = 3'b100;
    localparam WB_ALU  = 2'b00;
    localparam WB_MEM  = 2'b01;
    localparam WB_PC4  = 2'b10;
    localparam WB_UIMM = 2'b11;
    localparam ALU_ADD = 4'b0000;
    localparam ALU_SLL = 4'b0001;
    localparam ALU_SLT = 4'b0010;
    localparam ALU_XOR = 4'b0100;
    localparam ALU_SRL = 4'b0101;
    localparam ALU_OR  = 4'b0110;
    localparam ALU_AND = 4'b0111;
    localparam ALU_SUB = 4'b1000;
    localparam ALU_SRA = 4'b1101;

    // R 型 {funct7,funct3} -> ALU 函数码
    function [3:0] r_alu_func;
        input [9:0] fc;
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
            default:         r_alu_func = ALU_ADD;
        endcase
    endfunction

    always @(*) begin
        // 默认值（气泡/未知指令全为"不动作"）
        reg_we  = 1'b0;
        dmem_we = 1'b0;
        alu_src = 1'b0;
        branch  = 1'b0;
        jump    = 1'b0;
        imm_sel = IMM_I;
        wb_sel  = WB_ALU;
        alu_op  = ALU_ADD;
        case (opcode)
            OPC_R: begin
                reg_we = 1'b1;
                alu_op = r_alu_func({funct7, funct3});
            end
            OPC_I: begin
                reg_we  = 1'b1;
                alu_src = 1'b1;
                case (funct3)
                    3'b000:  alu_op = ALU_ADD;
                    3'b001:  alu_op = ALU_SLL;
                    3'b010:  alu_op = ALU_SLT;
                    3'b100:  alu_op = ALU_XOR;
                    3'b101:  alu_op = (funct7[5]) ? ALU_SRA : ALU_SRL;
                    3'b110:  alu_op = ALU_OR;
                    3'b111:  alu_op = ALU_AND;
                    default: alu_op = ALU_ADD;
                endcase
            end
            OPC_LW: begin
                reg_we  = 1'b1;
                alu_src = 1'b1;
                wb_sel  = WB_MEM;
            end
            OPC_SW: begin
                dmem_we = 1'b1;
                alu_src = 1'b1;
                imm_sel = IMM_S;
            end
            OPC_BR: begin
                imm_sel = IMM_B;
                branch  = 1'b1;
            end
            OPC_JAL: begin
                reg_we  = 1'b1;
                wb_sel  = WB_PC4;
                jump    = 1'b1;
                imm_sel = IMM_J;
            end
            OPC_JALR: begin
                reg_we  = 1'b1;
                wb_sel  = WB_PC4;
                alu_src = 1'b1;
                jump    = 1'b1;
            end
            OPC_LUI: begin
                reg_we  = 1'b1;
                wb_sel  = WB_UIMM;
                imm_sel = IMM_U;
            end
            default: begin
            end
        endcase
    end
endmodule

// ============================ IF/ID 流水寄存器 ============================
// flush=1 注入 NOP（冲刷）；stall=1 保持原值（停顿）
module pipe_if_id_reg(
    input wire clk,
    input wire rst,
    input wire enable,
    input wire flush,
    input wire stall,
    input wire [31:0] pc_in,
    input wire [31:0] instr_in,
    output reg [31:0] pc_out,
    output reg [31:0] instr_out
    );
    localparam NOP = 32'h0000_0013;   // addi x0,x0,0
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pc_out    <= 32'b0;
            instr_out <= NOP;
        end
        else if (enable) begin
            if (flush) begin
                pc_out    <= 32'b0;
                instr_out <= NOP;
            end else if (!stall) begin
                pc_out    <= pc_in;
                instr_out <= instr_in;
            end
        end
    end
endmodule

// ============================ ID/EX 流水寄存器 ============================
// flush=1（冲刷或停顿气泡）时控制信号全部清零，数据位可不清
module pipe_id_ex_reg(
    input wire clk,
    input wire rst,
    input wire enable,
    input wire flush,
    input wire [31:0] pc_in,      output reg [31:0] pc_out,
    input wire [31:0] pc4_in,     output reg [31:0] pc4_out,
    input wire [31:0] rd1_in,     output reg [31:0] rd1_out,
    input wire [31:0] rd2_in,     output reg [31:0] rd2_out,
    input wire [31:0] imm_in,     output reg [31:0] imm_out,
    input wire [4:0]  rs1_in,     output reg [4:0]  rs1_out,
    input wire [4:0]  rs2_in,     output reg [4:0]  rs2_out,
    input wire [4:0]  rd_in,      output reg [4:0]  rd_out,
    input wire [2:0]  funct3_in,  output reg [2:0]  funct3_out,
    input wire        jal_sel_in, output reg        jal_sel_out,
    input wire        reg_we_in,  output reg        reg_we_out,
    input wire        dmem_we_in, output reg        dmem_we_out,
    input wire        alu_src_in, output reg        alu_src_out,
    input wire        branch_in,  output reg        branch_out,
    input wire        jump_in,    output reg        jump_out,
    input wire [1:0]  wb_sel_in,  output reg [1:0]  wb_sel_out,
    input wire [3:0]  alu_op_in,  output reg [3:0]  alu_op_out
    );
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // 气泡：控制信号清零 => 不会写寄存器、不会写内存、不会分支/跳转
            reg_we_out  <= 1'b0;
            dmem_we_out <= 1'b0;
            alu_src_out <= 1'b0;
            branch_out  <= 1'b0;
            jump_out    <= 1'b0;
            wb_sel_out  <= 2'b00;
            alu_op_out  <= 4'b0000;
            pc_out      <= 32'b0;
            pc4_out     <= 32'b0;
            jal_sel_out <= 1'b0;
            rd1_out     <= 32'b0;
            rd2_out     <= 32'b0;
            imm_out     <= 32'b0;
            rs1_out     <= 5'b0;
            rs2_out     <= 5'b0;
            rd_out      <= 5'b0;
            funct3_out  <= 3'b0;
        end
        else if (enable) begin
            if (flush) begin
                reg_we_out  <= 1'b0;
                dmem_we_out <= 1'b0;
                alu_src_out <= 1'b0;
                branch_out  <= 1'b0;
                jump_out    <= 1'b0;
                wb_sel_out  <= 2'b00;
                alu_op_out  <= 4'b0000;
                pc_out      <= 32'b0;
                pc4_out     <= 32'b0;
                jal_sel_out <= 1'b0;
                rd1_out     <= 32'b0;
                rd2_out     <= 32'b0;
                imm_out     <= 32'b0;
                rs1_out     <= 5'b0;
                rs2_out     <= 5'b0;
                rd_out      <= 5'b0;
                funct3_out  <= 3'b0;
            end else begin
                pc_out      <= pc_in;
                pc4_out     <= pc4_in;
                rd1_out     <= rd1_in;
                rd2_out     <= rd2_in;
                imm_out     <= imm_in;
                rs1_out     <= rs1_in;
                rs2_out     <= rs2_in;
                rd_out      <= rd_in;
                funct3_out  <= funct3_in;
                jal_sel_out <= jal_sel_in;
                reg_we_out  <= reg_we_in;
                dmem_we_out <= dmem_we_in;
                alu_src_out <= alu_src_in;
                branch_out  <= branch_in;
                jump_out    <= jump_in;
                wb_sel_out  <= wb_sel_in;
                alu_op_out  <= alu_op_in;
            end
        end
    end
endmodule

// ============================ EX/MEM 流水寄存器 ============================
module pipe_ex_mem_reg(
    input wire clk,
    input wire rst,
    input wire enable,
    input wire [31:0] alu_y_in,   output reg [31:0] alu_y_out,
    input wire [31:0] store_in,   output reg [31:0] store_out,
    input wire [31:0] wb_val_in,  output reg [31:0] wb_val_out,
    input wire [4:0]  rd_in,      output reg [4:0]  rd_out,
    input wire        reg_we_in,  output reg        reg_we_out,
    input wire        dmem_we_in, output reg        dmem_we_out,
    input wire [1:0]  wb_sel_in,  output reg [1:0]  wb_sel_out
    );
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            alu_y_out   <= 32'b0;
            store_out   <= 32'b0;
            wb_val_out  <= 32'b0;
            rd_out      <= 5'b0;
            reg_we_out  <= 1'b0;
            dmem_we_out <= 1'b0;
            wb_sel_out  <= 2'b00;
        end
        else if (enable) begin
            alu_y_out   <= alu_y_in;
            store_out   <= store_in;
            wb_val_out  <= wb_val_in;
            rd_out      <= rd_in;
            reg_we_out  <= reg_we_in;
            dmem_we_out <= dmem_we_in;
            wb_sel_out  <= wb_sel_in;
        end
    end
endmodule

// ============================ MEM/WB 流水寄存器 ============================
// 写回值在这里做最终选择：lw 选内存数据，其余选 EX 段算好的值
module pipe_mem_wb_reg(
    input wire clk,
    input wire rst,
    input wire enable,
    input wire [31:0] wb_val_in,
    input wire [31:0] mem_in,
    input wire [1:0]  wb_sel_in,
    input wire [4:0]  rd_in,
    input wire        reg_we_in,
    output reg [31:0] wb_data_out,
    output reg [4:0]  rd_out,
    output reg        reg_we_out
    );
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wb_data_out <= 32'b0;
            rd_out      <= 5'b0;
            reg_we_out  <= 1'b0;
        end
        else if (enable) begin
            wb_data_out <= (wb_sel_in == 2'b01) ? mem_in : wb_val_in;
            rd_out      <= rd_in;
            reg_we_out  <= reg_we_in;
        end
    end
endmodule

// ============================ 前递单元 ============================
// 判断 EX 级指令的 rs1/rs2 应该取哪个来源：
//   2'b10 = EX/MEM（上一条指令的结果，最快）
//   2'b01 = MEM/WB（上上条指令的结果）
//   2'b00 = 寄存器堆原始读出
// 注意排除 x0（永远为 0，不需要前递）
module pipe_forwarding_unit(
    input wire [4:0] id_ex_rs1,
    input wire [4:0] id_ex_rs2,
    input wire [4:0] exmem_rd,
    input wire [4:0] memwb_rd,
    input wire       exmem_reg_we,
    input wire       memwb_reg_we,
    output reg [1:0] forward_a,
    output reg [1:0] forward_b
    );
    always @(*) begin
        // rs1 的前递选择（EX/MEM 优先，它更新）
        if (exmem_reg_we && (exmem_rd != 5'd0) && (exmem_rd == id_ex_rs1))
            forward_a = 2'b10;
        else if (memwb_reg_we && (memwb_rd != 5'd0) && (memwb_rd == id_ex_rs1))
            forward_a = 2'b01;
        else
            forward_a = 2'b00;
        // rs2 的前递选择
        if (exmem_reg_we && (exmem_rd != 5'd0) && (exmem_rd == id_ex_rs2))
            forward_b = 2'b10;
        else if (memwb_reg_we && (memwb_rd != 5'd0) && (memwb_rd == id_ex_rs2))
            forward_b = 2'b01;
        else
            forward_b = 2'b00;
    end
endmodule

// ============================ 冒险检测单元 ============================
// 只检测 load-use：
//   EX 级是 lw（reg_we 且 wb_sel=内存），若 ID 级指令的 rs1/rs2 与 lw 的 rd 相同，
//   则 ID 级指令必须停 1 拍（冻结 PC 与 IF/ID，向 ID/EX 注气泡）。
//   停 1 拍之后 lw 的数据已到 MEM/WB，可以前递。
// 优化项：按指令真实使用的寄存器域检测，避免对 jal/lui 误停顿
module pipe_hazard_unit(
    input wire        id_ex_reg_we,
    input wire [1:0]  id_ex_wb_sel,
    input wire [4:0]  id_ex_rd,
    input wire [31:0] if_id_instr,
    output reg        stall
    );
    wire mem_read = id_ex_reg_we && (id_ex_wb_sel == 2'b01);  // EX 级是 lw
    wire [6:0] op = if_id_instr[6:0];
    // rs1 域被使用的指令：除 jal（rs1 域是立即数）、lui（不用 rs1）之外
    wire use_rs1 = (op != 7'b1101111) && (op != 7'b0110111);
    // rs2 域被使用的指令：R 型运算、分支、sw
    wire use_rs2 = (op == 7'b0110011) || (op == 7'b1100011) || (op == 7'b0100011);
    wire [4:0] rs1 = if_id_instr[19:15];
    wire [4:0] rs2 = if_id_instr[24:20];
    always @(*) begin
        stall = 1'b0;
        if (mem_read && (id_ex_rd != 5'd0) &&
            ((use_rs1 && (rs1 == id_ex_rd)) || (use_rs2 && (rs2 == id_ex_rd))))
            stall = 1'b1;
    end
endmodule
