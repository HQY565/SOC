`timescale 1ns/1ps

module tb_cordic_exp_parallel_10ch;
    logic clk = 1'b0;
    logic resetn = 1'b0;
    logic start = 1'b0;
    logic [159:0] in_q12_flat = 160'd0;
    wire [319:0] exp_q12_flat;
    wire [9:0] invalid_mask;
    wire busy;
    wire done;
    integer golden [0:9];

    always #5 clk = ~clk;

    cordic_exp_parallel_10ch dut (
        .clk(clk), .resetn(resetn), .start(start),
        .in_q12_flat(in_q12_flat), .exp_q12_flat(exp_q12_flat),
        .invalid_mask(invalid_mask), .busy(busy), .done(done)
    );

    task automatic set_ch(input integer ch, input integer q12, input integer expect_q12);
        begin
            in_q12_flat[ch*16 +: 16] = q12[15:0];
            golden[ch] = expect_q12;
        end
    endtask

    task automatic test_case(input integer id, input logic [9:0] expected_invalid);
        integer cycles;
        integer got;
        begin
            @(negedge clk);
            start = 1'b1;
            @(posedge clk);
            #1;
            if (busy !== 1'b1 || done !== 1'b0)
                $fatal(1, "CASE %0d: START failed", id);
            @(negedge clk);
            start = 1'b0;
            cycles = 0;
            while (done !== 1'b1 && cycles < 25) begin
                @(posedge clk);
                #1;
                cycles = cycles + 1;
            end
            if (done !== 1'b1 || busy !== 1'b0 || cycles != 16)
                $fatal(1, "CASE %0d: expected DONE after 16 clocks; got %0d", id, cycles);
            if (invalid_mask !== expected_invalid)
                $fatal(1, "CASE %0d: invalid_mask=%03h expected=%03h",
                       id, invalid_mask, expected_invalid);
            for (integer ch = 0; ch < 10; ch = ch + 1) begin
                got = $signed(exp_q12_flat[ch*32 +: 32]);
                $display("CASE %0d CH%0d exp_Q12=%0d expected=%0d", id, ch, got, golden[ch]);
                if (expected_invalid[ch]) begin
                    if (got !== 0)
                        $fatal(1, "CASE %0d CH%0d: invalid output not zero", id, ch);
                end
                else if (got < golden[ch]-3 || got > golden[ch]+3)
                    $fatal(1, "CASE %0d CH%0d: exp mismatch", id, ch);
            end
            repeat (3) @(posedge clk);
            #1;
            if (done !== 1'b1)
                $fatal(1, "CASE %0d: sticky DONE lost", id);
            $display("PASS: CASE %0d 10CH full exp complete in %0d iteration clocks", id, cycles);
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        resetn = 1'b1;

        // Input is signed Q12; exp output is unsigned positive Q12.
        set_ch(0,-2839,2048); set_ch(1,-2500,2225);
        set_ch(2,-2048,2484); set_ch(3,-1661,2731);
        set_ch(4,-1178,3072); set_ch(5, -914,3277);
        set_ch(6, -482,3641); set_ch(7,    0,4096);
        set_ch(8,  914,5120); set_ch(9, 2839,8192);
        test_case(1,10'h000);

        set_ch(0,-2600,2171); set_ch(1,-1400,2910);
        set_ch(2, -700,3453); set_ch(3, -100,3997);
        set_ch(4,  100,4197); set_ch(5,  482,4608);
        set_ch(6, 1178,5461); set_ch(7, 1661,6144);
        set_ch(8, 2200,7008); set_ch(9, 2600,7727);
        test_case(2,10'h000);

        // CH0 and CH9 are deliberately outside [-2839,+2839].
        set_ch(0,-3000,0);    set_ch(1,-2839,2048);
        set_ch(2,-1000,3209); set_ch(3,    0,4096);
        set_ch(4,  200,4301); set_ch(5,  550,4685);
        set_ch(6, 1000,5229); set_ch(7, 1661,6144);
        set_ch(8, 2839,8192); set_ch(9, 3000,0);
        test_case(3,10'h201);

        $display("=========================================");
        $display("ALL 10-CHANNEL FULL EXP RTL TESTS PASSED");
        $display("=========================================");
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "Full exp simulation timeout");
    end
endmodule
