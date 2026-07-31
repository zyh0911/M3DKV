// ===========================================================================
//  bf16_addsub_fused.v -- fused BF16 add/subtract ("butterfly") unit
//
//  Produces  y_sum = a + b  and  y_diff = a - b  in the same combinational
//  block, sharing everything that does not actually differ between the two.
//
//  The structural fact this exploits:
//
//      For a fixed pair of operands, exactly one of {a+b, a-b} is an
//      effective ADDITION of magnitudes and the other is an effective
//      SUBTRACTION -- never two additions, never two subtractions.
//
//          sign(a) == sign(b) :  a+b = |L|+|S|      a-b = |L|-|S|
//          sign(a) != sign(b) :  a+b = |L|-|S|      a-b = |L|+|S|
//
//      (L = larger magnitude operand, S = smaller.)
//
//  So instead of two general adders, each of which must be able to do either
//  operation, this unit builds one dedicated magnitude-adder and one
//  dedicated magnitude-subtracter and swaps them onto the two outputs.
//
//  What that buys, relative to two instances of bf16_add:
//
//    * ONE compare / swap network, ONE exponent difference, ONE aligner
//      (the variable right shifter is the most expensive block in the
//      front end) and ONE sticky tree -- all shared.
//    * The add path can only ever need a 1-bit RIGHT shift to normalise
//      (a magnitude sum never loses leading bits), so it needs no
//      leading-zero counter and no left shifter at all.
//    * The subtract path can never carry out (|L|-|S| <= |L|), so it needs
//      no right-shift path.
//      A general adder has to implement both, twice.
//
//  What still has to be duplicated: the two rounders, the two exponent
//  adjusts and the two packers -- the results genuinely differ.
//
//  Numerics are bit-identical to bf16_add for both outputs; see that file for
//  why 3 guard bits and a sticky-borrow are sufficient.
// ===========================================================================
`timescale 1ns/1ps

module bf16_addsub_fused (
    input  wire [15:0] a,
    input  wire [15:0] b,
    output wire [15:0] y_sum,       // a + b
    output wire [15:0] y_diff,      // a - b
    output wire [3:0]  flags_sum,   // {nv, of, uf, nx}
    output wire [3:0]  flags_diff
);

    localparam [15:0] QNAN = 16'h7FC0;

    // =====================================================================
    //  Shared front end
    // =====================================================================
    wire       sa = a[15];
    wire [7:0] ea = a[14:7];
    wire [6:0] fa = a[6:0];
    wire       sb = b[15];
    wire [7:0] eb = b[14:7];
    wire [6:0] fb = b[6:0];

    wire a_emax = &ea;
    wire b_emax = &eb;
    wire a_inf  = a_emax & ~|fa;
    wire b_inf  = b_emax & ~|fb;
    wire a_nan  = a_emax &  |fa;
    wire b_nan  = b_emax &  |fb;
    wire a_snan = a_nan & ~fa[6];
    wire b_snan = b_nan & ~fb[6];

    //  magnitude sort -- independent of both signs, hence shared
    wire b_bigger = (b[14:0] > a[14:0]);

    wire       s_l  = b_bigger ? sb : sa;
    wire [7:0] e_lr = b_bigger ? eb : ea;
    wire [7:0] e_sr = b_bigger ? ea : eb;
    wire [6:0] f_l  = b_bigger ? fb : fa;
    wire [6:0] f_s  = b_bigger ? fa : fb;

    wire [7:0] sig_l = {|e_lr, f_l};
    wire [7:0] sig_s = {|e_sr, f_s};
    wire [8:0] E_l   = |e_lr ? {1'b0, e_lr} : 9'd1;
    wire [8:0] E_s   = |e_sr ? {1'b0, e_sr} : 9'd1;
    wire [8:0] ediff = E_l - E_s;

    //  one aligner, one sticky tree
    wire [4:0]  sh        = (ediff > 9'd12) ? 5'd12 : ediff[4:0];
    wire [11:0] al_l      = {1'b0, sig_l, 3'b000};
    wire [11:0] al_s_full = {1'b0, sig_s, 3'b000};
    wire [11:0] al_s      = al_s_full >> sh;
    wire [11:0] lost_mask = ~(12'hFFF << sh);
    wire        sticky    = |(al_s_full & lost_mask);

    // =====================================================================
    //  Two dedicated magnitude operations
    // =====================================================================
    wire [11:0] mag_add = al_l + al_s;                      // bit 11 = carry
    wire [11:0] mag_sub = al_l - al_s - {11'd0, sticky};     // never carries

    // ---------------------------------------------------------------------
    //  ADD path : normalise = at most one right shift, no LZ, no left shifter
    // ---------------------------------------------------------------------
    wire        carry_a = mag_add[11];
    wire [10:0] mA      = carry_a ? mag_add[11:1] : mag_add[10:0];
    wire        stA     = carry_a ? (mag_add[0] | sticky) : sticky;
    wire [8:0]  EA      = carry_a ? (E_l + 9'd1) : E_l;

    wire [17:0] rp_add = round_pack(mA, stA, EA);
    wire        ovf_add = rp_add[17];
    wire        nx_add  = rp_add[15];
    wire        sub_add = rp_add[16];
    wire [14:0] mag_add_pk = rp_add[14:0];

    // ---------------------------------------------------------------------
    //  SUB path : normalise = leading-zero count + left shift, no right path
    // ---------------------------------------------------------------------
    reg [3:0] lz;
    always @* begin
        casez (mag_sub[10:0])
            11'b1??????????: lz = 4'd0;
            11'b01?????????: lz = 4'd1;
            11'b001????????: lz = 4'd2;
            11'b0001???????: lz = 4'd3;
            11'b00001??????: lz = 4'd4;
            11'b000001?????: lz = 4'd5;
            11'b0000001????: lz = 4'd6;
            11'b00000001???: lz = 4'd7;
            11'b000000001??: lz = 4'd8;
            11'b0000000001?: lz = 4'd9;
            11'b00000000001: lz = 4'd10;
            default:         lz = 4'd11;       // mag_sub == 0
        endcase
    end

    wire [8:0]  E_lm1 = E_l - 9'd1;
    wire [3:0]  shl   = ({5'd0, lz} > E_lm1) ? E_lm1[3:0] : lz;
    wire [10:0] mS    = mag_sub[10:0] << shl;
    wire [8:0]  ES    = E_l - {5'd0, shl};

    wire [17:0] rp_sub = round_pack(mS, sticky, ES);
    wire        nx_sub = rp_sub[15];
    wire        sub_sub = rp_sub[16];
    wire [14:0] mag_sub_pk = rp_sub[14:0];
    wire        zero_sub   = ~|mag_sub;   // exact cancellation

    // =====================================================================
    //  Route the two magnitudes onto the two outputs
    // =====================================================================
    wire same_sign = ~(sa ^ sb);

    //  Whichever output takes the magnitude SUM has both effective operands
    //  of sign sa, so its sign is sa.
    //  Whichever output takes the magnitude DIFFERENCE takes the sign of the
    //  larger operand, under that output's effective signs:
    //      y_sum  (signs differ) -> s_l
    //      y_diff (signs equal)  -> s_l ^ b_bigger   (b's sign is flipped)
    wire sgn_sub_for_sum  = s_l;
    wire sgn_sub_for_diff = s_l ^ b_bigger;

    //  a magnitude-difference of zero is +0 for both outputs under RNE
    wire [15:0] res_sum_num  = same_sign ? {sa, mag_add_pk}
                             : (zero_sub ? 16'h0000 : {sgn_sub_for_sum, mag_sub_pk});
    wire [15:0] res_diff_num = same_sign
                             ? (zero_sub ? 16'h0000 : {sgn_sub_for_diff, mag_sub_pk})
                             : {sa, mag_add_pk};

    // ---- specials -------------------------------------------------------
    wire any_nan   = a_nan | b_nan;
    wire any_inf   = a_inf | b_inf;
    wire inf_inf   = a_inf & b_inf;
    wire nan_sum   = any_nan | (inf_inf & ~same_sign);   // (+Inf) + (-Inf)
    wire nan_diff  = any_nan | (inf_inf &  same_sign);   // (+Inf) - (+Inf)

    wire [15:0] inf_sum  = {a_inf ? sa :  sb, 8'hFF, 7'd0};
    wire [15:0] inf_diff = {a_inf ? sa : ~sb, 8'hFF, 7'd0};

    assign y_sum  = nan_sum  ? QNAN : any_inf ? inf_sum  : res_sum_num;
    assign y_diff = nan_diff ? QNAN : any_inf ? inf_diff : res_diff_num;

    // ---- flags ----------------------------------------------------------
    wire snan_op = a_snan | b_snan;

    wire spec_sum  = nan_sum  | any_inf | (~same_sign & zero_sub);
    wire spec_diff = nan_diff | any_inf | ( same_sign & zero_sub);

    wire sum_takes_add  =  same_sign;
    wire diff_takes_add = ~same_sign;

    wire of_s = ~spec_sum  & sum_takes_add  & ovf_add;
    wire nx_s = ~spec_sum  & (sum_takes_add  ? (nx_add | ovf_add) : nx_sub);
    wire uf_s = ~spec_sum  & ~of_s &
                (sum_takes_add ? (sub_add & nx_add) : (sub_sub & nx_sub));

    wire of_d = ~spec_diff & diff_takes_add & ovf_add;
    wire nx_d = ~spec_diff & (diff_takes_add ? (nx_add | ovf_add) : nx_sub);
    wire uf_d = ~spec_diff & ~of_d &
                (diff_takes_add ? (sub_add & nx_add) : (sub_sub & nx_sub));

    assign flags_sum  = {snan_op | (inf_inf & ~same_sign), of_s, uf_s, nx_s};
    assign flags_diff = {snan_op | (inf_inf &  same_sign), of_d, uf_d, nx_d};

    // =====================================================================
    //  Shared round-and-pack description (inlined twice by synthesis)
    //  returns {overflow, subnormal, inexact, exp[7:0], frac[6:0]}
    // =====================================================================
    function [17:0] round_pack;
        input [10:0] m_pre;
        input        st_ex;
        input [8:0]  E_pre;
        reg [7:0] mant;
        reg       g, r, s, round_up, mant_ovf, subn, ovf;
        reg [8:0] mant_r, E_f;
        reg [7:0] mant_f;
        begin
            mant     = m_pre[10:3];
            g        = m_pre[2];
            r        = m_pre[1];
            s        = m_pre[0] | st_ex;
            round_up = g & (r | s | mant[0]);
            mant_r   = {1'b0, mant} + {8'd0, round_up};
            mant_ovf = mant_r[8];
            mant_f   = mant_ovf ? 8'h80 : mant_r[7:0];
            E_f      = E_pre + {8'd0, mant_ovf};
            ovf      = (E_f >= 9'd255);
            subn     = ~mant_f[7];
            round_pack = {ovf, subn, (g | r | s),
                          ovf ? 8'hFF : (subn ? 8'd0 : E_f[7:0]),
                          ovf ? 7'd0  : mant_f[6:0]};
        end
    endfunction

endmodule
