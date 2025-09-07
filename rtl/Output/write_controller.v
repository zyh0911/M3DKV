`timescale 1ns/1ps

module write_controller #(
    parameter INPUT_WIDTH = 32,
    parameter INPUT_NUM = 2,
    parameter OUTPUT_NUM = 1024,
    parameter OUTPUT_RAM_WIDTH = OUTPUT_NUM * INPUT_WIDTH,
    parameter OUTPUT_RAM_DEPTH = 2
)(
    input wire clk,
    input wire aresetn,

    // handshake with the ping-pong buffer
    output wire ovalid,
    input wire oready,

    input wire [INPUT_NUM * INPUT_WIDTH - 1 : 0] idata,
    input wire ivalid,
    output wire iready,

    output wire [OUTPUT_RAM_WIDTH - 1 : 0] wdata,
    output wire [$clog2(OUTPUT_RAM_DEPTH) + 1 - 1 : 0] waddr,
    output wire wen
);

    wire [INPUT_NUM * INPUT_WIDTH - 1 : 0] data_fifo_data_in;
    wire [OUTPUT_NUM / INPUT_NUM - 1 : 0] data_fifo_push;
    wire [OUTPUT_NUM / INPUT_NUM - 1 : 0] data_fifo_full;
    wire [OUTPUT_RAM_WIDTH - 1 : 0] data_fifo_data_out;
    wire data_fifo_pull;
    wire [OUTPUT_NUM / INPUT_NUM - 1 : 0] data_fifo_empty;

    reg [$clog2(OUTPUT_RAM_DEPTH) + 1 - 1 : 0] waddr_reg;
    always @(posedge clk or negedge aresetn) begin
        if (~aresetn) begin
            waddr_reg <= 0;
        end
        else if (data_fifo_pull) begin
            if (waddr_reg == OUTPUT_RAM_DEPTH - 1) begin
                waddr_reg <= 0;
            end
            else begin
                waddr_reg <= waddr_reg + 1;
            end
        end
    end

    reg [$clog2(OUTPUT_NUM) - 1 : 0] cnt;
    always @(posedge clk or negedge aresetn) begin
        if (~aresetn) begin
            cnt <= 0;
        end
        else begin
            if (ivalid && iready) begin
                if (cnt + INPUT_NUM >= OUTPUT_NUM) begin
                    cnt <= 0;
                end
                else begin
                    cnt <= cnt + INPUT_NUM;
                end
            end
        end
    end

    reg [$clog2(OUTPUT_NUM / INPUT_NUM) - 1 : 0] fifo_sel;
    always @(posedge clk or negedge aresetn) begin
        if (~aresetn) begin
            fifo_sel <= 0;
        end
        else begin
            if (ivalid && iready) begin
                if (cnt + INPUT_NUM >= OUTPUT_NUM) begin
                    fifo_sel <= 0;
                end
                else begin
                    fifo_sel <= fifo_sel + 1;
                end
            end
        end
    end

    generate
        genvar i;
        for (i = 0; i < OUTPUT_NUM / INPUT_NUM; i = i + 1) begin: FIFO
            sync_fifo #(
                .ADDR_WIDTH(1),
                .DATA_WIDTH(INPUT_WIDTH * INPUT_NUM)
            ) u_data_sync_fifo (
                .aclk(clk),
                .aresetn(aresetn),
                .data_in(data_fifo_data_in),
                .push(data_fifo_push[i]),
                .full(data_fifo_full[i]),
                .data_out(data_fifo_data_out[i * INPUT_WIDTH * INPUT_NUM +: INPUT_WIDTH * INPUT_NUM]),
                .pull(data_fifo_pull),
                .empty(data_fifo_empty[i])
            );

            assign data_fifo_push[i] = ivalid && iready && (fifo_sel == i);
        end
    endgenerate
    

    assign data_fifo_data_in = idata;
    assign data_fifo_pull = oready && ~|data_fifo_empty;


    assign iready = ~&data_fifo_full;
    assign wdata = data_fifo_data_out;
    assign waddr = waddr_reg;
    assign wen = data_fifo_pull;

    assign ovalid = (waddr == (OUTPUT_RAM_DEPTH - 1)) && data_fifo_pull;


endmodule
