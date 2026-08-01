// ===========================================================================
//  tb_power.v -- switching-activity workload for the single-path BF16 adder
//
//  Not a checking testbench (tb/tb_bf16_add.v does that).  This one only
//  drives back-to-back operand pairs and dumps a VCD so vcd2saif can produce
//  the SAIF that Design Compiler annotates for power.
//
//  The timescale is 1ps so the SAIF duration lands in the same time unit as
//  the ASAP7 library, which is what keeps the toggle rates (and therefore the
//  power numbers) on the right scale.
//
//  Plusargs
//    +mode=uniform  two independent uniform random operands.  Most pairs then
//                   differ by a large exponent, the small one is shifted out
//                   entirely and the normaliser barely moves -> LOW activity.
//    +mode=near     |ea - eb| <= 4 (default).  Alignment shifter, cancellation
//                   and the LZC + left shift are all exercised -> the case an
//                   accumulator or an FHT butterfly actually produces.
//    +nops=<n>      operations to drive (default 20000)
//    +period=<ps>   one operation every <ps> picoseconds (default 650)
// ===========================================================================
`timescale 1ps/1ps

module tb_power;

    reg  [15:0] a, b;
    wire [15:0] y;

    bf16_add #(.E(8), .M(7)) dut (
        .sa_i(a[15]), .ea_i(a[14:7]), .ma_i(a[6:0]),
        .sb_i(b[15]), .eb_i(b[14:7]), .mb_i(b[6:0]),
        .s_o(y[15]),  .e_o(y[14:7]),  .m_o(y[6:0])
    );

    integer seed = 32'h0BADF00D;
    integer nops, period, i;
    reg [1023:0] modestr;
    reg          near;

    // an all-ones exponent is Inf/NaN in IEEE and out of spec for this DUT
    function [15:0] sane;
        input [15:0] v;
        begin
            sane = (v[14:7] == 8'hFF) ? {v[15], 8'hFE, v[6:0]} : v;
        end
    endfunction

    function [15:0] rnd_near;               // exponent within +/-4 of av
        input [15:0] av;
        reg   [31:0] r;
        integer      delta, ee;
        begin
            r     = $random(seed);
            delta = (r[3:0] % 9) - 4;
            ee    = av[14:7] + delta;
            if (ee < 1)   ee = 1;
            if (ee > 254) ee = 254;
            rnd_near = {r[16], ee[7:0], r[6:0]};
        end
    endfunction

    initial begin
        if (!$value$plusargs("nops=%d",   nops))   nops   = 20000;
        if (!$value$plusargs("period=%d", period)) period = 650;
        near = 1'b1;
        if ($value$plusargs("mode=%s", modestr))
            near = (modestr[8*7-1:0] != "uniform");

        $display("tb_power: mode=%s nops=%0d period=%0dps",
                 near ? "near" : "uniform", nops, period);

        $dumpfile("bf16_add.vcd");
        $dumpvars(0, tb_power.dut);

        // settle before the window that vcd2saif measures
        a = 16'h3F80; b = 16'h3F80;
        #(period);

        for (i = 0; i < nops; i = i + 1) begin
            a = sane($random(seed));
            if (a[14:7] == 8'd0) a[14:7] = 8'd127;      // keep operands finite-nonzero
            b = near ? rnd_near(a) : sane($random(seed));
            #(period);
        end

        $display("tb_power: %0d ops driven over %0d ps", nops, nops*period);
        $finish;
    end

endmodule
