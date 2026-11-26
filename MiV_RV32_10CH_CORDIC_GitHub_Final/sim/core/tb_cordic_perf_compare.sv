`timescale 1ns/1ps

// Fair core-only comparison:
// 1 real CORDIC datapath processes 10 values sequentially;
// 10 real datapaths process the same 10 values in one batch.
// No CPU/MMIO overhead is included here.
module tb_cordic_perf_compare;
    logic clk = 1'b0;
    always #5 clk = ~clk; // 10 ns per simulated clock
    logic resetn = 1'b0;

    logic ln1_start = 1'b0;
    logic ln10_start = 1'b0;
    logic exp1_start = 1'b0;
    logic exp10_start = 1'b0;

    logic [15:0] ln1_in = 16'd4096;
    logic [159:0] ln10_in = '0;
    logic [15:0] exp1_in = 16'd0;
    logic [159:0] exp10_in = '0;

    wire [31:0] ln1_out;
    wire [319:0] ln10_out;
    wire [0:0] ln1_invalid;
    wire [9:0] ln10_invalid;
    wire ln1_busy, ln1_done, ln10_busy, ln10_done;

    wire [31:0] exp1_out;
    wire [319:0] exp10_out;
    wire [0:0] exp1_invalid;
    wire [9:0] exp10_invalid;
    wire exp1_busy, exp1_done, exp10_busy, exp10_done;

    integer ln_inputs [0:9];
    integer exp_inputs [0:9];
    integer ln_expected [0:9];
    integer exp_expected [0:9];
    logic [31:0] ln1_saved [0:9];
    logic [31:0] exp1_saved [0:9];

    time ln1_start_time, ln1_end_time;
    time ln10_start_time, ln10_end_time;
    time exp1_start_time, exp1_end_time;
    time exp10_start_time, exp10_end_time;
    integer seq_ln_cycles, par_ln_cycles;
    integer seq_exp_cycles, par_exp_cycles;
    real ln_speedup, exp_speedup;

    cordic_ln_single dut_ln1 (
        .clk(clk), .resetn(resetn), .start(ln1_start),
        .a_q12_flat(ln1_in), .ln_q12_flat(ln1_out),
        .invalid_mask(ln1_invalid), .busy(ln1_busy), .done(ln1_done)
    );
    cordic_ln_parallel_10ch dut_ln10 (
        .clk(clk), .resetn(resetn), .start(ln10_start),
        .a_q12_flat(ln10_in), .ln_q12_flat(ln10_out),
        .invalid_mask(ln10_invalid), .busy(ln10_busy), .done(ln10_done)
    );
    cordic_exp_single dut_exp1 (
        .clk(clk), .resetn(resetn), .start(exp1_start),
        .in_q12_flat(exp1_in), .exp_q12_flat(exp1_out),
        .invalid_mask(exp1_invalid), .busy(exp1_busy), .done(exp1_done)
    );
    cordic_exp_parallel_10ch dut_exp10 (
        .clk(clk), .resetn(resetn), .start(exp10_start),
        .in_q12_flat(exp10_in), .exp_q12_flat(exp10_out),
        .invalid_mask(exp10_invalid), .busy(exp10_busy), .done(exp10_done)
    );

    task automatic check_result(
        input integer measured,
        input integer expected,
        input integer ch,
        input integer is_exp
    );
        begin
            if (measured < expected - 3 || measured > expected + 3)
                $fatal(1, "Incorrect %s CH%0d: got=%0d expected=%0d",
                       is_exp ? "EXP" : "LN", ch, measured, expected);
        end
    endtask

    task automatic run_ln1(input integer ch);
        integer count;
        begin
            @(negedge clk);
            ln1_in = ln_inputs[ch][15:0];
            ln1_start = 1'b1;
            @(posedge clk); #1;
            if (ch == 0) ln1_start_time = $time;
            if (ln1_busy !== 1'b1 || ln1_done !== 1'b0)
                $fatal(1, "LN single start failed CH%0d", ch);
            @(negedge clk);
            ln1_start = 1'b0;
            count = 0;
            while (ln1_done !== 1'b1 && count < 25) begin
                @(posedge clk); #1;
                count = count + 1;
            end
            if (count != 16 || ln1_busy !== 1'b0 || ln1_invalid !== 1'b0)
                $fatal(1, "LN single did not finish correctly CH%0d", ch);
            ln1_saved[ch] = ln1_out;
            check_result($signed(ln1_out), ln_expected[ch], ch, 0);
            if (ch == 9) ln1_end_time = $time;
        end
    endtask

    task automatic run_exp1(input integer ch);
        integer count;
        begin
            @(negedge clk);
            exp1_in = exp_inputs[ch][15:0];
            exp1_start = 1'b1;
            @(posedge clk); #1;
            if (ch == 0) exp1_start_time = $time;
            if (exp1_busy !== 1'b1 || exp1_done !== 1'b0)
                $fatal(1, "EXP single start failed CH%0d", ch);
            @(negedge clk);
            exp1_start = 1'b0;
            count = 0;
            while (exp1_done !== 1'b1 && count < 25) begin
                @(posedge clk); #1;
                count = count + 1;
            end
            if (count != 16 || exp1_busy !== 1'b0 || exp1_invalid !== 1'b0)
                $fatal(1, "EXP single did not finish correctly CH%0d", ch);
            exp1_saved[ch] = exp1_out;
            check_result($signed(exp1_out), exp_expected[ch], ch, 1);
            if (ch == 9) exp1_end_time = $time;
        end
    endtask

    task automatic run_ln10;
        integer count;
        integer result_val;
        begin
            @(negedge clk);
            for (integer ch = 0; ch < 10; ch = ch + 1)
                ln10_in[ch*16 +: 16] = ln_inputs[ch][15:0];
            ln10_start = 1'b1;
            @(posedge clk); #1;
            ln10_start_time = $time;
            if (ln10_busy !== 1'b1 || ln10_done !== 1'b0)
                $fatal(1, "LN ten-channel start failed");
            @(negedge clk);
            ln10_start = 1'b0;
            count = 0;
            while (ln10_done !== 1'b1 && count < 25) begin
                @(posedge clk); #1;
                count = count + 1;
            end
            ln10_end_time = $time;
            if (count != 16 || ln10_busy !== 1'b0 || ln10_invalid !== 10'd0)
                $fatal(1, "LN ten-channel did not finish correctly");
            for (integer ch = 0; ch < 10; ch = ch + 1) begin
                result_val = $signed(ln10_out[ch*32 +: 32]);
                check_result(result_val, ln_expected[ch], ch, 0);
                if (ln10_out[ch*32 +: 32] !== ln1_saved[ch])
                    $fatal(1, "LN single/ten mismatched CH%0d", ch);
            end
            $display("PASS: LN 1CH and 10CH all 10 outputs identical");
        end
    endtask

    task automatic run_exp10;
        integer count;
        integer result_val;
        begin
            @(negedge clk);
            for (integer ch = 0; ch < 10; ch = ch + 1)
                exp10_in[ch*16 +: 16] = exp_inputs[ch][15:0];
            exp10_start = 1'b1;
            @(posedge clk); #1;
            exp10_start_time = $time;
            if (exp10_busy !== 1'b1 || exp10_done !== 1'b0)
                $fatal(1, "EXP ten-channel start failed");
            @(negedge clk);
            exp10_start = 1'b0;
            count = 0;
            while (exp10_done !== 1'b1 && count < 25) begin
                @(posedge clk); #1;
                count = count + 1;
            end
            exp10_end_time = $time;
            if (count != 16 || exp10_busy !== 1'b0 || exp10_invalid !== 10'd0)
                $fatal(1, "EXP ten-channel did not finish correctly");
            for (integer ch = 0; ch < 10; ch = ch + 1) begin
                result_val = $signed(exp10_out[ch*32 +: 32]);
                check_result(result_val, exp_expected[ch], ch, 1);
                if (exp10_out[ch*32 +: 32] !== exp1_saved[ch])
                    $fatal(1, "EXP single/ten mismatched CH%0d", ch);
            end
            $display("PASS: EXP 1CH and 10CH all 10 outputs identical");
        end
    endtask

    initial begin
        // Use exactly the same 10 test vectors as the verified ln/exp designs.
        ln_inputs[0]=2048; ln_inputs[1]=2560; ln_inputs[2]=3072;
        ln_inputs[3]=3584; ln_inputs[4]=4096; ln_inputs[5]=4608;
        ln_inputs[6]=5120; ln_inputs[7]=5632; ln_inputs[8]=6144;
        ln_inputs[9]=8192;
        ln_expected[0]=-2839; ln_expected[1]=-1925; ln_expected[2]=-1178;
        ln_expected[3]=-547;  ln_expected[4]=0;     ln_expected[5]=482;
        ln_expected[6]=914;   ln_expected[7]=1304;  ln_expected[8]=1661;
        ln_expected[9]=2839;

        exp_inputs[0]=-2839; exp_inputs[1]=-2500; exp_inputs[2]=-2048;
        exp_inputs[3]=-1661; exp_inputs[4]=-1178; exp_inputs[5]=-914;
        exp_inputs[6]=-482;  exp_inputs[7]=0;     exp_inputs[8]=914;
        exp_inputs[9]=2839;
        exp_expected[0]=2048; exp_expected[1]=2225; exp_expected[2]=2484;
        exp_expected[3]=2731; exp_expected[4]=3072; exp_expected[5]=3277;
        exp_expected[6]=3641; exp_expected[7]=4096; exp_expected[8]=5120;
        exp_expected[9]=8192;

        repeat (3) @(negedge clk);
        resetn = 1'b1;

        $display("=== LN: single-channel sequential 10 inputs ===");
        for (integer ch = 0; ch < 10; ch = ch + 1)
            run_ln1(ch);
        $display("=== LN: ten-channel parallel 10 inputs ===");
        run_ln10();

        $display("=== EXP: single-channel sequential 10 inputs ===");
        for (integer ch = 0; ch < 10; ch = ch + 1)
            run_exp1(ch);
        $display("=== EXP: ten-channel parallel 10 inputs ===");
        run_exp10();

        // Start-acceptance to last-DONE wall clock at 10 ns/cycle.
        seq_ln_cycles = (ln1_end_time - ln1_start_time) / 10;
        par_ln_cycles = (ln10_end_time - ln10_start_time) / 10;
        seq_exp_cycles = (exp1_end_time - exp1_start_time) / 10;
        par_exp_cycles = (exp10_end_time - exp10_start_time) / 10;
        ln_speedup = 1.0 * seq_ln_cycles / par_ln_cycles;
        exp_speedup = 1.0 * seq_exp_cycles / par_exp_cycles;

        $display("============================================");
        $display("CORE-ONLY PERFORMANCE (10 inputs, no CPU/MMIO)");
        $display("LN  : 1CH sequential = %0d clocks, 10CH parallel = %0d clocks, speedup = %0.3f X",
                 seq_ln_cycles, par_ln_cycles, ln_speedup);
        $display("EXP : 1CH sequential = %0d clocks, 10CH parallel = %0d clocks, speedup = %0.3f X",
                 seq_exp_cycles, par_exp_cycles, exp_speedup);
        $display("Note: NOT an overall CPU speedup; no synthesis/Fmax measured.");
        $display("ALL LN/EXP CORE PERFORMANCE TESTS PASSED");
        $display("============================================");
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "Performance benchmark timeout");
    end
endmodule
