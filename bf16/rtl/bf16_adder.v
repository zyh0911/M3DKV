// ===========================================================================
//  bf16_adder.v -- registered wrapper around the combinational bf16_add
//
//  PIPE = 0 : pure combinational (no clk used).  Synthesis then needs a
//             max_delay constraint instead of a clock -- constraints.tcl
//             handles that automatically.
//  PIPE = 1 : output register only  (port -> logic -> flop)
//  PIPE = 2 : input AND output registers (default).  This is the one to
//             characterise: the critical path is a clean reg-to-reg path
//             containing exactly the adder.
//
//  vld_in/vld_out is a simple data-valid tag travelling with the operands;
//  the datapath itself has no back pressure (fully pipelined, 1 result/cycle).
// ===========================================================================
`timescale 1ns/1ps

module bf16_adder #(
    parameter PIPE = 2
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        vld_in,
    input  wire [15:0] a,
    input  wire [15:0] b,
    input  wire        sub,
    output wire [15:0] y,
    output wire [3:0]  flags,    // {nv, of, uf, nx}
    output wire        vld_out
);

    // ---------------- input stage ----------------
    wire [15:0] a_i, b_i;
    wire        sub_i, vld_i;

    generate
    if (PIPE >= 2) begin : g_in_reg
        reg [15:0] a_q, b_q;
        reg        sub_q, vld_q;
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                a_q   <= 16'd0;
                b_q   <= 16'd0;
                sub_q <= 1'b0;
                vld_q <= 1'b0;
            end else begin
                a_q   <= a;
                b_q   <= b;
                sub_q <= sub;
                vld_q <= vld_in;
            end
        end
        assign a_i   = a_q;
        assign b_i   = b_q;
        assign sub_i = sub_q;
        assign vld_i = vld_q;
    end else begin : g_in_comb
        assign a_i   = a;
        assign b_i   = b;
        assign sub_i = sub;
        assign vld_i = vld_in;
    end
    endgenerate

    // ---------------- datapath ----------------
    wire [15:0] y_c;
    wire        nv_c, of_c, uf_c, nx_c;

    bf16_add u_add (
        .a   (a_i),
        .b   (b_i),
        .sub (sub_i),
        .y   (y_c),
        .nv  (nv_c),
        .of  (of_c),
        .uf  (uf_c),
        .nx  (nx_c)
    );

    // ---------------- output stage ----------------
    generate
    if (PIPE >= 1) begin : g_out_reg
        reg [15:0] y_q;
        reg [3:0]  fl_q;
        reg        vo_q;
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                y_q  <= 16'd0;
                fl_q <= 4'd0;
                vo_q <= 1'b0;
            end else begin
                y_q  <= y_c;
                fl_q <= {nv_c, of_c, uf_c, nx_c};
                vo_q <= vld_i;
            end
        end
        assign y       = y_q;
        assign flags   = fl_q;
        assign vld_out = vo_q;
    end else begin : g_out_comb
        assign y       = y_c;
        assign flags   = {nv_c, of_c, uf_c, nx_c};
        assign vld_out = vld_i;
    end
    endgenerate

endmodule
