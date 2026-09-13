`timescale 1ns / 1ps
// 中断功能测试（单周期 RV32_CPU）
// 与 tb_int.v 同一测试程序、同一语义：中断处理(mem[1]=0x55) + 返回续跑(mem[0]=5)。
module tb_int_sc;
    reg        clk = 0;
    reg        reset = 1;
    reg        enable = 0;
    reg        int_req = 0;
    reg        int_en = 0;
    wire [31:0] mepc_out;
    wire [31:0] x31_out;

    RV32_CPU #(
        .IMEM_FILE("int_test.mem"),
        .INT_VECTOR(32'h00000040)
    ) dut (
        .clk(clk), .reset(reset), .enable(enable),
        .x31_out(x31_out),
        .retire_ovf(), .ovf_out(),
        .int_req(int_req), .int_en(int_en),
        .mepc_out(mepc_out)
    );

    always #5 clk = ~clk;   // 100 MHz

    // 单周期：跟踪 PC 经过 0x40（ISR 入口）即认为中断被响应
    integer isr_pc_seen = 0;
    always @(posedge clk) begin
        if (dut.pc == 32'h00000040) isr_pc_seen = isr_pc_seen + 1;
    end

    initial begin
        repeat (4) @(negedge clk);
        reset  = 0;
        enable = 1;
        int_en = 1;

        // 主程序约 9 拍可达 0x14 哨兵；在第 4 拍附近拉中断，保证在循环中被截获
        repeat (4) @(negedge clk);
        int_req = 1;
        repeat (2) @(negedge clk);
        int_req = 0;

        // 等主程序写完 mem[0]（0x14 哨兵自循环，PC 停在 0x14）
        repeat (40) @(negedge clk);

        if (isr_pc_seen == 0)
            $fatal(1, "FAIL: PC 从未到达 0x40 (ISR)，中断未响应");
        if (dut.u_dmem.ram[0] !== 32'd5)
            $fatal(1, "FAIL: mem[0] exp 5 got %08h (返回后主程序未完成)", dut.u_dmem.ram[0]);
        if (dut.u_dmem.ram[1] !== 32'h00000055)
            $fatal(1, "FAIL: mem[1] exp 0x55 got %08h (ISR 未执行)", dut.u_dmem.ram[1]);
        if (x31_out !== 32'd5)
            $fatal(1, "FAIL: 最终 x31 exp 5 got %08h", x31_out);
        $display("PASS tb_int_sc: 中断响应 %0d 次, mem[0]=5, mem[1]=0x55, mepc=0x%08h, x31=5", isr_pc_seen, mepc_out);
        $finish;
    end

    reg sim_passed = 0;
    always @(posedge clk) if (dut.pc == 32'h00000040) sim_passed <= 1;
    initial begin
        #100000;
        if (!sim_passed)
            $fatal(1, "tb_int_sc timeout");
        $finish;
    end
endmodule