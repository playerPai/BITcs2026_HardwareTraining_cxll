`timescale 1ns / 1ps
// tb_overflow_sc.v
// Overflow-detection testbench for the SINGLE-CYCLE RV32I CPU.
// Runs the same overflow_test.mem as the pipeline version.
// Single-cycle has no retire_pc/retire_instr ports, so this tb tracks the
// retired-instruction ordinal instead (one instruction per enabled cycle):
//   ord 0: lui  x1,0x80000                  (setup)
//   ord 1: addi x1,x1,-1  MIN-1  -> OVF=1   (building MAX also overflows)
//   ord 2: addi x2,x0,1                     (setup)
//   ord 3: add  x3,x1,x2  MAX+1  -> OVF=1
//   ord 5: addi x2,x0,-1                    (setup)
//   ord 6: add  x3,x1,x2  MAX-1  -> OVF=0
//   ord 8: lui  x2,0x80000                  (setup)
//   ord 9: addi x3,x2,-1  MIN-1  -> OVF=1
//   ord 11/12: addi x4/x5 (setup)
//   ord 13: add  x6,x4,x5 10+20  -> OVF=0
//   ord 15: sub  x7,x2,x4  MIN-10 -> OVF=1
// Memory results (same as pipeline version):
//   mem[0]=0x80000000 mem[1]=0x7FFFFFFE mem[2]=0x7FFFFFFF
//   mem[3]=30         mem[4]=0x7FFFFFF6
// Final x31 (monitor) = 0x7FFFFFF6 (last SW stores x7).

module tb_overflow_sc;
    reg  clk = 0;
    reg  reset = 1;
    reg  enable = 0;

    wire [31:0] x31_out;
    wire        retire_ovf;
    wire        ovf_out;

    integer inst_ord = -1;      // 退休指令序号（-1 = 尚未开始）
    integer overflow_events = 0;
    reg sim_passed = 0;

    RV32_CPU #(.IMEM_FILE("overflow_test.mem")) dut (
        .clk(clk), .reset(reset), .enable(enable),
        .x31_out(x31_out),
        .retire_ovf(retire_ovf),
        .ovf_out(ovf_out),
        .int_req(1'b0), .int_en(1'b0), .mepc_out()
    );

    always #5 clk = ~clk;   // 100 MHz

    // 单周期每条有效指令一拍，按退休序号核对溢出标志
    always @(posedge clk) begin
        if (enable && !reset) begin
            inst_ord = inst_ord + 1;
            case (inst_ord)
                1: begin // addi x1,x1,-1 (MIN-1) -> overflow
                    if (!retire_ovf) $fatal(1, "FAIL ord1 (MIN-1) expected OVF=1");
                    else overflow_events = overflow_events + 1;
                end
                3: begin // add MAX+1 -> overflow
                    if (!retire_ovf) $fatal(1, "FAIL ord3 (MAX+1) expected OVF=1");
                    else overflow_events = overflow_events + 1;
                end
                6: begin // add MAX-1 -> no overflow
                    if (retire_ovf) $fatal(1, "FAIL ord6 (MAX-1) expected OVF=0");
                end
                9: begin // addi MIN-1 -> overflow
                    if (!retire_ovf) $fatal(1, "FAIL ord9 (MIN-1) expected OVF=1");
                    else overflow_events = overflow_events + 1;
                end
                13: begin // add 10+20 -> no overflow
                    if (retire_ovf) $fatal(1, "FAIL ord13 (10+20) expected OVF=0");
                end
                15: begin // sub MIN-10 -> overflow
                    if (!retire_ovf) $fatal(1, "FAIL ord15 (MIN-10) expected OVF=1");
                    else overflow_events = overflow_events + 1;
                end
                default: ;
            endcase
        end
    end

    initial begin
        overflow_events = 0;
        repeat (4) @(negedge clk);   // hold reset
        enable = 1;
        reset = 0;

        repeat (40) @(negedge clk);  // 18 条指令 + 余量

        // 1) 逐指令溢出标志
        if (overflow_events != 4)
            $fatal(1, "FAIL: expected 4 overflow events, got %0d", overflow_events);
        if (!ovf_out)
            $fatal(1, "FAIL: sticky ovf_out should be 1");

        // 2) 数据内存（单周期 dmem 同/异步读）
        if (dut.u_dmem.ram[0] !== 32'h80000000)
            $fatal(1, "FAIL: mem[0] exp 0x80000000 got %08h", dut.u_dmem.ram[0]);
        if (dut.u_dmem.ram[1] !== 32'h7FFFFFFE)
            $fatal(1, "FAIL: mem[1] exp 0x7FFFFFFE got %08h", dut.u_dmem.ram[1]);
        if (dut.u_dmem.ram[2] !== 32'h7FFFFFFF)
            $fatal(1, "FAIL: mem[2] exp 0x7FFFFFFF got %08h", dut.u_dmem.ram[2]);
        if (dut.u_dmem.ram[3] !== 32'd30)
            $fatal(1, "FAIL: mem[3] exp 30 got %08h", dut.u_dmem.ram[3]);
        if (dut.u_dmem.ram[4] !== 32'h7FFFFFF6)
            $fatal(1, "FAIL: mem[4] exp 0x7FFFFFF6 got %08h", dut.u_dmem.ram[4]);

        if (x31_out !== 32'h7FFFFFF6)
            $fatal(1, "FAIL: final x31 mon exp 0x7FFFFFF6 got %08h", x31_out);

        $display("PASS tb_overflow_sc: %0d overflow events, flags/mem/x31 all correct", overflow_events);
        sim_passed = 1;
        $finish;
    end

    initial begin
        #200000;
        if (!sim_passed)
            $fatal(1, "tb_overflow_sc timeout");
        $finish;
    end
endmodule