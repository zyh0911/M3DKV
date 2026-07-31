// ===========================================================================
//  bf16_add.v -- combinational bfloat16 (BF16) adder / subtractor
//
//  Format : [15] sign | [14:7] exponent (bias 127) | [6:0] fraction
//           i.e. the top half of an IEEE-754 binary32.  8-bit significand
//           (1 implicit + 7 stored), subnormals and specials supported.
//
//  Rounding : round-to-nearest, ties-to-even (RNE) only.
//
//  Structure (classic single-path adder, exact by construction):
//     unpack -> magnitude sort -> align smaller operand (3 GRS bits + a
//     true sticky) -> add/subtract -> normalise (1 right / N left shift,
//     clamped so the result can go subnormal) -> RNE round -> pack.
//
//  Why 3 extra bits are enough:
//     * sticky can only be set when the alignment shift is >= 4, and in that
//       case an effective subtraction cancels at most 0 leading bits, so the
//       normalising left shift is 0 whenever sticky is 1;
//     * a normalising left shift of >= 2 needs exponent difference <= 1, and
//       then nothing was shifted out at all.
//     For an effective subtraction the borrow caused by the discarded tail is
//     modelled exactly by subtracting the sticky bit; the remaining residue is
//     in (0,1) ulp of the S position, which keeps S = 1.
//
//  Flags (IEEE names): nv = invalid, of = overflow, uf = underflow (tiny AND
//  inexact, i.e. after rounding), nx = inexact.  No sNaN payload propagation:
//  any NaN result is the canonical qNaN 0x7FC0.
//
//  Note on uf: every BF16 value is an integer multiple of the smallest
//  subnormal, so a sum of two of them is too -- a result in the subnormal
//  range is therefore always exact and uf can never fire for addition.  The
//  logic is kept so the flag interface is complete (and correct if this block
//  is ever reused with a wider aligner).
// ===========================================================================
`timescale 1ns/1ps

module bf16_add (
    input  wire [15:0] a,
    input  wire [15:0] b,
    input  wire        sub,   // 0 -> a + b , 1 -> a - b
    output wire [15:0] y,
    output wire        nv,    // invalid   (sNaN operand, or Inf - Inf)
    output wire        of,    // overflow
    output wire        uf,    // underflow
    output wire        nx     // inexact
);

    localparam [15:0] QNAN = 16'h7FC0;

    // -----------------------------------------------------------------
    //  1. unpack + classify
    // -----------------------------------------------------------------
    wire        sa = a[15];
    wire [7:0]  ea = a[14:7];
    wire [6:0]  fa = a[6:0];

    wire        sb = b[15] ^ sub;          // subtraction = add with flipped sign
    wire [7:0]  eb = b[14:7];
    wire [6:0]  fb = b[6:0];

    wire a_emax = &ea;
    wire b_emax = &eb;
    wire a_inf  = a_emax & ~|fa;
    wire b_inf  = b_emax & ~|fb;
    wire a_nan  = a_emax &  |fa;
    wire b_nan  = b_emax &  |fb;
    wire a_snan = a_nan & ~fa[6];
    wire b_snan = b_nan & ~fb[6];

    // -----------------------------------------------------------------
    //  2. sort by magnitude ( "l" = large, "s" = small )
    //     The 15-bit field {exp,frac} orders magnitudes directly, including
    //     subnormals, which is exactly what the comparison needs.
    // -----------------------------------------------------------------
    wire b_bigger = (b[14:0] > a[14:0]);

    wire        s_l  = b_bigger ? sb : sa;
    wire        s_s  = b_bigger ? sa : sb;
    wire [7:0]  e_lr = b_bigger ? eb : ea;
    wire [7:0]  e_sr = b_bigger ? ea : eb;
    wire [6:0]  f_l  = b_bigger ? fb : fa;
    wire [6:0]  f_s  = b_bigger ? fa : fb;

    // significand = {implicit bit, fraction}; subnormals use exponent 1
    wire [7:0] sig_l = {|e_lr, f_l};
    wire [7:0] sig_s = {|e_sr, f_s};
    wire [8:0] E_l   = |e_lr ? {1'b0, e_lr} : 9'd1;
    wire [8:0] E_s   = |e_sr ? {1'b0, e_sr} : 9'd1;
    wire [8:0] ediff = E_l - E_s;                  // >= 0 by construction

    // -----------------------------------------------------------------
    //  3. align : 12-bit datapath = 1 carry | 8 significand | G R S
    // -----------------------------------------------------------------
    wire [4:0]  sh        = (ediff > 9'd12) ? 5'd12 : ediff[4:0];
    wire [11:0] al_l      = {1'b0, sig_l, 3'b000};
    wire [11:0] al_s_full = {1'b0, sig_s, 3'b000};
    wire [11:0] al_s      = al_s_full >> sh;
    wire [11:0] lost_mask = ~(12'hFFF << sh);      // bits the shift discards
    wire        sticky    = |(al_s_full & lost_mask);

    // -----------------------------------------------------------------
    //  4. add / subtract   (al_s <= al_l always, so no negative result)
    // -----------------------------------------------------------------
    wire        eff_sub = s_l ^ s_s;
    wire [11:0] sum     = eff_sub ? (al_l - al_s - {11'd0, sticky})
                                  : (al_l + al_s);

    // -----------------------------------------------------------------
    //  5. normalise
    // -----------------------------------------------------------------
    wire carry = sum[11];

    reg [3:0] lz;                                  // leading zeros of sum[10:0]
    always @* begin
        casez (sum[10:0])
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
            default:         lz = 4'd11;           // sum == 0
        endcase
    end

    // never shift past the subnormal boundary (exponent must stay >= 1)
    wire [8:0] E_lm1 = E_l - 9'd1;
    wire [3:0] shl   = ({5'd0, lz} > E_lm1) ? E_lm1[3:0] : lz;

    wire [10:0] m_pre = carry ? sum[11:1] : (sum[10:0] << shl);
    wire        st_ex = carry ? (sum[0] | sticky) : sticky;
    wire [8:0]  E_pre = carry ? (E_l + 9'd1) : (E_l - {5'd0, shl});

    // -----------------------------------------------------------------
    //  6. round to nearest even
    // -----------------------------------------------------------------
    wire [7:0] mant = m_pre[10:3];
    wire       g    = m_pre[2];
    wire       r    = m_pre[1];
    wire       s    = m_pre[0] | st_ex;

    wire       round_up = g & (r | s | mant[0]);
    wire [8:0] mant_r   = {1'b0, mant} + {8'd0, round_up};
    wire       mant_ovf = mant_r[8];               // 0xFF + 1 -> 0x100

    wire [7:0] mant_f = mant_ovf ? 8'h80 : mant_r[7:0];
    wire [8:0] E_f    = E_pre + {8'd0, mant_ovf};

    // -----------------------------------------------------------------
    //  7. pack
    // -----------------------------------------------------------------
    wire        exp_ovf    = (E_f >= 9'd255);
    wire        subnorm    = ~mant_f[7];           // implies E_f == 1
    wire [7:0]  e_out      = subnorm ? 8'd0 : E_f[7:0];
    wire [15:0] res_normal = exp_ovf ? {s_l, 8'hFF, 7'd0}
                                     : {s_l, e_out, mant_f[6:0]};

    // exact cancellation (or 0 + 0): RNE gives +0 unless both operands are -0
    wire        zero_res  = ~|sum;
    wire [15:0] res_zero  = {(s_l == s_s) ? s_l : 1'b0, 15'd0};

    wire        any_nan   = a_nan | b_nan;
    wire        inf_minus = a_inf & b_inf & (sa ^ sb);
    wire        res_is_nan= any_nan | inf_minus;
    wire        any_inf   = a_inf | b_inf;
    wire [15:0] res_inf   = {a_inf ? sa : sb, 8'hFF, 7'd0};

    assign y = res_is_nan ? QNAN     :
               any_inf    ? res_inf  :
               zero_res   ? res_zero : res_normal;

    wire special = res_is_nan | any_inf | zero_res;

    assign nv = a_snan | b_snan | inf_minus;
    assign nx = ~special & ((g | r | s) | exp_ovf);
    assign of = ~special & exp_ovf;
    assign uf = ~special & ~exp_ovf & subnorm & (g | r | s);

endmodule
