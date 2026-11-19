`timescale 1ns/1ps

module tb_miv_cpu_ln_exp_standalone;
    localparam logic [31:0] RAM_BASE   = 32'h6000_0000;
    localparam int unsigned RAM_WORDS  = 2048; // 8 KiB, byte-addressed via word index
    localparam logic [31:0] RESULT_ADDR = 32'h6000_1000;
    localparam logic [31:0] EXP_ADDR    = 32'h6000_1004;
    localparam logic [31:0] DONE_ADDR   = 32'h6000_1008;
    localparam logic [31:0] EXPECT_LN   = 32'd1660;   // 0x0000067C = ln(1.5) Q12
    localparam logic [31:0] EXPECT_EXP  = 32'd11134;  // 0x00002B7E = exp(1) Q12
    localparam logic [31:0] DONE_MARKER = 32'hC0DE_0002;
    localparam logic [31:0] LN_PC       = 32'h6000_0070;
    localparam logic [31:0] EXP_PC      = 32'h6000_00F4;
    localparam logic [31:0] CORDIC_INSN = 32'h06F7_578B;

    logic clk = 0;
    logic resetn = 0;
    always #5 clk = ~clk;

    logic [31:0] ram [0:RAM_WORDS-1];

    wire ifu_emi_req_valid;
    wire ifu_emi_req_ready;
    wire [31:0] ifu_emi_req_addr;
    logic ifu_emi_resp_valid = 0;
    wire ifu_emi_resp_ready;
    logic [31:0] ifu_emi_resp_data = 0;
    logic ifu_emi_resp_error = 0;

    wire lsu_emi_req_valid;
    wire lsu_emi_req_ready;
    wire [3:0] lsu_emi_req_wr_byte_en;
    wire [31:0] lsu_emi_req_addr;
    wire lsu_emi_req_read;
    wire lsu_emi_req_write;
    wire lsu_emi_req_fence;
    wire [31:0] lsu_emi_req_wr_data;
    logic lsu_emi_resp_valid = 0;
    wire lsu_emi_resp_ready;
    logic [31:0] lsu_emi_resp_rd_data = 0;
    logic lsu_emi_resp_error = 0;

    wire trace_valid;
    wire [31:0] trace_iaddr;
    wire [31:0] trace_insn;
    wire trace_exception;
    wire gpr_ram_init_done;

    integer retired = 0;
    int unsigned ln_cordic_count = 0;
    int unsigned exp_cordic_count = 0;
    bit seen_ln = 0;
    bit seen_exp = 0;
    bit seen_done_clear = 0;
    bit seen_done = 0;

    // The original RTL hart, NOT the earlier EXU-only testbench.
    miv_rv32_hart #(
        .l_core_reset_vector(RAM_BASE),
        .l_core_cfg_hw_debug(0),
        .l_core_cfg_hw_multiply_divide(0),
        .l_core_cfg_hw_compressed(0),
        .l_core_cfg_hw_sp_float(0),
        .l_core_cfg_gpr_type(1)
    ) dut (
        .clk(clk), .resetn(resetn),
        .core_soft_reset(1'b0),
        .parity_en(1'b0),
        .gpr_uncorrectable_ecc_error(),
        .time_count(64'd0),
        .hart_id(32'd0),

        .ifu_emi_req_valid(ifu_emi_req_valid),
        .ifu_emi_req_ready(ifu_emi_req_ready),
        .ifu_emi_req_rd_byte_en(),
        .ifu_emi_req_addr(ifu_emi_req_addr),
        .ifu_emi_req_addr_p(),
        .ifu_emi_resp_valid(ifu_emi_resp_valid),
        .ifu_emi_resp_ready(ifu_emi_resp_ready),
        .ifu_emi_resp_data(ifu_emi_resp_data),
        .ifu_emi_resp_data_p(4'b0000),
        .ifu_emi_resp_error(ifu_emi_resp_error),
        .icache_flush(),
        .ram_init_soft_debug_reset(),

        .lsu_emi_req_valid(lsu_emi_req_valid),
        .lsu_emi_req_ready(lsu_emi_req_ready),
        .lsu_emi_req_rd_byte_en(),
        .lsu_emi_req_wr_byte_en(lsu_emi_req_wr_byte_en),
        .lsu_emi_req_addr(lsu_emi_req_addr),
        .lsu_emi_req_addr_p(),
        .lsu_emi_req_fence(lsu_emi_req_fence),
        .lsu_emi_req_read(lsu_emi_req_read),
        .lsu_emi_req_write(lsu_emi_req_write),
        .lsu_emi_req_wr_data(lsu_emi_req_wr_data),
        .lsu_emi_req_wr_data_p(),
        .lsu_emi_resp_valid(lsu_emi_resp_valid),
        .lsu_emi_resp_ready(lsu_emi_resp_ready),
        .lsu_emi_resp_error(lsu_emi_resp_error),
        .lsu_emi_resp_rd_data(lsu_emi_resp_rd_data),
        .lsu_emi_resp_rd_data_p(4'b0000),

        .debug_reset(1'b0),
        .debug_core_reset(1'b0),
        .debug_active(1'b0),
        .debug_csr_gpr_req_wr_data(32'd0),
        .debug_csr_req_valid(1'b0),
        .debug_csr_req_ready(),
        .debug_csr_req_wr_en(1'b0),
        .debug_csr_req_rd_en(1'b0),
        .debug_csr_req_addr(12'd0),
        .debug_csr_resp_rd_data(),
        .debug_csr_resp_valid(),
        .debug_csr_resp_ready(1'b1),
        .debug_gpr_req_valid(1'b0),
        .debug_gpr_req_ready(),
        .debug_gpr_req_wr_en(1'b0),
        .debug_gpr_req_rd_en(1'b0),
        .debug_gpr_req_addr(6'd0),
        .debug_gpr_resp_rd_data(),
        .debug_gpr_resp_valid(),
        .debug_gpr_resp_ready(1'b1),
        .debug_halt_req(1'b0),
        .debug_halt_ack(),
        .debug_resethalt_req(1'b0),
        .debug_resethalt_ack(),
        .debug_resume_req(1'b0),
        .debug_resume_ack(),
        .debug_mode(),

        .m_sw_irq(1'b0),
        .m_timer_irq(1'b0),
        .m_external_irq(1'b0),
        .sys_ext_irq_src(10'd0),
        .formal_trace_instr(),
        .formal_trace_pc(),
        .formal_trace_reset_taken(),
        .formal_trace_instr_retire(),
        .trace_valid(trace_valid),
        .trace_iaddr(trace_iaddr),
        .trace_insn(trace_insn),
        .trace_priv(),
        .trace_exception(trace_exception),
        .trace_interrupt(),
        .trace_cause(),
        .trace_tval(),
        .icache_ram_init_done(1'b1),
        .gpr_ram_init_done(gpr_ram_init_done),
        .gpr_ecc_error_injection(2'b00)
    );

    function automatic bit in_ram(input logic [31:0] addr);
        return (addr >= RAM_BASE) && (addr < RAM_BASE + RAM_WORDS * 4);
    endfunction

    // One outstanding instruction read: request accepted on rising edge,
    // response valid from the following cycle, held until resp_ready.
    assign ifu_emi_req_ready = resetn && !ifu_emi_resp_valid;
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            ifu_emi_resp_valid <= 1'b0;
            ifu_emi_resp_data  <= 32'b0;
            ifu_emi_resp_error <= 1'b0;
        end else begin
            if (ifu_emi_resp_valid && ifu_emi_resp_ready)
                ifu_emi_resp_valid <= 1'b0;
            if (ifu_emi_req_valid && ifu_emi_req_ready) begin
                ifu_emi_resp_valid <= 1'b1;
                ifu_emi_resp_error <= !in_ram(ifu_emi_req_addr);
                if (in_ram(ifu_emi_req_addr)) begin
                    ifu_emi_resp_data <= ram[(ifu_emi_req_addr - RAM_BASE) >> 2];
                    if (retired < 25)
                        $display("IFETCH addr=%08h", ifu_emi_req_addr);
                end else begin
                    ifu_emi_resp_data <= 32'd0;
                    $display("IFETCH OUT OF RANGE: %08h", ifu_emi_req_addr);
                end
            end
        end
    end

    // One outstanding LSU operation: byte-enable writes and acknowledge
    // reads, writes, and fences one cycle after the accepted request.
    assign lsu_emi_req_ready = resetn && !lsu_emi_resp_valid;
    always @(posedge clk or negedge resetn) begin : data_memory
        integer lane;
        integer idx;
        if (!resetn) begin
            lsu_emi_resp_valid <= 1'b0;
            lsu_emi_resp_rd_data <= 32'b0;
            lsu_emi_resp_error <= 1'b0;
        end else begin
            if (lsu_emi_resp_valid && lsu_emi_resp_ready)
                lsu_emi_resp_valid <= 1'b0;
            if (lsu_emi_req_valid && lsu_emi_req_ready) begin
                lsu_emi_resp_valid <= 1'b1;
                lsu_emi_resp_error <= !in_ram(lsu_emi_req_addr);
                lsu_emi_resp_rd_data <= 32'b0;
                if (in_ram(lsu_emi_req_addr)) begin
                    idx = (lsu_emi_req_addr - RAM_BASE) >> 2;
                    if (lsu_emi_req_read)
                        lsu_emi_resp_rd_data <= ram[idx];
                    if (lsu_emi_req_write) begin
                        for (lane = 0; lane < 4; lane = lane + 1)
                            if (lsu_emi_req_wr_byte_en[lane])
                                ram[idx][lane*8 +: 8] <= lsu_emi_req_wr_data[lane*8 +: 8];
                        $display("CPU LSU WRITE %08h <- %08h  be=%b", lsu_emi_req_addr,
                                 lsu_emi_req_wr_data, lsu_emi_req_wr_byte_en);
                        if (lsu_emi_req_addr == RESULT_ADDR) begin
                            if (lsu_emi_req_wr_byte_en !== 4'b1111 ||
                                lsu_emi_req_wr_data !== EXPECT_LN)
                                $fatal(1, "ln(1.5) wrong: expected %08h got %08h",
                                       EXPECT_LN, lsu_emi_req_wr_data);
                            seen_ln <= 1'b1;
                            $display("PASS: CPU stored ln(1.5) Q12=%0d", EXPECT_LN);
                        end
                        if (lsu_emi_req_addr == EXP_ADDR) begin
                            if (lsu_emi_req_wr_byte_en !== 4'b1111 ||
                                lsu_emi_req_wr_data !== EXPECT_EXP)
                                $fatal(1, "exp(1) wrong: expected %08h got %08h",
                                       EXPECT_EXP, lsu_emi_req_wr_data);
                            seen_exp <= 1'b1;
                            $display("PASS: CPU stored exp(1) Q12=%0d", EXPECT_EXP);
                        end
                        if (lsu_emi_req_addr == DONE_ADDR) begin
                            if (lsu_emi_req_wr_byte_en !== 4'b1111)
                                $fatal(1, "Invalid completion marker byte enable");
                            if (lsu_emi_req_wr_data == 32'd0) begin
                                seen_done_clear <= 1'b1;
                                $display("CPU cleared completion marker");
                            end else if (lsu_emi_req_wr_data == DONE_MARKER) begin
                                seen_done <= 1'b1;
                                $display("CPU wrote final completion marker");
                            end else begin
                                $fatal(1, "Unexpected completion marker=%08h",
                                       lsu_emi_req_wr_data);
                            end
                        end
                    end
                end else begin
                    $display("LSU OUT OF RANGE: %08h", lsu_emi_req_addr);
                end
            end
        end
    end

    // CPU retire trace proves instruction was executed by the real hart.
    always @(posedge clk) begin
        if (resetn && trace_valid) begin
            retired <= retired + 1;
            if (retired < 25)
                $display("RETIRED PC=%08h INSN=%08h exception=%b", trace_iaddr,
                         trace_insn, trace_exception);
            // Two custom instruction sites in the uploaded ELF, each retired 13 times.
            if (trace_insn[6:0] == 7'h0B) begin
                if (trace_insn !== CORDIC_INSN)
                    $fatal(1, "Unexpected custom instruction: %08h", trace_insn);
                if (trace_iaddr == LN_PC) begin
                    ln_cordic_count <= ln_cordic_count + 1;
                    $display("LN CORDIC retired, count=%0d", ln_cordic_count + 1);
                    if (ln_cordic_count >= 13)
                        $fatal(1, "Too many ln CORDIC instructions");
                end else if (trace_iaddr == EXP_PC) begin
                    exp_cordic_count <= exp_cordic_count + 1;
                    $display("EXP CORDIC retired, count=%0d", exp_cordic_count + 1);
                    if (exp_cordic_count >= 13)
                        $fatal(1, "Too many exp CORDIC instructions");
                end else begin
                    $fatal(1, "Unexpected CORDIC location PC=%08h", trace_iaddr);
                end
            end
            if (trace_exception)
                $fatal(1, "CPU exception PC=%08h instr=%08h", trace_iaddr, trace_insn);
        end
    end

    initial begin
        $display("Loading embedded SoftConsole ln/exp program ...");
        // Embedded from the latest SoftConsole ELF/HEX (436 bytes). No .mem file needed.
        for (int word_i = 0; word_i < RAM_WORDS; word_i++) ram[word_i] = 32'h00000000;
        ram[  0] = 32'h00002117;
        ram[  1] = 32'hFF010113;
        ram[  2] = 32'h0040006F;
        ram[  3] = 32'h600006B7;
        ram[  4] = 32'h600017B7;
        ram[  5] = 32'h00001637;
        ram[  6] = 32'h00003737;
        ram[  7] = 32'h000108B7;
        ram[  8] = 32'h18468513;
        ram[  9] = 32'h0007A423;
        ram[ 10] = 32'h18468693;
        ram[ 11] = 32'h80060613;
        ram[ 12] = 32'h80070713;
        ram[ 13] = 32'h00000593;
        ram[ 14] = 32'h00100813;
        ram[ 15] = 32'h00100313;
        ram[ 16] = 32'hFFF88893;
        ram[ 17] = 32'h00D00E93;
        ram[ 18] = 32'h00400F13;
        ram[ 19] = 32'h01881F93;
        ram[ 20] = 32'h00000E13;
        ram[ 21] = 32'h011677B3;
        ram[ 22] = 32'h01071713;
        ram[ 23] = 32'h00F76733;
        ram[ 24] = 32'hFFF64793;
        ram[ 25] = 32'h01F7D793;
        ram[ 26] = 32'h01F79793;
        ram[ 27] = 32'h01F7E7B3;
        ram[ 28] = 32'h06F7578B;
        ram[ 29] = 32'h4107D713;
        ram[ 30] = 32'h01079793;
        ram[ 31] = 32'h4107D793;
        ram[ 32] = 32'h0C064E63;
        ram[ 33] = 32'h0006A603;
        ram[ 34] = 32'h001E0E13;
        ram[ 35] = 32'h00C585B3;
        ram[ 36] = 32'h00078613;
        ram[ 37] = 32'hFC6E10E3;
        ram[ 38] = 32'h00180813;
        ram[ 39] = 32'h0BD81463;
        ram[ 40] = 32'h600017B7;
        ram[ 41] = 32'h00159593;
        ram[ 42] = 32'h00001737;
        ram[ 43] = 32'h00010837;
        ram[ 44] = 32'h00B7A023;
        ram[ 45] = 32'h35270713;
        ram[ 46] = 32'h00000793;
        ram[ 47] = 32'h4E900613;
        ram[ 48] = 32'h00100693;
        ram[ 49] = 32'h00100893;
        ram[ 50] = 32'hFFF80813;
        ram[ 51] = 32'h00D00E13;
        ram[ 52] = 32'h00400E93;
        ram[ 53] = 32'h01869F13;
        ram[ 54] = 32'h00000313;
        ram[ 55] = 32'h0107F7B3;
        ram[ 56] = 32'h01071713;
        ram[ 57] = 32'h00F76733;
        ram[ 58] = 32'h01F65793;
        ram[ 59] = 32'h01F79793;
        ram[ 60] = 32'h01E7E7B3;
        ram[ 61] = 32'h06F7578B;
        ram[ 62] = 32'h4107D713;
        ram[ 63] = 32'h01079793;
        ram[ 64] = 32'h4107D793;
        ram[ 65] = 32'h00052583;
        ram[ 66] = 32'h06064A63;
        ram[ 67] = 32'h00130313;
        ram[ 68] = 32'h40B60633;
        ram[ 69] = 32'hFD1314E3;
        ram[ 70] = 32'h00168693;
        ram[ 71] = 32'h05C69663;
        ram[ 72] = 32'h00F707B3;
        ram[ 73] = 32'h00179793;
        ram[ 74] = 32'h60001737;
        ram[ 75] = 32'h00F72223;
        ram[ 76] = 32'hC0DE07B7;
        ram[ 77] = 32'h00278793;
        ram[ 78] = 32'h00F72423;
        ram[ 79] = 32'h00000013;
        ram[ 80] = 32'hFFDFF06F;
        ram[ 81] = 32'h00200313;
        ram[ 82] = 32'h01E80463;
        ram[ 83] = 32'h00100313;
        ram[ 84] = 32'h00468693;
        ram[ 85] = 32'h00078613;
        ram[ 86] = 32'hEF5FF06F;
        ram[ 87] = 32'h0006A603;
        ram[ 88] = 32'h40C00633;
        ram[ 89] = 32'hF25FF06F;
        ram[ 90] = 32'h00200893;
        ram[ 91] = 32'h01D68463;
        ram[ 92] = 32'h00100893;
        ram[ 93] = 32'h00450513;
        ram[ 94] = 32'hF5DFF06F;
        ram[ 95] = 32'h40B005B3;
        ram[ 96] = 32'hF8DFF06F;
        ram[ 97] = 32'h000008CA;
        ram[ 98] = 32'h00000416;
        ram[ 99] = 32'h00000203;
        ram[100] = 32'h00000100;
        ram[101] = 32'h00000080;
        ram[102] = 32'h00000040;
        ram[103] = 32'h00000020;
        ram[104] = 32'h00000010;
        ram[105] = 32'h00000008;
        ram[106] = 32'h00000004;
        ram[107] = 32'h00000002;
        ram[108] = 32'h00000001;
        // Fail early if the wrong .mem (the old single-CORDIC firmware) was loaded.
        if (ram[(LN_PC - RAM_BASE) >> 2] !== CORDIC_INSN ||
            ram[(EXP_PC - RAM_BASE) >> 2] !== CORDIC_INSN)
            $fatal(1, "Incorrect firmware image: missing ln/exp CORDIC instruction words");
        repeat (8) @(negedge clk);
        resetn = 1'b1;
        wait (seen_done);
        @(negedge clk);
        if (!seen_done_clear || !seen_ln || !seen_exp)
            $fatal(1, "Missing software stores: clear=%b ln=%b exp=%b",
                   seen_done_clear, seen_ln, seen_exp);
        if (ln_cordic_count !== 13 || exp_cordic_count !== 13)
            $fatal(1, "Custom instruction count mismatch: ln=%0d exp=%0d",
                   ln_cordic_count, exp_cordic_count);
        if (ram[(RESULT_ADDR - RAM_BASE) >> 2] !== EXPECT_LN ||
            ram[(EXP_ADDR    - RAM_BASE) >> 2] !== EXPECT_EXP ||
            ram[(DONE_ADDR   - RAM_BASE) >> 2] !== DONE_MARKER)
            $fatal(1, "Final RAM results mismatch");
        $display("==============================================");
        $display("PASS: Mi-V CPU retired 13 ln CORDIC instructions");
        $display("PASS: Mi-V CPU retired 13 exp CORDIC instructions");
        $display("PASS: ln(1.5) = %0d / 4096 = %f", EXPECT_LN, $itor(EXPECT_LN)/4096.0);
        $display("PASS: exp(1)  = %0d / 4096 = %f", EXPECT_EXP, $itor(EXPECT_EXP)/4096.0);
        $display("PASS: CPU wrote completion marker C0DE0002");
        $display("FULL CPU LN/EXP CORDIC INTEGRATION PASSED");
        $display("==============================================");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "TIMEOUT: CPU has not written completion marker");
    end
endmodule
