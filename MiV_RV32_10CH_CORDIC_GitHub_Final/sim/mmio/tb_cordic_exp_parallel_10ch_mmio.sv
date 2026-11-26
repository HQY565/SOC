`timescale 1ns/1ps

module tb_cordic_exp_parallel_10ch_mmio;
    localparam logic [31:0] BASE       = 32'h6001_0000;
    localparam logic [31:0] START_REG  = BASE + 32'h80;
    localparam logic [31:0] STATUS_REG = BASE + 32'h84;
    localparam logic [31:0] INVALID_REG= BASE + 32'h88;
    localparam logic [31:0] OUT_BASE   = BASE + 32'h100;

    logic clk = 1'b0;
    logic resetn = 1'b0;
    always #5 clk = ~clk;

    logic bus_valid = 1'b0;
    logic bus_write = 1'b0;
    logic [31:0] bus_addr = 32'd0;
    logic [31:0] bus_wdata = 32'd0;
    wire bus_ready;
    wire bus_resp_valid;
    logic bus_resp_ready = 1'b0;
    wire [31:0] bus_rdata;
    wire bus_error;
    wire busy;
    wire done_sticky;
    integer golden [0:9];

    cordic_exp_parallel_10ch_mmio dut (
        .clk(clk), .resetn(resetn),
        .bus_valid(bus_valid), .bus_write(bus_write),
        .bus_addr(bus_addr), .bus_wdata(bus_wdata),
        .bus_ready(bus_ready),
        .bus_resp_valid(bus_resp_valid),
        .bus_resp_ready(bus_resp_ready),
        .bus_rdata(bus_rdata), .bus_error(bus_error),
        .busy(busy), .done_sticky(done_sticky)
    );

    task automatic access_reg(
        input  logic        wr,
        input  logic [31:0] addr,
        input  logic [31:0] data,
        output logic [31:0] result,
        output logic        error
    );
        begin
            @(negedge clk);
            while (bus_ready !== 1'b1)
                @(negedge clk);
            bus_valid = 1'b1;
            bus_write = wr;
            bus_addr = addr;
            bus_wdata = data;
            @(posedge clk);
            #1;
            if (bus_resp_valid !== 1'b1)
                $fatal(1, "MMIO response missing addr=%08h", addr);
            result = bus_rdata;
            error = bus_error;
            // Stall response for one clock: payload must remain stable.
            @(posedge clk);
            #1;
            if ((bus_resp_valid !== 1'b1) ||
                (bus_rdata !== result) || (bus_error !== error))
                $fatal(1, "MMIO response not held stable");
            @(negedge clk);
            bus_valid = 1'b0;
            bus_resp_ready = 1'b1;
            @(posedge clk);
            #1;
            if (bus_resp_valid !== 1'b0)
                $fatal(1, "MMIO response did not retire");
            bus_resp_ready = 1'b0;
        end
    endtask

    task automatic write_ok(input logic [31:0] addr, input logic [31:0] data);
        logic [31:0] r;
        logic err;
        begin
            access_reg(1'b1, addr, data, r, err);
            if (err) $fatal(1, "MMIO WRITE failed addr=%08h", addr);
        end
    endtask

    task automatic read_ok(input logic [31:0] addr, output logic [31:0] r);
        logic err;
        begin
            access_reg(1'b0, addr, 32'd0, r, err);
            if (err) $fatal(1, "MMIO READ failed addr=%08h", addr);
        end
    endtask

    task automatic load_ch(input integer ch, input integer in_q12,
                           input integer expected_q12);
        begin
            write_ok(BASE + 4*ch, in_q12);
            golden[ch] = expected_q12;
        end
    endtask

    task automatic run_case(input integer case_id,
                            input logic [9:0] expected_invalid);
        logic [31:0] status;
        logic [31:0] invalid;
        logic [31:0] value;
        integer count;
        integer got;
        begin
            write_ok(START_REG, 32'd1);
            status = 32'd0;
            count = 0;
            while ((status[0] !== 1'b1) && (count < 40)) begin
                read_ok(STATUS_REG, status);
                count = count + 1;
            end
            if (status !== 32'h0000_0001)
                $fatal(1, "CASE %0d: bad STATUS=%08h", case_id, status);
            repeat (3) @(posedge clk);
            read_ok(STATUS_REG, status);
            if (status !== 32'h0000_0001)
                $fatal(1, "CASE %0d: sticky DONE lost", case_id);
            read_ok(INVALID_REG, invalid);
            if (invalid !== {22'd0, expected_invalid})
                $fatal(1, "CASE %0d: bad INVALID=%08h", case_id, invalid);
            for (integer ch=0; ch<10; ch=ch+1) begin
                read_ok(OUT_BASE + 4*ch, value);
                got = $signed(value);
                $display("CASE %0d CH%0d exp_Q12=%0d expected=%0d",
                         case_id, ch, got, golden[ch]);
                if (expected_invalid[ch]) begin
                    if (got !== 0)
                        $fatal(1, "CASE %0d CH%0d invalid result", case_id, ch);
                end
                else if ((got < golden[ch]-3) || (got > golden[ch]+3))
                    $fatal(1, "CASE %0d CH%0d wrong exp output", case_id, ch);
            end
            $display("PASS: CASE %0d 10CH full exp MMIO", case_id);
        end
    endtask

    logic [31:0] rdata;
    logic error;
    initial begin
        repeat (4) @(negedge clk);
        resetn = 1'b1;

        // Reading a result before the first START must fail.
        access_reg(1'b0, OUT_BASE, 32'd0, rdata, error);
        if ((error !== 1'b1) || (rdata !== 32'hDEAD_BEEF))
            $fatal(1, "Premature read not rejected");
        $display("PASS: premature EXP result READ rejected");

        // CASE 1 matches the already passed independent EXP RTL test.
        load_ch(0,-2839,2048);
        load_ch(1,-2500,2225);
        load_ch(2,-2048,2484);
        load_ch(3,-1661,2731);
        load_ch(4,-1178,3072);
        load_ch(5, -914,3277);
        load_ch(6, -482,3641);
        load_ch(7,    0,4096);
        load_ch(8,  914,5120);
        load_ch(9, 2839,8192);
        run_case(1, 10'h000);

        // Reject undefined address and writes to read-only registers.
        access_reg(1'b0, BASE + 32'h28, 32'd0, rdata, error);
        if (error !== 1'b1) $fatal(1, "Invalid address accepted");
        access_reg(1'b1, STATUS_REG, 32'd1, rdata, error);
        if (error !== 1'b1) $fatal(1, "STATUS write accepted");
        access_reg(1'b1, INVALID_REG, 32'd0, rdata, error);
        if (error !== 1'b1) $fatal(1, "INVALID write accepted");
        // 0x0000FFFF is not a proper sign extension of signed 16-bit -1.
        access_reg(1'b1, BASE, 32'h0000_FFFF, rdata, error);
        if (error !== 1'b1) $fatal(1, "Bad sign extension accepted");
        $display("PASS: invalid MMIO accesses/sign extension rejected");

        // CASE 2 includes invalid signed-Q12 inputs CH0 and CH9.
        load_ch(0,-3000,0);
        load_ch(1,-2839,2048);
        load_ch(2,-1000,3209);
        load_ch(3,    0,4096);
        load_ch(4,  200,4301);
        load_ch(5,  550,4685);
        load_ch(6, 1000,5229);
        load_ch(7, 1661,6144);
        load_ch(8, 2839,8192);
        load_ch(9, 3000,0);
        run_case(2, 10'h201);

        $display("========================================");
        $display("ALL 10CH FULL EXP MMIO TESTS PASSED");
        $display("========================================");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1,"EXP MMIO simulation timeout");
    end
endmodule
