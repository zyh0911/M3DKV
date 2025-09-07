module GEMV_shared_block2 #(
    parameter BANK_DATA_WIDTH                                 = 16,
    parameter BANK_NUM                                        = 8,
    parameter MACRO_DATA_WIDTH                                = 16,
    parameter ROUND                                           = 128,
    parameter EXP_WIDTH                                       = 8,
    parameter MANTISSA_WIDTH                                  = 7,
    parameter SIGN_WIDTH                                      = 1,
    parameter FP_WIDTH                                        = 16,
    parameter PARALLEL_ROW                                    = 32,
    parameter ADDER_TREE_WIDTH                                = 4,
    parameter BIT_SERIAL_ACC_WIDTH                            = 8,
    parameter COMPUTE_CYCLE                                   = MANTISSA_WIDTH + SIGN_WIDTH + 1
)(
    input  wire                                               clk,
    input  wire                                               rst_n,

    input  wire [PARALLEL_ROW * MACRO_DATA_WIDTH * BANK_NUM-1:0]  nmc_cmOut,
    input  wire                                               nmc_cmOut_vld,
    output wire                                               nmc_cmOut_rdy,

    output wire                                               bit_serial_acc_vld,
    output wire                                               bit_serial_acc_rdy,
    input  wire [EXP_WIDTH - 1 : 0]                           nmc_exp_max,
    input  wire                                               nmc_exp_max_vld,
    output wire                                               nmc_exp_max_rdy,
    input  wire [PARALLEL_ROW*EXP_WIDTH - 1 : 0]              data_wr_exp_max,
    input  wire                                               data_wr_exp_max_vld,
    output wire                                               data_wr_exp_max_rdy,

    output wire [PARALLEL_ROW * FP_WIDTH - 1:0]               fp_macro_result,
    output wire                                               fp_macro_result_vld,
    input  wire                                               fp_macro_result_rdy
);

wire [PARALLEL_ROW * BIT_SERIAL_ACC_WIDTH - 1:0] bit_serial_acc;
wire [PARALLEL_ROW - 1:0] bit_serial_acc_rdy_temp;
wire [PARALLEL_ROW - 1:0] data_wr_exp_max_rdy_temp;
wire [FP_WIDTH-1:0] fp_macro_result_temp [0:PARALLEL_ROW - 1];
wire [PARALLEL_ROW - 1:0] fp_macro_result_vld_temp;

Accumulation_top # (
    .BANK_DATA_WIDTH                                          (BANK_DATA_WIDTH),
    .BANK_NUM                                                 (BANK_NUM),
    .MACRO_DATA_WIDTH                                         (MACRO_DATA_WIDTH),
    .COL_BLOCK_SIZE                                           (PARALLEL_ROW),
    .ADDER_TREE_WIDTH                                         (ADDER_TREE_WIDTH),
    .BIT_SERIAL_ACC_WIDTH                                     (BIT_SERIAL_ACC_WIDTH),
    .COMPUTE_CYCLE                                            (COMPUTE_CYCLE),
    .ROUND                                                    (ROUND)
)u_Accumulation_top (  
    .clk                                                      (clk),
    .rst_n                                                    (rst_n),
    .nmc_cmOut                                                (nmc_cmOut),
    .nmc_cmOut_vld                                            (nmc_cmOut_vld),
    .nmc_cmOut_rdy                                            (nmc_cmOut_rdy),
    .bit_serial_acc                                           (bit_serial_acc),
    .bit_serial_acc_vld                                       (bit_serial_acc_vld),
    .bit_serial_acc_rdy                                       (bit_serial_acc_rdy)
);

genvar i;
generate
    for (i = 0; i < PARALLEL_ROW; i = i + 1) begin : bf16_combination_block
        bf16_combination # (
        .BIT_SERIAL_ACC_WIDTH                                 (BIT_SERIAL_ACC_WIDTH),
        .COMPUTE_CYCLE                                        (COMPUTE_CYCLE),
        .BANK_NUM                                             (BANK_NUM),
        .EXP_WIDTH                                            (EXP_WIDTH),
        .MANTISSA_WIDTH                                       (MANTISSA_WIDTH),
        .SIGN_WIDTH                                           (SIGN_WIDTH),
        .FP_WIDTH                                             (FP_WIDTH)
    )u_bf16_combination(  
        .clk                                                  (clk),
        .rst_n                                                (rst_n),
        .bit_serial_acc                                       (bit_serial_acc[i*BIT_SERIAL_ACC_WIDTH +: BIT_SERIAL_ACC_WIDTH]),
        .bit_serial_acc_vld                                   (bit_serial_acc_vld),
        .bit_serial_acc_rdy                                   (bit_serial_acc_rdy_temp[i]),
        .nmc_exp_max                                          (nmc_exp_max),
        .nmc_exp_max_vld                                      (nmc_exp_max_vld),
        .nmc_exp_max_rdy                                      (nmc_exp_max_rdy),
        .data_wr_exp_max                                      (data_wr_exp_max[i*EXP_WIDTH +: EXP_WIDTH]),
        .data_wr_exp_max_vld                                  (data_wr_exp_max_vld),
        .data_wr_exp_max_rdy                                  (data_wr_exp_max_rdy_temp[i]),
        .fp_macro_result                                      (fp_macro_result_temp[i]),
        .fp_macro_result_vld                                  (fp_macro_result_vld_temp[i]),
        .fp_macro_result_rdy                                  (fp_macro_result_rdy)
    );
    end
endgenerate
 

generate
    for (i = 0; i < PARALLEL_ROW; i = i + 1) begin : assign_fp_macro_result
        assign fp_macro_result[i*FP_WIDTH +: FP_WIDTH] = fp_macro_result_temp[i];
    end
endgenerate
assign fp_macro_result_vld = &fp_macro_result_vld_temp;
assign bit_serial_acc_rdy = &bit_serial_acc_rdy_temp;
assign data_wr_exp_max_rdy = &data_wr_exp_max_rdy_temp;

endmodule