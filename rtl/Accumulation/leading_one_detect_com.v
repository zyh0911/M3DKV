module leading_one_detect_com #(
    parameter INPUT_WIDTH = 1,
    parameter OUTPUT_WIDTH = $clog2(INPUT_WIDTH) + 1
) (
    input wire [INPUT_WIDTH - 1 : 0] idata,
    output reg [OUTPUT_WIDTH - 1 : 0] odata
);

integer i;
always @(*) begin
    odata = 'd0;
    for (i = INPUT_WIDTH - 1; i >= 0; i = i - 1) begin: LEADING_ONE_DETECT
        if (idata[i] == 1'b1) begin
            odata = INPUT_WIDTH - 1 - i + 1'b1;
            break;
        end
    end
end
    
endmodule