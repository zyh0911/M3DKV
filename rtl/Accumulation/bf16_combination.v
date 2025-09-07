module bf16_combination #(
    parameter BIT_SERIAL_ACC_WIDTH =10,
    parameter COMPUTE_CYCLE = 5,
    parameter BANK_NUM = 5,
    parameter EXP_WIDTH = 4,
	parameter MANTISSA_WIDTH = 3,
	parameter SIGN_WIDTH = 1,
	parameter FP_WIDTH = 8
)(
    input                                               clk,
    input                                               rst_n,

    input  [BIT_SERIAL_ACC_WIDTH- 1 : 0]                bit_serial_acc,
    input                                               bit_serial_acc_vld,
    output                                              bit_serial_acc_rdy,
    
    input  [EXP_WIDTH - 1 : 0]                          nmc_exp_max,
    input                                               nmc_exp_max_vld,
    output                                              nmc_exp_max_rdy,
    
    input  [EXP_WIDTH - 1 : 0]                          data_wr_exp_max,
    input                                               data_wr_exp_max_vld,
    output                                              data_wr_exp_max_rdy,

    output [FP_WIDTH - 1 : 0]                           fp_macro_result,
    output reg                                          fp_macro_result_vld,
    input                                               fp_macro_result_rdy

);
reg [EXP_WIDTH - 1 : 0] nmc_exp_max_d;
reg [EXP_WIDTH - 1 : 0] data_wr_exp_max_d;

wire stall = fp_macro_result_vld & ~fp_macro_result_rdy;
reg [SIGN_WIDTH - 1 : 0] bf16_macro_sign;
reg [EXP_WIDTH -1: 0] bf16_macro_exp;
reg bit_serial_acc_vld_reg;
wire [MANTISSA_WIDTH - 1 : 0] bf16_macro_mantissa;
    
reg [BIT_SERIAL_ACC_WIDTH-1:0] bit_serial_acc_abs;
wire [$clog2(BIT_SERIAL_ACC_WIDTH) + 1 - 1 : 0] leading_one_pos;

always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        bf16_macro_sign <='d0;
        bit_serial_acc_abs <= 'd0;
        bit_serial_acc_vld_reg <= 'd0;
    end 
    else if (stall) begin
        
    end
    else begin
        if (bit_serial_acc_vld) begin
            bit_serial_acc_abs <= (bit_serial_acc[BIT_SERIAL_ACC_WIDTH-1]) ? -bit_serial_acc: bit_serial_acc;
            bf16_macro_sign <= bit_serial_acc[BIT_SERIAL_ACC_WIDTH-1];
        end
        bit_serial_acc_vld_reg <= bit_serial_acc_vld;
    end
end

leading_one_detect_com # (
    .INPUT_WIDTH                                (BIT_SERIAL_ACC_WIDTH),
    .OUTPUT_WIDTH                               ($clog2(BIT_SERIAL_ACC_WIDTH) + 1)
  )u_leading_one_detect_com (
    .idata                                      (bit_serial_acc_abs),
    .odata                                      (leading_one_pos)
);

always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        nmc_exp_max_d <= 'd0;
        data_wr_exp_max_d <= 'd0;
        bf16_macro_exp <= 'd0;
        fp_macro_result_vld <= 1'b0;
    end
    else if (stall) begin
        
    end
    else begin
        if (nmc_exp_max_vld) begin
            nmc_exp_max_d <= nmc_exp_max;
        end
        if (data_wr_exp_max_vld) begin
            data_wr_exp_max_d <= data_wr_exp_max;
        end
        if (bit_serial_acc_vld_reg) begin
            bf16_macro_exp <= data_wr_exp_max_d + nmc_exp_max_d - (2**(EXP_WIDTH - 1) - 1) - (leading_one_pos - 1'b1) + BIT_SERIAL_ACC_WIDTH - COMPUTE_CYCLE - BANK_NUM + 'd3; 
            fp_macro_result_vld <= 1'b1;
        end
        else begin
            bf16_macro_exp <= bf16_macro_exp;
            fp_macro_result_vld <= 1'b0;
        end
    end
end

assign bf16_macro_mantissa =  bit_serial_acc_abs[BIT_SERIAL_ACC_WIDTH - 1 - leading_one_pos -: MANTISSA_WIDTH];
assign fp_macro_result = {bf16_macro_sign,bf16_macro_exp,bf16_macro_mantissa};

assign bit_serial_acc_rdy =  ~stall;
assign data_wr_exp_max_rdy = ~stall;
assign nmc_exp_max_rdy = ~stall;

endmodule
