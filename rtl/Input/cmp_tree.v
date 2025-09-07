`timescale 1ns/1ps

module cmp_tree #(
    parameter INPUT_WIDTH = 32,
    parameter INPUT_NUM = 1024
)(
    input wire [INPUT_NUM * INPUT_WIDTH - 1 : 0] idata,
    output wire [INPUT_WIDTH - 1 : 0] max
);
    wire [INPUT_NUM * INPUT_WIDTH - 1 : 0] data_wire [0 : $clog2(INPUT_NUM)];

    generate
        genvar i, j;
        for (i = 0; i <= $clog2(INPUT_NUM); i = i + 1) begin
            for (j = 0; j < INPUT_NUM / 2**i; j = j + 1) begin
                if (i == 0) begin
                    assign data_wire[0][j * INPUT_WIDTH +: INPUT_WIDTH] = idata[j * INPUT_WIDTH +: INPUT_WIDTH]; //layer 0
                end
                else begin
                    assign data_wire[i][j * INPUT_WIDTH +: INPUT_WIDTH] = data_wire[i - 1][j * 2 * INPUT_WIDTH +: INPUT_WIDTH] > data_wire[i - 1][(j * 2 + 1) * INPUT_WIDTH +: INPUT_WIDTH] ? data_wire[i - 1][j * 2 * INPUT_WIDTH +: INPUT_WIDTH] : data_wire[i - 1][(j * 2 + 1) * INPUT_WIDTH +: INPUT_WIDTH];
                end
            end
        end
    endgenerate

    assign max = data_wire[$clog2(INPUT_NUM)];

endmodule
