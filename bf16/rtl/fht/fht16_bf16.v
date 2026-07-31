// ===========================================================================
//  fht16_bf16.v -- 16-point Fast Hadamard Transform, floating-point datapath.
//
//  4 stages x 8 butterflies = 32 butterflies = 64 BF16 add/sub operations.
//  Stage s pairs the indices that differ in bit s, so the output is in
//  natural (Hadamard) order and the whole thing is in-place.
//
//      FUSED = 1  each butterfly is one bf16_addsub_fused  (shared front end)
//      FUSED = 0  each butterfly is two independent bf16_add
//
//  Purely combinational -- the point of this block is to measure the logic,
//  not to propose a pipeline.  Status flags are left unconnected: an FHT
//  datapath has no use for per-butterfly IEEE flags, and letting DC prune
//  them is the honest cost of the transform.
// ===========================================================================
`timescale 1ns/1ps

module fht16_bf16 #(
    parameter FUSED = 1
) (
    input  wire [255:0] din,    // 16 x BF16, element i at din[16*i +: 16]
    output wire [255:0] dout
);

    wire [255:0] stg [0:4];
    assign stg[0] = din;

    genvar gs, gi;
    generate
        for (gs = 0; gs < 4; gs = gs + 1) begin : g_stage
            for (gi = 0; gi < 16; gi = gi + 1) begin : g_bfly
                if (((gi >> gs) & 1) == 0) begin : g_lo
                    wire [15:0] ys, yd;
                    wire [3:0]  fs, fd;

                    if (FUSED != 0) begin : g_f
                        bf16_addsub_fused u_bf (
                            .a          (stg[gs][16*gi              +: 16]),
                            .b          (stg[gs][16*(gi|(1<<gs))    +: 16]),
                            .y_sum      (ys),
                            .y_diff     (yd),
                            .flags_sum  (fs),
                            .flags_diff (fd)
                        );
                    end else begin : g_2x
                        bf16_addsub_2x u_bf (
                            .a          (stg[gs][16*gi              +: 16]),
                            .b          (stg[gs][16*(gi|(1<<gs))    +: 16]),
                            .y_sum      (ys),
                            .y_diff     (yd),
                            .flags_sum  (fs),
                            .flags_diff (fd)
                        );
                    end

                    assign stg[gs+1][16*gi           +: 16] = ys;
                    assign stg[gs+1][16*(gi|(1<<gs)) +: 16] = yd;
                end
            end
        end
    endgenerate

    assign dout = stg[4];

endmodule
