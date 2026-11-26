`timescale 1ns/1ps

// ================================================================
// 10-channel HYPERBOLIC CORDIC, LN in Q12
// Input:  unsigned a_q12, 4096 = 1.0, supported 2048..8192 (0.5..2.0)
// Output: signed ln_q12, 4096 = 1.0 in the logarithm result
// Internal: signed X/Y Q26 and Z Q28, 16 stages with repeats at 4,13
// START: one-cycle pulse. DONE: sticky until next accepted START.
// Every channel has separate X/Y/Z registers; the stage counter is shared.
// ================================================================
module cordic_ln_parallel_10ch (
    input  logic         clk,
    input  logic         resetn,
    input  logic         start,
    input  logic [159:0] a_q12_flat,
    output logic [319:0] ln_q12_flat,
    output logic [9:0]   invalid_mask,
    output logic         busy,
    output logic         done
);
    logic signed [31:0] x [0:9];
    logic signed [31:0] y [0:9];
    logic signed [31:0] z [0:9];
    logic signed [31:0] x_next [0:9];
    logic signed [31:0] y_next [0:9];
    logic signed [31:0] z_next [0:9];
    logic [4:0] stage;
    logic [4:0] shift_amt;
    logic signed [31:0] angle_q28;

    function automatic logic [4:0] stage_shift(input logic [4:0] n);
        case (n)
             0: stage_shift =  1;
             1: stage_shift =  2;
             2: stage_shift =  3;
             3: stage_shift =  4;
             4: stage_shift =  4; // hyperbolic repeat
             5: stage_shift =  5;
             6: stage_shift =  6;
             7: stage_shift =  7;
             8: stage_shift =  8;
             9: stage_shift =  9;
            10: stage_shift = 10;
            11: stage_shift = 11;
            12: stage_shift = 12;
            13: stage_shift = 13;
            14: stage_shift = 13; // hyperbolic repeat
            15: stage_shift = 14;
            default: stage_shift = 14;
        endcase
    endfunction

    // Same Q28 atanh LUT values used in the original single-channel work.
    function automatic logic signed [31:0] atanh_q28(input logic [4:0] s);
        case (s)
             1: atanh_q28 = 32'sh08C9F53D;
             2: atanh_q28 = 32'sh04162BBE;
             3: atanh_q28 = 32'sh0202B124;
             4: atanh_q28 = 32'sh01005589;
             5: atanh_q28 = 32'sh00800AAC;
             6: atanh_q28 = 32'sh00400155;
             7: atanh_q28 = 32'sh0020002B;
             8: atanh_q28 = 32'sh00100005;
             9: atanh_q28 = 32'sh00080001;
            10: atanh_q28 = 32'sh00040000;
            11: atanh_q28 = 32'sh00020000;
            12: atanh_q28 = 32'sh00010000;
            13: atanh_q28 = 32'sh00008000;
            14: atanh_q28 = 32'sh00004000;
            default: atanh_q28 = 32'sd0;
        endcase
    endfunction

    // ln(a) = 2 * atanh((a-1)/(a+1)); Z is Q28.
    // ln_Q12 = round(2 * Z / 2^16) = round(Z / 2^15).
    function automatic logic signed [31:0] z_to_ln_q12(
        input logic signed [31:0] zz
    );
        logic signed [31:0] positive_mag;
        begin
            if (zz >= 0) begin
                z_to_ln_q12 = (zz + 32'sd16384) >>> 15;
            end else begin
                positive_mag = -zz;
                z_to_ln_q12 = -((positive_mag + 32'sd16384) >>> 15);
            end
        end
    endfunction

    always_comb begin
        shift_amt = stage_shift(stage);
        angle_q28 = atanh_q28(shift_amt);
        for (int k = 0; k < 10; k = k + 1) begin
            x_next[k] = x[k];
            y_next[k] = y[k];
            z_next[k] = z[k];
            if (busy && !invalid_mask[k]) begin
                if (y[k] > 0) begin
                    x_next[k] = x[k] - (y[k] >>> shift_amt);
                    y_next[k] = y[k] - (x[k] >>> shift_amt);
                    z_next[k] = z[k] + angle_q28;
                end else if (y[k] < 0) begin
                    x_next[k] = x[k] + (y[k] >>> shift_amt);
                    y_next[k] = y[k] + (x[k] >>> shift_amt);
                    z_next[k] = z[k] - angle_q28;
                end
                // Exact Y=0 is already converged; hold X/Y/Z.
            end
        end
    end

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            busy         <= 1'b0;
            done         <= 1'b0;
            stage        <= 5'd0;
            invalid_mask <= 10'd0;
            ln_q12_flat  <= 320'd0;
            for (int k = 0; k < 10; k = k + 1) begin
                x[k] <= 32'sd0;
                y[k] <= 32'sd0;
                z[k] <= 32'sd0;
            end
        end else if (start && !busy) begin
            // Latch all ten inputs together at the same rising edge.
            busy        <= 1'b1;
            done        <= 1'b0;
            stage       <= 5'd0;
            ln_q12_flat <= 320'd0;
            for (int k = 0; k < 10; k = k + 1) begin
                invalid_mask[k] <=
                    (a_q12_flat[k*16 +: 16] < 16'd2048) ||
                    (a_q12_flat[k*16 +: 16] > 16'd8192);
                // a is Q12; shift by 14 to make internal X/Y Q26.
                x[k] <= ($signed({1'b0, a_q12_flat[k*16 +: 16]})
                          + 32'sd4096) <<< 14;
                y[k] <= ($signed({1'b0, a_q12_flat[k*16 +: 16]})
                          - 32'sd4096) <<< 14;
                z[k] <= 32'sd0;
            end
        end else if (busy) begin
            for (int k = 0; k < 10; k = k + 1) begin
                x[k] <= x_next[k];
                y[k] <= y_next[k];
                z[k] <= z_next[k];
                if (stage == 5'd15) begin
                    ln_q12_flat[k*32 +: 32] <= invalid_mask[k]
                         ? 32'd0 : z_to_ln_q12(z_next[k]);
                end
            end
            if (stage == 5'd15) begin
                busy <= 1'b0;
                done <= 1'b1;
            end else begin
                stage <= stage + 5'd1;
            end
        end
        // done remains asserted until the next accepted START.
    end
endmodule
