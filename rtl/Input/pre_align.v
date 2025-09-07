// `define MAN(x, low)     x[low +: MANTISSA_WIDTH]
// `define EXP(x, low)     x[low + MANTISSA_WIDTH +: EXP_WIDTH]
// `define SIGN(x, low)    x[low + MANTISSA_WIDTH + EXP_WIDTH +: SIGN_WIDTH]
module pre_align #(     
    parameter EXP_WIDTH = 4,
	parameter MANTISSA_WIDTH = 3,
	parameter SIGN_WIDTH = 1,
	parameter FP_WIDTH = 8,

    parameter MACRO_DATA_WIDTH = 128,                                    
    parameter CMP_STAGES_PER_REG = 4
)(
    input                                                                     clk, 
    input                                                                     rst_n, 

    input  [MACRO_DATA_WIDTH * FP_WIDTH - 1: 0]                               data_in,
    input                                                                     data_in_vld,
    output                                                                    data_in_rdy,

    output [EXP_WIDTH - 1 : 0]                                                exp_max,
    output [MACRO_DATA_WIDTH * (SIGN_WIDTH + MANTISSA_WIDTH + 1) - 1: 0]      mantissa_plus_aligned,
    output                                                                    pre_aligned_vld,
    input                                                                     pre_aligned_rdy
);
wire shift_rdy;
wire mantissa_rdy;
assign data_in_rdy = mantissa_rdy & shift_rdy;

wire [EXP_WIDTH * MACRO_DATA_WIDTH - 1: 0] shift;
reg [EXP_WIDTH - 1 : 0] exp_max_reg0;
wire [EXP_WIDTH - 1 : 0] exp_max_temp;
    
wire [MACRO_DATA_WIDTH * EXP_WIDTH - 1 : 0] data_in_exp;
wire [MACRO_DATA_WIDTH * (SIGN_WIDTH + MANTISSA_WIDTH) - 1 : 0] data_in_sign_mantissa;
genvar i;
generate
    for (i = 0; i < MACRO_DATA_WIDTH; i = i + 1) begin
        assign data_in_sign_mantissa[i * (SIGN_WIDTH + MANTISSA_WIDTH) +: (SIGN_WIDTH + MANTISSA_WIDTH)] = {data_in[i * FP_WIDTH + MANTISSA_WIDTH + EXP_WIDTH +: SIGN_WIDTH],data_in[i * FP_WIDTH +: MANTISSA_WIDTH]};
        assign data_in_exp[i * EXP_WIDTH +: EXP_WIDTH] = data_in[i * FP_WIDTH + MANTISSA_WIDTH +: EXP_WIDTH];
    end
endgenerate

cmp_exp_shift # (
    .MACRO_DATA_WIDTH                           (MACRO_DATA_WIDTH),
    .CMP_STAGES_PER_REG                         (CMP_STAGES_PER_REG),
    .EXP_WIDTH                                  (EXP_WIDTH),
    .MANTISSA_WIDTH                             (MANTISSA_WIDTH),
    .SIGN_WIDTH                                 (SIGN_WIDTH),
    .FP_WIDTH                                   (FP_WIDTH)
)u_cmp_exp_shift(
    .exp_data_in                                (data_in_exp),
    .shift_data_out                             (shift),
    .exp_max_data_out                           (exp_max_temp)
);

always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        exp_max_reg0 <= 0;
    end else if (data_in_vld) begin
        exp_max_reg0 <= exp_max_temp;
    end
end
assign exp_max = exp_max_reg0;

mantissa_shift # (
    .MACRO_DATA_WIDTH                           (MACRO_DATA_WIDTH),
    .SIGN_WIDTH                                 (SIGN_WIDTH),
    .MANTISSA_WIDTH                             (MANTISSA_WIDTH),
    .EXP_WIDTH                                  (EXP_WIDTH)
) u_mantissa_shift_inst (
    .clk                                        (clk),
    .rst_n                                      (rst_n),
    .mantissa                                   (data_in_sign_mantissa),
    .mantissa_vld                               (data_in_vld),
    .mantissa_rdy                               (mantissa_rdy),
    .shift                                      (shift),
    .shift_vld                                  (data_in_vld),
    .shift_rdy                                  (shift_rdy),
    .mantissa_plus_aligned                      (mantissa_plus_aligned),
    .mantissa_plus_aligned_vld                  (pre_aligned_vld),
    .mantissa_plus_aligned_rdy                  (pre_aligned_rdy)
);

    
endmodule