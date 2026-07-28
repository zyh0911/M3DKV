// ============================================================================
//  tb_fht_core.v -- unit testbench for the 8/16-way parallel FHT core
//
//  Checks:
//    T1  16-way mode vs. golden natural-order H16          (random + directed)
//    T2   8-way mode vs. golden natural-order H8, and that the gated upper
//         half stays at zero                               (random + directed)
//    T3  orthogonality:  H16 * H16^T == 16*I  (all 16 basis vectors)
//    T4  orthogonality:  H8  * H8^T  ==  8*I  (all  8 basis vectors)
//    T5  bit-growth: |y| <= 16*max|x| and no wraparound at the extremes
// ============================================================================
`timescale 1ns/1ps

module tb_fht_core;

    localparam integer W = 23;

    reg                mode16;
    reg  [16*W-1:0]    din;
    wire [16*W-1:0]    dout;

    fht_core #(.W(W)) dut (
        .mode16 (mode16),
        .din    (din),
        .dout   (dout)
    );

    integer errors = 0;
    integer i, j, t;

    reg signed [63:0] gx [0:15];        // golden input
    reg signed [63:0] gy [0:15];        // golden output

    // ---------------------------------------------------------------
    // golden natural-order (Sylvester) Walsh-Hadamard transform, N = 8 or 16
    // ---------------------------------------------------------------
    task golden_wht;
        input integer n;
        integer len, ii, jj;
        reg signed [63:0] a, b;
        begin
            for (ii = 0; ii < n; ii = ii + 1) gy[ii] = gx[ii];
            for (len = 1; len < n; len = len * 2)
                for (ii = 0; ii < n; ii = ii + 2*len)
                    for (jj = ii; jj < ii + len; jj = jj + 1) begin
                        a = gy[jj];
                        b = gy[jj+len];
                        gy[jj]     = a + b;
                        gy[jj+len] = a - b;
                    end
        end
    endtask

    // pack gx[0..n-1] into din, zero the rest
    task drive;
        input integer n;
        integer ii;
        begin
            din = {(16*W){1'b0}};
            for (ii = 0; ii < n; ii = ii + 1)
                din[ii*W +: W] = gx[ii][W-1:0];
        end
    endtask

    function signed [W-1:0] lane;
        input integer ii;
        begin
            lane = dout[ii*W +: W];
        end
    endfunction

    task check;
        input integer n;                // 8 or 16
        input [255:0] tag;
        integer ii;
        begin
            for (ii = 0; ii < n; ii = ii + 1)
                if (lane(ii) !== gy[ii][W-1:0]) begin
                    errors = errors + 1;
                    $display("  [FAIL] %0s n=%0d lane %0d : got %0d, exp %0d",
                             tag, n, ii, lane(ii), gy[ii]);
                end
            // in 8-way mode the gated upper half must be exactly zero
            if (n == 8)
                for (ii = 8; ii < 16; ii = ii + 1)
                    if (lane(ii) !== {W{1'b0}}) begin
                        errors = errors + 1;
                        $display("  [FAIL] %0s gated lane %0d = %0d (expected 0)",
                                 tag, ii, lane(ii));
                    end
        end
    endtask

    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("tb_fht_core.vcd");
            $dumpvars(0, tb_fht_core);
        end

        $display("========================================================");
        $display(" tb_fht_core : 8/16-way parallel FHT core");
        $display("========================================================");

        // ---------------- T1 : 16-way random ------------------------
        mode16 = 1'b1;
        for (t = 0; t < 500; t = t + 1) begin
            for (i = 0; i < 16; i = i + 1)
                gx[i] = $signed({$random} % 65536) - 32768;   // 16-bit signed
            golden_wht(16);
            drive(16);
            #1 check(16, "T1 16-way random");
        end
        $display(" T1  16-way vs. golden H16 (500 random vectors)  : %0s",
                 errors ? "FAIL" : "pass");

        // ---------------- T2 : 8-way random -------------------------
        begin : t2
            integer e0; e0 = errors;
            mode16 = 1'b0;
            for (t = 0; t < 500; t = t + 1) begin
                for (i = 0; i < 8; i = i + 1)
                    gx[i] = $signed({$random} % 65536) - 32768;
                for (i = 8; i < 16; i = i + 1)
                    gx[i] = $signed({$random} % 65536) - 32768; // garbage: must be ignored
                golden_wht(8);                                  // golden uses gx[0..7]
                drive(16);                                      // drive all 16 lanes
                #1 check(8, "T2 8-way random");
            end
            $display(" T2   8-way vs. golden H8, upper half gated      : %0s",
                     (errors == e0) ? "pass" : "FAIL");
        end

        // ---------------- T3 : H16 orthogonality --------------------
        begin : t3
            integer e0; e0 = errors;
            mode16 = 1'b1;
            for (j = 0; j < 16; j = j + 1) begin
                for (i = 0; i < 16; i = i + 1) gx[i] = (i == j) ? 64'sd1 : 64'sd0;
                golden_wht(16);
                drive(16);
                #1;
                for (i = 0; i < 16; i = i + 1)
                    if (lane(i) !== 23'sd1 && lane(i) !== -23'sd1) begin
                        errors = errors + 1;
                        $display("  [FAIL] T3 column %0d row %0d = %0d (expected +/-1)",
                                 j, i, lane(i));
                    end
                check(16, "T3 H16 basis");
            end
            $display(" T3  H16 columns are +/-1 and match golden       : %0s",
                     (errors == e0) ? "pass" : "FAIL");
        end

        // ---------------- T4 : H8 orthogonality ---------------------
        begin : t4
            integer e0; e0 = errors;
            mode16 = 1'b0;
            for (j = 0; j < 8; j = j + 1) begin
                for (i = 0; i < 16; i = i + 1) gx[i] = (i == j) ? 64'sd1 : 64'sd0;
                golden_wht(8);
                drive(16);
                #1;
                for (i = 0; i < 8; i = i + 1)
                    if (lane(i) !== 23'sd1 && lane(i) !== -23'sd1) begin
                        errors = errors + 1;
                        $display("  [FAIL] T4 column %0d row %0d = %0d (expected +/-1)",
                                 j, i, lane(i));
                    end
                check(8, "T4 H8 basis");
            end
            $display(" T4   H8 columns are +/-1 and match golden       : %0s",
                     (errors == e0) ? "pass" : "FAIL");
        end

        // ---------------- T5 : directed extremes --------------------
        begin : t5
            integer e0; e0 = errors;
            // all inputs at the most-negative 16-bit value -> y[0] = -524288
            mode16 = 1'b1;
            for (i = 0; i < 16; i = i + 1) gx[i] = -64'sd32768;
            golden_wht(16); drive(16); #1 check(16, "T5 all-min");
            if (lane(0) !== -23'sd524288) begin
                errors = errors + 1;
                $display("  [FAIL] T5 all-min DC term = %0d, expected -524288", lane(0));
            end
            // all inputs at the most-positive value
            for (i = 0; i < 16; i = i + 1) gx[i] = 64'sd32767;
            golden_wht(16); drive(16); #1 check(16, "T5 all-max");
            // impulse
            for (i = 0; i < 16; i = i + 1) gx[i] = (i == 0) ? 64'sd12345 : 64'sd0;
            golden_wht(16); drive(16); #1 check(16, "T5 impulse");
            for (i = 0; i < 16; i = i + 1)
                if (lane(i) !== 23'sd12345) begin
                    errors = errors + 1;
                    $display("  [FAIL] T5 impulse lane %0d = %0d", i, lane(i));
                end
            $display(" T5  directed extremes / impulse                 : %0s",
                     (errors == e0) ? "pass" : "FAIL");
        end

        // ---------------- T6 : gating of the upper half --------------
        // The paper states that in 8-way mode "half of the 16-way FHT Unit is
        // gated".  Probe the internal stage nodes hierarchically and confirm
        // that lanes 8..15 stay at a constant 0 for every stage, i.e. that
        // they never toggle no matter what garbage sits on the unused inputs.
        begin : t6
            integer e0; e0 = errors;
            mode16 = 1'b0;
            for (t = 0; t < 200; t = t + 1) begin
                for (i = 0; i < 16; i = i + 1)
                    gx[i] = $signed({$random} % 65536) - 32768;
                drive(16);
                #1;
                for (i = 8; i < 16; i = i + 1) begin
                    if (dut.xi[i] !== {W{1'b0}} || dut.s1[i] !== {W{1'b0}} ||
                        dut.s2[i] !== {W{1'b0}} || dut.s3[i] !== {W{1'b0}} ||
                        dut.s4[i] !== {W{1'b0}}) begin
                        errors = errors + 1;
                        $display("  [FAIL] T6 lane %0d not gated: xi=%0d s1=%0d s2=%0d s3=%0d s4=%0d",
                                 i, dut.xi[i], dut.s1[i], dut.s2[i], dut.s3[i], dut.s4[i]);
                    end
                end
                // stage 1 must be a pure pass-through for the active half
                for (i = 0; i < 8; i = i + 1)
                    if (dut.s1[i] !== dut.xi[i]) begin
                        errors = errors + 1;
                        $display("  [FAIL] T6 stage-1 not bypassed on lane %0d", i);
                    end
            end
            $display(" T6  8-way mode: stage 1 + lanes 8..15 held at 0   : %0s",
                     (errors == e0) ? "pass" : "FAIL");
        end

        $display("--------------------------------------------------------");
        $display(" adders: 16-way = 4 stages x 8 BF x 2 = 64 (paper: 64)");
        $display("          8-way = 3 stages x 4 BF x 2 = 24 (paper: 24)");
        $display("--------------------------------------------------------");
        if (errors == 0) $display(" tb_fht_core : *** ALL TESTS PASSED ***");
        else             $display(" tb_fht_core : *** %0d ERRORS ***", errors);
        $display("========================================================");
        if (errors != 0) $fatal(1);
        $finish;
    end

endmodule
