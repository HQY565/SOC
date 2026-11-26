`timescale 1ns/1ps

// Ten independent full hyperbolic CORDIC EXP channels.
// Input: signed Q12 (value = input / 4096), range -2839..+2839.
// Output: unsigned positive Q12 (value = output / 4096).
// Each START launches 16 stages, with repeated shifts 4 and 13.
module cordic_exp_parallel_10ch (
    input  logic         clk,
    input  logic         resetn,
    input  logic         start,
    input  logic [159:0] in_q12_flat,
    output logic [319:0] exp_q12_flat,
    output logic [9:0]   invalid_mask,
    output logic         busy,
    output logic         done
);

    logic signed [31:0] x [0:9];
    logic signed [31:0] y [0:9];
    logic signed [31:0] z [0:9];
    logic signed [31:0] xn [0:9];
    logic signed [31:0] yn [0:9];
    logic signed [31:0] zn [0:9];
    logic [4:0] stage;
    logic [4:0] shift_amt;
    logic signed [31:0] angle;

    // The compensation for the 16-stage hyperbolic gain is 1/K.
    // round(1.2074970670 * 2^28) = 324135026.
    localparam logic signed [31:0] X0_Q28 = 32'sd324135026;

    function automatic logic [4:0] shift_for(input logic [4:0] n);
        case (n)
             0: shift_for =  1;
             1: shift_for =  2;
             2: shift_for =  3;
             3: shift_for =  4;
             4: shift_for =  4;
             5: shift_for =  5;
             6: shift_for =  6;
             7: shift_for =  7;
             8: shift_for =  8;
             9: shift_for =  9;
            10: shift_for = 10;
            11: shift_for = 11;
            12: shift_for = 12;
            13: shift_for = 13;
            14: shift_for = 13;
            15: shift_for = 14;
            default: shift_for = 14;
        endcase
    endfunction

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

    // Hyperbolic rotation mode:
    // Z >= 0: X'=X+(Y>>i), Y'=Y+(X>>i), Z'=Z-atanh(2^-i)
    // Z <  0: X'=X-(Y>>i), Y'=Y-(X>>i), Z'=Z+atanh(2^-i)
    // At the end: exp(Z_in) = cosh(Z_in) + sinh(Z_in) ~= X + Y.
    always_comb begin
        shift_amt = shift_for(stage);
        angle = atanh_q28(shift_amt);
        for (int k = 0; k < 10; k = k + 1) begin
            xn[k] = x[k];
            yn[k] = y[k];
            zn[k] = z[k];
            if (busy && !invalid_mask[k]) begin
                if (z[k] >= 0) begin
                    xn[k] = x[k] + (y[k] >>> shift_amt);
                    yn[k] = y[k] + (x[k] >>> shift_amt);
                    zn[k] = z[k] - angle;
                end
                else begin
                    xn[k] = x[k] - (y[k] >>> shift_amt);
                    yn[k] = y[k] - (x[k] >>> shift_amt);
                    zn[k] = z[k] + angle;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            busy <= 1'b0;
            done <= 1'b0;
            stage <= 5'd0;
            invalid_mask <= 10'd0;
            exp_q12_flat <= 320'd0;
            for (int k = 0; k < 10; k = k + 1) begin
                x[k] <= 32'sd0;
                y[k] <= 32'sd0;
                z[k] <= 32'sd0;
            end
        end
        else if (start && !busy) begin
            busy <= 1'b1;
            done <= 1'b0;
            stage <= 5'd0;
            exp_q12_flat <= 320'd0;
            for (int k = 0; k < 10; k = k + 1) begin
                invalid_mask[k] <=
                    ($signed(in_q12_flat[k*16 +: 16]) < -16'sd2839) ||
                    ($signed(in_q12_flat[k*16 +: 16]) >  16'sd2839);
                x[k] <= X0_Q28;
                y[k] <= 32'sd0;
                // Sign-extend Q12 to 32 bits, then scale to Q28.
                z[k] <= $signed({{16{in_q12_flat[k*16+15]}},
                                 in_q12_flat[k*16 +: 16]}) <<< 16;
            end
        end
        else if (busy) begin
            for (int k = 0; k < 10; k = k + 1) begin
                x[k] <= xn[k];
                y[k] <= yn[k];
                z[k] <= zn[k];
                if (stage == 5'd15) begin
                    // Positive result: round Q28 to Q12.
                    exp_q12_flat[k*32 +: 32] <= invalid_mask[k]
                        ? 32'd0
                        : (xn[k] + yn[k] + 32'sd32768) >>> 16;
                end
            end
            if (stage == 5'd15) begin
                busy <= 1'b0;
                done <= 1'b1; // sticky until next START
            end
            else begin
                stage <= stage + 5'd1;
            end
        end
    end
endmodule
