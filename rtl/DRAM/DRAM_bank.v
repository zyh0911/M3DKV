module DRAM_bank #(
    parameter MACROS_ADDR_WIDTH = 8,       
    parameter MACRO_DATA_WIDTH = 128,      
    parameter MACROS_NUM = 4, 
    parameter MACRO_COLUMN = 256,        
    parameter MACRO_ROW = 128                
)(
    input                         clk,
    input [MACROS_ADDR_WIDTH-1:0] addr, 
    input                         we, 
    input                         cme, 
    input [MACRO_DATA_WIDTH*MACROS_NUM-1:0] d, 
    input [MACRO_DATA_WIDTH*MACROS_NUM-1:0] cmIn,
    
    output [MACRO_DATA_WIDTH*MACROS_NUM-1:0] q, 
    output [MACRO_DATA_WIDTH*MACROS_NUM-1:0] cmOut
);

genvar i;
generate
    for (i = 0; i < MACROS_NUM; i = i + 1) begin : gen_macros_i
        DRAM_macros #(
            .MACROS_ADDR_WIDTH      (MACROS_ADDR_WIDTH),
            .MACRO_DATA_WIDTH       (MACRO_DATA_WIDTH),
            .MACRO_COLUMN           (MACRO_COLUMN),
            .MACRO_ROW              (MACRO_ROW)
        ) u_DRAM_macros (              
            .clk                    (clk),
            .addr                   (addr),                 
            .we                     (we),                 
            .cme                    (cme),               
            .d                      (d[i*MACRO_DATA_WIDTH +:MACRO_DATA_WIDTH]),             
            .cmIn                   (cmIn[i*MACRO_DATA_WIDTH +:MACRO_DATA_WIDTH]),            
            .q                      (q[i*MACRO_DATA_WIDTH +:MACRO_DATA_WIDTH]),            
            .cmOut                  (cmOut[i*MACRO_DATA_WIDTH +:MACRO_DATA_WIDTH])           
        );              
    end
endgenerate

endmodule