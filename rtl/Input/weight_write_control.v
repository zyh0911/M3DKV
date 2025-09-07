module weight_write_control #(
    parameter BANK_DATA_WIDTH = 128,       
    parameter BANK_NUM = 8,                
    parameter MACROS_ADDR_WIDTH = 8,       
    parameter MACRO_COLUMN = 16,          
    parameter MACRO_ROW = 16,
    parameter EXP_WIDTH = 4              
)(
    input                                        clk, 
    input                                        rst_n, 

    input  [BANK_DATA_WIDTH * BANK_NUM - 1:0]    data_wr,
    input                                        data_wr_vld,
    output                                       data_wr_rdy,

    output [MACROS_ADDR_WIDTH-1:0]               nmc_addr_wr, 
    output                                       nmc_addr_wr_vld,
    output [BANK_DATA_WIDTH * BANK_NUM - 1:0]    nmc_d
);
parameter log2_MACRO_COLUMN = $clog2(MACRO_COLUMN);
parameter log2_MACRO_ROW = $clog2(MACRO_ROW);

reg [log2_MACRO_COLUMN + log2_MACRO_ROW : 0 ] nmc_addr_wr_cnt;
wire nmc_addr_wr_is_max = (nmc_addr_wr_cnt == MACRO_COLUMN * MACRO_ROW - 1);
wire nmc_addr_wr_will_update_now = data_wr_vld & data_wr_rdy;

always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        nmc_addr_wr_cnt <= 'd0;
    end
    else begin
        if (nmc_addr_wr_will_update_now) begin
            nmc_addr_wr_cnt <= (nmc_addr_wr_is_max) ? 'd0 : nmc_addr_wr_cnt + 1;
        end
    end
end

genvar i, j;
generate
    for (i = 0; i < BANK_DATA_WIDTH; i = i + 1) begin : bit_slice
        for (j = 0; j < BANK_NUM; j = j + 1) begin : bank_slice
            assign nmc_d[j * BANK_DATA_WIDTH + i] = data_wr[i * BANK_NUM + j];
        end
    end
endgenerate

assign nmc_addr_wr_vld = data_wr_vld;
assign nmc_addr_wr = nmc_addr_wr_cnt;
assign data_wr_rdy = 1'b1;
    
endmodule