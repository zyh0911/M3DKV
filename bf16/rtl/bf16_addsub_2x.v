// ===========================================================================
//  bf16_addsub_2x.v -- baseline for the fused unit: two independent bf16_add
//                      instances, one wired to add and one to subtract.
//
//  Same ports as bf16_addsub_fused, so bf16_addsub_unit can swap the two and
//  DC sees exactly the same wrapper, constraints and IO in both runs.
// ===========================================================================
`timescale 1ns/1ps

module bf16_addsub_2x (
    input  wire [15:0] a,
    input  wire [15:0] b,
    output wire [15:0] y_sum,
    output wire [15:0] y_diff,
    output wire [3:0]  flags_sum,
    output wire [3:0]  flags_diff
);

    wire nv_s, of_s, uf_s, nx_s;
    wire nv_d, of_d, uf_d, nx_d;

    bf16_add u_sum (
        .a(a), .b(b), .sub(1'b0),
        .y(y_sum), .nv(nv_s), .of(of_s), .uf(uf_s), .nx(nx_s)
    );

    bf16_add u_diff (
        .a(a), .b(b), .sub(1'b1),
        .y(y_diff), .nv(nv_d), .of(of_d), .uf(uf_d), .nx(nx_d)
    );

    assign flags_sum  = {nv_s, of_s, uf_s, nx_s};
    assign flags_diff = {nv_d, of_d, uf_d, nx_d};

endmodule
