`timescale 1ns/1ps

/* Single-path BF16 adder
 *
 * Conventions / assumptions:
 *  - no subnormals: e == 0 means +/-0, the mantissa field is ignored
 *  - no inf / NaN: overflow is clamped to the largest finite number
 *  - round to zero (truncation)
 *  - N + (-N) returns +0
 *
 * Internally the addition is performed on z = x +/- y with |x| >= |y|,
 * this is the magnitude-swapped version of a and b.
 */

/* ------------------------------------------------------------------
 * compare and swap
 *
 * The swap decision is made on the *full magnitude* {e, m}, not on the
 * exponent alone: with an exponent-only compare, ea == eb && mb > ma
 * makes the significand subtraction go negative and wrap around.
 * Since {e, m} is monotonic with magnitude, a single (E+M)-bit subtract
 * gives the comparison for free through its borrow bit.
 * ------------------------------------------------------------------ */
module compare_and_select #(
	parameter int E = 8,
	parameter int M = 7
)(
	input  wire         sa_i,
	input  wire [E-1:0] ea_i,
	input  wire [M-1:0] ma_i,

	input  wire         sb_i,
	input  wire [E-1:0] eb_i,
	input  wire [M-1:0] mb_i,

	output wire         sx_o,        // sign of the larger magnitude operand
	output wire [E-1:0] ex_o,        // exponent of the larger magnitude operand
	output wire [M-1:0] mx_o,        // significand of the larger magnitude operand
	output wire [M-1:0] my_o,        // significand of the smaller magnitude operand
	output wire [E-1:0] shift_o,     // ex - ey, alignment shift amount
	output wire         x_nzero_o,   // hidden bit of x
	output wire         y_nzero_o    // hidden bit of y
);

wire [E+M-1:0] mag_a, mag_b;
wire [E+M-1:0] mag_diff_unused;
wire           swap;                 // |a| < |b|

assign mag_a = {ea_i, ma_i};
assign mag_b = {eb_i, mb_i};

// borrow out of |a| - |b| is the compare result, no separate comparator
assign {swap, mag_diff_unused} = mag_a - mag_b;

// both exponent differences computed in parallel: avoids serialising
// compare -> subtract on the critical path
wire [E-1:0] eab_diff, eba_diff;
wire         eab_diff_carry_unused, eba_diff_carry_unused;

assign {eab_diff_carry_unused, eab_diff} = ea_i - eb_i;
assign {eba_diff_carry_unused, eba_diff} = eb_i - ea_i;

wire [E-1:0] ey_o; //unused

assign shift_o      = swap ? eba_diff : eab_diff;
assign {ex_o, ey_o}   = swap ? {eb_i, ea_i} : {ea_i, eb_i};
assign {mx_o, my_o} = swap ? {mb_i, ma_i} : {ma_i, mb_i};
assign sx_o         = swap ? sb_i : sa_i;

// no subnormals: a null exponent means the value is zero, so the hidden
// bit has to be cleared, otherwise 0 is treated as 1.0 * 2^0
assign x_nzero_o = |ex_o;
assign y_nzero_o = |ey_o;

endmodule

/* ------------------------------------------------------------------
 * significand alignment and add / sub
 *
 * The datapath is M+2 bits wide: hidden bit + M + one extra lsb. That
 * extra lsb is not a rounding bit, it is what gets shifted back in when
 * the result is left normalised by one position after a cancellation
 * (exponent difference of 1), which keeps that case exact.
 *
 * Since the operands are magnitude ordered, mx >= my_shift always holds
 * and the subtraction can never go negative, so a single adder with
 * conditional inversion + carry in covers both operations.
 * ------------------------------------------------------------------ */
module add_sub_mantissa #(
	parameter int E = 8,
	parameter int M = 7
)(
	input  wire [M-1:0] mx_i,
	input  wire [M-1:0] my_i,
	input  wire         x_nzero_i,
	input  wire         y_nzero_i,
	input  wire         op_sub_i,       // sa ^ sb
	input  wire [E-1:0] shift_diff_i,

	output wire [M+1:0] m_o,
	output wire         ovf_o           // addition carried out, needs a >>1
);

// the shift amount only has M+3 useful values, clamping it here keeps the
// barrel shifter at $clog2(M+3) stages instead of E
localparam int SH_W = $clog2(M+3);

wire [SH_W-1:0] sh;
wire            over_shift;

assign over_shift = shift_diff_i > (M+2);
assign sh         = over_shift ? SH_W'(M+2) : shift_diff_i[SH_W-1:0];

wire [M+1:0] mx_expanded, my_expanded, my_shift;

assign mx_expanded = {x_nzero_i, mx_i & {M{x_nzero_i}}, 1'b0};
assign my_expanded = {y_nzero_i, my_i & {M{y_nzero_i}}, 1'b0};
assign my_shift    = my_expanded >> sh;

// sticky: y is truncated by the alignment, so on a subtraction the exact
// result sits one ulp below mx - my_shift. Dropping it, as is often done
// for a round to zero, gives a result one ulp *above* the truncated one.
// The mask is a shift of a constant, ie a thermometer decoder.
wire [M+1:0] shift_mask;
wire         sticky;

assign shift_mask = ~({(M+2){1'b1}} << sh);
assign sticky     = |(my_expanded & shift_mask);

// single adder: m_o = mx +/- my_shift (- sticky)
wire         sub_en;
wire [M+1:0] my_op;
wire         cin;
wire         cout;

assign sub_en = op_sub_i & y_nzero_i;
assign my_op  = my_shift ^ {M+2{sub_en}};
// two's complement wants +1, the sticky borrow wants -1: they cancel out,
// so the correction is free
assign cin    = sub_en & ~sticky;

assign {cout, m_o} = mx_expanded + my_op + {{M+1{1'b0}}, cin};

// on a subtraction the carry out is always 1 (no borrow), it only carries
// information in the addition case
assign ovf_o = cout & ~sub_en;

endmodule

/* ------------------------------------------------------------------
 * leading zero count, priority encoder
 * cnt_o == W when the input is all zeros
 * ------------------------------------------------------------------ */
module lzc_lite #(
	parameter int W  = 9,
	parameter int CW = $clog2(W+1)
)(
	input  wire  [W-1:0]  data_i,
	output logic [CW-1:0] cnt_o
);

always_comb begin
	cnt_o = CW'(W);
	// scanning upwards, the last branch taken is the msb that is set
	for (int k = 0; k < W; k++)
		if (data_i[k]) cnt_o = CW'(W-1-k);
end

endmodule

/* ------------------------------------------------------------------
 * normalisation and round to zero
 *
 * Single path, so the LZC + variable left shift is always in the loop,
 * there is no near/far split to hide it behind the alignment shifter.
 * ------------------------------------------------------------------ */
module normalize_rz #(
	parameter int E = 8,
	parameter int M = 7
)(
	input  wire         sx_i,
	input  wire [E-1:0] ex_i,
	input  wire         x_nzero_i,
	input  wire [M+1:0] m_i,
	input  wire         ovf_i,

	output wire         s_o,
	output wire [E-1:0] e_o,
	output wire [M-1:0] m_o
);

localparam int CW = $clog2(M+3);

wire [CW-1:0] lz;

lzc_lite #(.W(M+2), .CW(CW)) m_lzc (
	.data_i(m_i),
	.cnt_o (lz)
);

// cancellation: left normalise
wire [M+1:0] m_shifted;
assign m_shifted = m_i << lz;

wire [E-1:0] e_dec;
wire         e_uf;
assign {e_uf, e_dec} = ex_i - {{E-CW{1'b0}}, lz};

// round to zero: clamp to the largest finite number instead of going to inf
wire rz_max;
assign rz_max = ex_i == {{E-1{1'b1}}, 1'b0};

logic [E-1:0] e_norm;
logic [M-1:0] m_norm;

always_comb begin
	if (ovf_i) begin
		// the hidden bit is the carry out, drop the 2 lsbs
		e_norm = rz_max ? ex_i : ex_i + {{E-1{1'b0}}, 1'b1};
		m_norm = rz_max ? {M{1'b1}} : m_i[M+1:2];
	end else begin
		// m_shifted[M+1] is the hidden bit, [0] is the extra lsb
		e_norm = e_dec;
		m_norm = m_shifted[M:1];
	end
end

// flush to zero: x null (hence y null too), full cancellation, or the
// normalisation pushed the exponent to / below 0, no subnormals here
wire res_zero;
assign res_zero = ~x_nzero_i | (~ovf_i & (~|m_i | e_uf | ~|e_dec));

assign s_o = sx_i & ~res_zero;      // N + (-N) returns +0
assign e_o = res_zero ? {E{1'b0}} : e_norm;
assign m_o = res_zero ? {M{1'b0}} : m_norm;

endmodule

/* ------------------------------------------------------------------
 * top
 * ------------------------------------------------------------------ */
module bf16_add #(
	parameter int E = 8,
	parameter int M = 7
)(
	input  wire         sa_i,
	input  wire [E-1:0] ea_i,
	input  wire [M-1:0] ma_i,

	input  wire         sb_i,
	input  wire [E-1:0] eb_i,
	input  wire [M-1:0] mb_i,

	output wire         s_o,
	output wire [E-1:0] e_o,
	output wire [M-1:0] m_o
);

// compare & swap
wire         sx;
wire [E-1:0] ex;
wire [M-1:0] mx, my;
wire [E-1:0] shift_diff;
wire         x_nzero, y_nzero;

compare_and_select #(.E(E), .M(M)) m_compare_and_select (
	.sa_i     (sa_i),
	.ea_i     (ea_i),
	.ma_i     (ma_i),
	.sb_i     (sb_i),
	.eb_i     (eb_i),
	.mb_i     (mb_i),
	.sx_o     (sx),
	.ex_o     (ex),
	.mx_o     (mx),
	.my_o     (my),
	.shift_o  (shift_diff),
	.x_nzero_o(x_nzero),
	.y_nzero_o(y_nzero)
);

// sign
wire op_sub;
assign op_sub = sa_i ^ sb_i;

// align + add / sub
wire [M+1:0] mr;
wire         mr_ovf;

add_sub_mantissa #(.E(E), .M(M)) m_add_sub_mantissa (
	.mx_i        (mx),
	.my_i        (my),
	.x_nzero_i   (x_nzero),
	.y_nzero_i   (y_nzero),
	.op_sub_i    (op_sub),
	.shift_diff_i(shift_diff),
	.m_o         (mr),
	.ovf_o       (mr_ovf)
);

// normalise + round
normalize_rz #(.E(E), .M(M)) m_normalize_rz (
	.sx_i     (sx),
	.ex_i     (ex),
	.x_nzero_i(x_nzero),
	.m_i      (mr),
	.ovf_i    (mr_ovf),
	.s_o      (s_o),
	.e_o      (e_o),
	.m_o      (m_o)
);

`ifdef FORMAL

always @(*) begin
	// xcheck
	sva_xcheck_i: assert(~$isunknown({sa_i, ea_i, ma_i, sb_i, eb_i, mb_i}));
	sva_xcheck_o: assert(~$isunknown({s_o, e_o, m_o}));

	// the whole datapath relies on the magnitude ordering of the swap
	sva_swap_mag_geq: assert({ex, mx} >= {m_compare_and_select.ey, my});

	// magnitude ordering => the subtraction never borrows
	sva_sub_no_borrow: assert(~m_add_sub_mantissa.sub_en | m_add_sub_mantissa.cout);
end

`endif

endmodule
