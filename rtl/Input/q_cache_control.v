module q_cache_control #(
    parameter MACRO_ROW = 4,
    parameter Q_BUF_ADDR_WIDTH = 2,
    parameter MACRO_DATA_WIDTH = 16,
    parameter EXP_WIDTH = 8,
	parameter MANTISSA_WIDTH = 7,
	parameter SIGN_WIDTH = 1,
	parameter FP_WIDTH = 16,
    parameter COL_BLOCK_SIZE = 32,
    parameter log2_COL_BLOCK_SIZE = $clog2(COL_BLOCK_SIZE)
)(
    input                                                                       clk, 
    input                                                                       rst_n, 

    input [EXP_WIDTH -1:0]                                                      exp_max,
    input [MACRO_DATA_WIDTH * (SIGN_WIDTH + MANTISSA_WIDTH + 1) - 1: 0]         mantissa_plus_aligned,
    input                                                                       mantissa_plus_aligned_vld,
    output reg                                                                  mantissa_plus_aligned_rdy,

    output reg [EXP_WIDTH -1:0]                                                 exp_max_out,
    output reg [MACRO_DATA_WIDTH * (SIGN_WIDTH + MANTISSA_WIDTH + 1) - 1: 0]    mantissa_plus_aligned_out,
    output reg                                                                  q_buf_wr_en,
    output reg[Q_BUF_ADDR_WIDTH-1:0]                                            q_buf_wr_addr,
    output reg                                                                  q_buf_rd_en,
    output reg[Q_BUF_ADDR_WIDTH-1:0]                                            q_buf_rd_addr,
    input                                                                       q_buf_rd_addr_rdy
);
reg [1:0] state, next_state;
reg [log2_COL_BLOCK_SIZE:0] col_block_cnt;
wire col_block_cnt_is_max = (col_block_cnt == MACRO_ROW - 1);
wire col_block_cnt_will_update_now = (q_buf_rd_addr == 2**Q_BUF_ADDR_WIDTH - 1) & q_buf_rd_en & q_buf_rd_addr_rdy;

always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        state <= 2'b00;
    end else begin
        state <= next_state;
    end
end

always @(*) begin
    case (state)
        2'b00: begin
            if (mantissa_plus_aligned_vld) begin
                next_state = 2'b01;
            end else begin
                next_state = 2'b00;
            end
        end
        2'b01: begin
            if (q_buf_wr_addr == 2**Q_BUF_ADDR_WIDTH - 1) begin
                next_state = 2'b10;
            end else begin
                next_state = 2'b01;
            end
        end
        2'b10: begin
            if (col_block_cnt_is_max & col_block_cnt_will_update_now) begin
                next_state = 2'b00;
            end else begin
                next_state = 2'b10;
            end
        end
        default: next_state = 2'b00;
    endcase
end

always @(*) begin
    mantissa_plus_aligned_rdy = 1'b0;
    q_buf_wr_en = 1'b0;
    q_buf_rd_en = 1'b0;
    case (state)
        2'b00: begin
            mantissa_plus_aligned_rdy = 1'b1;
        end
        2'b01:begin
            mantissa_plus_aligned_rdy = 1'b1;
            q_buf_wr_en = 1'b1;
        end 
        2'b10:begin
            q_buf_rd_en = 1'b1;
        end
        default: begin
            mantissa_plus_aligned_rdy = 1'b0;
            q_buf_wr_en = 1'b0;
            q_buf_rd_en = 1'b0;
        end
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        q_buf_wr_addr <= 'd0;
        q_buf_rd_addr <= 'd0;
    end else begin
        if ((state == 2'b01) & mantissa_plus_aligned_vld) begin
            q_buf_wr_addr <= (q_buf_wr_addr == 2**Q_BUF_ADDR_WIDTH - 1) ? 'd0 : q_buf_wr_addr + 1;
        end else begin
            q_buf_wr_addr <= q_buf_wr_addr;
        end
        if (q_buf_rd_en & q_buf_rd_addr_rdy) begin
            q_buf_rd_addr <= (q_buf_rd_addr == 2**Q_BUF_ADDR_WIDTH - 1) ? 'd0 : q_buf_rd_addr + 1;
        end else begin
            q_buf_rd_addr <= q_buf_rd_addr;
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        col_block_cnt <= 'd0;
    end else begin
        if (col_block_cnt_will_update_now) begin
            col_block_cnt <= (col_block_cnt == MACRO_ROW - 1) ? 'd0 : col_block_cnt + 1;
        end
        else begin
            col_block_cnt <= col_block_cnt;
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        mantissa_plus_aligned_out <= 'd0;
        exp_max_out <= 'd0;
    end else begin
        mantissa_plus_aligned_out <= mantissa_plus_aligned;
        exp_max_out <= exp_max;
    end
end

endmodule