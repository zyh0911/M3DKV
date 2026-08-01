// ===========================================================================
//  bf16_ref_model.vh -- reference model for the single-path BF16 adder
//                       (bf16adder/src/adder.sv)
//
//  The DUT is deliberately NOT IEEE-754, and this model follows its
//  conventions exactly:
//    - no subnormals : e == 0 is +/-0 and the fraction field is ignored
//    - no Inf / NaN  : an all-ones exponent is out of spec, the testbench
//                      never drives one
//    - round toward zero (truncation)
//    - overflow clamps to the largest finite number instead of going to Inf
//    - every zero result is +0, including -0 + -0 and N + (-N)
//
//  Written in a deliberately different style from the RTL: both significands
//  are placed in a 64-bit field with 32 guard bits, the alignment is a plain
//  right shift with a separate sticky and the rounding is a plain floor, so
//  the "the two's complement +1 and the sticky borrow cancel out" trick of
//  the M+2 bit datapath cannot hide inside the model.
//
//  Generic in (E, M) so the reduced-parameter sweeps can share it.
//
//  `include "bf16_ref_model.vh"    inside the testbench module.
// ===========================================================================

    // -------------------------------------------------------------------
    //  ref_add_gen -- packed result for any (E, M) with E+M+1 <= 16
    // -------------------------------------------------------------------
    function [15:0] ref_add_gen;
        input [15:0] ain;
        input [15:0] bin;
        input        subin;
        input [31:0] EW;
        input [31:0] MW;

        reg         s_a, s_b, s_l, s_s;
        reg  [15:0] e_a, e_b, f_a, f_b;
        reg  [15:0] e_l, e_s, sg_a, sg_b, sg_l, sg_s;
        reg  [15:0] mask_m, mask_e, mask_mag;
        reg  [63:0] W_l, W_s, W_s_full, S64;
        reg         st;
        // emax is an integer, not a reg: comparing a signed integer against
        // an unsigned reg makes the whole comparison unsigned, which turns an
        // underflowed (negative) exponent into a huge positive one
        integer     d, p, k, sh, Er, emax;
        begin
            mask_m   = (16'd1 << MW) - 16'd1;
            mask_e   = (16'd1 << EW) - 16'd1;
            mask_mag = (16'd1 << (EW + MW)) - 16'd1;
            emax     = (1 << EW) - 2;              // largest legal exponent

            s_a = (ain >> (EW + MW)) & 16'd1;
            e_a = (ain >> MW) & mask_e;
            f_a =  ain & mask_m;

            // a subtraction is an addition with the sign of b flipped, there
            // are no NaNs to make that distinction observable
            s_b = ((bin >> (EW + MW)) & 16'd1) ^ subin;
            e_b = (bin >> MW) & mask_e;
            f_b =  bin & mask_m;

            if (e_a == 16'd0 && e_b == 16'd0) begin
                ref_add_gen = 16'd0;                          // +0
            end else if (e_b == 16'd0) begin
                ref_add_gen = (s_a << (EW + MW)) | (e_a << MW) | f_a;
            end else if (e_a == 16'd0) begin
                ref_add_gen = (s_b << (EW + MW)) | (e_b << MW) | f_b;
            end else begin
                sg_a = (16'd1 << MW) | f_a;                   // hidden bit
                sg_b = (16'd1 << MW) | f_b;

                // {e, m} is monotonic with the magnitude
                if ((bin & mask_mag) > (ain & mask_mag)) begin
                    s_l = s_b; sg_l = sg_b; e_l = e_b;
                    s_s = s_a; sg_s = sg_a; e_s = e_a;
                end else begin
                    s_l = s_a; sg_l = sg_a; e_l = e_a;
                    s_s = s_b; sg_s = sg_b; e_s = e_b;
                end

                d        = e_l - e_s;
                W_l      = {48'd0, sg_l} << 32;
                W_s_full = {48'd0, sg_s} << 32;

                if (d > 32) begin
                    W_s = 64'd0;
                    st  = 1'b1;                    // sg_s is never 0 here
                end else begin
                    W_s = W_s_full >> d;
                    st  = ((W_s << d) != W_s_full);
                end

                // truncation toward zero: the discarded tail of an effective
                // subtraction is a borrow, floor(x - eps) == x - 1 for any
                // eps in (0, 1)
                if (s_l == s_s) S64 = W_l + W_s;
                else            S64 = W_l - W_s - (st ? 64'd1 : 64'd0);

                if (S64 == 64'd0) begin
                    ref_add_gen = 16'd0;           // exact cancellation -> +0
                end else begin
                    p = 0;
                    for (k = 0; k < 64; k = k + 1)
                        if (S64[k]) p = k;

                    Er = e_l + p - (32 + MW);
                    sh = p - MW;

                    if (sh < 1 || sh > 62) begin
                        $display("REFERENCE MODEL BROKEN: sh=%0d p=%0d", sh, p);
                        $finish;
                    end

                    if (Er > emax)                 // overflow -> max finite
                        ref_add_gen = (s_l << (EW + MW)) | (emax << MW) | mask_m;
                    else if (Er < 1)               // no subnormals -> +0
                        ref_add_gen = 16'd0;
                    else
                        ref_add_gen = (s_l << (EW + MW)) | (Er << MW) |
                                      ((S64 >> sh) & {48'd0, mask_m});
                end
            end
        end
    endfunction

    // -------------------------------------------------------------------
    //  bfloat16 shorthand
    // -------------------------------------------------------------------
    function [15:0] ref_add;
        input [15:0] ain;
        input [15:0] bin;
        input        subin;
        begin
            ref_add = ref_add_gen(ain, bin, subin, 32'd8, 32'd7);
        end
    endfunction
