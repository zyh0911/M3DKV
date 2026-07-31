// ===========================================================================
//  fht16_bfp.v -- 16-point Fast Hadamard Transform, shared-exponent
//                 (block floating point) datapath.
//
//  Align the 16 BF16 inputs ONCE against the block-maximum exponent, then run
//  all four butterfly stages as bare two's-complement integer add/sub, then
//  optionally pack back to BF16.
//
//  Width budget (see doc/float_vs_fixed_cost.md):
//
//      W  =  1 (sign)  +  G (growth)  +  8 (significand)  +  D (headroom)
//
//  G = 4 makes the transform overflow-proof: every output is a signed sum of
//  16 aligned values each < 2^(8+D), so it fits in 1+4+8+D bits exactly.  No
//  saturation logic is needed and every intermediate add is EXACT -- there is
//  no rounding anywhere between the aligner and the packer.
//
//  D is what costs accuracy: an element k exponents below the block maximum
//  keeps all 8 significand bits while k <= D, degrades to 8-(k-D) bits, and
//  reaches zero at k > D+7.
//
//  Fixed-point value semantics: dout_fx[i] represents
//      value_i  =  dout_fx[i] * 2^(e_shared - 134 - D)
// ===========================================================================
`timescale 1ns/1ps

module fht16_bfp #(
    parameter W    = 16,   // datapath width
    parameter G    = 4,    // growth headroom bits (4 = overflow-proof)
    parameter PACK = 0     // 1 = renormalise the 16 outputs back to BF16
) (
    input  wire [255:0]    din,       // 16 x BF16
    output wire [7:0]      e_shared,  // block exponent (biased, BF16 field)
    output wire [16*W-1:0] dout_fx,   // 16 x W-bit signed  (always valid)
    output wire [255:0]    dout_bf    // 16 x BF16          (PACK = 1 only)
);

    localparam integer D     = W - 9 - G;
    localparam integer SHW   = 5;
    localparam integer SHMAX = D + 8;   // shift that empties the word

    // -----------------------------------------------------------------
    //  unpack
    // -----------------------------------------------------------------
    wire       SGN [0:15];
    wire [7:0] SIG [0:15];
    wire [7:0] E   [0:15];

    genvar i, gs, gi;
    generate
        for (i = 0; i < 16; i = i + 1) begin : g_unpack
            wire [15:0] x = din[16*i +: 16];
            assign SGN[i] = x[15];
            assign SIG[i] = {|x[14:7], x[6:0]};        // implicit bit
            assign E[i]   = |x[14:7] ? x[14:7] : 8'd1; // subnormals sit at E=1
        end
    endgenerate

    // -----------------------------------------------------------------
    //  block maximum exponent -- 4-level tree of 8-bit compares
    // -----------------------------------------------------------------
    wire [7:0] mx1 [0:7];
    wire [7:0] mx2 [0:3];
    wire [7:0] mx3 [0:1];

    generate
        for (i = 0; i < 8; i = i + 1) begin : g_max1
            assign mx1[i] = (E[2*i] > E[2*i+1]) ? E[2*i] : E[2*i+1];
        end
        for (i = 0; i < 4; i = i + 1) begin : g_max2
            assign mx2[i] = (mx1[2*i] > mx1[2*i+1]) ? mx1[2*i] : mx1[2*i+1];
        end
        for (i = 0; i < 2; i = i + 1) begin : g_max3
            assign mx3[i] = (mx2[2*i] > mx2[2*i+1]) ? mx2[2*i] : mx2[2*i+1];
        end
    endgenerate

    assign e_shared = (mx3[0] > mx3[1]) ? mx3[0] : mx3[1];

    // -----------------------------------------------------------------
    //  align -- one variable right shifter per element, once for the whole
    //  transform.  This is the only shifter in the design.
    // -----------------------------------------------------------------
    wire [16*W-1:0] x0;

    generate
        for (i = 0; i < 16; i = i + 1) begin : g_align
            wire [7:0]     shr  = e_shared - E[i];
            wire           gone = (shr > SHMAX);
            wire [SHW-1:0] sh   = gone ? SHMAX : shr[SHW-1:0];
            wire [W-1:0]   base = {{(W-8){1'b0}}, SIG[i]} << D;
            wire [W-1:0]   mag  = base >> sh;
            assign x0[W*i +: W] = SGN[i] ? (~mag + 1'b1) : mag;
        end
    endgenerate

    // -----------------------------------------------------------------
    //  4 butterfly stages, bare integer add/sub, no rounding
    // -----------------------------------------------------------------
    wire [16*W-1:0] stg [0:4];
    assign stg[0] = x0;

    generate
        for (gs = 0; gs < 4; gs = gs + 1) begin : g_stage
            for (gi = 0; gi < 16; gi = gi + 1) begin : g_bfly
                if (((gi >> gs) & 1) == 0) begin : g_lo
                    assign stg[gs+1][W*gi +: W] =
                        stg[gs][W*gi           +: W] +
                        stg[gs][W*(gi|(1<<gs)) +: W];
                end else begin : g_hi
                    assign stg[gs+1][W*gi +: W] =
                        stg[gs][W*(gi & ~(1<<gs)) +: W] -
                        stg[gs][W*gi              +: W];
                end
            end
        end
    endgenerate

    assign dout_fx = stg[4];

    // -----------------------------------------------------------------
    //  optional pack back to BF16
    // -----------------------------------------------------------------
    generate
        if (PACK != 0) begin : g_pack
            for (i = 0; i < 16; i = i + 1) begin : g_p
                bfp_to_bf16 #(.W(W), .D(D)) u_pk (
                    .x        (stg[4][W*i +: W]),
                    .e_shared (e_shared),
                    .y        (dout_bf[16*i +: 16])
                );
            end
        end else begin : g_nopack
            assign dout_bf = 256'd0;
        end
    endgenerate

endmodule
