`timescale 1ns/1ps

module tb_cordic_ln_parallel_10ch;
    logic clk = 1'b0;
    logic resetn = 1'b0;
    logic start = 1'b0;
    always #5 clk = ~clk;

    logic [159:0] a_q12_flat = 160'd0;
    wire  [319:0] ln_q12_flat;
    wire  [9:0]   invalid_mask;
    wire          busy;
    wire          done;
    integer golden [0:9];

    cordic_ln_parallel_10ch dut (
        .clk(clk), .resetn(resetn), .start(start),
        .a_q12_flat(a_q12_flat), .ln_q12_flat(ln_q12_flat),
        .invalid_mask(invalid_mask), .busy(busy), .done(done)
    );

    task automatic set_ch(
        input integer ch, input integer input_q12,
        input integer math_ln_q12
    );
        begin
            a_q12_flat[ch*16 +: 16] = input_q12[15:0];
            golden[ch] = math_ln_q12;
        end
    endtask

    // Golden values = round(ln(input_Q12/4096.0)*4096),
    // calculated independently, not derived from the DUT's LUT.
    task automatic run_case(input integer case_no,
                            input logic [9:0] expected_invalid);
        integer got;
        integer cycles;
        begin
            @(negedge clk);
            start = 1'b1;
            @(posedge clk);
            #1;
            if (busy !== 1'b1 || done !== 1'b0)
                $fatal(1, "CASE %0d: START failed", case_no);
            @(negedge clk);
            start = 1'b0;

            cycles = 0;
            while (done !== 1'b1 && cycles < 25) begin
                @(posedge clk);
                #1;
                cycles = cycles + 1;
            end
            if (done !== 1'b1 || busy !== 1'b0)
                $fatal(1, "CASE %0d: ln CORDIC timeout", case_no);
            if (cycles != 16)
                $fatal(1, "CASE %0d: expected 16 stages, got %0d", case_no, cycles);
            if (invalid_mask !== expected_invalid)
                $fatal(1, "CASE %0d: bad invalid mask %03h", case_no, invalid_mask);

            for (integer ch = 0; ch < 10; ch = ch + 1) begin
                got = $signed(ln_q12_flat[ch*32 +: 32]);
                if (expected_invalid[ch]) begin
                    if (got !== 0)
                        $fatal(1, "CASE %0d CH%0d invalid result not zero", case_no,ch);
                    $display("CASE %0d CH%0d invalid input correctly flagged",case_no,ch);
                end else begin
                    $display("CASE %0d CH%0d ln_Q12=%0d expected=%0d diff=%0d",
                             case_no,ch,got,golden[ch],got-golden[ch]);
                    if (got < golden[ch]-3 || got > golden[ch]+3)
                        $fatal(1,"CASE %0d CH%0d ln error > 3 Q12 LSB",case_no,ch);
                end
            end

            // DONE remains asserted after completion (CPU can poll it later).
            repeat (3) @(posedge clk);
            #1;
            if (done !== 1'b1)
                $fatal(1,"CASE %0d: sticky DONE lost",case_no);
            $display("PASS: CASE %0d 10CH full ln complete in %0d iteration clocks",
                     case_no,cycles);
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        resetn = 1'b1;

        // CASE 1: 0.5 through 2.0, includes ln(1)=0, ln(1.5), ln(2)
        set_ch(0, 2048,-2839);  // ln(0.5)
        set_ch(1, 2560,-1925);
        set_ch(2, 3072,-1178);
        set_ch(3, 3584, -547);
        set_ch(4, 4096,    0);  // ln(1.0)
        set_ch(5, 4608,  482);
        set_ch(6, 5120,  914);
        set_ch(7, 5632, 1304);
        set_ch(8, 6144, 1661);  // ln(1.5)
        set_ch(9, 8192, 2839);  // ln(2.0)
        run_case(1, 10'h000);

        // CASE 2: another ten independent inputs, START can run again
        set_ch(0, 2304,-2357);
        set_ch(1, 2816,-1535);
        set_ch(2, 3328, -850);
        set_ch(3, 3840, -264);
        set_ch(4, 4352,  248);
        set_ch(5, 4864,  704);
        set_ch(6, 5376, 1114);
        set_ch(7, 5888, 1486);
        set_ch(8, 6912, 2143);
        set_ch(9, 7680, 2575);
        run_case(2, 10'h000);

        // CASE 3: invalid range is explicitly rejected, not silently clamped
        set_ch(0,    0,    0);  // ln(0) invalid
        set_ch(1, 1024,    0);  // below supported range
        set_ch(2, 3072,-1178);
        set_ch(3, 3584, -547);
        set_ch(4, 4096,    0);
        set_ch(5, 4608,  482);
        set_ch(6, 5120,  914);
        set_ch(7, 5632, 1304);
        set_ch(8, 6144, 1661);
        set_ch(9, 9000,    0);  // above supported range
        run_case(3, 10'h203);

        $display("=======================================");
        $display("ALL 10-CHANNEL FULL LN RTL TESTS PASSED");
        $display("=======================================");
        $finish;
    end

    initial begin
        #5000;
        $fatal(1,"Timeout: 10CH ln simulation did not finish");
    end
endmodule
