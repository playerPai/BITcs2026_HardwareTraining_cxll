`timescale 1ns / 1ps
// 流水线 CPU 测试平台（与单周期 tb_cpu 同一套思路）：
//   1) 10ns 周期时钟 + 20ns 复位
//   2) cyc 周期计数器（读总周期数）
//   3) #2000000（200 万 ns = 20 万拍）后自动打印寄存器堆与数据存储器并 $stop
// 核对方法：打印值与各测试程序（.asm 头部注释 / 仿真步骤指南验收表）比对，
// 或直接用 工具\verify_cpu.py 的期望表作参考答案。
module tb_pipeline;

    reg clk;
    reg rst;
    reg [31:0] cyc;   // 周期计数器
    integer i;

    pipeline_top dut (
        .clk(clk),
        .rst(rst)
    );

    // 时钟：10ns 周期
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 复位：上电保持 20ns 后释放
    initial begin
        rst = 1;
        #20;
        rst = 0;
    end

    // 周期计数
    always @(posedge clk) begin
        if (rst) cyc <= 0;
        else     cyc <= cyc + 1;
    end

    // 仿真结束前打印：周期数 + 寄存器堆 + 数据存储器（前 32 字）
    initial begin
        #2000000;
        $display("===== sim finished, total cycles = %0d =====", cyc);
        $display("----- register file (x0..x31) -----");
        for (i = 0; i < 32; i = i + 1)
            $display("x%0d = 0x%08h (%0d)", i, dut.u_regfile.regs[i], $signed(dut.u_regfile.regs[i]));
        $display("----- dmem (non-zero words, first 32) -----");
        for (i = 0; i < 32; i = i + 1)
            if (dut.u_dmem.ram[i] !== 32'h0)
                $display("mem[%0d] = 0x%08h", i, dut.u_dmem.ram[i]);
        $display("===== end =====");
        $stop;
    end

endmodule