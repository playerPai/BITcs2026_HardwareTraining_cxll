`timescale 1ns / 1ps

module tb_cpu;

    reg clk;
    reg rst;
    reg [31:0] cyc;   //周期计数器（性能统计：跑到pass死循环时读它）
    integer i;

    cpu_top dut (
        .clk(clk),
        .rst(rst)
    );

    // 时钟：10ns周期
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 复位
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

    // 仿真结束前打印：周期数 + 寄存器堆 + 数据存储器（前32字）
    initial begin
        #2000000;              // 20万拍，sort16 等长程序足够
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