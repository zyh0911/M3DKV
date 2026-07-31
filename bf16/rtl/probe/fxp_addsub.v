// Fixed-point add/subtract units, for an apples-to-apples area comparison
// against bf16_add under identical synthesis conditions.
// Same interface shape: two operands, one sub select, one result.
`timescale 1ns/1ps

//  16-bit signed, same word width as BF16 (wrapping, no saturation)
module fxp_addsub16 (
    input  wire signed [15:0] a,
    input  wire signed [15:0] b,
    input  wire               sub,
    output wire signed [15:0] y
);
    assign y = sub ? (a - b) : (a + b);
endmodule

//  16-bit signed with saturation -- what a real accelerator datapath needs
module fxp_addsub16_sat (
    input  wire signed [15:0] a,
    input  wire signed [15:0] b,
    input  wire               sub,
    output wire signed [15:0] y
);
    wire signed [16:0] ext = sub ? ({a[15], a} - {b[15], b})
                                 : ({a[15], a} + {b[15], b});
    assign y = (ext >  17'sd32767) ? 16'sh7FFF :
               (ext < -17'sd32768) ? 16'sh8000 : ext[15:0];
endmodule

//  23-bit signed, the width the FHT butterfly network actually carries
module fxp_addsub23 (
    input  wire signed [22:0] a,
    input  wire signed [22:0] b,
    input  wire               sub,
    output wire signed [22:0] y
);
    assign y = sub ? (a - b) : (a + b);
endmodule
