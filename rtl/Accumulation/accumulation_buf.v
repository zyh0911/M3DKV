module accumulation_buf #(                      
    parameter MACRO_COLUMN = 4,
    parameter MACRO_ROW = 32,
    parameter log2_MACRO_ROW = $clog2(MACRO_ROW),
    parameter log2_MACRO_COLUMN = $clog2(MACRO_COLUMN),
    parameter EXP_WIDTH = 8,
	parameter MANTISSA_WIDTH = 7,
	parameter SIGN_WIDTH = 1,
	parameter FP_WIDTH = 16
)(
    input                                       clk,
    input                                       rst_n,
    input [FP_WIDTH-1:0]                        fp_macro_result,
    input                                       fp_macro_result_vld,
    output                                      fp_macro_result_rdy,

    output [FP_WIDTH-1:0]                       fp_col_block_result,
    output reg                                  fp_col_block_result_vld,
    input                                       fp_col_block_result_rdy
); 
wire [FP_WIDTH-1:0] add_a,add_b,adder_out;
reg [log2_MACRO_COLUMN-1:0] fp_macro_result_cnt;          
reg [FP_WIDTH-1:0] sum_reg;

wire stall = fp_col_block_result_vld & ~fp_col_block_result_rdy;

always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        fp_macro_result_cnt <= 0;
    end else if (stall) begin
        
    end
    else if (fp_macro_result_vld) begin
        fp_macro_result_cnt <= (fp_macro_result_cnt == MACRO_COLUMN - 1) ? 0: fp_macro_result_cnt + 1;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        fp_col_block_result_vld <= 1'b0;
    end else if (stall) begin
        
    end
    else if (fp_macro_result_cnt == MACRO_COLUMN - 1 && fp_macro_result_vld) begin
        fp_col_block_result_vld <= 1'b1;
        
    end
    else begin
        fp_col_block_result_vld <= 1'b0;

    end
end

assign add_b = (fp_macro_result_cnt == 0) ? {FP_WIDTH{1'b0}} : sum_reg;
assign add_a = fp_macro_result;

reg fp_macro_result_vld_d;

always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        fp_macro_result_vld_d <= 1'b0;
    end else if (stall) begin
        
    end else begin
        fp_macro_result_vld_d <= fp_macro_result_vld;
    end                 
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        sum_reg <= {FP_WIDTH{1'b0}};
    else if (stall) begin
    
    end
    else if (fp_macro_result_vld_d)               
        sum_reg <= adder_out;
    else if ((fp_macro_result_cnt == MACRO_COLUMN - 1) & fp_macro_result_vld & fp_col_block_result_rdy)
        sum_reg <= {FP_WIDTH{1'b0}};
end

fp_add_single_cycle # (
    .EXP_WIDTH                              (EXP_WIDTH),
    .MANTISSA_WIDTH                         (MANTISSA_WIDTH),
    .SIGN_WIDTH                             (SIGN_WIDTH),
    .FP_WIDTH                               (FP_WIDTH)
)u_float_adder_single_cycle(
    .clk                                    (clk),
    .rstn                                   (rst_n),
    .add_a                                  (add_a),
    .add_b                                  (add_b),
    .adder_out                              (adder_out)
);



assign fp_macro_result_rdy = ~stall;
assign fp_col_block_result = (fp_col_block_result_vld) ? adder_out : 0;
endmodule