// Probe A: front half of bf16_add -- unpack, magnitude sort, align, add/sub.
// Code copied verbatim from rtl/bf16_add.v so the delay is representative.
`timescale 1ns/1ps
module bf16_probe_a (
    input  wire [15:0] a,
    input  wire [15:0] b,
    input  wire        sub,
    output wire [11:0] sum,
    output wire        sticky,
    output wire [8:0]  E_l,
    output wire        s_l,
    output wire        s_s
);
    wire        sa = a[15];
    wire [7:0]  ea = a[14:7];
    wire [6:0]  fa = a[6:0];
    wire        sb = b[15] ^ sub;
    wire [7:0]  eb = b[14:7];
    wire [6:0]  fb = b[6:0];

    wire b_bigger = (b[14:0] > a[14:0]);

    assign s_l = b_bigger ? sb : sa;
    assign s_s = b_bigger ? sa : sb;
    wire [7:0]  e_lr = b_bigger ? eb : ea;
    wire [7:0]  e_sr = b_bigger ? ea : eb;
    wire [6:0]  f_l  = b_bigger ? fb : fa;
    wire [6:0]  f_s  = b_bigger ? fa : fb;

    wire [7:0] sig_l = {|e_lr, f_l};
    wire [7:0] sig_s = {|e_sr, f_s};
    assign     E_l   = |e_lr ? {1'b0, e_lr} : 9'd1;
    wire [8:0] E_s   = |e_sr ? {1'b0, e_sr} : 9'd1;
    wire [8:0] ediff = E_l - E_s;

    wire [4:0]  sh        = (ediff > 9'd12) ? 5'd12 : ediff[4:0];
    wire [11:0] al_l      = {1'b0, sig_l, 3'b000};
    wire [11:0] al_s_full = {1'b0, sig_s, 3'b000};
    wire [11:0] al_s      = al_s_full >> sh;
    wire [11:0] lost_mask = ~(12'hFFF << sh);
    assign      sticky    = |(al_s_full & lost_mask);

    wire eff_sub = s_l ^ s_s;
    assign sum = eff_sub ? (al_l - al_s - {11'd0, sticky}) : (al_l + al_s);
endmodule
