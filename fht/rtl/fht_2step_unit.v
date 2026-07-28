// ============================================================================
//  fht_2step_unit.v -- 2-step hierarchical FHT Rotation Unit (128-way group)
//
//  Reproduction of Fig. 11(a)/(b) of
//    J. Kim et al., "LightRot: A Light-Weighted Rotation Scheme and
//    Architecture for Accurate Low-Bit LLM Inference," IEEE JETCAS 15(2), 2025.
//
//  ---------------------------------------------------------------------------
//  Algorithm
//  ---------------------------------------------------------------------------
//  A 128-point Walsh-Hadamard rotation is factorised as
//
//        H_128 = H_8 (x) H_16          ( (x) = Kronecker product )
//
//  so with the element index written as  idx = r*16 + c :
//
//        1st step : for each of the 8 rows r, y[r,:] = H_16 * x[r,:]   (x8)
//        2nd step : for each of the 16 cols c, z[:,c] = H_8  * y[:,c]  (x16)
//
//  which is exactly the "x8 / x16" annotation on the right-hand side of
//  Fig. 11(a).  A single 8/16-way FHT core is time-multiplexed over both
//  steps (in the 2nd step half the core is gated -> 24 active adders), and a
//  16x8 Transposable Register File supplies the two different access strides
//  (stride 1 for step 1, stride 16 for step 2).
//
//  Adder cost:   64 (16-way network)  vs. 896 for a flat 128-way FHT.
//
//  ---------------------------------------------------------------------------
//  Schedule (40 cycles per 128-element rotation task)
//  ---------------------------------------------------------------------------
//     LOAD   :  8 cycles  -- 16 IA/cycle from FP-MEM (via Gathering Unit)
//     STEP1  :  8 cycles  -- row r : TRF row read -> 16-way FHT -> row write
//     STEP2  : 16 cycles  -- col c : TRF col read ->  8-way FHT -> col write
//     OUT    :  8 cycles  -- 16 rotated values/cycle to the Quantization Unit
//
//  ---------------------------------------------------------------------------
//  Numerics
//  ---------------------------------------------------------------------------
//  Inputs are DW-bit signed fixed point.  The internal / output word width is
//  W = DW + 7, i.e. full bit growth of log2(128) = 7 bits, so the transform is
//  bit-exact and can never overflow.  The 1/sqrt(128) normalisation is NOT
//  applied here -- as in the paper it is folded into the scale factor of the
//  downstream Quantization Unit.
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module fht_2step_unit #(
    parameter integer DW = 16,          // input word width  (signed)
    parameter integer W  = DW + 7       // internal/output width (full growth)
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // ---- control ---------------------------------------------------------
    input  wire                 start,      // pulse: begin a rotation task
    output wire                 busy,
    output reg                  done,       // 1-cycle pulse at end of task

    // ---- input stream : 16 activations per beat, 8 beats -----------------
    output wire                 din_ready,
    input  wire                 din_valid,
    input  wire [16*DW-1:0]     din,

    // ---- output stream : 16 rotated values per beat, 8 beats --------------
    output reg                  dout_valid,
    output wire [16*W-1:0]      dout
);

    localparam [2:0] S_IDLE  = 3'd0,
                     S_LOAD  = 3'd1,
                     S_STEP1 = 3'd2,
                     S_STEP2 = 3'd3,
                     S_OUT   = 3'd4;

    reg  [2:0] state, nstate;
    reg  [4:0] cnt;                     // 0..15

    // ------------------------------------------------------------------
    // TRF
    // ------------------------------------------------------------------
    wire [2:0]        row_addr;
    wire [16*W-1:0]   row_rdata;
    reg               row_we;
    reg  [16*W-1:0]   row_wdata;

    wire [3:0]        col_addr;
    wire [8*W-1:0]    col_rdata;
    reg               col_we;
    wire [8*W-1:0]    col_wdata;

    assign row_addr = cnt[2:0];
    assign col_addr = cnt[3:0];

    trf_16x8 #(.W(W)) u_trf (
        .clk       (clk),
        .rst_n     (rst_n),
        .row_addr  (row_addr),
        .row_rdata (row_rdata),
        .row_we    (row_we),
        .row_wdata (row_wdata),
        .col_addr  (col_addr),
        .col_rdata (col_rdata),
        .col_we    (col_we),
        .col_wdata (col_wdata)
    );

    // ------------------------------------------------------------------
    // 8/16-way FHT core (time-multiplexed between the two steps)
    // ------------------------------------------------------------------
    wire              mode16 = (state == S_STEP1);
    reg  [16*W-1:0]   fht_din;
    wire [16*W-1:0]   fht_dout;

    fht_core #(.W(W)) u_fht (
        .mode16 (mode16),
        .din    (fht_din),
        .dout   (fht_dout)
    );

    // step 1 : whole TRF row (stride 1) -> all 16 lanes
    // step 2 : TRF column (stride 16)   -> lanes 0..7, upper half tied low
    //          (fht_core additionally isolates them internally)
    always @* begin
        if (state == S_STEP1)
            fht_din = row_rdata;
        else
            fht_din = { {(8*W){1'b0}}, col_rdata };
    end

    assign col_wdata = fht_dout[8*W-1:0];

    // ------------------------------------------------------------------
    // Input sign-extension: DW -> W
    // ------------------------------------------------------------------
    wire [16*W-1:0] din_ext;
    genvar g;
    generate
        for (g = 0; g < 16; g = g + 1) begin : g_sext
            assign din_ext[g*W +: W] =
                { {(W-DW){din[g*DW + DW - 1]}}, din[g*DW +: DW] };
        end
    endgenerate

    // ------------------------------------------------------------------
    // TRF write muxing
    // ------------------------------------------------------------------
    always @* begin
        row_we    = 1'b0;
        col_we    = 1'b0;
        row_wdata = din_ext;
        case (state)
            S_LOAD : begin
                row_we    = din_valid;
                row_wdata = din_ext;
            end
            S_STEP1: begin
                row_we    = 1'b1;
                row_wdata = fht_dout;
            end
            S_STEP2: begin
                col_we    = 1'b1;
            end
            default: ;
        endcase
    end

    assign din_ready = (state == S_LOAD);
    assign dout      = row_rdata;
    assign busy      = (state != S_IDLE);

    // ------------------------------------------------------------------
    // FSM
    // ------------------------------------------------------------------
    wire load_beat = (state == S_LOAD) && din_valid;

    always @* begin
        nstate = state;
        case (state)
            S_IDLE : if (start)                   nstate = S_LOAD;
            S_LOAD : if (load_beat && cnt == 5'd7) nstate = S_STEP1;
            S_STEP1: if (cnt == 5'd7)              nstate = S_STEP2;
            S_STEP2: if (cnt == 5'd15)             nstate = S_OUT;
            S_OUT  : if (cnt == 5'd7)              nstate = S_IDLE;
            default:                               nstate = S_IDLE;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            cnt        <= 5'd0;
            done       <= 1'b0;
            dout_valid <= 1'b0;
        end else begin
            state <= nstate;
            done  <= (state == S_OUT) && (cnt == 5'd7);

            // counter: advances every cycle except in LOAD, where it waits
            // for din_valid; it restarts at 0 on every state change.
            if (nstate != state)
                cnt <= 5'd0;
            else if (state == S_IDLE)
                cnt <= 5'd0;
            else if (state == S_LOAD)
                cnt <= cnt + {4'd0, din_valid};
            else
                cnt <= cnt + 5'd1;

            // dout is a combinational read of TRF row `cnt`, so it is valid
            // during the whole S_OUT state.
            dout_valid <= (nstate == S_OUT);
        end
    end

endmodule

`default_nettype wire
