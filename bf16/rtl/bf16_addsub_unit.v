// ===========================================================================
//  bf16_addsub_unit.v -- registered wrapper shared by both add/sub cores.
//
//    FUSED = 1 : bf16_addsub_fused   (one shared front end)
//    FUSED = 0 : bf16_addsub_2x      (two independent bf16_add)
//
//  Identical wrapper, ports and register count in both cases, so a DC run of
//  one against the other differs only in the core.
//
//    PIPE = 0 : combinational
//    PIPE = 1 : output registers
//    PIPE = 2 : input + output registers (default)
// ===========================================================================
`timescale 1ns/1ps

module bf16_addsub_unit #(
    parameter FUSED = 1,
    parameter PIPE  = 2
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        vld_in,
    input  wire [15:0] a,
    input  wire [15:0] b,
    output wire [15:0] y_sum,
    output wire [15:0] y_diff,
    output wire [3:0]  flags_sum,
    output wire [3:0]  flags_diff,
    output wire        vld_out
);

    // ---------------- input stage ----------------
    wire [15:0] a_i, b_i;
    wire        vld_i;

    generate
    if (PIPE >= 2) begin : g_in_reg
        reg [15:0] a_q, b_q;
        reg        vld_q;
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                a_q   <= 16'd0;
                b_q   <= 16'd0;
                vld_q <= 1'b0;
            end else begin
                a_q   <= a;
                b_q   <= b;
                vld_q <= vld_in;
            end
        end
        assign a_i   = a_q;
        assign b_i   = b_q;
        assign vld_i = vld_q;
    end else begin : g_in_comb
        assign a_i   = a;
        assign b_i   = b;
        assign vld_i = vld_in;
    end
    endgenerate

    // ---------------- core ----------------
    wire [15:0] ys_c, yd_c;
    wire [3:0]  fs_c, fd_c;

    generate
    if (FUSED) begin : g_fused
        bf16_addsub_fused u_core (
            .a(a_i), .b(b_i),
            .y_sum(ys_c), .y_diff(yd_c),
            .flags_sum(fs_c), .flags_diff(fd_c)
        );
    end else begin : g_2x
        bf16_addsub_2x u_core (
            .a(a_i), .b(b_i),
            .y_sum(ys_c), .y_diff(yd_c),
            .flags_sum(fs_c), .flags_diff(fd_c)
        );
    end
    endgenerate

    // ---------------- output stage ----------------
    generate
    if (PIPE >= 1) begin : g_out_reg
        reg [15:0] ys_q, yd_q;
        reg [3:0]  fs_q, fd_q;
        reg        vo_q;
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                ys_q <= 16'd0;
                yd_q <= 16'd0;
                fs_q <= 4'd0;
                fd_q <= 4'd0;
                vo_q <= 1'b0;
            end else begin
                ys_q <= ys_c;
                yd_q <= yd_c;
                fs_q <= fs_c;
                fd_q <= fd_c;
                vo_q <= vld_i;
            end
        end
        assign y_sum      = ys_q;
        assign y_diff     = yd_q;
        assign flags_sum  = fs_q;
        assign flags_diff = fd_q;
        assign vld_out    = vo_q;
    end else begin : g_out_comb
        assign y_sum      = ys_c;
        assign y_diff     = yd_c;
        assign flags_sum  = fs_c;
        assign flags_diff = fd_c;
        assign vld_out    = vld_i;
    end
    endgenerate

endmodule
