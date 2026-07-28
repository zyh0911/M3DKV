// ============================================================================
//  fht_core.v -- 8/16-way parallel Fast Hadamard Transform (FHT) datapath
//
//  Reproduction of the FHT Unit in Fig. 11(b) of
//    J. Kim et al., "LightRot: A Light-Weighted Rotation Scheme and
//    Architecture for Accurate Low-Bit Large Language Model Inference,"
//    IEEE JETCAS, vol. 15, no. 2, June 2025.
//
//  A single physical 16-lane / 4-stage radix-2 butterfly network that can be
//  operated in two modes:
//
//    mode16 = 1 : 16-way FHT   -> 4 stages x 8 butterflies x 2 = 64 adders
//                                (paper: "16-way FHT Unit (64 Adder)")
//    mode16 = 0 : 8-way  FHT   -> "half of the 16-way FHT Unit is gated"
//                                Stage 1 (the distance-8 stage) and lanes
//                                8..15 are gated off, leaving
//                                3 stages x 4 butterflies x 2 = 24 adders
//                                (paper: "8-way FHT Unit (24 Adder)")
//
//  Stage ordering matches the crossing pattern drawn in Fig. 11(b)
//  (decimation-in-frequency: widest crossings first):
//
//      Stage 1 : butterflies on index bit[3]  (distance 8)   <-- gated
//      Stage 2 : butterflies on index bit[2]  (distance 4)
//      Stage 3 : butterflies on index bit[1]  (distance 2)
//      Stage 4 : butterflies on index bit[0]  (distance 1)
//
//  The result is the *natural (Sylvester) order* Walsh-Hadamard transform:
//      y = H_16 * x        (mode16 = 1)
//      y[0:7] = H_8 * x[0:7], y[8:15] = 0   (mode16 = 0)
//
//  No 1/sqrt(N) normalisation is applied here -- exactly as in the paper the
//  scale factor is folded into the downstream Quantization Unit.  The datapath
//  is purely combinational (4 adder levels easily close 250 MHz in 28 nm).
//
//  Overflow: the caller must provide enough headroom in W.  fht_2step_unit
//  uses W = DW + 7 so that a full 128-point transform of DW-bit inputs can
//  never overflow.
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module fht_core #(
    parameter integer W = 23            // datapath word width (signed)
)(
    input  wire                mode16,  // 1 = 16-way, 0 = 8-way (half gated)
    input  wire [16*W-1:0]     din,     // lane i = din[i*W +: W]
    output wire [16*W-1:0]     dout     // lane i = dout[i*W +: W]
);

    integer i;

    wire signed [W-1:0] x  [0:15];      // unpacked input
    reg  signed [W-1:0] xi [0:15];      // after operand isolation
    reg  signed [W-1:0] s1 [0:15];      // after stage 1 (distance 8)
    reg  signed [W-1:0] s2 [0:15];      // after stage 2 (distance 4)
    reg  signed [W-1:0] s3 [0:15];      // after stage 3 (distance 2)
    reg  signed [W-1:0] s4 [0:15];      // after stage 4 (distance 1)

    genvar g;
    generate
        for (g = 0; g < 16; g = g + 1) begin : g_io
            assign x[g]            = din[g*W +: W];
            assign dout[g*W +: W]  = s4[g];
        end
    endgenerate

    // ------------------------------------------------------------------
    // Operand isolation: in 8-way mode the upper 8 lanes are forced to 0 so
    // that no toggling propagates into the gated half of the network.
    // ------------------------------------------------------------------
    always @* begin
        for (i = 0; i < 8; i = i + 1)
            xi[i] = x[i];
        for (i = 8; i < 16; i = i + 1)
            xi[i] = mode16 ? x[i] : {W{1'b0}};
    end

    // ------------------------------------------------------------------
    // Stage 1 : distance-8 butterflies.  Gated in 8-way mode.
    //   With xi[8..15] == 0 the "+" path degenerates to a pass-through of the
    //   lower half, and the "-" path is explicitly forced to 0, which keeps
    //   the whole upper half of stages 2..4 quiet.
    // ------------------------------------------------------------------
    always @* begin
        for (i = 0; i < 8; i = i + 1) begin
            s1[i]   = xi[i] + xi[i+8];
            s1[i+8] = mode16 ? (xi[i] - xi[i+8]) : {W{1'b0}};
        end
    end

    // ------------------------------------------------------------------
    // Stage 2 : distance-4 butterflies
    // ------------------------------------------------------------------
    always @* begin
        for (i = 0; i < 16; i = i + 1) begin
            if (((i >> 2) & 1) == 0) begin
                s2[i]   = s1[i] + s1[i+4];
                s2[i+4] = s1[i] - s1[i+4];
            end
        end
    end

    // ------------------------------------------------------------------
    // Stage 3 : distance-2 butterflies
    // ------------------------------------------------------------------
    always @* begin
        for (i = 0; i < 16; i = i + 1) begin
            if (((i >> 1) & 1) == 0) begin
                s3[i]   = s2[i] + s2[i+2];
                s3[i+2] = s2[i] - s2[i+2];
            end
        end
    end

    // ------------------------------------------------------------------
    // Stage 4 : distance-1 butterflies
    // ------------------------------------------------------------------
    always @* begin
        for (i = 0; i < 16; i = i + 1) begin
            if ((i & 1) == 0) begin
                s4[i]   = s3[i] + s3[i+1];
                s4[i+1] = s3[i] - s3[i+1];
            end
        end
    end

endmodule

`default_nettype wire
