// Probe B: back half of bf16_add -- normalise, round, pack.
// Code copied verbatim from rtl/bf16_add.v (the special-case mux is left out;
// it is 2-3 gate levels on a path that is not critical).
`timescale 1ns/1ps
module bf16_probe_b (
    input  wire [11:0] sum,
    input  wire        sticky,
    input  wire [8:0]  E_l,
    input  wire        s_l,
    input  wire        s_s,
    output wire [15:0] y,
    output wire        of,
    output wire        uf,
    output wire        nx
);
    wire carry = sum[11];

    reg [3:0] lz;
    always @* begin
        casez (sum[10:0])
            11'b1??????????: lz = 4'd0;
            11'b01?????????: lz = 4'd1;
            11'b001????????: lz = 4'd2;
            11'b0001???????: lz = 4'd3;
            11'b00001??????: lz = 4'd4;
            11'b000001?????: lz = 4'd5;
            11'b0000001????: lz = 4'd6;
            11'b00000001???: lz = 4'd7;
            11'b000000001??: lz = 4'd8;
            11'b0000000001?: lz = 4'd9;
            11'b00000000001: lz = 4'd10;
            default:         lz = 4'd11;
        endcase
    end

    wire [8:0] E_lm1 = E_l - 9'd1;
    wire [3:0] shl   = ({5'd0, lz} > E_lm1) ? E_lm1[3:0] : lz;

    wire [10:0] m_pre = carry ? sum[11:1] : (sum[10:0] << shl);
    wire        st_ex = carry ? (sum[0] | sticky) : sticky;
    wire [8:0]  E_pre = carry ? (E_l + 9'd1) : (E_l - {5'd0, shl});

    wire [7:0] mant = m_pre[10:3];
    wire       g    = m_pre[2];
    wire       r    = m_pre[1];
    wire       s    = m_pre[0] | st_ex;

    wire       round_up = g & (r | s | mant[0]);
    wire [8:0] mant_r   = {1'b0, mant} + {8'd0, round_up};
    wire       mant_ovf = mant_r[8];

    wire [7:0] mant_f = mant_ovf ? 8'h80 : mant_r[7:0];
    wire [8:0] E_f    = E_pre + {8'd0, mant_ovf};

    wire        exp_ovf    = (E_f >= 9'd255);
    wire        subnorm    = ~mant_f[7];
    wire [7:0]  e_out      = subnorm ? 8'd0 : E_f[7:0];
    wire [15:0] res_normal = exp_ovf ? {s_l, 8'hFF, 7'd0}
                                     : {s_l, e_out, mant_f[6:0]};
    wire        zero_res = ~|sum;
    wire [15:0] res_zero = {(s_l == s_s) ? s_l : 1'b0, 15'd0};

    assign y  = zero_res ? res_zero : res_normal;
    assign nx = ~zero_res & ((g | r | s) | exp_ovf);
    assign of = ~zero_res & exp_ovf;
    assign uf = ~zero_res & ~exp_ovf & subnorm & (g | r | s);
endmodule
