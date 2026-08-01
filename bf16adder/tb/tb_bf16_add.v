// ===========================================================================
//  tb_bf16_add.v -- self-checking testbench for the single-path BF16 adder
//                   (bf16adder/src/adder.sv)
//
//  The DUT is not IEEE-754: no subnormals, no Inf/NaN, round toward zero,
//  overflow clamps to the largest finite number and every zero result is +0.
//  bf16_ref_model.vh models exactly those conventions.  An all-ones exponent
//  is out of spec (it would be Inf/NaN in IEEE), so no phase ever drives one.
//
//  Phases
//    1. directed corner cases     -- hand-written expected values, mostly the
//                                    places where these conventions differ
//                                    from IEEE (RTZ vs RNE, FTZ, clamp, +0)
//    2. structured cross product  -- ~430 interesting operands, add and sub
//    3. constrained-random        -- uniform, and exponent-correlated pairs
//    4. reduced-parameter sweeps  -- the same RTL at #(E=4,M=3) is small
//                                    enough to check exhaustively, which is
//                                    what actually pins the structure down;
//                                    #(E=5,M=4) too with +full
//
//  Plusargs
//    +dump=<file> : write "a b sub y" hex vectors for tb/bf16_ref.py
//    +nrand=<n>   : random vectors per pattern (default 200000)
//    +full        : also run the E=5,M=4 exhaustive sweep (~2M checks)
// ===========================================================================
`timescale 1ns/1ps

module tb_bf16_add;

    // ------------------------------------------------------------------
    //  DUT : bfloat16 configuration
    //  a - b is driven as a + (-b); with no NaNs that is exact
    // ------------------------------------------------------------------
    reg  [15:0] a, b;
    reg         sub;
    wire [15:0] y;

    bf16_add #(.E(8), .M(7)) dut (
        .sa_i(a[15]),       .ea_i(a[14:7]), .ma_i(a[6:0]),
        .sb_i(b[15] ^ sub), .eb_i(b[14:7]), .mb_i(b[6:0]),
        .s_o(y[15]),        .e_o(y[14:7]),  .m_o(y[6:0])
    );

    // ------------------------------------------------------------------
    //  Reduced-parameter instances for the exhaustive sweeps
    // ------------------------------------------------------------------
    localparam E2 = 4, M2 = 3, W2 = E2 + M2 + 1;    //  8 bit
    localparam E3 = 5, M3 = 4, W3 = E3 + M3 + 1;    // 10 bit

    reg  [W2-1:0] a2, b2;
    reg           sub2;
    wire [W2-1:0] y2;

    bf16_add #(.E(E2), .M(M2)) dut2 (
        .sa_i(a2[W2-1]),        .ea_i(a2[W2-2:M2]), .ma_i(a2[M2-1:0]),
        .sb_i(b2[W2-1] ^ sub2), .eb_i(b2[W2-2:M2]), .mb_i(b2[M2-1:0]),
        .s_o(y2[W2-1]),         .e_o(y2[W2-2:M2]),  .m_o(y2[M2-1:0])
    );

    reg  [W3-1:0] a3, b3;
    reg           sub3;
    wire [W3-1:0] y3;

    bf16_add #(.E(E3), .M(M3)) dut3 (
        .sa_i(a3[W3-1]),        .ea_i(a3[W3-2:M3]), .ma_i(a3[M3-1:0]),
        .sb_i(b3[W3-1] ^ sub3), .eb_i(b3[W3-2:M3]), .mb_i(b3[M3-1:0]),
        .s_o(y3[W3-1]),         .e_o(y3[W3-2:M3]),  .m_o(y3[M3-1:0])
    );

    // ------------------------------------------------------------------
    //  Reference model: 64-bit alignment, 32 guard bits, explicit sticky
    // ------------------------------------------------------------------
    `include "bf16_ref_model.vh"

    // ------------------------------------------------------------------
    //  Bookkeeping
    // ------------------------------------------------------------------
    integer errors = 0;
    integer checks = 0;
    integer dump_fd = 0;
    integer dump_left = 0;
    reg     dump_arm = 1'b0;                // armed for the random phase only

    // an all-ones exponent is Inf/NaN in IEEE and out of spec for this DUT
    function [15:0] sane;
        input [15:0] v;
        begin
            sane = (v[14:7] == 8'hFF) ? {v[15], 8'hFE, v[6:0]} : v;
        end
    endfunction

    task check;                             // bfloat16, model expectation
        input [15:0] ia, ib;
        input        is;
        reg   [15:0] exp;
        begin
            a = ia; b = ib; sub = is;
            #1;
            exp = ref_add(ia, ib, is);
            checks = checks + 1;
            if (y !== exp) begin
                errors = errors + 1;
                if (errors <= 40)
                    $display("  MISMATCH  a=%h b=%h sub=%b  ->  y=%h  expected %h",
                             ia, ib, is, y, exp);
            end
            if (dump_fd != 0 && dump_arm && dump_left > 0) begin
                $fdisplay(dump_fd, "%h %h %b %h", ia, ib, is, y);
                dump_left = dump_left - 1;
            end
        end
    endtask

    task check_exact;                       // directed, hand-written value
        input [15:0] ia, ib;
        input        is;
        input [15:0] exp;
        begin
            a = ia; b = ib; sub = is;
            #1;
            checks = checks + 1;
            if (y !== exp) begin
                errors = errors + 1;
                $display("  DIRECTED MISMATCH  a=%h b=%h sub=%b -> y=%h exp %h",
                         ia, ib, is, y, exp);
            end
        end
    endtask

    task check2;                            // reduced instance, E=4 M=3
        input [W2-1:0] ia, ib;
        input          is;
        reg    [15:0]  exp;
        begin
            a2 = ia; b2 = ib; sub2 = is;
            #1;
            exp = ref_add_gen({{16-W2{1'b0}}, ia}, {{16-W2{1'b0}}, ib}, is, E2, M2);
            checks = checks + 1;
            if (y2 !== exp[W2-1:0]) begin
                errors = errors + 1;
                if (errors <= 40)
                    $display("  E4M3 MISMATCH  a=%h b=%h sub=%b -> y=%h exp %h",
                             ia, ib, is, y2, exp[W2-1:0]);
            end
        end
    endtask

    task check3;                            // reduced instance, E=5 M=4
        input [W3-1:0] ia, ib;
        input          is;
        reg    [15:0]  exp;
        begin
            a3 = ia; b3 = ib; sub3 = is;
            #1;
            exp = ref_add_gen({{16-W3{1'b0}}, ia}, {{16-W3{1'b0}}, ib}, is, E3, M3);
            checks = checks + 1;
            if (y3 !== exp[W3-1:0]) begin
                errors = errors + 1;
                if (errors <= 40)
                    $display("  E5M4 MISMATCH  a=%h b=%h sub=%b -> y=%h exp %h",
                             ia, ib, is, y3, exp[W3-1:0]);
            end
        end
    endtask

    // ------------------------------------------------------------------
    //  Operand pool for the structured cross product
    // ------------------------------------------------------------------
    reg [15:0] pool [0:1023];
    integer    npool;
    reg [7:0]  exps [0:10];
    reg [6:0]  frcs [0:7];

    task build_pool;
        integer i, j, s, f;
        begin
            // no 8'hFF: that is Inf/NaN territory and out of spec here
            exps[0]=8'd0;   exps[1]=8'd1;   exps[2]=8'd2;
            exps[3]=8'd125; exps[4]=8'd126; exps[5]=8'd127;
            exps[6]=8'd128; exps[7]=8'd129; exps[8]=8'd252;
            exps[9]=8'd253; exps[10]=8'd254;
            frcs[0]=7'd0;  frcs[1]=7'd1;   frcs[2]=7'd2;   frcs[3]=7'd63;
            frcs[4]=7'd64; frcs[5]=7'd65;  frcs[6]=7'd126; frcs[7]=7'd127;

            npool = 0;
            for (s = 0; s < 2; s = s + 1)
                for (i = 0; i < 11; i = i + 1)
                    for (j = 0; j < 8; j = j + 1) begin
                        pool[npool] = {s[0], exps[i], frcs[j]};
                        npool = npool + 1;
                    end
            // every fraction at two adjacent exponents: exercises the whole
            // alignment / cancellation range one shift at a time
            for (f = 0; f < 128; f = f + 1) begin
                pool[npool] = {1'b0, 8'd127, f[6:0]}; npool = npool + 1;
                pool[npool] = {1'b0, 8'd126, f[6:0]}; npool = npool + 1;
            end
        end
    endtask

    // ------------------------------------------------------------------
    //  Random helpers
    // ------------------------------------------------------------------
    integer seed = 32'h1234_5678;

    function [15:0] rnd16;
        input dummy;
        begin
            rnd16 = sane($random(seed));
        end
    endfunction

    function [15:0] rnd_near;               // b with an exponent close to a's
        input [15:0] av;
        reg   [31:0] r;
        integer      delta, ee;
        begin
            r     = $random(seed);
            delta = (r[3:0] % 9) - 4;       // -4 .. +4
            ee    = av[14:7] + delta;
            if (ee < 0)   ee = 0;
            if (ee > 254) ee = 254;
            rnd_near = {r[16], ee[7:0], r[6:0]};
        end
    endfunction

    // ------------------------------------------------------------------
    //  Main
    // ------------------------------------------------------------------
    integer i, j, n, nrand;
    reg [15:0] va, vb;
    reg [1023:0] dumpfile;

    initial begin
        if ($value$plusargs("dump=%s", dumpfile)) begin
            dump_fd   = $fopen(dumpfile, "w");
            dump_left = 50000;
        end
        if (!$value$plusargs("nrand=%d", nrand)) nrand = 200000;

        $display("======================================================");
        $display(" tb_bf16_add  (single-path, RTZ, FTZ, clamped)");
        $display("======================================================");

        // ---- phase 1 : directed ---------------------------------------
        $display("[1] directed corner cases");
        check_exact(16'h3F80, 16'h3F80, 1'b0, 16'h4000); // 1 + 1 = 2
        check_exact(16'h3F80, 16'h3F00, 1'b0, 16'h3FC0); // 1 + 0.5 = 1.5
        check_exact(16'h4000, 16'h3F80, 1'b1, 16'h3F80); // 2 - 1 = 1
        check_exact(16'h3F80, 16'h4000, 1'b1, 16'hBF80); // 1 - 2 = -1

        // every zero result is +0, IEEE would keep -0 in the next three
        check_exact(16'h3F80, 16'h3F80, 1'b1, 16'h0000); // N - N   = +0
        check_exact(16'hBF80, 16'h3F80, 1'b0, 16'h0000); // -1 + 1  = +0
        check_exact(16'h8000, 16'h8000, 1'b0, 16'h0000); // -0 + -0 = +0
        check_exact(16'h8000, 16'h0000, 1'b1, 16'h0000); // -0 - +0 = +0
        check_exact(16'h0000, 16'h0000, 1'b0, 16'h0000); // +0 + +0 = +0

        // e == 0 is zero whatever the fraction says (no subnormals)
        check_exact(16'h007F, 16'h3F80, 1'b0, 16'h3F80); // "subnormal" + 1
        check_exact(16'h807F, 16'h0041, 1'b0, 16'h0000); // two flavours of 0
        check_exact(16'h3F80, 16'h0001, 1'b0, 16'h3F80); // 1 + 0

        // round to zero.  ulp at 1.0 is 2^-7 (0x3C00), half an ulp is 0x3B80
        check_exact(16'h3F80, 16'h3BC0, 1'b0, 16'h3F80); // 1 + 0.75 ulp, RNE: 3F81
        check_exact(16'h3F81, 16'h3B80, 1'b0, 16'h3F81); // tie,           RNE: 3F82
        check_exact(16'h3F80, 16'h3C40, 1'b0, 16'h3F81); // 1 + 1.5 ulp,   RNE: 3F82
        check_exact(16'h3F80, 16'h0180, 1'b0, 16'h3F80); // 1 + 2^-124, sticky only
        check_exact(16'h3F80, 16'h0180, 1'b1, 16'h3F7F); // 1 - 2^-124, borrow
        check_exact(16'h3F80, 16'h3F81, 1'b1, 16'hBC00); // 1 - (1+ulp) = -2^-7

        // alignment boundaries: the datapath is M+2 = 9 bits
        check_exact(16'h3F80, 16'h3B00, 1'b0, 16'h3F80); // shift 9,  add
        check_exact(16'h3F80, 16'h3B00, 1'b1, 16'h3F7F); // shift 9,  sub
        check_exact(16'h3F80, 16'h3980, 1'b1, 16'h3F7F); // shift 12, clamped

        // overflow clamps to the largest finite number, IEEE would give Inf
        check_exact(16'h7F7F, 16'h7F7F, 1'b0, 16'h7F7F); // maxnorm * 2
        check_exact(16'hFF7F, 16'hFF7F, 1'b0, 16'hFF7F); // -maxnorm * 2
        check_exact(16'h7F7F, 16'h3F80, 1'b0, 16'h7F7F); // maxnorm + 1
        check_exact(16'h7EFF, 16'h7EFF, 1'b0, 16'h7F7F); // one binade below

        // underflow flushes to +0, IEEE would give a subnormal
        check_exact(16'h00C0, 16'h0080, 1'b1, 16'h0000); // 0.5 * 2^-126
        check_exact(16'h0100, 16'h0080, 1'b1, 16'h0080); // exponent 1 is fine
        if (errors == 0) $display("    ok (%0d directed checks)", checks);

        // ---- phase 2 : structured cross product -----------------------
        $display("[2] structured cross product");
        build_pool;
        n = errors;
        for (i = 0; i < npool; i = i + 1)
            for (j = 0; j < npool; j = j + 1) begin
                check(pool[i], pool[j], 1'b0);
                check(pool[i], pool[j], 1'b1);
            end
        $display("    %0d operands -> %0d checks, %0d new mismatches",
                 npool, 2*npool*npool, errors - n);

        // ---- phase 3 : random -----------------------------------------
        $display("[3] random (%0d uniform + %0d exponent-correlated)", nrand, nrand);
        n = errors;
        dump_arm = 1'b1;                    // the vectors worth re-checking
        for (i = 0; i < nrand; i = i + 1) begin
            va = rnd16(0);
            vb = rnd16(0);
            check(va, vb, va[0]);
        end
        for (i = 0; i < nrand; i = i + 1) begin
            va = rnd16(0);
            vb = rnd_near(va);
            check(va, vb, vb[0]);
        end
        $display("    %0d new mismatches", errors - n);

        // ---- phase 4 : reduced-parameter exhaustive --------------------
        $display("[4] exhaustive #(E=%0d,M=%0d)", E2, M2);
        n = errors;
        sweep_e4m3;
        $display("    %0d new mismatches", errors - n);

        if ($test$plusargs("full")) begin
            $display("[4b] exhaustive #(E=%0d,M=%0d)", E3, M3);
            n = errors;
            sweep_e5m4;
            $display("    %0d new mismatches", errors - n);
        end else begin
            $display("[4b] exhaustive #(E=%0d,M=%0d) skipped, use +full", E3, M3);
        end

        // ---- summary ---------------------------------------------------
        if (dump_fd != 0) $fclose(dump_fd);
        $display("======================================================");
        if (errors == 0)
            $display(" PASS -- %0d checks, 0 mismatches", checks);
        else
            $display(" FAIL -- %0d checks, %0d mismatches", checks, errors);
        $display("======================================================");
        $finish;
    end

    // ------------------------------------------------------------------
    //  Exhaustive sweeps.  Operands with an all-ones exponent are skipped,
    //  they are the Inf/NaN encodings the DUT does not implement.
    // ------------------------------------------------------------------
    task sweep_e4m3;
        integer ia, ib;
        reg [W2-1:0] va2, vb2;
        begin
            for (ia = 0; ia < (1 << W2); ia = ia + 1) begin
                va2 = ia;
                if (&va2[W2-2:M2])
                    ;
                else
                    for (ib = 0; ib < (1 << W2); ib = ib + 1) begin
                        vb2 = ib;
                        if (~&vb2[W2-2:M2]) begin
                            check2(va2, vb2, 1'b0);
                            check2(va2, vb2, 1'b1);
                        end
                    end
            end
        end
    endtask

    task sweep_e5m4;
        integer ia, ib;
        reg [W3-1:0] va3, vb3;
        begin
            for (ia = 0; ia < (1 << W3); ia = ia + 1) begin
                va3 = ia;
                if (&va3[W3-2:M3])
                    ;
                else
                    for (ib = 0; ib < (1 << W3); ib = ib + 1) begin
                        vb3 = ib;
                        if (~&vb3[W3-2:M3]) begin
                            check3(va3, vb3, 1'b0);
                            check3(va3, vb3, 1'b1);
                        end
                    end
            end
        end
    endtask

endmodule
