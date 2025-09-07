module DRAM_macros #(
    parameter MACROS_ADDR_WIDTH = 8,       
    parameter MACRO_DATA_WIDTH = 128,    
    parameter MACRO_COLUMN = 256,        
    parameter MACRO_ROW = 128            
)(  
    input                           clk,
    input [MACROS_ADDR_WIDTH-1:0]   addr, 
    input                           we, 
    input                           cme, 
    input [MACRO_DATA_WIDTH-1:0]    d, 
    input [MACRO_DATA_WIDTH-1:0]    cmIn,
    
    output reg [MACRO_DATA_WIDTH-1:0] q, //memory mode output data
    output reg [MACRO_DATA_WIDTH-1:0] cmOut
);

localparam RAM_DEPTH = MACRO_COLUMN * MACRO_ROW;
reg [MACRO_DATA_WIDTH-1:0] mem [0:RAM_DEPTH-1];

always @(posedge clk) begin
    if (we) begin
        mem[addr] <= d;
    end
    else begin
        if (cme) begin
            cmOut <= cmIn & mem[addr];
        end
        else begin
            q <= mem[addr];
        end
    end
end

endmodule