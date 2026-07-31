// ===========================================================================
//  tb_bf16_add.v -- self-checking testbench for the BF16 adder
//
//  Checks the combinational core (bf16_add) against an independent reference
//  model written in a deliberately different style: the reference aligns into
//  a 64-bit field with 48 guard bits and a separate sticky, so a shared
//  "clever trick" bug in the 12-bit datapath cannot hide.
//
//  Phases
//    1. directed specials      -- NaN / Inf / zeros / subnormals / ties,
//                                 with hand-written expected values
//    2. structured cross product of ~430 interesting operands (both sub=0/1)
//    3. constrained-random     -- uniform, and exponent-correlated pairs
//    4. pipeline check         -- bf16_adder(PIPE=2) must reproduce the core
//
//  Plusargs
//    +saif        : instead of checking, drive N random ops through
//                   bf16_adder and dump bf16_adder.vcd (DUT subtree only)
//    +dump=<file> : write "a b sub y" hex vectors for tb/bf16_ref.py
//    +nrand=<n>   : number of random vectors (default 200000)
// ===========================================================================
`timescale 1ns/1ps

module tb_bf16_add;

    // ------------------------------------------------------------------
    //  DUT (combinational core)
    // ------------------------------------------------------------------
    reg  [15:0] a, b;
    reg         sub;
    wire [15:0] y;
    wire        nv, of, uf, nx;

    //  +define+GATE_SIM binds the DC netlist instead of the RTL.  uniquify
    //  renames the designs, so the gate modules are bf16_add_0 /
    //  bf16_adder_PIPE2; the port names are unchanged.
`ifdef GATE_SIM
    bf16_add_0 dut_core (
`else
    bf16_add dut_core (
`endif
        .a(a), .b(b), .sub(sub),
        .y(y), .nv(nv), .of(of), .uf(uf), .nx(nx)
    );

    // ------------------------------------------------------------------
    //  Pipelined wrapper (phase 4 + SAIF workload)
    // ------------------------------------------------------------------
    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg  [15:0] pa, pb;
    reg         psub, pvld;
    wire [15:0] py;
    wire [3:0]  pflags;
    wire        pvld_out;

`ifdef GATE_SIM
    bf16_adder_PIPE2 dut (
`else
    bf16_adder #(.PIPE(2)) dut (
`endif
        .clk(clk), .rst_n(rst_n), .vld_in(pvld),
        .a(pa), .b(pb), .sub(psub),
        .y(py), .flags(pflags), .vld_out(pvld_out)
    );

    always #1 clk = ~clk;

    // ------------------------------------------------------------------
    //  Reference model: 64-bit alignment, 48 guard bits, explicit sticky
    // ------------------------------------------------------------------
    `include "bf16_ref_model.vh"

    // ------------------------------------------------------------------
    //  Bookkeeping
    // ------------------------------------------------------------------
    integer errors = 0;
    integer checks = 0;
    integer dump_fd = 0;
    integer dump_left = 0;

    task show;
        input [15:0] ia, ib;
        input        is;
        input [15:0] got, exp;
        begin
            $display("  MISMATCH  a=%h b=%h sub=%b  ->  y=%h  expected %h",
                     ia, ib, is, got, exp);
        end
    endtask

    task check;
        input [15:0] ia, ib;
        input        is;
        reg   [15:0] exp;
        begin
            a = ia; b = ib; sub = is;
            #1;
            exp = ref_add(ia, ib, is);
            checks = checks + 1;
            // any NaN encoding is acceptable, compare as "is NaN"
            if (!(is_nan(y) && is_nan(exp)) && (y !== exp)) begin
                errors = errors + 1;
                if (errors <= 40) show(ia, ib, is, y, exp);
            end
            if (dump_fd != 0 && dump_left > 0) begin
                // the flags are checked by tb/bf16_ref.py, which can compute
                // them exactly from the rational result
                $fdisplay(dump_fd, "%h %h %b %h %b%b%b%b",
                          ia, ib, is, y, nv, of, uf, nx);
                dump_left = dump_left - 1;
            end
        end
    endtask


    task check_flags;                       // directed check of {nv,of,uf,nx}
        input [15:0] ia, ib;
        input        is;
        input [3:0]  exp;
        begin
            a = ia; b = ib; sub = is;
            #1;
            checks = checks + 1;
            if ({nv, of, uf, nx} !== exp) begin
                errors = errors + 1;
                $display("  FLAG MISMATCH  a=%h b=%h sub=%b -> nv/of/uf/nx=%b%b%b%b exp %b",
                         ia, ib, is, nv, of, uf, nx, exp);
            end
        end
    endtask

    task check_exact;                       // directed, hand-written expectation
        input [15:0] ia, ib;
        input        is;
        input [15:0] exp;
        begin
            a = ia; b = ib; sub = is;
            #1;
            checks = checks + 1;
            if (!(is_nan(y) && is_nan(exp)) && (y !== exp)) begin
                errors = errors + 1;
                $display("  DIRECTED MISMATCH  a=%h b=%h sub=%b -> y=%h exp %h",
                         ia, ib, is, y, exp);
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
            exps[0]=8'd0;   exps[1]=8'd1;   exps[2]=8'd2;
            exps[3]=8'd125; exps[4]=8'd126; exps[5]=8'd127;
            exps[6]=8'd128; exps[7]=8'd129; exps[8]=8'd253;
            exps[9]=8'd254; exps[10]=8'd255;
            frcs[0]=7'd0;  frcs[1]=7'd1;   frcs[2]=7'd2;   frcs[3]=7'd63;
            frcs[4]=7'd64; frcs[5]=7'd65;  frcs[6]=7'd126; frcs[7]=7'd127;

            npool = 0;
            for (s = 0; s < 2; s = s + 1)
                for (i = 0; i < 11; i = i + 1)
                    for (j = 0; j < 8; j = j + 1) begin
                        pool[npool] = {s[0], exps[i], frcs[j]};
                        npool = npool + 1;
                    end
            // every fraction at two adjacent exponents: exercises alignment,
            // ties and the round-up-into-the-next-binade path
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
            rnd16 = $random(seed);
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
        if ($test$plusargs("saif")) begin
            saif_run;
            $finish;
        end

        if ($value$plusargs("dump=%s", dumpfile)) begin
            dump_fd   = $fopen(dumpfile, "w");
            dump_left = 50000;
        end
        if (!$value$plusargs("nrand=%d", nrand)) nrand = 200000;

        $display("======================================================");
        $display(" tb_bf16_add");
        $display("======================================================");

        // ---- phase 1 : directed ---------------------------------------
        $display("[1] directed special cases");
        check_exact(16'h3F80, 16'h3F80, 1'b0, 16'h4000); // 1 + 1 = 2
        check_exact(16'h3F80, 16'h3F00, 1'b0, 16'h3FC0); // 1 + 0.5 = 1.5
        check_exact(16'h3F80, 16'h3F80, 1'b1, 16'h0000); // 1 - 1 = +0
        check_exact(16'h8000, 16'h8000, 1'b0, 16'h8000); // -0 + -0 = -0
        check_exact(16'h8000, 16'h0000, 1'b0, 16'h0000); // -0 + +0 = +0
        check_exact(16'h0000, 16'h0000, 1'b1, 16'h0000); // +0 - +0 = +0
        check_exact(16'h0000, 16'h8000, 1'b1, 16'h0000); // +0 - -0 = +0
        check_exact(16'h8000, 16'h0000, 1'b1, 16'h8000); // -0 - +0 = -0
        check_exact(16'h7F80, 16'h7F80, 1'b0, 16'h7F80); // inf + inf
        check_exact(16'h7F80, 16'h7F80, 1'b1, 16'h7FC0); // inf - inf = NaN
        check_exact(16'h7F80, 16'h3F80, 1'b0, 16'h7F80); // inf + 1
        check_exact(16'h7FC1, 16'h3F80, 1'b0, 16'h7FC0); // NaN + 1
        check_exact(16'h7F7F, 16'h7F7F, 1'b0, 16'h7F80); // maxnorm*2 -> inf
        check_exact(16'h0001, 16'h0001, 1'b0, 16'h0002); // subnormal + subnormal
        check_exact(16'h007F, 16'h0001, 1'b0, 16'h0080); // subnorm -> min normal
        check_exact(16'h0080, 16'h0001, 1'b1, 16'h007F); // min normal -> subnorm
        // ulp at 1.0 is 2^-7, so 0x3B80 = 2^-8 is exactly half an ulp
        check_exact(16'h3F80, 16'h3B80, 1'b0, 16'h3F80); // tie -> even (down)
        check_exact(16'h3F81, 16'h3B80, 1'b0, 16'h3F82); // tie -> even (up)
        check_exact(16'h3F80, 16'h3BC0, 1'b0, 16'h3F81); // 0.75 ulp -> up
        check_exact(16'h3F80, 16'h3B00, 1'b0, 16'h3F80); // 0.25 ulp -> down
        check_exact(16'h3F80, 16'h0001, 1'b0, 16'h3F80); // 1 + tiny  (sticky only)
        check_exact(16'h4000, 16'h3F80, 1'b1, 16'h3F80); // 2 - 1 = 1
        check_exact(16'hBF80, 16'h3F80, 1'b0, 16'h0000); // -1 + 1 = +0

        //                                              {nv, of, uf, nx}
        check_flags(16'h3F80, 16'h3F80, 1'b0, 4'b0000); // 1+1 exact
        check_flags(16'h3F80, 16'h0001, 1'b0, 4'b0001); // sticky only -> inexact
        check_flags(16'h7F80, 16'h7F80, 1'b1, 4'b1000); // Inf - Inf -> invalid
        check_flags(16'h7F81, 16'h3F80, 1'b0, 4'b1000); // sNaN operand -> invalid
        check_flags(16'h7FC1, 16'h3F80, 1'b0, 4'b0000); // qNaN is quiet
        check_flags(16'h7F7F, 16'h7F7F, 1'b0, 4'b0101); // overflow + inexact
        check_flags(16'h7F80, 16'h3F80, 1'b0, 4'b0000); // Inf + 1 is exact
        check_flags(16'h0003, 16'h0002, 1'b0, 4'b0000); // subnormal sum, exact
        check_flags(16'h0080, 16'h0001, 1'b1, 4'b0000); // exact -> subnormal
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

        // ---- phase 4 : pipelined wrapper ------------------------------
        $display("[4] bf16_adder PIPE=2 pipeline consistency");
        n = errors;
        pipe_check;
        $display("    %0d new mismatches", errors - n);

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
    //  Phase 4 : drive the wrapper, compare against the reference with a
    //  2-cycle expectation pipeline
    // ------------------------------------------------------------------
    //  PIPE=2 latency is 2 cycles, so right after the posedge of iteration t
    //  the output register holds the result of the operands issued at t-1.
    task pipe_check;
        integer t, nvec;
        reg [15:0] ra, rb, cur, prev, pv_a, pv_b;
        reg        rs, pv_s;
        begin
            nvec  = 20000;
            rst_n = 1'b0;
            pvld  = 1'b0;
            prev  = 16'h0;
            @(posedge clk); @(posedge clk);
            rst_n = 1'b1;

            for (t = 0; t < nvec; t = t + 1) begin
                ra = rnd16(0);
                rb = (t[0]) ? rnd_near(ra) : rnd16(0);
                rs = ra[1];
                @(negedge clk);
                pa = ra;  pb = rb;  psub = rs;  pvld = 1'b1;
                cur = ref_add(ra, rb, rs);
                @(posedge clk);
                #0.2;
                if (t >= 1) begin
                    checks = checks + 1;
                    if (!(is_nan(py) && is_nan(prev)) && (py !== prev)) begin
                        errors = errors + 1;
                        if (errors <= 40)
                            $display("  PIPE MISMATCH t=%0d a=%h b=%h sub=%b y=%h exp=%h",
                                     t, pv_a, pv_b, pv_s, py, prev);
                    end
                    if (pvld_out !== 1'b1) begin
                        errors = errors + 1;
                        $display("  PIPE VALID MISSING at t=%0d", t);
                    end
                end
                prev = cur;  pv_a = ra;  pv_b = rb;  pv_s = rs;
            end
            @(negedge clk); pvld = 1'b0;
        end
    endtask

    // ------------------------------------------------------------------
    //  SAIF workload : back-to-back random adds through the wrapper.
    //  Reset is excluded from the dump window so the activity is realistic.
    // ------------------------------------------------------------------
    task saif_run;
        integer t, nops;
        reg [15:0] ra, rb;
        begin
            if (!$value$plusargs("nops=%d", nops)) nops = 20000;
            rst_n = 1'b0;
            pvld  = 1'b0;
            pa    = 16'h0;
            pb    = 16'h0;
            psub  = 1'b0;
            @(posedge clk); @(posedge clk);
            rst_n = 1'b1;
            @(posedge clk);

            $dumpfile("bf16_adder.vcd");
            $dumpvars(0, tb_bf16_add.dut);
            $dumpon;

            for (t = 0; t < nops; t = t + 1) begin
                ra = rnd16(0);
                // half of the traffic has correlated exponents, which is what
                // real workloads (accumulation) look like
                rb = (t[0]) ? rnd_near(ra) : rnd16(0);
                @(negedge clk);
                pa = ra; pb = rb; psub = ra[1]; pvld = 1'b1;
            end
            @(posedge clk); @(posedge clk); @(posedge clk);
            $dumpoff;
            $display("SAIF workload done: %0d ops -> bf16_adder.vcd", nops);
        end
    endtask

endmodule
