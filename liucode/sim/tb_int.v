`timescale 1ns / 1ps
// 中断功能测试（五级流水线 RV32_Pipeline）
// 程序: 主程序 x1 从 0 数到 5 写 mem[0]=5 后哨兵停住;
//       运行中拉高 int_req 一次 -> 跳 0x40 ISR: mem[1]=0x55 -> mret 返回续跑。
// 检查: 中断确实被处理(mem[1]==0x55)、返回后主程序续跑(mem[0]==5)、
//       mret 恢复执行(最终 x31==5, retire 哨兵出现)。
module tb_int;
    reg        clk = 0;
    reg        reset = 1;
    reg        enable = 0;
    reg        int_req = 0;
    reg        int_en = 0;
    wire       retire_valid;
    wire [31:0] retire_pc;
    wire [31:0] mepc_out;
    wire [31:0] x31_out;

    RV32_Pipeline #(
        .IMEM_FILE("int_test.mem"),
        .INT_VECTOR(32'h00000040)
    ) dut (
        .clk(clk), .reset(reset), .enable(enable),
        .x31_out(x31_out),
        .retire_valid(retire_valid),
        .retire_pc(retire_pc),
        .retire_instr(),
        .retire_ovf(), .ovf_out(),
        .int_req(int_req), .int_en(int_en),
        .mepc_out(mepc_out)
    );

    always #5 clk = ~clk;   // 100 MHz

    integer int_seen = 0;

    // 监视 ISR 首指令退休（PC=0x40）
    always @(posedge clk) begin
        if (retire_valid && retire_pc == 32'h00000040)
            int_seen = int_seen + 1;
    end

    initial begin
        repeat (4) @(negedge clk);
        reset  = 0;
        enable = 1;
        int_en = 1;

        // 让主程序跑 10 拍（x1 循环计数中），然后拉高中断请求 3 拍
        repeat (10) @(negedge clk);
        int_req = 1;
        repeat (3) @(negedge clk);
        int_req = 0;

        // 等待主程序走到 0x14 哨兵（beq x0,x0,0 自循环）
        wait (retire_valid && retire_pc == 32'h00000014);
        repeat (10) @(negedge clk);   // 等 x31 粘性/写回稳定

        // 检查
        if (dut.u_dmem.ram[0] !== 32'd5)
            $fatal(1, "FAIL: mem[0] exp 5 got %08h (主程序未正常完成)", dut.u_dmem.ram[0]);
        if (dut.u_dmem.ram[1] !== 32'h00000055)
            $fatal(1, "FAIL: mem[1] exp 0x55 got %08h (ISR 未执行)", dut.u_dmem.ram[1]);
        if (int_seen != 1)
            $fatal(1, "FAIL: ISR(PC=0x40) 退休次数 exp 1 got %0d", int_seen);
        if (x31_out !== 32'd5)
            $fatal(1, "FAIL: 最终 x31 exp 5 got %08h", x31_out);
        $display("PASS tb_int: mem[0]=5, mem[1]=0x55, ISR x1, mepc=0x%08h, x31=5", mepc_out);
        $finish;
    end

    // 超时保险（PASS 后不再误报）
    reg sim_passed = 0;
    always @(posedge clk) if (retire_valid && retire_pc == 32'h00000014) sim_passed <= 1;
    initial begin
        #100000;   // 100us
        if (!sim_passed)
            $fatal(1, "tb_int timeout");
        $finish;
    end
endmodule