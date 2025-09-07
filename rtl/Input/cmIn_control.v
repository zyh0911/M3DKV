module cmIn_control #(
    parameter MACRO_DATA_WIDTH = 16,       
    parameter COMPUTE_CYCLE = 8,            
    parameter MACROS_ADDR_WIDTH = 8,        
    parameter BANK_DATA_WIDTH = 512,        
    parameter BANK_NUM = 9,                 
    parameter MACRO_ROW = 32,              
    parameter MACRO_COLUMN = 4,           
    parameter COL_BLOCK_SIZE = 32,
    parameter Q_BUF_ADDR_WIDTH = 2              
)(
    input                                                clk, 
    input                                                rst_n, 

    input [MACRO_DATA_WIDTH * COMPUTE_CYCLE - 1 : 0]     data_in,
    input                                                data_in_vld,
    output                                               data_in_rdy,
    output                                               data_in_update,   

    output reg [MACROS_ADDR_WIDTH-1:0]                   nmc_addr, 
    output [BANK_DATA_WIDTH * BANK_NUM-1:0]              nmc_cmIn,
    output                                               nmc_cmIn_vld,
    input                                                nmc_cmIn_rdy

);

localparam log2COMPUTE_CYCLE = $clog2(COMPUTE_CYCLE);
localparam log2_MACRO_ROW = $clog2(MACRO_ROW);
localparam log2_MACRO_COLUMN = $clog2(MACRO_COLUMN);

wire stall = nmc_cmIn_vld & ~nmc_cmIn_rdy;

reg [log2COMPUTE_CYCLE-1:0] bit_serial_cnt;
wire bit_serial_cnt_is_max = (bit_serial_cnt == COMPUTE_CYCLE - 1);
wire bit_serial_cnt_will_update_now = nmc_cmIn_vld & nmc_cmIn_rdy;

always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        bit_serial_cnt <= 0;
    end
    else if (stall) begin
        // stall
    end
    else begin
        if (bit_serial_cnt_will_update_now) begin
            bit_serial_cnt <= (bit_serial_cnt_is_max) ? 'd0 : bit_serial_cnt + 1;
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        nmc_addr <= 'd0;
    end
    else if (stall) begin
        // stall
    end
    else begin
        if (bit_serial_cnt_is_max & bit_serial_cnt_will_update_now) begin
            nmc_addr <= (nmc_addr == MACRO_ROW * MACRO_COLUMN) ? 'd0 : nmc_addr + 1;
        end
        else begin
            nmc_addr <= nmc_addr;
        end
    end
end


wire [MACRO_DATA_WIDTH-1:0] nmc_cmIn_temp;
genvar i;
generate
    for (i = 0; i < MACRO_DATA_WIDTH; i = i + 1) begin : gen_nmc_cmIn_temp
        assign nmc_cmIn_temp[i] = data_in [i * COMPUTE_CYCLE + bit_serial_cnt];
    end
endgenerate

assign nmc_cmIn = {(BANK_NUM * COL_BLOCK_SIZE){nmc_cmIn_temp}};
assign nmc_cmIn_vld = data_in_vld;
assign data_in_update = bit_serial_cnt_is_max & bit_serial_cnt_will_update_now & ~stall;
assign data_in_rdy = nmc_cmIn_rdy & ~stall;

endmodule