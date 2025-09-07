module bit_serial_acc  #(
    parameter ADDER_TREE_WIDTH = 8,        
    parameter BIT_SERIAL_ACC_WIDTH = 16,   
    parameter COMPUTE_CYCLE = 8,
    parameter ROUND = 128          
)(
    input                                       clk,
    input                                       rst_n,

    input  [ADDER_TREE_WIDTH-1:0]               adder_tree_sum,
    input                                       adder_tree_sum_vld,
    output                                      adder_tree_sum_rdy,

    output reg [BIT_SERIAL_ACC_WIDTH-1:0]       bit_serial_acc,
    output reg                                  bit_serial_acc_vld,
    input                                       bit_serial_acc_rdy

);
localparam log2COMPUTE_CYCLE = $clog2(COMPUTE_CYCLE);
localparam log2ROUND = $clog2(ROUND);
wire stall = bit_serial_acc_vld & ~bit_serial_acc_rdy;

reg [log2COMPUTE_CYCLE:0] bit_serial_cnt;
reg [log2ROUND : 0] bit_serial_acc_cnt;
wire bit_serial_cnt_will_update;
wire bit_serial_cnt_clear;
assign bit_serial_cnt_will_update = adder_tree_sum_vld & adder_tree_sum_rdy;
assign bit_serial_cnt_clear = (bit_serial_acc_cnt == ROUND)? 1'b1 : 1'b0;

always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        bit_serial_cnt <= 'd0;
    end
    else begin
        if (stall) begin
            
        end
        else if (bit_serial_cnt_will_update) begin
            bit_serial_cnt <= (bit_serial_cnt == COMPUTE_CYCLE-1) ? 'd0 : bit_serial_cnt + 1;
        end else if (bit_serial_cnt_clear) begin
            bit_serial_cnt <= 0;
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        bit_serial_acc_cnt <= 'd0;
    end
    else begin
        if (stall) begin
            
        end
        else if ((bit_serial_cnt == COMPUTE_CYCLE-1)) begin
            bit_serial_acc_cnt <= (bit_serial_cnt_clear) ? 0 : bit_serial_acc_cnt + 1;
        end else begin
            bit_serial_acc_cnt <= bit_serial_acc_cnt;
        end
    end
end

wire [BIT_SERIAL_ACC_WIDTH-1:0] adder_tree_sum_ext,temp_adder_tree_sum_ext;
assign adder_tree_sum_ext = {{(COMPUTE_CYCLE+1){adder_tree_sum[ADDER_TREE_WIDTH-1]}}, adder_tree_sum};
assign temp_adder_tree_sum_ext = $unsigned(-$signed(adder_tree_sum_ext));

always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        bit_serial_acc <= 'd0;
    end
    else if (stall) begin
        
    end else begin
        if (bit_serial_cnt_will_update) begin
            if (bit_serial_cnt == COMPUTE_CYCLE-1) begin
                bit_serial_acc <= bit_serial_acc + ($unsigned(-$signed(adder_tree_sum_ext)) << (COMPUTE_CYCLE-1));
            end
            else if (bit_serial_cnt == 0) begin
                bit_serial_acc <= adder_tree_sum_ext;
            end
            else begin
                bit_serial_acc <= bit_serial_acc + (adder_tree_sum_ext << bit_serial_cnt);
            end
        end
    end
end


always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        bit_serial_acc_vld <= 'd0;
    end
    else if (stall) begin
        
    end else begin
        if (bit_serial_cnt_will_update) begin
            bit_serial_acc_vld <= (bit_serial_cnt == COMPUTE_CYCLE-1) ? 1'b1 : 1'b0;
        end else if (bit_serial_acc_rdy & bit_serial_acc_vld) begin
            bit_serial_acc_vld <= 1'b0;
        end 
    end
end
assign adder_tree_sum_rdy =  ~stall;
    
endmodule