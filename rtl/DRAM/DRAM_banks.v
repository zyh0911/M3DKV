
module DRAM_banks #(
    parameter MACROS_ADDR_WIDTH = 8,       
    parameter BANK_DATA_WIDTH = 128,       
    parameter BANK_NUM = 8,                
    parameter MACRO_DATA_WIDTH = 128,                
    parameter COL_BLOCK_SIZE = 4,                
    parameter MACRO_COLUMN = 16,                
    parameter MACRO_ROW = 16             
)(
    input                                   clk, 
    input                                   rst_n, 
    input [MACROS_ADDR_WIDTH-1:0]           nmc_addr, 
    input                                   nmc_we, 
    input                                   nmc_cme, 
    input [BANK_DATA_WIDTH*BANK_NUM-1:0]    nmc_d, 
    input [BANK_DATA_WIDTH*BANK_NUM-1:0]    nmc_cmIn,
    input                                   nmc_cmIn_vld,
    output                                  nmc_cmIn_rdy,
    
    output [BANK_DATA_WIDTH*BANK_NUM-1:0]   nmc_q,
    output [BANK_DATA_WIDTH*BANK_NUM-1:0]   nmc_cmOut,
    output                                  nmc_cmOut_vld,
    input                                   nmc_cmOut_rdy 
);

wire stall = nmc_cmOut_vld & !nmc_cmOut_rdy & ~nmc_we;

reg nmc_cmOut_vld_d;

always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        nmc_cmOut_vld_d <= 'd0;
    end
    else begin
        if (stall) begin
            // stall
        end else begin
            nmc_cmOut_vld_d <= nmc_cmIn_vld;
        end
    end
end

genvar i;
generate
    for (i = 0; i < BANK_NUM; i = i + 1) begin : gen_bank_i
        DRAM_bank #(
            .MACROS_ADDR_WIDTH          (MACROS_ADDR_WIDTH),
            .MACRO_DATA_WIDTH           (MACRO_DATA_WIDTH),
            .MACROS_NUM                 (COL_BLOCK_SIZE),
            .MACRO_COLUMN               (MACRO_COLUMN),        
            .MACRO_ROW                  (MACRO_ROW)   
        ) u_DRAM_bank (
            .clk                        (clk),
            .addr                       (nmc_addr),
            .we                         (nmc_we),
            .cme                        (nmc_cme),
            .d                          (nmc_d[i*BANK_DATA_WIDTH +:BANK_DATA_WIDTH]),
            .cmIn                       (nmc_cmIn[i*BANK_DATA_WIDTH +:BANK_DATA_WIDTH]),
            .q                          (nmc_q[i*BANK_DATA_WIDTH +:BANK_DATA_WIDTH]),
            .cmOut                      (nmc_cmOut[i*BANK_DATA_WIDTH +:BANK_DATA_WIDTH]) 
        );
    end
endgenerate

assign nmc_cmIn_rdy = !stall;
assign nmc_cmOut_vld = nmc_cmOut_vld_d;

endmodule