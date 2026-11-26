`timescale 1ns/1ps
// Ten-channel full-LN CPU-like MMIO bridge (simulation bus, not AXI/APB).
// 0x00..0x24: 10 unsigned Q12 inputs, 0x80: START,
// 0x84: STATUS, 0x88: INVALID, 0x100..0x124: signed Q12 ln results.
module cordic_ln_parallel_10ch_mmio #(
    parameter logic [31:0] BASE = 32'h6001_0000
)(
    input  logic        clk,
    input  logic        resetn,
    input  logic        bus_valid,
    input  logic        bus_write,
    input  logic [31:0] bus_addr,
    input  logic [31:0] bus_wdata,
    output logic        bus_ready,
    output logic        bus_resp_valid,
    input  logic        bus_resp_ready,
    output logic [31:0] bus_rdata,
    output logic        bus_error,
    output logic        busy,
    output logic        done_sticky
);
    logic [15:0] input_q12 [0:9];
    wire [159:0] input_flat;
    wire [319:0] result_flat;
    wire [31:0] result_q12 [0:9];
    wire [9:0] invalid_mask;
    logic start_pulse, resp_pending;
    wire [31:0] offset = bus_addr - BASE;

    assign bus_ready = resetn && !resp_pending;
    assign bus_resp_valid = resp_pending;

    generate
        for (genvar g = 0; g < 10; g = g + 1) begin : g_pack
            assign input_flat[g*16 +: 16] = input_q12[g];
            assign result_q12[g] = result_flat[g*32 +: 32];
        end
    endgenerate

    cordic_ln_parallel_10ch u_ln (
        .clk(clk), .resetn(resetn), .start(start_pulse),
        .a_q12_flat(input_flat), .ln_q12_flat(result_flat),
        .invalid_mask(invalid_mask), .busy(busy), .done(done_sticky)
    );

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            start_pulse <= 1'b0;
            resp_pending <= 1'b0;
            bus_rdata <= 32'd0;
            bus_error <= 1'b0;
            for (int k=0; k<10; k=k+1) input_q12[k] <= 16'd0;
        end
        else begin
            start_pulse <= 1'b0;
            if (resp_pending) begin
                if (bus_resp_ready) resp_pending <= 1'b0;
            end
            else if (bus_valid && bus_ready) begin
                resp_pending <= 1'b1;
                bus_rdata <= 32'd0;
                bus_error <= 1'b0;
                if ((bus_addr >= BASE) && (offset <= 32'h24) &&
                    (offset[1:0] == 2'b00)) begin
                    if (bus_write && !busy && !start_pulse &&
                        (bus_wdata[31:16] == 16'd0))
                        input_q12[offset[5:2]] <= bus_wdata[15:0];
                    else bus_error <= 1'b1;
                end
                else if ((bus_addr >= BASE) && (offset == 32'h80)) begin
                    if (bus_write && (bus_wdata == 32'd1) && !busy && !start_pulse)
                        start_pulse <= 1'b1;
                    else bus_error <= 1'b1;
                end
                else if ((bus_addr >= BASE) && (offset == 32'h84)) begin
                    if (!bus_write) bus_rdata <= {30'd0, busy, done_sticky};
                    else bus_error <= 1'b1;
                end
                else if ((bus_addr >= BASE) && (offset == 32'h88)) begin
                    if (!bus_write) bus_rdata <= {22'd0, invalid_mask};
                    else bus_error <= 1'b1;
                end
                else if ((bus_addr >= BASE) && (offset >= 32'h100) &&
                         (offset <= 32'h124) && (offset[1:0] == 2'b00)) begin
                    if (!bus_write && done_sticky)
                        bus_rdata <= result_q12[offset[5:2]];
                    else begin
                        bus_error <= 1'b1;
                        bus_rdata <= 32'hDEAD_BEEF;
                    end
                end
                else bus_error <= 1'b1;
            end
        end
    end
endmodule
