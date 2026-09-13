`timescale 1ns / 1ps
// tb_overflow.v
// Overflow-detection testbench for the pipelined RV32I CPU.
// Runs overflow_test.mem and checks, per retired instruction:
//   - retire_ovf matches the expectation of each arithmetic scenario
//   - data memory holds the expected truncated results
//   - sticky ovf_out is asserted after any overflow
// Expected scenarios (PC -> overflow flag):
//   0x04 addi x1,x1,-1 (MIN-1, 构造 MAX 用) -> OVF=1
//   0x0C add  x3,x1,x2 (MAX+1)     -> OVF=1
//   0x18 add  x3,x1,x2 (MAX-1)     -> OVF=0
//   0x24 addi x3,x2,-1 (MIN-1)     -> OVF=1
//   0x34 add  x6,x4,x5 (10+20)     -> OVF=0
//   0x3C sub  x7,x2,x4 (MIN-10)    -> OVF=1
// Memory results: mem[0]=0x80000000 mem[1]=0x7FFFFFFE mem[2]=0x7FFFFFFF
//                 mem[3]=30        mem[4]=0x7FFFFFF6
// Final x31 (monitor) = 0x7FFFFFF6 (last SW stores x7).

module tb_overflow;
    reg  clk = 0;
    reg  reset = 1;
    reg  enable = 0;
    integer i;

    wire [31:0] x31_out;
    wire        retire_valid;
    wire [31:0] retire_pc;
    wire [31:0] retire_instr;
    wire        retire_ovf;
    wire        ovf_out;

    RV32_Pipeline #(.IMEM_FILE("overflow_test.mem")) dut (
        .clk(clk), .reset(reset), .enable(enable),
        .x31_out(x31_out),
        .retire_valid(retire_valid),
        .retire_pc(retire_pc),
        .retire_instr(retire_instr),
        .retire_ovf(retire_ovf),
        .ovf_out(ovf_out),
        .int_req(1'b0), .int_en(1'b0), .mepc_out()
    );

    always #5 clk = ~clk;   // 100 MHz

    // Per-retired-instruction overflow check against the expected table.
    integer overflow_events;
    integer checked;
    reg sim_passed = 0;
    always @(posedge clk) begin
        if (retire_valid) begin
            case (retire_pc)
                32'h00000004: begin // addi MIN-1 (build MAX) -> overflow
                    checked = checked + 1;
                    if (!retire_ovf) $fatal(1, "FAIL: PC 0x04 (MIN-1) expected OVF=1");
                    else overflow_events = overflow_events + 1;
                end
                32'h0000000C: begin // add MAX+1 -> overflow
                    checked = checked + 1;
                    if (!retire_ovf) $fatal(1, "FAIL: PC 0x0C (MAX+1) expected OVF=1");
                    else overflow_events = overflow_events + 1;
                end
                32'h00000018: begin // add MAX-1 -> no overflow
                    checked = checked + 1;
                    if (retire_ovf) $fatal(1, "FAIL: PC 0x18 (MAX-1) expected OVF=0");
                end
                32'h00000024: begin // addi MIN-1 -> overflow
                    checked = checked + 1;
                    if (!retire_ovf) $fatal(1, "FAIL: PC 0x24 (MIN-1) expected OVF=1");
                    else overflow_events = overflow_events + 1;
                end
                32'h00000034: begin // add 10+20 -> no overflow
                    checked = checked + 1;
                    if (retire_ovf) $fatal(1, "FAIL: PC 0x34 (10+20) expected OVF=0");
                end
                32'h0000003C: begin // sub MIN-10 -> overflow
                    checked = checked + 1;
                    if (!retire_ovf) $fatal(1, "FAIL: PC 0x3C (MIN-10) expected OVF=1");
                    else overflow_events = overflow_events + 1;
                end
                default: ;
            endcase
        end
    end

    initial begin
        overflow_events = 0;
        checked = 0;
        repeat (4) @(negedge clk);   // hold reset for 4 cycles
        enable = 1;
        reset = 0;

        // Run until the terminal sentinel (beq x0,x0,0 = 0x00000063) retires.
        wait (dut.retire_valid && dut.retire_instr === 32'h00000063);
        repeat (10) @(negedge clk);  // let the last SW commit and WB settle

        // 1) Per-instruction overflow flags.
        if (checked != 6)
            $fatal(1, "FAIL: expected 6 checked arithmetic instructions, got %0d", checked);
        if (overflow_events != 4)
            $fatal(1, "FAIL: expected 4 overflow events, got %0d", overflow_events);

        // 2) Sticky flag must be set (overflow happened).
        if (!ovf_out)
            $fatal(1, "FAIL: sticky ovf_out should be 1");

        // 3) Data memory contents (dmem base 256 words at [0..511], addr word index).
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

        $display("PASS tb_overflow: %0d overflow events, %0d checked, flags/mem/x31 all correct", overflow_events, checked);
        sim_passed = 1;
        $finish;
    end

    initial begin
        #200000;
        if (!sim_passed)
            $fatal(1, "tb_overflow timeout");
        $finish;
    end
endmodule