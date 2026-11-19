`timescale 1ns/1ps

module tb_miv_cpu_cordic;
    localparam logic [31:0] RAM_BASE   = 32'h6000_0000;
    localparam int unsigned RAM_WORDS  = 2048; // 8 KiB, byte-addressed via word index
    localparam logic [31:0] RESULT_ADDR = 32'h6000_1000;
    localparam logic [31:0] DONE_ADDR   = 32'h6000_1004;

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
    bit seen_cordic = 0;
    bit seen_result = 0;
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
                                lsu_emi_req_wr_data !== 32'h0C00_0000)
                                $fatal(1, "Result store failed, got %08h", lsu_emi_req_wr_data);
                            seen_result <= 1'b1;
                        end
                        if (lsu_emi_req_addr == DONE_ADDR) begin
                            if (lsu_emi_req_wr_byte_en !== 4'b1111 ||
                                lsu_emi_req_wr_data !== 32'hC0DE_0001)
                                $fatal(1, "Done marker failed");
                            seen_done <= 1'b1;
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
            if (trace_iaddr == 32'h6000_0018 && trace_insn == 32'h06E7_D78B && !trace_exception) begin
                seen_cordic <= 1'b1;
                $display("CPU EXECUTED CORDIC_END at PC=60000018");
            end
            if (trace_exception)
                $fatal(1, "CPU exception PC=%08h instr=%08h", trace_iaddr, trace_insn);
        end
    end

    initial begin
        $display("Loading compiled SoftConsole program ...");
        $readmemh("C:/Libero v2024.09/icicle-kit-reference-design-2024.09/MPFS_ICICLE/simulation/cordic_test/cpu_prog.mem", ram);
        repeat (8) @(negedge clk);
        resetn = 1'b1;
        wait (seen_done);
        @(negedge clk);
        if (!seen_cordic || !seen_result)
            $fatal(1, "Incomplete integration: cordic=%b result=%b", seen_cordic, seen_result);
        if (ram[(RESULT_ADDR - RAM_BASE)>>2] !== 32'h0C00_0000 ||
            ram[(DONE_ADDR   - RAM_BASE)>>2] !== 32'hC0DE_0001)
            $fatal(1, "Final RAM contents incorrect");
        $display("========================================");
        $display("PASS: Mi-V CPU fetched CORDIC instruction");
        $display("PASS: Mi-V CPU retired CORDIC instruction");
        $display("PASS: CPU LSU stored result 0C000000");
        $display("PASS: CPU LSU stored completion marker");
        $display("FULL CPU + CORDIC INTEGRATION PASSED");
        $display("========================================");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "TIMEOUT: CPU has not written completion marker");
    end
endmodule
