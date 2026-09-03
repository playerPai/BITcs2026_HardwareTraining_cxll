`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/20 15:07:11
// Design Name: 
// Module Name: CPU
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module cpu_top(
input wire clk,
input wire rst
    );
wire [31:0] instr;
wire [31:0] pc;
wire [31:0] pc_plus4;
wire [31:0] pc_next;
wire [4:0] rs1; 
wire [4:0] rs2;
wire [4:0] rd;
assign rs1 = instr[19:15];
assign rs2 = instr[24:20];
assign rd = instr[11:7];
wire      reg_we;
wire      branch;
wire      dmem_we;
wire      alu_src;
wire [1:0] imm_sel;
wire [1:0] wb_sel;
wire [2:0] alu_op;
wire [31:0] rd1;
wire [31:0] rd2;
wire [31:0] imm;
wire [31:0] br_off;
wire [31:0] imm_u;
wire [31:0] alu_b;
wire [31:0] alu_y;
wire [31:0] dmem_rdata;
wire [31:0] wb_data;
wire take_branch;
//pc
    pc_reg u_pc(
    .clk(clk),
    .rst(rst),
    .pc_next(pc_next),
    .pc(pc)
    );
    assign pc_plus4 = pc + 32'd4;
    
 //指令存储器
    imem u_imem(
    .addr(pc),
    .instr(instr)
    );
    
//控制器
    ctrl u_ctrl(
    .instr(instr),
    .dmem_we(dmem_we),
    .imm_sel(imm_sel),
    .alu_op(alu_op),
    .alu_src(alu_src),
    .branch(branch),
    .reg_we(reg_we),
    .wb_sel(wb_sel)
    );
    
 //立即数生成器
    imm_gen u_imm_gen(
    .instr(instr),
    .imm_sel(imm_sel),
    .imm(imm),
    .br_off(br_off),
    .imm_u(imm_u)
    );
    
//寄存器堆

    regfile u_regfile(
    .clk(clk),
    .we(reg_we),
    .ra1(rs1),
    .ra2(rs2),
    .rd1(rd1),
    .rd2(rd2),
    .wd(wb_data),
    .wa(rd)
    );
    
    assign alu_b = (alu_src)?imm:rd2;
    
//ALU
    alu u_alu(
    .a(rd1),
    .b(alu_b),
    .alu_op(alu_op),
    .y(alu_y)
    );
    
//数据存储器
    dmem u_dmem(
    .clk(clk),
    .addr(alu_y),
    .we(dmem_we),
    .rdata(dmem_rdata),
    .wdata(rd2)
    );
    
//分支单元
    br_unit u_br_unit(
     .branch(branch),
     .funct3(instr[14:12]),
     .rs1_val(rd1),
     .rs2_val(rd2),
     .take_branch(take_branch)
     );
     
   assign wb_data = (wb_sel==2'b00)? alu_y :
                    (wb_sel==2'b01)? dmem_rdata :
                    (wb_sel==2'b10)? pc_plus4 :
                                     imm_u;

   assign pc_next = (take_branch)? (pc + br_off) : pc_plus4;
   
endmodule

module pc_reg(
    input wire clk,
    input wire rst,
    input wire [31:0] pc_next,
    output reg [31:0] pc
    );
    
    always@(posedge clk or posedge rst)begin
        if(rst)
            pc <= 32'b0;
        else 
            pc <= pc_next;
        end
endmodule

module imem(
    input wire [31:0] addr,
    output wire [31:0] instr
    );
    
    reg [31:0] rom [0:255];
    initial begin
        $readmemh("inst.mem",rom);
    end 
    //rom按4字节存储，按字寻址，取指令时地址右移2位（相当于除以4）
    assign instr = rom[addr[31:2]];        
endmodule

module dmem(
    input wire clk,
    input wire we,
    input wire [31:0] addr,
    input wire [31:0] wdata,
    output wire [31:0] rdata
    );
    reg [31:0] ram [0:9];
    integer i;
    initial begin 
        for (i=0; i<10 ; i = i+1)
            ram[i] = 32'b0;
    end 
    
    always@(posedge clk)begin
        if(we)
            ram[addr[31:2]] <= wdata;
    end    
    
    assign rdata = ram[addr[31:2]];
endmodule

module regfile(
    input wire clk,
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
        for(i=0; i<32 ; i=i+1)
            regs[i] = 32'b0;
     end
     always@(posedge clk) begin
        if (we&&(wa != 5'd0))
            regs[wa] <= wd;
     end
     //riscv规范：0号寄存器恒为零
     assign rd1 = (ra1 == 5'd0)? 32'b0 : regs[ra1];
     assign rd2 = (ra2 == 5'd0)? 32'b0 : regs[ra2];
     
     endmodule
    
module alu(
    input wire [2:0] alu_op,
    input wire [31:0] a,
    input wire [31:0] b,
    output reg [31:0] y
    );
    localparam ALU_ADD = 3'b000;
    localparam ALU_SUB = 3'b001;
    localparam ALU_OR = 3'b010;
    localparam ALU_SLT = 3'b011;
    
    always@(*)begin
        case(alu_op)
         ALU_ADD: y = a + b;
         ALU_SUB: y = a - b;
         ALU_OR : y = a | b;
         ALU_SLT: y = ($signed(a) < $signed(b))? 32'd1 : 32'd0;
         default : y = 32'b0;
         endcase 
    end 
endmodule

module imm_gen(
    input wire [31:0] instr,
    input wire [1:0] imm_sel,
    output reg [31:0] imm,
    output wire [31:0] br_off,
    output wire [31:0] imm_u
    );
    //riscv四种常用立即数：I型、S型、B型、U型
    wire [31:0] imm_i;
    wire [31:0] imm_s;
    wire [31:0] imm_b;
    //{20{instr[31]}}表示将instr第31位复制20次，实现符号扩展
    assign imm_i = {{20{instr[31]}},instr[31:20]};
    assign imm_s = {{20{instr[31]}},instr[31:25],instr[11:7]};
    assign imm_b = {{19{instr[31]}},instr[31],instr[7],instr[30:25],instr[11:8],1'b0};
    assign imm_u = {instr[31:12],12'b0};
    assign br_off = imm_b;
    always@(*) begin
        case (imm_sel)
            2'b00: imm = imm_i;
            2'b01: imm = imm_s;
            2'b10: imm = imm_b;
            2'b11: imm = imm_u;
            default :imm = 32'b0;
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
        if(branch)begin
            case(funct3)
                3'b000:take_branch = (rs1_val == rs2_val);
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
    output reg [1:0] imm_sel,
    output reg [1:0] wb_sel,
    output reg [2:0] alu_op
    );
    wire [6:0] opcode;
    wire [2:0] funct3;
    wire [6:0] funct7;
    assign opcode = instr[6:0];
    assign funct3 = instr[14:12];
    assign funct7 = instr[31:25];
    localparam OPC_R   = 7'b0110011;
    localparam OPC_I   = 7'b0010011;
    localparam OPC_LW  = 7'b0000011;
    localparam OPC_SW  = 7'b0100011;
    localparam OPC_BR  = 7'b1100011;
    localparam IMM_I   = 2'b00;
    localparam IMM_S   = 2'b01;
    localparam IMM_B   = 2'b10;
    localparam IMM_U   = 2'b11;
    localparam WB_ALU  = 2'b00;
    localparam WB_MEM  = 2'b01;
    localparam WB_PC4  = 2'b10;
    localparam WB_UIMM = 2'b11;
    localparam ALU_ADD = 3'b000;
    localparam ALU_SUB = 3'b001;
    localparam ALU_OR  = 3'b010;
    localparam ALU_SLT = 3'b011;
    
    always @(*)begin
    //设置所有控制信号默认值，后续根据opcode、funct3、funct7修改
        reg_we = 1'b0;
        dmem_we = 1'b0;
        alu_src = 1'b0;
        branch = 1'b0;
        imm_sel = IMM_I;
        wb_sel = WB_ALU;
        alu_op = ALU_ADD;
        case (opcode)
            //R-type :add / sub / slt
            OPC_R: begin
                reg_we = 1'b1;
                wb_sel = WB_ALU;
                alu_src = 1'b0;
                case ({funct7,funct3})
                    {7'b0000000,3'b000}: alu_op = ALU_ADD;
                    {7'b0100000,3'b000}: alu_op = ALU_SUB;
                    {7'b0000000,3'b010}: alu_op = ALU_SLT;
                    default: alu_op = ALU_ADD;
                endcase
         end
            //I-type :ori,addi
            OPC_I:begin
                if(funct3 == 3'b110)begin
                    reg_we = 1'b1;
                    alu_src = 1'b1;
                    imm_sel = IMM_I;
                    wb_sel = WB_ALU;
                    alu_op = ALU_OR;
                  end
                 else if(funct3 == 3'b000)begin
                    reg_we = 1'b1;
                    alu_src = 1'b1;
                    imm_sel = IMM_I;
                    wb_sel = WB_ALU;
                    alu_op = ALU_ADD;
                    
                  end
          end
          //lw
            OPC_LW :begin
                reg_we = 1'b1;
                dmem_we = 1'b0;
                alu_src = 1'b1;
                imm_sel = IMM_I;
                wb_sel = WB_MEM;
                alu_op = ALU_ADD;
           end
           //sw
            OPC_SW :begin
                reg_we = 1'b0;
                dmem_we = 1'b1;
                alu_src = 1'b1;
                imm_sel = IMM_S;
                alu_op = ALU_ADD;
           end
           //beq
           OPC_BR :begin
                reg_we = 1'b0;
                dmem_we = 1'b0;
                alu_src = 1'b0;
                imm_sel = IMM_B;
                branch = 1'b1;
                alu_op = ALU_SUB;
            end
            default :begin
            
            end
        endcase
     end
    endmodule