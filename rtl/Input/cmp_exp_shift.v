
module cmp_exp_shift #(
    parameter MACRO_DATA_WIDTH = 128,
    parameter CMP_STAGES_PER_REG = 4,
    parameter EXP_WIDTH = 4,
	parameter MANTISSA_WIDTH = 3,
	parameter SIGN_WIDTH = 1,
	parameter FP_WIDTH = 8
)(
    input  [EXP_WIDTH * MACRO_DATA_WIDTH - 1: 0]         exp_data_in,

    output reg [EXP_WIDTH * MACRO_DATA_WIDTH - 1: 0]     shift_data_out,
    output [EXP_WIDTH - 1: 0]                            exp_max_data_out
);


cmp_tree # (
    .INPUT_WIDTH                                            (EXP_WIDTH),
    .INPUT_NUM                                              (MACRO_DATA_WIDTH)
  )
  cmp_tree_inst (
    .idata                                                  (exp_data_in),
    .max                                                    (exp_max_data_out)
  );

integer i;
always @(*) begin
    for (i = 0; i < MACRO_DATA_WIDTH; i = i + 1) begin
        shift_data_out[i*EXP_WIDTH +: EXP_WIDTH] =  exp_max_data_out[EXP_WIDTH - 1: 0] - exp_data_in[i*EXP_WIDTH +: EXP_WIDTH];
    end
end
   

endmodule