// ===========================================================================
//  tb_gls.v -- gate-level check of the synthesised BF16 adder netlist
//
//  ../tb/tb_bf16_add.v instantiates three parameterisations of bf16_add; a
//  synthesised netlist has no parameters, so it cannot bind to that testbench.
//  This one drives the E=8, M=7 netlist only, against the same reference
//  model, with the same directed + structured + random stimulus.
//
//    iverilog -g2012 -I ../tb -s tb_gls tb_gls.v <netlist>.v <asap7 models>
//
//  Zero-delay functional check: the ASAP7 models carry specify blocks, so
//  settling is allowed 100 ns per vector rather than assumed instantaneous.
// ===========================================================================
`timescale 1ns/1ps

module tb_gls;

    reg  [15:0] a, b;
    reg         sub;
    wire [15:0] y;

    // sub is folded into b's sign: with no NaNs, a - b == a + (-b) exactly
    reg  [15:0] bx;
    always @(*) bx = {b[15] ^ sub, b[14:0]};

    bf16_add dut (
        .sa_i(a[15]),  .ea_i(a[14:7]),  .ma_i(a[6:0]),
        .sb_i(bx[15]), .eb_i(bx[14:7]), .mb_i(bx[6:0]),
        .s_o(y[15]),   .e_o(y[14:7]),   .m_o(y[6:0])
    );

    `include "bf16_ref_model.vh"

    integer errors = 0;
    integer checks = 0;
    integer nrand;

    function [15:0] sane;
        input [15:0] v;
        begin
            sane = (v[14:7] == 8'hFF) ? {v[15], 8'hFE, v[6:0]} : v;
        end
    endfunction

    task check;
        input [15:0] ia, ib;
        input        is;
        reg   [15:0] exp;
        begin
            a = ia; b = ib; sub = is;
            #100;                          // let the gate delays settle
            exp = ref_add(ia, ib, is);
            checks = checks + 1;
            if (y !== exp) begin
                errors = errors + 1;
                if (errors <= 40)
                    $display("  GLS MISMATCH  a=%h b=%h sub=%b -> y=%h exp %h",
                             ia, ib, is, y, exp);
            end
        end
    endtask

    // ---- same operand pool as the RTL testbench ---------------------------
    reg [15:0] pool [0:1023];
    integer    npool;
    reg [7:0]  exps [0:10];
    reg [6:0]  frcs [0:7];

    task build_pool;
        integer i, j, s, f;
        begin
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
            for (f = 0; f < 128; f = f + 1) begin
                pool[npool] = {1'b0, 8'd127, f[6:0]}; npool = npool + 1;
                pool[npool] = {1'b0, 8'd126, f[6:0]}; npool = npool + 1;
            end
        end
    endtask

    integer seed = 32'h1234_5678;
    integer i, j, n;
    reg [15:0] va, vb;

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

    initial begin
        if (!$value$plusargs("nrand=%d", nrand)) nrand = 20000;

        $display("======================================================");
        $display(" tb_gls -- gate-level netlist vs reference model");
        $display("======================================================");

        // directed
        check(16'h3F80, 16'h3F80, 1'b0);
        check(16'h3F80, 16'h3F00, 1'b0);
        check(16'h4000, 16'h3F80, 1'b1);
        check(16'h3F80, 16'h4000, 1'b1);
        check(16'h3F80, 16'h3F80, 1'b1);
        check(16'hBF80, 16'h3F80, 1'b0);
        check(16'h8000, 16'h8000, 1'b0);
        check(16'h0000, 16'h0000, 1'b0);
        check(16'h7F7F, 16'h7F7F, 1'b0);
        check(16'h00C0, 16'h0080, 1'b1);
        $display("[1] directed          : %0d checks, %0d mismatches", checks, errors);

        // structured cross product
        n = errors;
        build_pool;
        for (i = 0; i < npool; i = i + 1)
            for (j = 0; j < npool; j = j + 1) begin
                check(pool[i], pool[j], 1'b0);
                check(pool[i], pool[j], 1'b1);
            end
        $display("[2] structured        : %0d checks, %0d new mismatches",
                 2*npool*npool, errors - n);

        // random
        n = errors;
        for (i = 0; i < nrand; i = i + 1) begin
            va = sane($random(seed));
            vb = sane($random(seed));
            check(va, vb, va[0]);
        end
        for (i = 0; i < nrand; i = i + 1) begin
            va = sane($random(seed));
            vb = rnd_near(va);
            check(va, vb, vb[0]);
        end
        $display("[3] random            : %0d checks, %0d new mismatches",
                 2*nrand, errors - n);

        $display("======================================================");
        if (errors == 0) $display(" GLS PASS -- %0d checks, 0 mismatches", checks);
        else             $display(" GLS FAIL -- %0d checks, %0d mismatches", checks, errors);
        $display("======================================================");
        $finish;
    end

endmodule
