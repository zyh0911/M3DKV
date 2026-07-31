// ===========================================================================
//  bfp_to_bf16.v -- renormalise one W-bit two's-complement value carrying a
//                   shared exponent back into a BF16 word.
//
//      value  =  x * 2^(e_shared - 134 - D)
//
//  Leading-zero count, left shift, round-to-nearest-even, pack.  This is the
//  block that a BFP FHT can DELETE if its consumer accepts shared-exponent
//  data (an MX-format quantiser does), which is why it is a separate module:
//  its area is the price of insisting on a BF16 output.
//
//  Two deliberate simplifications, both stated rather than hidden:
//    - results below the BF16 normal range flush to zero (no subnormals).
//      The shared exponent is the block maximum, so anything that far down is
//      already below the transform's own error floor.
//    - overflow clamps to the largest finite BF16 rather than producing Inf.
// ===========================================================================
`timescale 1ns/1ps

module bfp_to_bf16 #(
    parameter W = 16,
    parameter D = 3
) (
    input  wire [W-1:0] x,
    input  wire [7:0]   e_shared,
    output wire [15:0]  y
);

    wire         sgn = x[W-1];
    wire [W-1:0] mag = sgn ? (~x + 1'b1) : x;

    // position of the most significant set bit
    integer   k;
    reg [4:0] p;
    reg       any;
    always @* begin
        p   = 5'd0;
        any = 1'b0;
        for (k = 0; k < W; k = k + 1)
            if (mag[k]) begin
                p   = k[4:0];
                any = 1'b1;
            end
    end

    wire [4:0]   shl     = (W-1) - p;
    wire [W-1:0] shifted = mag << shl;      // MSB now at bit W-1

    wire [7:0] m  = shifted[W-1 -: 8];
    wire       gb = shifted[W-9];
    wire       rb = shifted[W-10];
    wire       sb = |shifted[W-11:0];

    wire       rup  = gb & (rb | sb | m[0]);
    wire [8:0] mr   = {1'b0, m} + rup;
    wire       movf = mr[8];
    wire [7:0] mf   = movf ? 8'h80 : mr[7:0];

    // value = m * 2^(p-7) * 2^(e_shared-134-D)  ->  BF16 exponent field
    wire signed [10:0] ebf = $signed({3'b000, e_shared})
                           + $signed({6'b000000, p})
                           - (D + 7);
    wire signed [10:0] ef  = ebf + movf;

    wire flush = ~any | (ef <= 0);
    wire ovfl  = (ef >= 255);

    assign y = flush ? {sgn, 15'd0}
             : ovfl  ? {sgn, 8'hFE, 7'h7F}          // largest finite BF16
             :         {sgn, ef[7:0], mf[6:0]};

endmodule
