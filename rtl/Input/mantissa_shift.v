
module mantissa_shift #(
    parameter MACRO_DATA_WIDTH = 128,
    parameter SIGN_WIDTH = 1,
    parameter MANTISSA_WIDTH = 3,
    parameter EXP_WIDTH = 4
)(
    input                                                                 clk, 
    input                                                                 rst_n, 

    input  [MACRO_DATA_WIDTH * (SIGN_WIDTH + MANTISSA_WIDTH) - 1: 0]      mantissa,
    input                                                                 mantissa_vld,
    output                                                                mantissa_rdy,

    input  [EXP_WIDTH * MACRO_DATA_WIDTH - 1: 0]                          shift,
    input                                                                 shift_vld,
    output                                                                shift_rdy,

    output reg [MACRO_DATA_WIDTH * (SIGN_WIDTH + MANTISSA_WIDTH + 1) - 1: 0]  mantissa_plus_aligned,
    output reg                                                            mantissa_plus_aligned_vld,
    input                                                                 mantissa_plus_aligned_rdy
);

wire stall = mantissa_plus_aligned_vld & ~mantissa_plus_aligned_rdy;
genvar i;
generate
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mantissa_plus_aligned_vld <= 0;
        end else if (stall) begin
            // act_stall
        end else begin
            mantissa_plus_aligned_vld <= mantissa_vld & shift_vld;
        end
    end
    for (i = 0; i < MACRO_DATA_WIDTH; i = i + 1) begin 
        wire [MANTISSA_WIDTH - 1 : 0] mantissa_split = mantissa[i*(SIGN_WIDTH + MANTISSA_WIDTH) +: MANTISSA_WIDTH];
        wire sign_split = mantissa[i*(SIGN_WIDTH + MANTISSA_WIDTH) + MANTISSA_WIDTH +: SIGN_WIDTH];
        wire signed [MANTISSA_WIDTH + 2 - 1 : 0]mantissa_plus = sign_split ?
                                        ~ {{SIGN_WIDTH{1'b0}}, 1'b1, mantissa_split} + 1'b1 : 
                                        {{SIGN_WIDTH{1'b0}}, 1'b1, mantissa_split};
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                mantissa_plus_aligned[i*(SIGN_WIDTH + MANTISSA_WIDTH + 1) +: (SIGN_WIDTH + MANTISSA_WIDTH + 1)] <= 0;
            end else if (stall) begin
                // act_stall
            end else begin
                mantissa_plus_aligned[i*(SIGN_WIDTH + MANTISSA_WIDTH + 1) +: (SIGN_WIDTH + MANTISSA_WIDTH + 1)] <= mantissa_plus >>> shift[i*EXP_WIDTH +:EXP_WIDTH]; 
            end
        end
    end
endgenerate

assign shift_rdy = ~stall;
assign mantissa_rdy = ~stall;
    
endmodule