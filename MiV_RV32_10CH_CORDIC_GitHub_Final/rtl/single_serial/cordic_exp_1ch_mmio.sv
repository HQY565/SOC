`timescale 1ns/1ps
// REAL one-core serial baseline, 10 input slots, 1 CORDIC arithmetic core.
// Memory map unchanged from the verified ten-core CPU firmware:
// BASE+4*ch: WRITE 16-bit Q12 input (10 slots)
// BASE+0x80: WRITE 1 to start the batch
// BASE+0x84: READ status {busy, done} in bits [1:0]
// BASE+0x88: READ invalid bitmap of channels [9:0]
// BASE+0x100+4*ch: READ 32-bit Q12 result after done
// This is a simple custom simulation memory interface, not AXI/APB.
module cordic_exp_1ch_mmio #(
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
    logic [15:0] inputs [0:9];
    logic [31:0] outputs_q12 [0:9];
    logic [9:0] invalid_mask;

    logic resp_pending;
    logic start_pulse;
    wire [31:0] offset = bus_addr - BASE;

    assign bus_ready = resetn && !resp_pending;
    assign bus_resp_valid = resp_pending;

    // Exactly ONE arithmetic datapath. The scheduler reuses this core ten times.
    logic core_start;
    logic core_busy;
    logic core_done;
    wire core_invalid;
    wire [31:0] core_result;
    logic [3:0] index;

    cordic_exp_single u_single_core (
        .clk(clk),
        .resetn(resetn),
        .start(core_start),
        .in_q12_flat(inputs[index]),
        .exp_q12_flat(core_result),
        .invalid_mask(core_invalid),
        .busy(core_busy),
        .done(core_done)
    );

    typedef enum logic [1:0] {
        S_IDLE      = 2'd0,
        S_FIRE      = 2'd1,
        S_WAIT_BUSY = 2'd2,
        S_WAIT_DONE = 2'd3
    } state_t;
    state_t state;

    // Scheduler. A new core invocation is not counted complete until
    // core_busy has risen and core_done is observed for that invocation.
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state <= S_IDLE;
            core_start <= 1'b0;
            index <= 4'd0;
            busy <= 1'b0;
            done_sticky <= 1'b0;
            invalid_mask <= '0;
            for (int i=0; i<10; i=i+1)
                outputs_q12[i] <= 32'd0;
        end else begin
            core_start <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start_pulse) begin
                        index <= 4'd0;
                        busy <= 1'b1;
                        done_sticky <= 1'b0;
                        invalid_mask <= '0;
                        for (int i=0; i<10; i=i+1)
                            outputs_q12[i] <= 32'd0;
                        state <= S_FIRE;
                    end
                end
                S_FIRE: begin
                    core_start <= 1'b1;
                    state <= S_WAIT_BUSY;
                end
                S_WAIT_BUSY: begin
                    if (core_busy)
                        state <= S_WAIT_DONE;
                end
                S_WAIT_DONE: begin
                    if (core_done) begin
                        outputs_q12[index] <= core_result;
                        invalid_mask[index] <= core_invalid;
                        if (index == 4'd9) begin
                            busy <= 1'b0;
                            done_sticky <= 1'b1;
                            state <= S_IDLE;
                        end else begin
                            index <= index + 4'd1;
                            state <= S_FIRE;
                        end
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

    // MMIO responder. One outstanding read/write response; same bus contract
    // as the verified ten-core MMIO peripheral.
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            resp_pending <= 1'b0;
            start_pulse <= 1'b0;
            bus_rdata <= 32'd0;
            bus_error <= 1'b0;
            for (int i=0; i<10; i=i+1)
                inputs[i] <= 16'd0;
        end else begin
            start_pulse <= 1'b0;
            if (resp_pending) begin
                if (bus_resp_ready)
                    resp_pending <= 1'b0;
            end else if (bus_valid && bus_ready) begin
                resp_pending <= 1'b1;
                bus_rdata <= 32'd0;
                bus_error <= 1'b0;

                if ((bus_addr >= BASE) && (offset <= 32'h24) &&
                    (offset[1:0] == 2'b00)) begin
                    if (bus_write && !busy && !start_pulse &&
                        (bus_wdata[31:16] == {16{bus_wdata[15]}})) begin
                        inputs[offset[5:2]] <= bus_wdata[15:0];
                    end else begin
                        bus_error <= 1'b1;
                    end
                end else if ((bus_addr >= BASE) && (offset == 32'h80)) begin
                    if (bus_write && bus_wdata == 32'd1 &&
                        !busy && !start_pulse)
                        start_pulse <= 1'b1;
                    else
                        bus_error <= 1'b1;
                end else if ((bus_addr >= BASE) && (offset == 32'h84)) begin
                    if (!bus_write)
                        bus_rdata <= {30'd0, busy, done_sticky};
                    else
                        bus_error <= 1'b1;
                end else if ((bus_addr >= BASE) && (offset == 32'h88)) begin
                    if (!bus_write)
                        bus_rdata <= {22'd0, invalid_mask};
                    else
                        bus_error <= 1'b1;
                end else if ((bus_addr >= BASE) && (offset >= 32'h100) &&
                             (offset <= 32'h124) && (offset[1:0] == 2'b00)) begin
                    if (!bus_write && done_sticky)
                        bus_rdata <= outputs_q12[offset[5:2]];
                    else begin
                        bus_error <= 1'b1;
                        bus_rdata <= 32'hDEAD_BEEF;
                    end
                end else begin
                    bus_error <= 1'b1;
                end
            end
        end
    end
endmodule
