module GEMV_shared_block1 #(
    parameter EXP_WIDTH = 8,
	parameter MANTISSA_WIDTH = 7,
	parameter SIGN_WIDTH = 1,
	parameter FP_WIDTH = 16,
    parameter CMP_STAGES_PER_REG = 2, 

    parameter PARALLEL_ROW  = 32,
    parameter MACRO_DATA_WIDTH = 16
)(
    input  wire                                                                     clk,
    input  wire                                                                     rst_n,

    input  wire [PARALLEL_ROW*MACRO_DATA_WIDTH*FP_WIDTH-1:0]                        data_wr,
    input  wire                                                                     data_wr_vld,
    output wire                                                                     data_wr_rdy,

    output wire [PARALLEL_ROW*MACRO_DATA_WIDTH*(SIGN_WIDTH+MANTISSA_WIDTH+1)-1:0]   mantissa_plus_aligned,
    output wire [PARALLEL_ROW*EXP_WIDTH-1:0]                                        exp_max,
    output wire                                                                     mantissa_plus_aligned_vld,
    input  wire                                                                     mantissa_plus_aligned_rdy
);

wire [PARALLEL_ROW - 1: 0] data_wr_rdy_temp;
wire [PARALLEL_ROW - 1: 0] mantissa_plus_aligned_temp_vld;
genvar i;
generate
    for (i = 0; i < PARALLEL_ROW; i = i + 1) begin : data_wr_exp_pre_align
        pre_align # (
            .EXP_WIDTH                                  (EXP_WIDTH),
            .MANTISSA_WIDTH                             (MANTISSA_WIDTH),     
            .SIGN_WIDTH                                 (SIGN_WIDTH),  
            .FP_WIDTH                                   (FP_WIDTH),
            .MACRO_DATA_WIDTH                           (MACRO_DATA_WIDTH),
            .CMP_STAGES_PER_REG                         (CMP_STAGES_PER_REG)
        ) u_pre_align_wr_data (             
            .clk                                        (clk),
            .rst_n                                      (rst_n),
            .data_in                                    (data_wr[i * MACRO_DATA_WIDTH * FP_WIDTH +: MACRO_DATA_WIDTH * FP_WIDTH]),
            .data_in_vld                                (data_wr_vld),
            .data_in_rdy                                (data_wr_rdy_temp[i]),
            .exp_max                                    (exp_max[i*EXP_WIDTH +: EXP_WIDTH]),
            .mantissa_plus_aligned                      (mantissa_plus_aligned[i*(MACRO_DATA_WIDTH*(SIGN_WIDTH+MANTISSA_WIDTH+1)) +: MACRO_DATA_WIDTH*(SIGN_WIDTH+MANTISSA_WIDTH+1)]),
            .pre_aligned_vld                            (mantissa_plus_aligned_temp_vld[i]),
            .pre_aligned_rdy                            (mantissa_plus_aligned_rdy)
        );
    end
endgenerate

assign mantissa_plus_aligned_vld = &mantissa_plus_aligned_temp_vld;
assign data_wr_rdy = &data_wr_rdy_temp;
endmodule
