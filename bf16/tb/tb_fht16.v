// ===========================================================================
//  tb_fht16.v -- self-checking testbench for the 16-point FHT variants.
//
//  Phase 1 (exact):  inputs are small integers, chosen so that BOTH datapaths
//                    are exact -- no BF16 rounding, no BFP truncation.  Every
//                    design must then equal the exact integer Hadamard
//                    transform.  This is what verifies the butterfly wiring.
//  Phase 2 (error):  sweeps the in-block exponent spread and reports error
//                    against a real-arithmetic reference, for the float tree
//                    and for each BFP width on identical stimulus.  Two
//                    distributions: uniform spread, and the adversarial
//                    "one outlier + 15 small" case.
//
//  Also checks FUSED=1 against FUSED=0 bit-for-bit throughout.
// ===========================================================================
`timescale 1ns/1ps

module tb_fht16;

    localparam integer W16 = 16, G16 = 4, D16 = W16 - 9 - G16;  // D = 3
    localparam integer W23 = 23, G23 = 4, D23 = W23 - 9 - G23;  // D = 10

    reg  [255:0] din;

    wire [255:0] y_fused, y_2x, y_pack;
    wire [255:0] dummy_bf16, dummy_bf23;
    wire [7:0]   e16, e23, e16p;
    wire [16*W16-1:0] fx16, fx16p;
    wire [16*W23-1:0] fx23;

    fht16_bf16 #(.FUSED(1)) u_fused (.din(din), .dout(y_fused));
    fht16_bf16 #(.FUSED(0)) u_2x    (.din(din), .dout(y_2x));

    fht16_bfp #(.W(W16), .G(G16), .PACK(0)) u_bfp16
        (.din(din), .e_shared(e16),  .dout_fx(fx16),  .dout_bf(dummy_bf16));
    fht16_bfp #(.W(W23), .G(G23), .PACK(0)) u_bfp23
        (.din(din), .e_shared(e23),  .dout_fx(fx23),  .dout_bf(dummy_bf23));
    fht16_bfp #(.W(W16), .G(G16), .PACK(1)) u_bfp16p
        (.din(din), .e_shared(e16p), .dout_fx(fx16p), .dout_bf(y_pack));

    integer errors, checks;
    integer t, i, sp, mode;

    // ------------------------------------------------------------------
    //  helpers
    // ------------------------------------------------------------------
    function real bf16r;
        input [15:0] x;
        real    m;
        integer e;
        begin
            if (x[14:7] == 8'd0) begin
                m = x[6:0];
                e = 1 - 134;
            end else begin
                m = {1'b1, x[6:0]};
                e = x[14:7] - 134;
            end
            bf16r = m * (2.0 ** e);
            if (x[15]) bf16r = -bf16r;
        end
    endfunction

    function [15:0] int2bf16;
        input integer v;
        integer a, e, m;
        reg [7:0] ef, mf;
        begin
            a = (v < 0) ? -v : v;
            if (a == 0) int2bf16 = 16'h0000;
            else begin
                e = 0;
                m = a;
                while (m < 128) begin m = m * 2; e = e - 1; end
                while (m > 255) begin m = m / 2; e = e + 1; end
                ef = 134 + e;
                mf = m;
                int2bf16 = {(v < 0), ef, mf[6:0]};
            end
        end
    endfunction

    function signed [31:0] sx16;
        input [W16-1:0] v;
        begin sx16 = $signed({{(32-W16){v[W16-1]}}, v}); end
    endfunction

    function signed [31:0] sx23;
        input [W23-1:0] v;
        begin sx23 = $signed({{(32-W23){v[W23-1]}}, v}); end
    endfunction

    // block-maximum exponent, recomputed independently from din
    function integer emax_of_din;
        input dummy;
        integer ii, ee, mx;
        begin
            mx = 0;
            for (ii = 0; ii < 16; ii = ii + 1) begin
                ee = din[16*ii + 7 +: 8];
                if (ee == 0) ee = 1;
                if (ee > mx) mx = ee;
            end
            emax_of_din = mx;
        end
    endfunction

    // ------------------------------------------------------------------
    //  references
    // ------------------------------------------------------------------
    integer ref_i [0:15];
    real    ref_r [0:15];

    task fht_int;
        integer ss, ii;
        integer a [0:15];
        begin
            for (ss = 0; ss < 4; ss = ss + 1) begin
                for (ii = 0; ii < 16; ii = ii + 1) a[ii] = ref_i[ii];
                for (ii = 0; ii < 16; ii = ii + 1) begin
                    if (((ii >> ss) & 1) == 0) ref_i[ii] = a[ii] + a[ii | (1<<ss)];
                    else                       ref_i[ii] = a[ii & ~(1<<ss)] - a[ii];
                end
            end
        end
    endtask

    task fht_real;
        integer ss, ii;
        real a [0:15];
        begin
            for (ss = 0; ss < 4; ss = ss + 1) begin
                for (ii = 0; ii < 16; ii = ii + 1) a[ii] = ref_r[ii];
                for (ii = 0; ii < 16; ii = ii + 1) begin
                    if (((ii >> ss) & 1) == 0) ref_r[ii] = a[ii] + a[ii | (1<<ss)];
                    else                       ref_r[ii] = a[ii & ~(1<<ss)] - a[ii];
                end
            end
        end
    endtask

    integer emax, eint, expect_i, got_i;
    real    scale16, scale23, refmax, rr;
    real    e_f, e_b16, e_b23, e_pk;
    real    wf, w16v, w23v, wpk;                 // worst
    real    sf, s16v, s23v, spk;                 // sum of squares
    integer nacc;
    integer vals [0:15];

    initial begin
        errors  = 0;
        checks  = 0;

        // ==============================================================
        //  Phase 1 -- both datapaths must be EXACT
        // ==============================================================
        for (t = 0; t < 4000; t = t + 1) begin
            for (i = 0; i < 16; i = i + 1) begin
                vals[i] = ($random % 31);
                if (vals[i] >  15) vals[i] =  15;
                if (vals[i] < -15) vals[i] = -15;
                ref_i[i] = vals[i];
                din[16*i +: 16] = int2bf16(vals[i]);
            end
            fht_int;
            #1;
            emax = emax_of_din(0);

            for (i = 0; i < 16; i = i + 1) begin
                checks = checks + 1;

                if (y_fused[16*i +: 16] !== int2bf16(ref_i[i])) begin
                    errors = errors + 1;
                    if (errors < 10) $display("P1 fused[%0d]: %h want %h (%0d)",
                        i, y_fused[16*i +: 16], int2bf16(ref_i[i]), ref_i[i]);
                end
                if (y_fused[16*i +: 16] !== y_2x[16*i +: 16]) begin
                    errors = errors + 1;
                    if (errors < 10) $display("P1 fused != 2x at [%0d]", i);
                end
                if (y_pack[16*i +: 16] !== int2bf16(ref_i[i])) begin
                    errors = errors + 1;
                    if (errors < 10) $display("P1 pack[%0d]: %h want %h (%0d)",
                        i, y_pack[16*i +: 16], int2bf16(ref_i[i]), ref_i[i]);
                end

                // fx = FHT(value) * 2^(134 + D - emax)
                expect_i = ref_i[i] * (1 << (134 + D16 - emax));
                got_i    = sx16(fx16[W16*i +: W16]);
                if (got_i !== expect_i) begin
                    errors = errors + 1;
                    if (errors < 10) $display("P1 bfp16[%0d]: %0d want %0d",
                        i, got_i, expect_i);
                end
                expect_i = ref_i[i] * (1 << (134 + D23 - emax));
                got_i    = sx23(fx23[W23*i +: W23]);
                if (got_i !== expect_i) begin
                    errors = errors + 1;
                    if (errors < 10) $display("P1 bfp23[%0d]: %0d want %0d",
                        i, got_i, expect_i);
                end
            end
        end
        $display(" phase 1 (exact integer FHT) : %0d checks, %0d errors",
                 checks, errors);

        // ==============================================================
        //  Phase 2 -- accuracy vs. in-block exponent spread
        // ==============================================================
        $display("");
        $display("  distribution        spread |  BF16 tree            BFP W=16 (D=3)"
                 , "       BFP W=23 (D=10)      BFP W=16 + pack");
        $display("  ------------------------------------------------------------"
                 , "------------------------------------------------------");

        for (mode = 0; mode < 2; mode = mode + 1) begin
          for (sp = 0; sp <= 16; sp = sp + 2) begin
            wf = 0.0; w16v = 0.0; w23v = 0.0; wpk = 0.0;
            sf = 0.0; s16v = 0.0; s23v = 0.0; spk = 0.0;
            nacc = 0;

            for (t = 0; t < 3000; t = t + 1) begin
                for (i = 0; i < 16; i = i + 1) begin
                    din[16*i +: 16] = {$random} & 16'h807F;
                    if (mode == 0) begin
                        // uniform: every element somewhere in the spread
                        din[16*i + 7 +: 8] = (sp == 0) ? 8'd127
                                                       : (127 - ({$random} % (sp+1)));
                    end else begin
                        // adversarial: element 0 is the outlier, rest sit at
                        // the bottom of the spread
                        din[16*i + 7 +: 8] = (i == 0) ? 8'd127 : (127 - sp);
                    end
                    ref_r[i] = bf16r(din[16*i +: 16]);
                end
                fht_real;
                #1;

                refmax = 0.0;
                for (i = 0; i < 16; i = i + 1) begin
                    rr = (ref_r[i] < 0) ? -ref_r[i] : ref_r[i];
                    if (rr > refmax) refmax = rr;
                end
                if (refmax == 0.0) refmax = 1.0;

                eint    = e16;  scale16 = 2.0 ** (eint - 134 - D16);
                eint    = e23;  scale23 = 2.0 ** (eint - 134 - D23);

                for (i = 0; i < 16; i = i + 1) begin
                    e_f   = bf16r(y_fused[16*i +: 16])         - ref_r[i];
                    e_b16 = sx16(fx16[W16*i +: W16]) * scale16 - ref_r[i];
                    e_b23 = sx23(fx23[W23*i +: W23]) * scale23 - ref_r[i];
                    e_pk  = bf16r(y_pack[16*i +: 16])          - ref_r[i];
                    e_f   = (e_f   < 0 ? -e_f   : e_f  ) / refmax;
                    e_b16 = (e_b16 < 0 ? -e_b16 : e_b16) / refmax;
                    e_b23 = (e_b23 < 0 ? -e_b23 : e_b23) / refmax;
                    e_pk  = (e_pk  < 0 ? -e_pk  : e_pk ) / refmax;
                    if (e_f   > wf  ) wf   = e_f;
                    if (e_b16 > w16v) w16v = e_b16;
                    if (e_b23 > w23v) w23v = e_b23;
                    if (e_pk  > wpk ) wpk  = e_pk;
                    sf   = sf   + e_f  *e_f;
                    s16v = s16v + e_b16*e_b16;
                    s23v = s23v + e_b23*e_b23;
                    spk  = spk  + e_pk *e_pk;
                    nacc = nacc + 1;
                end

                for (i = 0; i < 16; i = i + 1)
                    if (y_fused[16*i +: 16] !== y_2x[16*i +: 16]) begin
                        errors = errors + 1;
                        if (errors < 20) $display("P2 fused != 2x t=%0d i=%0d",
                            t, i);
                    end
            end

            $display("  %s  %2d   | rms %.2e max %.2e | rms %.2e max %.2e | rms %.2e max %.2e | rms %.2e max %.2e",
                (mode == 0) ? "uniform    " : "outlier+15 ", sp,
                (sf  /nacc) ** 0.5, wf,
                (s16v/nacc) ** 0.5, w16v,
                (s23v/nacc) ** 0.5, w23v,
                (spk /nacc) ** 0.5, wpk);
          end
          $display("");
        end

        if (errors == 0) $display(" PASS -- %0d checks, 0 mismatches", checks);
        else             $display(" FAIL -- %0d checks, %0d mismatches", checks, errors);
        $finish;
    end

endmodule
