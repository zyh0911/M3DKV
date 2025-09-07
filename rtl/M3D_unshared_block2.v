module M3D_unshared_block2 #(
    parameter MACRO_ROW                                       = 2,
    parameter MACRO_COLUMN                                    = 4,
    parameter MACROS_ADDR_WIDTH                               = 4,
    parameter EXP_WIDTH                                       = 8,
    parameter MANTISSA_WIDTH                                  = 7,
    parameter SIGN_WIDTH                                      = 1,
    parameter FP_WIDTH                                        = 16,
    parameter PARALLEL_ROW                                    = 32,
    parameter Q_BUF_ADDR_WIDTH                                = 4
) (
    input  wire                                               clk,
    input  wire                                               rst_n,

    input  wire                                               bit_serial_acc_vld,
    input  wire                                               bit_serial_acc_rdy,

    output reg [Q_BUF_ADDR_WIDTH - 1 : 0]                     nmc_exp_max_addr,
    output reg [MACROS_ADDR_WIDTH-1: 0]                       data_wr_exp_max_addr,

    input  wire [PARALLEL_ROW * FP_WIDTH - 1:0]               fp_macro_result,
    input  wire                                               fp_macro_result_vld,
    output  wire                                              fp_macro_result_rdy,

    output wire [PARALLEL_ROW * FP_WIDTH - 1:0]               fp_col_block_result,
    output wire                                               fp_col_block_result_vld,
    input  wire                                               fp_col_block_result_rdy

);

wire [PARALLEL_ROW - 1:0] fp_macro_result_rdy_temp;
wire [PARALLEL_ROW - 1:0] fp_col_block_result_vld_temp;

// reg [MACROS_ADDR_WIDTH + $clog2(MACRO_ROW) + 1 - 1 : 0] data_wr_exp_max_addr_cnt;
always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        data_wr_exp_max_addr <= 0;
        nmc_exp_max_addr <= 0;
    end
    else begin
        if (bit_serial_acc_vld && bit_serial_acc_rdy) begin
            // data_wr_exp_max_addr_cnt <= data_wr_exp_max_addr_cnt + (1 << ($clog2(MACRO_ROW) + $clog2(MACRO_COLUMN))) + 1; 
            data_wr_exp_max_addr <= (data_wr_exp_max_addr == MACRO_ROW * MACRO_COLUMN - 1) ? 'd0 : data_wr_exp_max_addr + 1'b1;
            nmc_exp_max_addr <= (nmc_exp_max_addr == MACRO_COLUMN - 1) ? 'd0 : nmc_exp_max_addr + 1'b1;
        end
    end
end
// assign data_wr_exp_max_addr = data_wr_exp_max_addr_cnt[$clog2(MACROS_ADDR_WIDTH) + $clog2(MACRO_ROW) - 1 : $clog2(MACRO_ROW)];
// assign  = data_wr_exp_max_addr_cnt[MACROS_ADDR_WIDTH + $clog2(MACRO_ROW) - 1 : $clog2(MACRO_ROW)];
// reg [log2_MACRO_ROW - 1 : 0] nmc_exp_max_cnt;
// always @(posedge clk or negedge rst_n) begin
//     if (~rst_n) begin
//         nmc_exp_max_cnt <= 1'b0;
//     end else if (stall) begin
        
//     end
//     else begin
//         if (bit_serial_acc_vld && bit_serial_acc_rdy) begin
//             nmc_exp_max_cnt <= (nmc_exp_max_cnt == MACRO_ROW - 1) ? 'd0 : nmc_exp_max_cnt + 1'b1;
//         end
//     end
// end

genvar i;
generate
    for (i = 0; i < PARALLEL_ROW; i = i + 1) begin : macro_column_accumulation
        accumulation_buf # (
            .MACRO_COLUMN                                           (MACRO_COLUMN),
            .MACRO_ROW                                              (MACRO_ROW),
            .log2_MACRO_ROW                                         ($clog2(MACRO_ROW)),
            .log2_MACRO_COLUMN                                      ($clog2(MACRO_COLUMN)),
            .EXP_WIDTH                                              (EXP_WIDTH),
            .MANTISSA_WIDTH                                         (MANTISSA_WIDTH),
            .SIGN_WIDTH                                             (SIGN_WIDTH),
            .FP_WIDTH                                               (FP_WIDTH)
        )accumulation_buf_inst (
            .clk                                                    (clk),
            .rst_n                                                  (rst_n),
            .fp_macro_result                                        (fp_macro_result[i*FP_WIDTH +: FP_WIDTH]),
            .fp_macro_result_vld                                    (fp_macro_result_vld),
            .fp_macro_result_rdy                                    (fp_macro_result_rdy_temp[i]),
            .fp_col_block_result                                    (fp_col_block_result[i*FP_WIDTH +: FP_WIDTH]),
            .fp_col_block_result_vld                                (fp_col_block_result_vld_temp[i]),
            .fp_col_block_result_rdy                                (fp_col_block_result_rdy)
        );
    end
endgenerate

assign fp_macro_result_rdy = &fp_macro_result_rdy_temp;
assign fp_col_block_result_vld = &fp_col_block_result_vld_temp;

endmodule