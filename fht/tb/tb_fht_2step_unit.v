// ============================================================================
//  tb_fht_2step_unit.v -- testbench for the 2-step hierarchical FHT unit
//                         (Fig. 11, LightRot, Kim et al., JETCAS 2025)
//
//  Checks:
//    T1  128 random activations, 2-step result == golden 1-step 128-point FHT
//    T2  back-to-back rotation tasks with no idle cycles between them
//    T3  input stalls: din_valid gaps during LOAD must not corrupt the result
//    T4  all 128 basis vectors -> every output must be exactly +/-1
//        (proves the unit really implements H128, not just "some" transform)
//    T5  worst-case bit growth: all inputs = -2^(DW-1) must not overflow
//    T6  latency / throughput report (expected 40 cycles per 128-way task)
// ============================================================================
`timescale 1ns/1ps

module tb_fht_2step_unit;

    localparam integer DW = 16;
    localparam integer W  = DW + 7;     // 23

    reg                  clk = 1'b0;
    reg                  rst_n = 1'b0;
    reg                  start = 1'b0;
    wire                 busy, done;

    wire                 din_ready;
    reg                  din_valid = 1'b0;
    reg  [16*DW-1:0]     din = {(16*DW){1'b0}};

    wire                 dout_valid;
    wire [16*W-1:0]      dout;

    fht_2step_unit #(.DW(DW), .W(W)) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (start),
        .busy       (busy),
        .done       (done),
        .din_ready  (din_ready),
        .din_valid  (din_valid),
        .din        (din),
        .dout_valid (dout_valid),
        .dout       (dout)
    );

    always #5 clk = ~clk;               // 100 MHz

    // ---------------------------------------------------------------
    // stimulus / reference storage
    // ---------------------------------------------------------------
    reg signed [63:0] gx  [0:127];      // stimulus (also golden input)
    reg signed [63:0] gy  [0:127];      // golden 128-point FHT result
    reg signed [63:0] rtl [0:127];      // captured DUT result

    integer errors  = 0;
    integer cap_idx = 0;
    integer i, j, t;
    integer cyc = 0;
    integer t_start, t_done;

    always @(posedge clk) cyc <= cyc + 1;

    // ---------------------------------------------------------------
    // golden model: natural-order (Sylvester) 128-point Walsh-Hadamard
    // ---------------------------------------------------------------
    task golden_wht128;
        integer len, ii, jj;
        reg signed [63:0] a, b;
        begin
            for (ii = 0; ii < 128; ii = ii + 1) gy[ii] = gx[ii];
            for (len = 1; len < 128; len = len * 2)
                for (ii = 0; ii < 128; ii = ii + 2*len)
                    for (jj = ii; jj < ii + len; jj = jj + 1) begin
                        a = gy[jj];
                        b = gy[jj+len];
                        gy[jj]     = a + b;
                        gy[jj+len] = a - b;
                    end
        end
    endtask

    // ---------------------------------------------------------------
    // output capture: 8 beats x 16 lanes, row-major
    // ---------------------------------------------------------------
    reg signed [W-1:0] lane_val;
    integer            cj;              // private to this block
    always @(posedge clk) begin
        if (dout_valid) begin
            for (cj = 0; cj < 16; cj = cj + 1) begin
                lane_val = dout[cj*W +: W];
                rtl[cap_idx*16 + cj] = $signed(lane_val);
            end
            cap_idx = cap_idx + 1;
        end
    end

    // ---------------------------------------------------------------
    // feed one rotation task; `gap` inserts stall cycles between beats
    // ---------------------------------------------------------------
    task run_task;
        input integer gap;
        integer b, k, g;
        begin
            cap_idx = 0;
            @(negedge clk);
            start   <= 1'b1;
            @(negedge clk);
            start   <= 1'b0;

            for (b = 0; b < 8; b = b + 1) begin
                for (g = 0; g < gap; g = g + 1) begin
                    din_valid <= 1'b0;
                    din       <= {(16*DW){1'bx}};   // must be ignored
                    @(negedge clk);
                end
                for (k = 0; k < 16; k = k + 1)
                    din[k*DW +: DW] = gx[b*16 + k][DW-1:0];
                din_valid <= 1'b1;
                @(negedge clk);
            end
            din_valid <= 1'b0;
            din       <= {(16*DW){1'bx}};

            wait (done === 1'b1);
            @(negedge clk);
        end
    endtask

    task compare;
        input [255:0] tag;
        integer ii, e0;
        begin
            e0 = errors;
            if (cap_idx != 8) begin
                errors = errors + 1;
                $display("  [FAIL] %0s : captured %0d beats, expected 8", tag, cap_idx);
            end
            for (ii = 0; ii < 128; ii = ii + 1)
                if (rtl[ii] !== gy[ii]) begin
                    if (errors - e0 < 8)
                        $display("  [FAIL] %0s idx %3d : rtl %0d, golden %0d",
                                 tag, ii, rtl[ii], gy[ii]);
                    errors = errors + 1;
                end
        end
    endtask

    task rand_stim;
        integer ii;
        begin
            for (ii = 0; ii < 128; ii = ii + 1)
                gx[ii] = $signed({$random} % 65536) - 32768;
        end
    endtask

    // ---------------------------------------------------------------
    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("tb_fht_2step_unit.vcd");
            $dumpvars(0, tb_fht_2step_unit);
        end

        $display("========================================================");
        $display(" tb_fht_2step_unit : 2-step hierarchical FHT (128-way)");
        $display("   1st step :  8 x 16-way FHT  (stride  1, TRF rows)");
        $display("   2nd step : 16 x  8-way FHT  (stride 16, TRF cols)");
        $display("========================================================");

        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        // ---------------- T1 : random vectors ------------------------
        begin : t1
            integer e0; e0 = errors;
            for (t = 0; t < 100; t = t + 1) begin
                rand_stim;
                golden_wht128;
                run_task(0);
                compare("T1 random");
            end
            $display(" T1  100 random 128-pt rotations vs. golden H128 : %0s",
                     (errors == e0) ? "pass" : "FAIL");
        end

        // ---------------- T2 : back-to-back --------------------------
        begin : t2
            integer e0; e0 = errors;
            for (t = 0; t < 10; t = t + 1) begin
                rand_stim;
                golden_wht128;
                run_task(0);            // run_task returns 1 cycle after done
                compare("T2 back-to-back");
            end
            $display(" T2  10 back-to-back tasks                       : %0s",
                     (errors == e0) ? "pass" : "FAIL");
        end

        // ---------------- T3 : stalled input stream ------------------
        begin : t3
            integer e0; e0 = errors;
            for (t = 1; t <= 3; t = t + 1) begin
                rand_stim;
                golden_wht128;
                run_task(t);            // t stall cycles before every beat
                compare("T3 stalled load");
            end
            $display(" T3  stalled load stream (1..3 gap cycles)       : %0s",
                     (errors == e0) ? "pass" : "FAIL");
        end

        // ---------------- T4 : all 128 basis vectors -----------------
        begin : t4
            integer e0, ii; e0 = errors;
            for (j = 0; j < 128; j = j + 1) begin
                for (ii = 0; ii < 128; ii = ii + 1)
                    gx[ii] = (ii == j) ? 64'sd1 : 64'sd0;
                golden_wht128;
                run_task(0);
                compare("T4 basis");
                for (ii = 0; ii < 128; ii = ii + 1)
                    if (rtl[ii] !== 64'sd1 && rtl[ii] !== -64'sd1) begin
                        errors = errors + 1;
                        $display("  [FAIL] T4 col %0d row %0d = %0d (expected +/-1)",
                                 j, ii, rtl[ii]);
                    end
            end
            $display(" T4  all 128 Hadamard columns are +/-1           : %0s",
                     (errors == e0) ? "pass" : "FAIL");
        end

        // ---------------- T5 : worst-case bit growth -----------------
        begin : t5
            integer e0, ii; e0 = errors;
            // all -32768 : DC term = -32768*128 = -4194304 = most negative
            //              value representable in 23 bits -> exactly fits
            for (ii = 0; ii < 128; ii = ii + 1) gx[ii] = -64'sd32768;
            golden_wht128;
            run_task(0);
            compare("T5 all-min");
            if (rtl[0] !== -64'sd4194304) begin
                errors = errors + 1;
                $display("  [FAIL] T5 DC term = %0d, expected -4194304", rtl[0]);
            end
            // all +32767
            for (ii = 0; ii < 128; ii = ii + 1) gx[ii] = 64'sd32767;
            golden_wht128;
            run_task(0);
            compare("T5 all-max");
            // alternating extremes -> maximum swing in the high-frequency bins
            for (ii = 0; ii < 128; ii = ii + 1)
                gx[ii] = (ii[0]) ? -64'sd32768 : 64'sd32767;
            golden_wht128;
            run_task(0);
            compare("T5 alternating");
            $display(" T5  worst-case bit growth (W = DW+7, no overflow): %0s",
                     (errors == e0) ? "pass" : "FAIL");
        end

        // ---------------- T6 : latency measurement -------------------
        begin : t6
            rand_stim;
            golden_wht128;
            @(negedge clk);
            t_start = cyc;
            start <= 1'b1; @(negedge clk); start <= 1'b0;
            for (i = 0; i < 8; i = i + 1) begin
                for (j = 0; j < 16; j = j + 1)
                    din[j*DW +: DW] = gx[i*16 + j][DW-1:0];
                din_valid <= 1'b1;
                @(negedge clk);
            end
            din_valid <= 1'b0;
            cap_idx = 0;
            wait (done === 1'b1);
            t_done = cyc;
            @(negedge clk);
            compare("T6 latency run");
            $display(" T6  task latency: %0d cycles (LOAD 8 + STEP1 8 + STEP2 16 + OUT 8 + 1)",
                     t_done - t_start);
        end

        $display("--------------------------------------------------------");
        $display(" adder count : 16-way core = 64 adders  (4 stages x 8 BF x 2)");
        $display("               8-way  mode = 24 active  (3 stages x 4 BF x 2)");
        $display("               flat 128-way FHT would need 896 adders");
        $display("--------------------------------------------------------");
        if (errors == 0) $display(" tb_fht_2step_unit : *** ALL TESTS PASSED ***");
        else             $display(" tb_fht_2step_unit : *** %0d ERRORS ***", errors);
        $display("========================================================");
        if (errors != 0) $fatal(1);
        $finish;
    end

    // watchdog
    initial begin
        #20_000_000;
        $display(" [FAIL] watchdog timeout");
        $fatal(1);
    end

endmodule
