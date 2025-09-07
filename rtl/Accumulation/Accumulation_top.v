module Accumulation_top #(
    parameter BANK_DATA_WIDTH = 512,              
    parameter BANK_NUM = 8,                       
    parameter MACRO_DATA_WIDTH = 16,             
    parameter COL_BLOCK_SIZE = 32,                     
    parameter ADDER_TREE_WIDTH = 13,              
    parameter BIT_SERIAL_ACC_WIDTH = 32,          
    parameter COMPUTE_CYCLE = 8,
    parameter ROUND = 128                  
)(
    input                                               clk,
    input                                               rst_n,

    input  [BANK_DATA_WIDTH * BANK_NUM - 1: 0]          nmc_cmOut,
    input                                               nmc_cmOut_vld,
    output                                              nmc_cmOut_rdy,

    output  [BIT_SERIAL_ACC_WIDTH * COL_BLOCK_SIZE - 1 : 0] bit_serial_acc,
    output                                              bit_serial_acc_vld,
    input                                               bit_serial_acc_rdy   
);

//-------------------------------------split bits & compensation-------------------------------------------------------//

genvar i, j, k;

wire [BANK_NUM * MACRO_DATA_WIDTH-1:0] cmOut_split [0:COL_BLOCK_SIZE-1];
wire [ADDER_TREE_WIDTH * MACRO_DATA_WIDTH-1:0] cmOut_add [0:COL_BLOCK_SIZE-1];
generate
    for (i = 0; i < COL_BLOCK_SIZE; i = i + 1) begin : MACRO_LOOP
        localparam MACRO_OFFSET = i * MACRO_DATA_WIDTH;
        for (j = 0; j < MACRO_DATA_WIDTH; j = j + 1) begin : NUM_LOOP
            for (k = 0; k < BANK_NUM; k = k + 1) begin : BIT_LOOP
                localparam SRC_POS = MACRO_OFFSET + 
                                   (k * MACRO_DATA_WIDTH * COL_BLOCK_SIZE) + 
                                   j;                       
                localparam DST_POS = (j * BANK_NUM) + k;
                assign cmOut_split[i][DST_POS] = nmc_cmOut[SRC_POS];
            end
        end
    end
endgenerate

generate
    for (i = 0; i < COL_BLOCK_SIZE; i = i + 1) begin : MACRO_ADD
        for (j = 0; j < MACRO_DATA_WIDTH; j = j + 1) begin : NUM_MAP
            assign cmOut_add[i][(j*ADDER_TREE_WIDTH)+:ADDER_TREE_WIDTH] = 
                { {(ADDER_TREE_WIDTH - BANK_NUM){cmOut_split[i][(j*BANK_NUM)+BANK_NUM-1]}}, 
                cmOut_split[i][(j*BANK_NUM)+:BANK_NUM]                                   
            };
        end
    end
endgenerate


//----------------------------------------------adder tree--------------------------------------------------//
wire signed [ADDER_TREE_WIDTH-1:0] adder_tree_sum [0:COL_BLOCK_SIZE-1];
wire [COL_BLOCK_SIZE-1:0] adder_tree_sum_rdy;
wire [COL_BLOCK_SIZE-1:0] adder_tree_sum_vld;

generate
    for (i = 0; i < COL_BLOCK_SIZE; i = i + 1) begin : adder_tree
        adder_tree_reg #(
            .INPUT_WIDTH    (ADDER_TREE_WIDTH),
            .INPUT_NUM      (MACRO_DATA_WIDTH),
            .STAGES_PER_REG (4)
        )u_adder_tree_reg (
            .clk            (clk),
            .aresetn        (rst_n),

            .idata          (cmOut_add[i]),
            .ivalid         (nmc_cmOut_vld),
            .iready         (nmc_cmOut_rdy),

            .sum            (adder_tree_sum[i]),
            .ovalid         (adder_tree_sum_vld[i]),
            .oready         (adder_tree_sum_rdy[i])
        );
    end
endgenerate

//----------------------------------------------bit_serial_accumulation--------------------------------------------------//
wire [BIT_SERIAL_ACC_WIDTH-1:0] bit_serial_acc_temp [0:COL_BLOCK_SIZE-1];
wire [COL_BLOCK_SIZE-1:0] bit_serial_acc_vld_temp;

generate
    for (i = 0; i < COL_BLOCK_SIZE; i = i + 1) begin : bit_serial_accumulation
        bit_serial_acc #(
            .ADDER_TREE_WIDTH       (ADDER_TREE_WIDTH),
            .BIT_SERIAL_ACC_WIDTH   (BIT_SERIAL_ACC_WIDTH),
            .COMPUTE_CYCLE          (COMPUTE_CYCLE),
            .ROUND                  (ROUND)
        )u_bit_serial_acc (
            .clk                    (clk),              
            .rst_n                  (rst_n),          

            .adder_tree_sum         (adder_tree_sum[i]),  
            .adder_tree_sum_vld     (adder_tree_sum_vld[i]),  
            .adder_tree_sum_rdy     (adder_tree_sum_rdy[i]),  

            .bit_serial_acc         (bit_serial_acc_temp[i]),        
            .bit_serial_acc_vld     (bit_serial_acc_vld_temp[i]),
            .bit_serial_acc_rdy     (bit_serial_acc_rdy) 
        );
    end
endgenerate

generate
    for (i = 0; i < COL_BLOCK_SIZE; i = i + 1) begin :accumulation_output
       assign bit_serial_acc[i*BIT_SERIAL_ACC_WIDTH +: BIT_SERIAL_ACC_WIDTH] = bit_serial_acc_temp[i];
    end
endgenerate
assign bit_serial_acc_vld = & bit_serial_acc_vld_temp;

endmodule