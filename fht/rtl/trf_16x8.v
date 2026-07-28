// ============================================================================
//  trf_16x8.v -- Transposable Register File (TRF), 8 rows x 16 columns
//
//  Reproduction of the TRF in Fig. 11(b) of LightRot (Kim et al., JETCAS 2025).
//
//  Holds one full 128-element rotation group.  Element index mapping:
//
//        idx = row*16 + col       row in [0,8), col in [0,16)
//
//        col ->   0    1    2   ...  15
//   row 0     [  X0   X1   X2  ...  X15  ]
//   row 1     [ X16  X17  X18  ...  X31  ]
//    ...
//   row 7     [X112 X113 X114  ... X127  ]
//
//  Two access modes, exactly as the paper describes:
//
//    * Row-by-row access  (stride 1)  : 16 consecutive elements -> 1st step
//    * Col-by-col access  (stride 16) :  8 elements             -> 2nd step
//
//  Both ports do asynchronous (combinational) read and synchronous write, so
//  a read - transform - write-back can complete in a single cycle.
//  Simultaneous row_we and col_we never happens (FSM guarantees it); should it
//  occur, the row port wins.
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module trf_16x8 #(
    parameter integer W = 23
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // ---- row port : 16 elements, stride 1 -------------------------------
    input  wire [2:0]           row_addr,
    output wire [16*W-1:0]      row_rdata,
    input  wire                 row_we,
    input  wire [16*W-1:0]      row_wdata,

    // ---- col port : 8 elements, stride 16 -------------------------------
    input  wire [3:0]           col_addr,
    output wire [8*W-1:0]       col_rdata,
    input  wire                 col_we,
    input  wire [8*W-1:0]       col_wdata
);

    reg  [W-1:0] mem [0:127];

    wire [6:0] row_base = {row_addr, 4'b0000};   // row_addr * 16
    wire [6:0] col_base = {3'b000, col_addr};    // col_addr

    integer k;
    genvar  g;

    // ---- combinational reads --------------------------------------------
    generate
        // row-by-row : stride 1
        for (g = 0; g < 16; g = g + 1) begin : g_row_rd
            assign row_rdata[g*W +: W] = mem[row_base + g];
        end
        // col-by-col : stride 16
        for (g = 0; g < 8; g = g + 1) begin : g_col_rd
            assign col_rdata[g*W +: W] = mem[col_base + g*16];
        end
    endgenerate

    // ---- synchronous writes ---------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k = 0; k < 128; k = k + 1)
                mem[k] <= {W{1'b0}};
        end else if (row_we) begin
            for (k = 0; k < 16; k = k + 1)
                mem[row_addr*16 + k] <= row_wdata[k*W +: W];
        end else if (col_we) begin
            for (k = 0; k < 8; k = k + 1)
                mem[k*16 + col_addr] <= col_wdata[k*W +: W];
        end
    end

endmodule

`default_nettype wire
