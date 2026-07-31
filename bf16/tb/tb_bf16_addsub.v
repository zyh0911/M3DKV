// ===========================================================================
//  tb_bf16_addsub.v -- self-checking testbench for the fused add/subtract unit
//
//  Drives bf16_addsub_fused and bf16_addsub_2x with the same operands and
//  checks, for every vector:
//
//    * y_sum  against ref_add(a, b, 0)      (the 64-bit reference model)
//    * y_diff against ref_add(a, b, 1)
//    * fused outputs and flags bit-identical to the two-adder baseline
//
//  The baseline is built from bf16_add, which tb_bf16_add.v already verifies
//  against the reference model and the exact rational oracle, so "identical to
//  the baseline" is a strong statement.
//
//  Plusargs
//    +saif +dut=fused|2x : drive random traffic and dump that wrapper's VCD
//    +dump=<file>        : "a b sub y flags" vectors for tb/bf16_ref.py
//    +nrand=<n>          : random vectors (default 200000)
// ===========================================================================
`timescale 1ns/1ps

module tb_bf16_addsub;

    // ------------------------------------------------------------------
    //  Combinational cores, driven in lockstep
    // ------------------------------------------------------------------
    reg  [15:0] a, b;

    wire [15:0] yf_sum, yf_diff;
    wire [3:0]  ff_sum, ff_diff;
    wire [15:0] yr_sum, yr_diff;
    wire [3:0]  fr_sum, fr_diff;

    bf16_addsub_fused dut_fused (
        .a(a), .b(b),
        .y_sum(yf_sum), .y_diff(yf_diff),
        .flags_sum(ff_sum), .flags_diff(ff_diff)
    );

    bf16_addsub_2x dut_2x (
        .a(a), .b(b),
        .y_sum(yr_sum), .y_diff(yr_diff),
        .flags_sum(fr_sum), .flags_diff(fr_diff)
    );

    // ------------------------------------------------------------------
    //  Pipelined wrappers (phase 4 + SAIF workload)
    // ------------------------------------------------------------------
    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg  [15:0] pa, pb;
    reg         pvld;

    wire [15:0] pf_sum, pf_diff, p2_sum, p2_diff;
    wire [3:0]  pf_fs, pf_fd, p2_fs, p2_fd;
    wire        pf_vld, p2_vld;

    bf16_addsub_unit #(.FUSED(1), .PIPE(2)) dut_u_fused (
        .clk(clk), .rst_n(rst_n), .vld_in(pvld), .a(pa), .b(pb),
        .y_sum(pf_sum), .y_diff(pf_diff),
        .flags_sum(pf_fs), .flags_diff(pf_fd), .vld_out(pf_vld)
    );

    bf16_addsub_unit #(.FUSED(0), .PIPE(2)) dut_u_2x (
        .clk(clk), .rst_n(rst_n), .vld_in(pvld), .a(pa), .b(pb),
        .y_sum(p2_sum), .y_diff(p2_diff),
        .flags_sum(p2_fs), .flags_diff(p2_fd), .vld_out(p2_vld)
    );

    always #1 clk = ~clk;

    // ------------------------------------------------------------------
    //  Reference model (shared with tb_bf16_add.v)
    // ------------------------------------------------------------------
    `include "bf16_ref_model.vh"

    // ------------------------------------------------------------------
    //  Bookkeeping
    // ------------------------------------------------------------------
    integer errors = 0;
    integer checks = 0;
    integer dump_fd = 0;
    integer dump_left = 0;

    task check;
        input [15:0] ia, ib;
        reg   [15:0] xs, xd;
        begin
            a = ia; b = ib;
            #1;
            xs = ref_add(ia, ib, 1'b0);
            xd = ref_add(ia, ib, 1'b1);
            checks = checks + 2;

            if (!(is_nan(yf_sum) && is_nan(xs)) && (yf_sum !== xs)) begin
                errors = errors + 1;
                if (errors <= 40)
                    $display("  SUM  MISMATCH a=%h b=%h -> %h expected %h",
                             ia, ib, yf_sum, xs);
            end
            if (!(is_nan(yf_diff) && is_nan(xd)) && (yf_diff !== xd)) begin
                errors = errors + 1;
                if (errors <= 40)
                    $display("  DIFF MISMATCH a=%h b=%h -> %h expected %h",
                             ia, ib, yf_diff, xd);
            end

            // bit-for-bit equivalence with the two-adder baseline, flags included
            if ((yf_sum !== yr_sum) || (yf_diff !== yr_diff) ||
                (ff_sum !== fr_sum) || (ff_diff !== fr_diff)) begin
                errors = errors + 1;
                if (errors <= 40)
                    $display("  FUSED != 2x  a=%h b=%h  fused %h/%h %b/%b  2x %h/%h %b/%b",
                             ia, ib, yf_sum, yf_diff, ff_sum, ff_diff,
                             yr_sum, yr_diff, fr_sum, fr_diff);
            end

            if (dump_fd != 0 && dump_left > 1) begin
                $fdisplay(dump_fd, "%h %h 0 %h %b", ia, ib, yf_sum,  ff_sum);
                $fdisplay(dump_fd, "%h %h 1 %h %b", ia, ib, yf_diff, ff_diff);
                dump_left = dump_left - 2;
            end
        end
    endtask

    // ------------------------------------------------------------------
    //  Operand pool (same construction as tb_bf16_add.v)
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
            for (f = 0; f < 128; f = f + 1) begin
                pool[npool] = {1'b0, 8'd127, f[6:0]}; npool = npool + 1;
                pool[npool] = {1'b0, 8'd126, f[6:0]}; npool = npool + 1;
            end
        end
    endtask

    // ------------------------------------------------------------------
    //  Random helpers
    // ------------------------------------------------------------------
    integer seed = 32'h0BADC0DE;

    function [15:0] rnd16;
        input dummy;
        begin
            rnd16 = $random(seed);
        end
    endfunction

    function [15:0] rnd_near;
        input [15:0] av;
        reg   [31:0] r;
        integer      delta, ee;
        begin
            r     = $random(seed);
            delta = (r[3:0] % 9) - 4;
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
        $display(" tb_bf16_addsub   (fused vs. reference vs. two adders)");
        $display("======================================================");

        $display("[1] directed");
        check(16'h3F80, 16'h3F80);   // 1, 1     -> 2, +0
        check(16'h3F80, 16'hBF80);   // 1, -1    -> +0, 2
        check(16'h7F80, 16'h7F80);   // inf, inf -> inf, NaN
        check(16'h7F80, 16'hFF80);   // inf,-inf -> NaN, inf
        check(16'h0000, 16'h8000);   // +0, -0   -> +0, +0
        check(16'h8000, 16'h8000);   // -0, -0   -> -0, +0
        check(16'h8000, 16'h0000);   // -0, +0   -> +0, -0
        check(16'h7F7F, 16'h7F7F);   // maxnorm  -> inf, +0
        check(16'h7F7F, 16'hFF7F);   // +max,-max-> +0, inf
        check(16'h0001, 16'h0001);   // subnormals
        check(16'h0080, 16'h0001);   // normal/subnormal boundary
        check(16'h7FC1, 16'h3F80);   // NaN
        check(16'h3F80, 16'h3B80);   // tie -> even
        $display("    %0d checks", checks);

        $display("[2] structured cross product");
        build_pool;
        n = errors;
        for (i = 0; i < npool; i = i + 1)
            for (j = 0; j < npool; j = j + 1)
                check(pool[i], pool[j]);
        $display("    %0d operands -> %0d checks, %0d new mismatches",
                 npool, 2*npool*npool, errors - n);

        $display("[3] random (%0d uniform + %0d exponent-correlated)", nrand, nrand);
        n = errors;
        for (i = 0; i < nrand; i = i + 1) begin
            va = rnd16(0);
            vb = rnd16(0);
            check(va, vb);
        end
        for (i = 0; i < nrand; i = i + 1) begin
            va = rnd16(0);
            vb = rnd_near(va);
            check(va, vb);
        end
        $display("    %0d new mismatches", errors - n);

        $display("[4] pipelined wrappers, FUSED=1 vs FUSED=0");
        n = errors;
        pipe_check;
        $display("    %0d new mismatches", errors - n);

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
    //  Phase 4 : both wrappers, 2-cycle latency
    // ------------------------------------------------------------------
    task pipe_check;
        integer t, nvec;
        reg [15:0] ra, rb, cs, cd, ps_e, pd_e, pv_a, pv_b;
        begin
            nvec  = 20000;
            rst_n = 1'b0;
            pvld  = 1'b0;
            ps_e  = 16'h0;
            pd_e  = 16'h0;
            @(posedge clk); @(posedge clk);
            rst_n = 1'b1;

            for (t = 0; t < nvec; t = t + 1) begin
                ra = rnd16(0);
                rb = (t[0]) ? rnd_near(ra) : rnd16(0);
                @(negedge clk);
                pa = ra; pb = rb; pvld = 1'b1;
                cs = ref_add(ra, rb, 1'b0);
                cd = ref_add(ra, rb, 1'b1);
                @(posedge clk);
                #0.2;
                if (t >= 1) begin
                    checks = checks + 2;
                    if (!(is_nan(pf_sum) && is_nan(ps_e)) && (pf_sum !== ps_e)) begin
                        errors = errors + 1;
                        if (errors <= 40)
                            $display("  PIPE SUM  a=%h b=%h -> %h exp %h",
                                     pv_a, pv_b, pf_sum, ps_e);
                    end
                    if (!(is_nan(pf_diff) && is_nan(pd_e)) && (pf_diff !== pd_e)) begin
                        errors = errors + 1;
                        if (errors <= 40)
                            $display("  PIPE DIFF a=%h b=%h -> %h exp %h",
                                     pv_a, pv_b, pf_diff, pd_e);
                    end
                    if ((pf_sum !== p2_sum) || (pf_diff !== p2_diff) ||
                        (pf_fs !== p2_fs) || (pf_fd !== p2_fd) ||
                        (pf_vld !== p2_vld)) begin
                        errors = errors + 1;
                        if (errors <= 40)
                            $display("  PIPE FUSED != 2x at t=%0d", t);
                    end
                end
                ps_e = cs;  pd_e = cd;  pv_a = ra;  pv_b = rb;
            end
            @(negedge clk); pvld = 1'b0;
        end
    endtask

    // ------------------------------------------------------------------
    //  SAIF workload : +saif +dut=fused | +dut=2x
    // ------------------------------------------------------------------
    task saif_run;
        integer t, nops;
        reg [15:0] ra, rb;
        reg [63:0] which;
        begin
            if (!$value$plusargs("nops=%d", nops)) nops = 20000;
            if (!$value$plusargs("dut=%s", which)) which = "fused";

            rst_n = 1'b0;
            pvld  = 1'b0;
            pa    = 16'h0;
            pb    = 16'h0;
            @(posedge clk); @(posedge clk);
            rst_n = 1'b1;
            @(posedge clk);

            if (which == "2x") begin
                $dumpfile("bf16_addsub_2x.vcd");
                $dumpvars(0, tb_bf16_addsub.dut_u_2x);
            end else begin
                $dumpfile("bf16_addsub_fused.vcd");
                $dumpvars(0, tb_bf16_addsub.dut_u_fused);
            end
            $dumpon;

            for (t = 0; t < nops; t = t + 1) begin
                ra = rnd16(0);
                rb = (t[0]) ? rnd_near(ra) : rnd16(0);
                @(negedge clk);
                pa = ra; pb = rb; pvld = 1'b1;
            end
            @(posedge clk); @(posedge clk); @(posedge clk);
            $dumpoff;
            $display("SAIF workload done: %0d ops (%0s)", nops, which);
        end
    endtask

endmodule
