`timescale 1ns/1ps

// Real Mi-V RV32 hart loads the exact SoftConsole 10-channel FULL EXP firmware Intel HEX
// converted to embedded little-endian memory words below.
// Routes LSU MMIO to full-exp Q12 peripheral at 0x60010000..0x60010127.
// No Microchip SoC integration or physical FPGA hardware is claimed.
module tb_miv_cpu_exp10_perf;
    localparam string PERF_TAG = "EXP";
    localparam logic [31:0] RAM_BASE    = 32'h6000_0000;
    localparam int unsigned RAM_WORDS   = 2048; // 8 KiB
    localparam logic [31:0] MMIO_BASE   = 32'h6001_0000;
    localparam logic [31:0] RESULT_BASE = 32'h6000_1000;
    localparam logic [31:0] DONE_ADDR   = 32'h6000_1040;
    localparam logic [31:0] DONE_MARKER = 32'hC0DE_200A;
    localparam int NUM_CH = 10;

    // Exact SoftConsole full-exp test inputs, signed Q12 (x / 4096.0).
    function automatic logic [31:0] input_for(input integer ch);
        case (ch)
            0: input_for = -32'sd2839;
            1: input_for = -32'sd2500;
            2: input_for = -32'sd2048;
            3: input_for = -32'sd1661;
            4: input_for = -32'sd1178;
            5: input_for = -32'sd914;
            6: input_for = -32'sd482;
            7: input_for = 32'd0;
            8: input_for = 32'd914;
            9: input_for = 32'd2839;
            default: input_for = 32'hXXXX_XXXX;
        endcase
    endfunction

    function automatic integer signed expected_for(input integer ch);
        case (ch)
            0: expected_for = 2048;
            1: expected_for = 2225;
            2: expected_for = 2484;
            3: expected_for = 2731;
            4: expected_for = 3072;
            5: expected_for = 3277;
            6: expected_for = 3641;
            7: expected_for = 4096;
            8: expected_for = 5120;
            9: expected_for = 8192;
            default: expected_for = 0;
        endcase
    endfunction

    // Validate signed result within +/-3 Q12 LSB; reject unknown (X/Z) data.
    function automatic bit exp_matches(input integer ch,
                                      input logic [31:0] raw_data);
        integer signed got;
        begin
            got = $signed(raw_data);
            exp_matches = ((^raw_data !== 1'bx) &&
                          (got >= expected_for(ch) - 3) &&
                          (got <= expected_for(ch) + 3));
        end
    endfunction

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
    wire lsu_emi_resp_valid;
    wire lsu_emi_resp_ready;
    wire [31:0] lsu_emi_resp_rd_data;
    wire lsu_emi_resp_error;

    wire trace_valid;
    wire [31:0] trace_iaddr;
    wire [31:0] trace_insn;
    wire trace_exception;
    wire gpr_ram_init_done;

    integer retired = 0;
    bit seen_done_clear = 0;
    bit seen_done = 0;
    bit seen_parallel_start = 0;
    integer start_count = 0;
    bit seen_status_done = 0;
    bit [9:0] seen_input = '0;
    bit seen_invalid_read = 0;
    bit [9:0] seen_read = '0;
    bit [9:0] seen_ram_result = '0;

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

    // This range must include START 0x80, STATUS 0x84 and results 0x100..0x124.
    function automatic bit to_cordic_mmio(input logic [31:0] addr);
        return (addr >= MMIO_BASE) && (addr < MMIO_BASE + 32'h128);
    endfunction

    wire mmio_select = to_cordic_mmio(lsu_emi_req_addr);
    wire mmio_bus_ready;
    wire mmio_bus_resp_valid;
    wire [31:0] mmio_bus_rdata;
    wire mmio_bus_error;
    wire mmio_busy, mmio_done_sticky;
    logic mmio_pending;
    logic [31:0] mmio_active_addr;
    logic mmio_active_write;
    logic ram_resp_valid;
    logic [31:0] ram_resp_rd_data;
    logic ram_resp_error;

    assign lsu_emi_req_ready = resetn && !mmio_pending && !ram_resp_valid &&
                               (!mmio_select || mmio_bus_ready);
    wire mmio_bus_valid = resetn && lsu_emi_req_valid && mmio_select &&
                          !mmio_pending && !ram_resp_valid;
    wire mmio_bus_resp_ready = mmio_pending && lsu_emi_resp_ready;

    assign lsu_emi_resp_valid = mmio_pending ? mmio_bus_resp_valid : ram_resp_valid;
    assign lsu_emi_resp_rd_data = mmio_pending ? mmio_bus_rdata : ram_resp_rd_data;
    assign lsu_emi_resp_error = mmio_pending ? mmio_bus_error : ram_resp_error;

    cordic_exp_parallel_10ch_mmio #(.BASE(MMIO_BASE)) u_cordic_mmio (
        .clk(clk), .resetn(resetn),
        .bus_valid(mmio_bus_valid),
        .bus_write(lsu_emi_req_write),
        .bus_addr(lsu_emi_req_addr),
        .bus_wdata(lsu_emi_req_wr_data),
        .bus_ready(mmio_bus_ready),
        .bus_resp_valid(mmio_bus_resp_valid),
        .bus_resp_ready(mmio_bus_resp_ready),
        .bus_rdata(mmio_bus_rdata),
        .bus_error(mmio_bus_error),
        .busy(mmio_busy),
        .done_sticky(mmio_done_sticky)
    );

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


    // CPU LSU bus: route requests to RAM or full-exp 10-channel MMIO peripheral.
    // The 'CPU MMIO' transcript messages originate from actual Mi-V hart LSU pins.
    always @(posedge clk or negedge resetn) begin : data_memory
        integer lane;
        integer idx;
        integer ch;
        logic [31:0] offset;
        if (!resetn) begin
            ram_resp_valid      <= 1'b0;
            ram_resp_rd_data    <= 32'd0;
            ram_resp_error      <= 1'b0;
            mmio_pending        <= 1'b0;
            mmio_active_addr    <= 32'd0;
            mmio_active_write   <= 1'b0;
            seen_done_clear     <= 1'b0;
            seen_done           <= 1'b0;
            seen_parallel_start <= 1'b0;
            start_count <= 0;
            seen_status_done    <= 1'b0;
            seen_input          <= '0;
            seen_invalid_read   <= 1'b0;
            seen_read           <= '0;
            seen_ram_result     <= '0;
        end else begin
            if (ram_resp_valid && lsu_emi_resp_ready)
                ram_resp_valid <= 1'b0;

            if (mmio_pending && mmio_bus_resp_valid && lsu_emi_resp_ready) begin
                mmio_pending <= 1'b0;
                if (mmio_bus_error)
                    $fatal(1, "CPU MMIO access error: address=%08h", mmio_active_addr);
                if (!mmio_active_write) begin
                    $display("CPU MMIO READ  %08h -> %08h", mmio_active_addr, mmio_bus_rdata);
                    if (mmio_active_addr == MMIO_BASE + 32'h84) begin
                        if (mmio_bus_rdata == 32'h0000_0001)
                            seen_status_done <= 1'b1;
                        else if (mmio_bus_rdata !== 32'h0000_0000 &&
                                 mmio_bus_rdata !== 32'h0000_0002)
                            $fatal(1, "Invalid CPU-read STATUS: %08h", mmio_bus_rdata);
                    end else if (mmio_active_addr == MMIO_BASE + 32'h88) begin
                        if (mmio_bus_rdata !== 32'h0000_0000)
                            $fatal(1, "Firmware reported invalid exp inputs: %08h", mmio_bus_rdata);
                        seen_invalid_read <= 1'b1;
                    end else if (mmio_active_addr >= MMIO_BASE + 32'h100 &&
                                 mmio_active_addr < MMIO_BASE + 32'h128 &&
                                 mmio_active_addr[1:0] == 2'b00) begin
                        ch = (mmio_active_addr - (MMIO_BASE + 32'h100)) >> 2;
                        if (ch < 0 || ch >= NUM_CH)
                            $fatal(1, "Invalid CPU-read result channel %0d", ch);
                        if (!seen_status_done || !seen_invalid_read)
                            $fatal(1, "Result read before STATUS DONE/INVALID check");
                        if (!exp_matches(ch, mmio_bus_rdata))
                            $fatal(1, "CPU read CH%0d exp_Q12 wrong: got=%0d expected=%0d",
                                   ch, $signed(mmio_bus_rdata), expected_for(ch));
                        seen_read[ch] <= 1'b1;
                    end else
                        $fatal(1, "Unexpected MMIO read address=%08h", mmio_active_addr);
                end
            end

            if (lsu_emi_req_valid && lsu_emi_req_ready) begin
                if (mmio_select) begin
                    if ((lsu_emi_req_read ^ lsu_emi_req_write) !== 1'b1)
                        $fatal(1, "MMIO requires exactly one of READ or WRITE");
                    if (lsu_emi_req_addr[1:0] !== 2'b00)
                        $fatal(1, "Unaligned CPU MMIO access: %08h", lsu_emi_req_addr);
                    if (lsu_emi_req_write && lsu_emi_req_wr_byte_en !== 4'b1111)
                        $fatal(1, "CPU MMIO needs full word stores");
                    mmio_pending      <= 1'b1;
                    mmio_active_addr  <= lsu_emi_req_addr;
                    mmio_active_write <= lsu_emi_req_write;
                    if (lsu_emi_req_write) begin
                        $display("CPU MMIO WRITE %08h <- %08h", lsu_emi_req_addr,
                                 lsu_emi_req_wr_data);
                        offset = lsu_emi_req_addr - MMIO_BASE;
                        if (offset < 32'h28 && offset[1:0] == 2'b00) begin
                            ch = offset >> 2;
                            if (ch < 0 || ch >= NUM_CH)
                                $fatal(1, "Invalid exp input channel %0d", ch);
                            if (lsu_emi_req_wr_data !== input_for(ch))
                                $fatal(1, "CH%0d input mismatch: %08h expected %08h",
                                       ch, lsu_emi_req_wr_data, input_for(ch));
                            seen_input[ch] <= 1'b1;
                        end else if (offset == 32'h80) begin
                            if (lsu_emi_req_wr_data !== 32'd1 || seen_input !== 10'h3FF)
                                $fatal(1, "START occurred before all ten exp input writes");
                            seen_parallel_start <= 1'b1;
                            start_count <= start_count + 1;
                        end else
                            $fatal(1, "Unexpected MMIO CPU write address=%08h", lsu_emi_req_addr);
                    end
                end else begin
                    ram_resp_valid   <= 1'b1;
                    ram_resp_error   <= !in_ram(lsu_emi_req_addr);
                    ram_resp_rd_data <= 32'd0;
                    if (in_ram(lsu_emi_req_addr)) begin
                        idx = (lsu_emi_req_addr - RAM_BASE) >> 2;
                        if (lsu_emi_req_read)
                            ram_resp_rd_data <= ram[idx];
                        if (lsu_emi_req_write) begin
                            for (lane = 0; lane < 4; lane = lane + 1)
                                if (lsu_emi_req_wr_byte_en[lane])
                                    ram[idx][lane*8 +: 8] <= lsu_emi_req_wr_data[lane*8 +: 8];
                            $display("CPU LSU WRITE  %08h <- %08h be=%b",
                                     lsu_emi_req_addr, lsu_emi_req_wr_data,
                                     lsu_emi_req_wr_byte_en);
                            if (lsu_emi_req_addr >= RESULT_BASE &&
                                lsu_emi_req_addr < RESULT_BASE + NUM_CH*4 &&
                                lsu_emi_req_addr[1:0] == 2'b00) begin
                                ch = (lsu_emi_req_addr - RESULT_BASE) >> 2;
                                if (lsu_emi_req_wr_byte_en !== 4'b1111)
                                    $fatal(1, "CH%0d RAM result store is not full word", ch);
                                // Initial clearing writes zero before READs are ignored.
                                // Real result writes must follow MMIO reads.
                                if (seen_read[ch]) begin
                                    if (!exp_matches(ch, lsu_emi_req_wr_data))
                                        $fatal(1, "CH%0d RAM result wrong: got=%0d expected=%0d",
                                               ch, $signed(lsu_emi_req_wr_data), expected_for(ch));
                                    seen_ram_result[ch] <= 1'b1;
                                end else if (lsu_emi_req_wr_data !== 32'd0) begin
                                    $fatal(1, "Unexpected nonzero RAM write before CH%0d MMIO read", ch);
                                end
                            end
                            if (lsu_emi_req_addr == DONE_ADDR) begin
                                if (lsu_emi_req_wr_byte_en !== 4'b1111)
                                    $fatal(1, "Invalid completion store byte enables");
                                if (lsu_emi_req_wr_data == 32'd0)
                                    seen_done_clear <= 1'b1;
                                else if (lsu_emi_req_wr_data == DONE_MARKER)
                                    seen_done <= 1'b1;
                                else
                                    $fatal(1, "Firmware failure marker: %08h", lsu_emi_req_wr_data);
                            end
                        end
                    end else begin
                        $fatal(1, "CPU LSU RAM address out of range: %08h", lsu_emi_req_addr);
                    end
                end
            end
        end
    end

    // CPU retire trace: check the program is executed by the actual hart.
    always @(posedge clk) begin
        if (resetn && trace_valid) begin
            retired <= retired + 1;
            if (retired < 50)
                $display("RETIRED PC=%08h INSN=%08h exception=%b", trace_iaddr,
                         trace_insn, trace_exception);
            if (trace_exception)
                $fatal(1, "CPU exception PC=%08h INSN=%08h", trace_iaddr, trace_insn);
            // This full-exp MMIO firmware uses ordinary RISC-V lw/sw, not CORDIC_END.
            if (trace_insn[6:0] == 7'h0B)
                $fatal(1, "Unexpected CORDIC custom instruction in MMIO firmware");
        end
    end


    initial begin
        $display("Loading exact SoftConsole 10CH FULL EXP firmware (392 bytes, 98 words)...");
        for (int word_i = 0; word_i < RAM_WORDS; word_i++)
            ram[word_i] = 32'h0000_0000;
        // Embedded Intel HEX validated: record lengths, checksums, entry address,
        // endian order, and contiguous bytes from 0x60000000 through 0x60000187.
        ram[  0] = 32'h00002117;
        ram[  1] = 32'hFF010113;
        ram[  2] = 32'h0040006F;
        ram[  3] = 32'h600017B7;
        ram[  4] = 32'h0407A023;
        ram[  5] = 32'h0007A023;
        ram[  6] = 32'h0007A223;
        ram[  7] = 32'h0007A423;
        ram[  8] = 32'h0007A623;
        ram[  9] = 32'h0007A823;
        ram[ 10] = 32'h0007AA23;
        ram[ 11] = 32'h0007AC23;
        ram[ 12] = 32'h0007AE23;
        ram[ 13] = 32'h0207A023;
        ram[ 14] = 32'hFFFFF737;
        ram[ 15] = 32'h0207A223;
        ram[ 16] = 32'h4E970693;
        ram[ 17] = 32'h600107B7;
        ram[ 18] = 32'h00D7A023;
        ram[ 19] = 32'h63C70713;
        ram[ 20] = 32'h00E7A223;
        ram[ 21] = 32'h80000713;
        ram[ 22] = 32'h00E7A423;
        ram[ 23] = 32'h98300713;
        ram[ 24] = 32'h00E7A623;
        ram[ 25] = 32'hB6600713;
        ram[ 26] = 32'h00E7A823;
        ram[ 27] = 32'hC6E00713;
        ram[ 28] = 32'h00E7AA23;
        ram[ 29] = 32'hE1E00713;
        ram[ 30] = 32'h00E7AC23;
        ram[ 31] = 32'h0007AE23;
        ram[ 32] = 32'h39200713;
        ram[ 33] = 32'h02E7A023;
        ram[ 34] = 32'h00001737;
        ram[ 35] = 32'hB1770713;
        ram[ 36] = 32'h02E7A223;
        ram[ 37] = 32'h00100713;
        ram[ 38] = 32'h08E7A023;
        ram[ 39] = 32'h3E800713;
        ram[ 40] = 32'h0847A683;
        ram[ 41] = 32'h0016F693;
        ram[ 42] = 32'h04069463;
        ram[ 43] = 32'hFFF70713;
        ram[ 44] = 32'hFE0718E3;
        ram[ 45] = 32'hBAD007B7;
        ram[ 46] = 32'h60001737;
        ram[ 47] = 32'h00178793;
        ram[ 48] = 32'h04F72023;
        ram[ 49] = 32'h00000013;
        ram[ 50] = 32'hFFDFF06F;
        ram[ 51] = 32'hBAD007B7;
        ram[ 52] = 32'h60001737;
        ram[ 53] = 32'h00378793;
        ram[ 54] = 32'h04F72023;
        ram[ 55] = 32'h00000013;
        ram[ 56] = 32'hFFDFF06F;
        ram[ 57] = 32'hBAD007B7;
        ram[ 58] = 32'h00278793;
        ram[ 59] = 32'h0680006F;
        ram[ 60] = 32'h0887A683;
        ram[ 61] = 32'hFC069CE3;
        ram[ 62] = 32'h60000737;
        ram[ 63] = 32'hFFFF1537;
        ram[ 64] = 32'h600105B7;
        ram[ 65] = 32'h16070713;
        ram[ 66] = 32'h10078793;
        ram[ 67] = 32'hF0050513;
        ram[ 68] = 32'h12858593;
        ram[ 69] = 32'h00072603;
        ram[ 70] = 32'h0007A803;
        ram[ 71] = 32'h00A788B3;
        ram[ 72] = 32'h0108A023;
        ram[ 73] = 32'hFFD60893;
        ram[ 74] = 32'h01184663;
        ram[ 75] = 32'h00360613;
        ram[ 76] = 32'h01065463;
        ram[ 77] = 32'h00168693;
        ram[ 78] = 32'h00478793;
        ram[ 79] = 32'h00470713;
        ram[ 80] = 32'hFCB79AE3;
        ram[ 81] = 32'h60001737;
        ram[ 82] = 32'hF8069EE3;
        ram[ 83] = 32'hC0DE27B7;
        ram[ 84] = 32'h00A78793;
        ram[ 85] = 32'h04F72023;
        ram[ 86] = 32'h00000013;
        ram[ 87] = 32'hFFDFF06F;
        ram[ 88] = 32'h00000800;
        ram[ 89] = 32'h000008B1;
        ram[ 90] = 32'h000009B4;
        ram[ 91] = 32'h00000AAB;
        ram[ 92] = 32'h00000C00;
        ram[ 93] = 32'h00000CCD;
        ram[ 94] = 32'h00000E39;
        ram[ 95] = 32'h00001000;
        ram[ 96] = 32'h00001400;
        ram[ 97] = 32'h00002000;

        if (ram[0] !== 32'h00002117 ||
            ram[97] !== 32'h00002000)
            $fatal(1, "Incorrect embedded exp10 firmware image");

        repeat (8) @(negedge clk);
        resetn = 1'b1;
        wait (seen_done);
        @(negedge clk);

        if (!seen_done_clear || !seen_parallel_start || !seen_status_done ||
            !seen_invalid_read || start_count != 1 || seen_input !== 10'h3FF ||
            seen_read !== 10'h3FF || seen_ram_result !== 10'h3FF)
            $fatal(1, "Incomplete 10CH exp CPU flow: clear=%b start=%b status=%b invalid=%b starts=%0d IN=%b READ=%b RAM=%b",
                   seen_done_clear, seen_parallel_start, seen_status_done,
                   seen_invalid_read, start_count, seen_input, seen_read, seen_ram_result);

        for (int ch = 0; ch < NUM_CH; ch++) begin
            if (!exp_matches(ch, ram[((RESULT_BASE - RAM_BASE) >> 2) + ch]))
                $fatal(1, "Final RAM CH%0d exp_Q12 wrong: got=%0d expected=%0d",
                       ch, $signed(ram[((RESULT_BASE - RAM_BASE) >> 2) + ch]), expected_for(ch));
            $display("PASS: CPU CH%0d exp_Q12=%0d expected=%0d", ch,
                     $signed(ram[((RESULT_BASE - RAM_BASE) >> 2) + ch]), expected_for(ch));
        end
        if (ram[(DONE_ADDR - RAM_BASE) >> 2] !== DONE_MARKER)
            $fatal(1, "Final CPU RAM DONE marker mismatch");

        $display("=======================================================");
        $display("PASS: real Mi-V CPU wrote all ten Q12 exp inputs");
        $display("PASS: CPU issued one START for ten full-exp channels");
        $display("PASS: CPU observed MMIO STATUS DONE and INVALID=0");
        $display("PASS: CPU read ten Q12 exp results within +/-3 LSB");
        $display("PASS: CPU stored ten results and C0DE200A in RAM");
        $display("FULL CPU + 10CH FULL EXP CORDIC INTEGRATION PASSED");
        $display("=======================================================");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "TIMEOUT: CPU did not complete 10-channel full-exp program");
    end

    // --------------------------------------------------------------------
    // CPU+MMIO PERFORMANCE MONITOR (simulation only)
    // Clock is 10 ns, derived from always #5 clk = ~clk.
    // Captures bus handshakes rather than $finish time.
    // Do not include this monitor in FPGA synthesis.
    // --------------------------------------------------------------------
    time perf_ifetch_t = 0;
    time perf_first_input_t = 0;
    time perf_start_t = 0;
    time perf_core_busy_t = 0;
    time perf_core_done_t = 0;
    bit perf_reported = 0;

    always @(posedge clk) begin
        if (resetn) begin
            if (perf_ifetch_t == 0 && ifu_emi_req_valid && ifu_emi_req_ready)
                perf_ifetch_t = $time;

            if (perf_first_input_t == 0 &&
                lsu_emi_req_valid && lsu_emi_req_ready && lsu_emi_req_write &&
                lsu_emi_req_addr >= MMIO_BASE &&
                lsu_emi_req_addr <= MMIO_BASE + 32'h24)
                perf_first_input_t = $time;

            if (perf_start_t == 0 &&
                lsu_emi_req_valid && lsu_emi_req_ready && lsu_emi_req_write &&
                lsu_emi_req_addr == MMIO_BASE + 32'h80 &&
                lsu_emi_req_wr_data == 32'd1)
                perf_start_t = $time;

            if (perf_core_busy_t == 0 && mmio_busy)
                perf_core_busy_t = $time;
            if (perf_core_done_t == 0 && mmio_done_sticky)
                perf_core_done_t = $time;

            if (!perf_reported &&
                lsu_emi_req_valid && lsu_emi_req_ready && lsu_emi_req_write &&
                lsu_emi_req_addr == DONE_ADDR &&
                lsu_emi_req_wr_data == DONE_MARKER) begin
                perf_reported = 1'b1;
                if (perf_ifetch_t == 0 || perf_first_input_t == 0 ||
                    perf_start_t == 0 || perf_core_busy_t == 0 ||
                    perf_core_done_t == 0)
                    $fatal(1, "PERF %s: missing measurement milestone", PERF_TAG);
                $display("========================================================");
                $display("CPU SYSTEM PERFORMANCE: %s, 10 input values", PERF_TAG);
                $display("CPU_TOTAL_CYCLES         = %0d", ($time - perf_ifetch_t)/10);
                $display("CPU_MMIO_TO_RAM_CYCLES   = %0d", ($time - perf_first_input_t)/10);
                $display("START_TO_CORE_DONE       = %0d", (perf_core_done_t - perf_start_t)/10);
                $display("CORE_BUSY_TO_DONE        = %0d", (perf_core_done_t - perf_core_busy_t)/10);
                $display("CORE_DONE_TO_RAM_MARKER  = %0d", ($time - perf_core_done_t)/10);
                $display("NOTE: CPU_TOTAL is from first accepted IFETCH to successful RAM marker write");
                $display("NOTE: 10ch only. A 1ch CPU baseline is still needed for system speedup.");
                $display("========================================================");
            end
        end
    end

endmodule
