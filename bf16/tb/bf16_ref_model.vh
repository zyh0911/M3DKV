// ===========================================================================
//  bf16_ref_model.vh -- shared reference model for the BF16 testbenches.
//
//  Written in a deliberately different style from the RTL: the smaller
//  operand is aligned into a 64-bit field with 48 guard bits and an explicit
//  sticky, so a shared trick in the 12-bit datapath cannot hide a bug.
//
//  `include "bf16_ref_model.vh"   inside the testbench module.
// ===========================================================================

    function [15:0] ref_add;
        input [15:0] ain;
        input [15:0] bin;
        input        subin;

        reg         s_a, s_b;
        reg  [7:0]  e_a, e_b;
        reg  [6:0]  f_a, f_b;
        reg  [7:0]  sg_a, sg_b;
        reg  [8:0]  E_a, E_b;
        reg         nan_a, nan_b, inf_a, inf_b;
        reg         s_l, s_s;
        reg  [7:0]  sg_l, sg_s;
        reg  [8:0]  E_hi, E_lo;
        reg  [63:0] W_l, W_s, W_s_full, S64;
        reg         st, gbit, restbit;
        reg  [8:0]  m9;
        integer     d, p, k, sh;
        integer     Er;
        begin
            s_a = ain[15];  e_a = ain[14:7];  f_a = ain[6:0];
            s_b = bin[15] ^ subin;
            e_b = bin[14:7]; f_b = bin[6:0];

            nan_a = (e_a == 8'hFF) && (f_a != 0);
            nan_b = (e_b == 8'hFF) && (f_b != 0);
            inf_a = (e_a == 8'hFF) && (f_a == 0);
            inf_b = (e_b == 8'hFF) && (f_b == 0);

            if (nan_a || nan_b || (inf_a && inf_b && (s_a != s_b))) begin
                ref_add = 16'h7FC0;
            end else if (inf_a || inf_b) begin
                ref_add = {inf_a ? s_a : s_b, 8'hFF, 7'h00};
            end else begin
                sg_a = {(e_a != 0), f_a};
                sg_b = {(e_b != 0), f_b};
                E_a  = (e_a != 0) ? {1'b0, e_a} : 9'd1;
                E_b  = (e_b != 0) ? {1'b0, e_b} : 9'd1;

                if (bin[14:0] > ain[14:0]) begin
                    s_l = s_b; sg_l = sg_b; E_hi = E_b;
                    s_s = s_a; sg_s = sg_a; E_lo = E_a;
                end else begin
                    s_l = s_a; sg_l = sg_a; E_hi = E_a;
                    s_s = s_b; sg_s = sg_b; E_lo = E_b;
                end

                d        = E_hi - E_lo;
                W_l      = {56'd0, sg_l} << 48;
                W_s_full = {56'd0, sg_s} << 48;
                if (d > 48) begin
                    W_s = 64'd0;
                    st  = (sg_s != 0);
                end else begin
                    W_s = W_s_full >> d;
                    st  = ((W_s << d) != W_s_full);
                end

                if (s_l == s_s) S64 = W_l + W_s;
                else            S64 = W_l - W_s - (st ? 64'd1 : 64'd0);

                if (S64 == 0) begin
                    // exact cancellation (or 0 +/- 0): +0 unless both are -0
                    ref_add = {(s_l == s_s) ? s_l : 1'b0, 15'h0000};
                end else begin
                    p = 0;
                    for (k = 0; k < 64; k = k + 1)
                        if (S64[k]) p = k;

                    Er = E_hi + p - 55;
                    sh = p - 7;
                    if (Er < 1) begin
                        sh = sh + (1 - Er);
                        Er = 1;
                    end

                    if (sh < 1 || sh > 62) begin
                        $display("REFERENCE MODEL BROKEN: sh=%0d p=%0d", sh, p);
                        $finish;
                    end

                    m9      = (S64 >> sh) & 64'hFF;
                    gbit    = (S64 >> (sh - 1)) & 64'd1;
                    restbit = ((S64 & ((64'd1 << (sh - 1)) - 64'd1)) != 0) || st;

                    if (gbit && (restbit || m9[0])) begin
                        m9 = m9 + 9'd1;
                        if (m9[8]) begin
                            m9 = 9'h080;
                            Er = Er + 1;
                        end
                    end

                    if (Er >= 255)
                        ref_add = {s_l, 8'hFF, 7'h00};          // overflow -> Inf
                    else if (m9[7] == 1'b0)
                        ref_add = {s_l, 8'h00, m9[6:0]};        // subnormal
                    else
                        ref_add = {s_l, Er[7:0], m9[6:0]};
                end
            end
        end
    endfunction

    function is_nan;
        input [15:0] v;
        begin
            is_nan = (v[14:7] == 8'hFF) && (v[6:0] != 0);
        end
    endfunction
