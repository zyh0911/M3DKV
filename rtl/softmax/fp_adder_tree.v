// Generator : SpinalHDL v1.12.2    git head : f25edbcee624ef41548345cfb91c42060e33313f
// Component : FP_AddTree

`timescale 1ns/1ps

module fp_adder_tree (
  input  wire          io_inlet_valid,
  output wire          io_inlet_ready,
  input  wire [511:0]  io_inlet_payload,
  output wire          io_outlet_valid,
  input  wire          io_outlet_ready,
  output wire [15:0]   io_outlet_payload,
  input  wire          resetn,
  input  wire          clk
);

  wire       [15:0]   fpadd_adder_out;
  wire       [15:0]   fpadd_1_adder_out;
  wire       [15:0]   fpadd_2_adder_out;
  wire       [15:0]   fpadd_3_adder_out;
  wire       [15:0]   fpadd_4_adder_out;
  wire       [15:0]   fpadd_5_adder_out;
  wire       [15:0]   fpadd_6_adder_out;
  wire       [15:0]   fpadd_7_adder_out;
  wire       [15:0]   fpadd_8_adder_out;
  wire       [15:0]   fpadd_9_adder_out;
  wire       [15:0]   fpadd_10_adder_out;
  wire       [15:0]   fpadd_11_adder_out;
  wire       [15:0]   fpadd_12_adder_out;
  wire       [15:0]   fpadd_13_adder_out;
  wire       [15:0]   fpadd_14_adder_out;
  wire       [15:0]   fpadd_15_adder_out;
  wire       [15:0]   fpadd_16_adder_out;
  wire       [15:0]   fpadd_17_adder_out;
  wire       [15:0]   fpadd_18_adder_out;
  wire       [15:0]   fpadd_19_adder_out;
  wire       [15:0]   fpadd_20_adder_out;
  wire       [15:0]   fpadd_21_adder_out;
  wire       [15:0]   fpadd_22_adder_out;
  wire       [15:0]   fpadd_23_adder_out;
  wire       [15:0]   fpadd_24_adder_out;
  wire       [15:0]   fpadd_25_adder_out;
  wire       [15:0]   fpadd_26_adder_out;
  wire       [15:0]   fpadd_27_adder_out;
  wire       [15:0]   fpadd_28_adder_out;
  wire       [15:0]   fpadd_29_adder_out;
  wire       [15:0]   fpadd_30_adder_out;
  reg        [511:0]  buf_1;
  wire                io_inlet_fire;
  wire       [15:0]   vecBuf_0;
  wire       [15:0]   vecBuf_1;
  wire       [15:0]   vecBuf_2;
  wire       [15:0]   vecBuf_3;
  wire       [15:0]   vecBuf_4;
  wire       [15:0]   vecBuf_5;
  wire       [15:0]   vecBuf_6;
  wire       [15:0]   vecBuf_7;
  wire       [15:0]   vecBuf_8;
  wire       [15:0]   vecBuf_9;
  wire       [15:0]   vecBuf_10;
  wire       [15:0]   vecBuf_11;
  wire       [15:0]   vecBuf_12;
  wire       [15:0]   vecBuf_13;
  wire       [15:0]   vecBuf_14;
  wire       [15:0]   vecBuf_15;
  wire       [15:0]   vecBuf_16;
  wire       [15:0]   vecBuf_17;
  wire       [15:0]   vecBuf_18;
  wire       [15:0]   vecBuf_19;
  wire       [15:0]   vecBuf_20;
  wire       [15:0]   vecBuf_21;
  wire       [15:0]   vecBuf_22;
  wire       [15:0]   vecBuf_23;
  wire       [15:0]   vecBuf_24;
  wire       [15:0]   vecBuf_25;
  wire       [15:0]   vecBuf_26;
  wire       [15:0]   vecBuf_27;
  wire       [15:0]   vecBuf_28;
  wire       [15:0]   vecBuf_29;
  wire       [15:0]   vecBuf_30;
  wire       [15:0]   vecBuf_31;
  reg                 io_inlet_fire_delay_1;
  reg                 io_inlet_fire_delay_2;
  reg                 io_inlet_fire_delay_3;
  reg                 io_inlet_fire_delay_4;
  reg                 io_inlet_fire_delay_5;
  reg                 vPipe;

  fp_add_single_cycle #(
    .EXP_WIDTH      (8 ),
    .MANTISSA_WIDTH (7 ),
    .SIGN_WIDTH     (1 ),
    .FP_WIDTH       (16)
  ) fpadd (
    .clk       (clk                  ), //i
    .rstn      (resetn               ), //i
    .add_a     (vecBuf_0[15:0]       ), //i
    .add_b     (vecBuf_1[15:0]       ), //i
    .adder_out (fpadd_adder_out[15:0])  //o
  );
  fp_add_single_cycle #(
    .EXP_WIDTH      (8 ),
    .MANTISSA_WIDTH (7 ),
    .SIGN_WIDTH     (1 ),
    .FP_WIDTH       (16)
  ) fpadd_1 (
    .clk       (clk                    ), //i
    .rstn      (resetn                 ), //i
    .add_a     (vecBuf_2[15:0]         ), //i
    .add_b     (vecBuf_3[15:0]         ), //i
    .adder_out (fpadd_1_adder_out[15:0])  //o
  );
  fp_add_single_cycle #(
    .EXP_WIDTH      (8 ),
    .MANTISSA_WIDTH (7 ),
    .SIGN_WIDTH     (1 ),
    .FP_WIDTH       (16)
  ) fpadd_2 (
    .clk       (clk                    ), //i
    .rstn      (resetn                 ), //i
    .add_a     (vecBuf_4[15:0]         ), //i
    .add_b     (vecBuf_5[15:0]         ), //i
    .adder_out (fpadd_2_adder_out[15:0])  //o
  );
  fp_add_single_cycle #(
    .EXP_WIDTH      (8 ),
    .MANTISSA_WIDTH (7 ),
    .SIGN_WIDTH     (1 ),
    .FP_WIDTH       (16)
  ) fpadd_3 (
    .clk       (clk                    ), //i
    .rstn      (resetn                 ), //i
    .add_a     (vecBuf_6[15:0]         ), //i
    .add_b     (vecBuf_7[15:0]         ), //i
    .adder_out (fpadd_3_adder_out[15:0])  //o
  );
  fp_add_single_cycle #(
    .EXP_WIDTH      (8 ),
    .MANTISSA_WIDTH (7 ),
    .SIGN_WIDTH     (1 ),
    .FP_WIDTH       (16)
  ) fpadd_4 (
    .clk       (clk                    ), //i
    .rstn      (resetn                 ), //i
    .add_a     (vecBuf_8[15:0]         ), //i
    .add_b     (vecBuf_9[15:0]         ), //i
    .adder_out (fpadd_4_adder_out[15:0])  //o
  );
  fp_add_single_cycle #(
    .EXP_WIDTH      (8 ),
    .MANTISSA_WIDTH (7 ),
    .SIGN_WIDTH     (1 ),
    .FP_WIDTH       (16)
  ) fpadd_5 (
    .clk       (clk                    ), //i
    .rstn      (resetn                 ), //i
    .add_a     (vecBuf_10[15:0]        ), //i
    .add_b     (vecBuf_11[15:0]        ), //i
    .adder_out (fpadd_5_adder_out[15:0])  //o
  );
  fp_add_single_cycle #(
    .EXP_WIDTH      (8 ),
    .MANTISSA_WIDTH (7 ),
    .SIGN_WIDTH     (1 ),
    .FP_WIDTH       (16)
  ) fpadd_6 (
    .clk       (clk                    ), //i
    .rstn      (resetn                 ), //i
    .add_a     (vecBuf_12[15:0]        ), //i
    .add_b     (vecBuf_13[15:0]        ), //i
    .adder_out (fpadd_6_adder_out[15:0])  //o
  );
  fp_add_single_cycle #(
    .EXP_WIDTH      (8 ),
    .MANTISSA_WIDTH (7 ),
    .SIGN_WIDTH     (1 ),
    .FP_WIDTH       (16)
  ) fpadd_7 (
    .clk       (clk                    ), //i
    .rstn      (resetn                 ), //i
    .add_a     (vecBuf_14[15:0]        ), //i
    .add_b     (vecBuf_15[15:0]        ), //i
    .adder_out (fpadd_7_adder_out[15:0])  //o
  );
  fp_add_single_cycle #(
    .EXP_WIDTH      (8 ),
    .MANTISSA_WIDTH (7 ),
    .SIGN_WIDTH     (1 ),
    .FP_WIDTH       (16)
  ) fpadd_8 (
    .clk       (clk                    ), //i
    .rstn      (resetn                 ), //i
    .add_a     (vecBuf_16[15:0]        ), //i
    .add_b     (vecBuf_17[15:0]        ), //i
    .adder_out (fpadd_8_adder_out[15:0])  //o
  );
  fp_add_single_cycle #(
    .EXP_WIDTH      (8 ),
    .MANTISSA_WIDTH (7 ),
    .SIGN_WIDTH     (1 ),
    .FP_WIDTH       (16)
  ) fpadd_9 (
    .clk       (clk                    ), //i
    .rstn      (resetn                 ), //i
    .add_a     (vecBuf_18[15:0]        ), //i
    .add_b     (vecBuf_19[15:0]        ), //i
    .adder_out (fpadd_9_adder_out[15:0])  //o
  );
  fp_add_single_cycle #(
    .EXP_WIDTH      (8 ),
    .MANTISSA_WIDTH (7 ),
    .SIGN_WIDTH     (1 ),
    .FP_WIDTH       (16)
  ) fpadd_10 (
    .clk       (clk                     ), //i
    .rstn      (resetn                  ), //i
    .add_a     (vecBuf_20[15:0]         ), //i
    .add_b     (vecBuf_21[15:0]         ), //i
    .adder_out (fpadd_10_adder_out[15:0])  //o
  );
  fp_add_single_cycle #(
    .EXP_WIDTH      (8 ),
    .MANTISSA_WIDTH (7 ),
    .SIGN_WIDTH     (1 ),
    .FP_WIDTH       (16)
  ) fpadd_11 (
    .clk       (clk                     ), //i
    .rstn      (resetn                  ), //i
    .add_a     (vecBuf_22[15:0]         ), //i
    .add_b     (vecBuf_23[15:0]         ), //i
    .adder_out (fpadd_11_adder_out[15:0])  //o
  );
  fp_add_single_cycle #(
    .EXP_WIDTH      (8 ),
    .MANTISSA_WIDTH (7 ),
    .SIGN_WIDTH     (1 ),
    .FP_WIDTH       (16)
  ) fpadd_12 (
    .clk       (clk                     ), //i
    .rstn      (resetn                  ), //i
    .add_a     (vecBuf_24[15:0]         ), //i
    .add_b     (vecBuf_25[15:0]         ), //i
    .adder_out (fpadd_12_adder_out[15:0])  //o
  );
  fp_add_single_cycle #(
    .EXP_WIDTH      (8 ),
    .MANTISSA_WIDTH (7 ),
    .SIGN_WIDTH     (1 ),
    .FP_WIDTH       (16)
  ) fpadd_13 (
    .clk       (clk                     ), //i
    .rstn      (resetn                  ), //i
    .add_a     (vecBuf_26[15:0]         ), //i
    .add_b     (vecBuf_27[15:0]         ), //i
    .adder_out (fpadd_13_adder_out[15:0])  //o
  );
  fp_add_single_cycle #(
    .EXP_WIDTH      (8 ),
    .MANTISSA_WIDTH (7 ),
    .SIGN_WIDTH     (1 ),
    .FP_WIDTH       (16)
  ) fpadd_14 (
    .clk       (clk                     ), //i
    .rstn      (resetn                  ), //i
    .add_a     (vecBuf_28[15:0]         ), //i
    .add_b     (vecBuf_29[15:0]         ), //i
    .adder_out (fpadd_14_adder_out[15:0])  //o
  );
  fp_add_single_cycle #(
    .EXP_WIDTH      (8 ),
    .MANTISSA_WIDTH (7 ),
    .SIGN_WIDTH     (1 ),
    .FP_WIDTH       (16)
  ) fpadd_15 (
    .clk       (clk                     ), //i
    .rstn      (resetn                  ), //i
    .add_a     (vecBuf_30[15:0]         ), //i
    .add_b     (vecBuf_31[15:0]         ), //i
    .adder_out (fpadd_15_adder_out[15:0])  //o
  );
  fp_add_single_cycle #(
    .EXP_WIDTH      (8 ),
    .MANTISSA_WIDTH (7 ),
    .SIGN_WIDTH     (1 ),
    .FP_WIDTH       (16)
  ) fpadd_16 (
    .clk       (clk                     ), //i
    .rstn      (resetn                  ), //i
    .add_a     (fpadd_adder_out[15:0]   ), //i
    .add_b     (fpadd_1_adder_out[15:0] ), //i
    .adder_out (fpadd_16_adder_out[15:0])  //o
  );
  fp_add_single_cycle #(
    .EXP_WIDTH      (8 ),
    .MANTISSA_WIDTH (7 ),
    .SIGN_WIDTH     (1 ),
    .FP_WIDTH       (16)
  ) fpadd_17 (
    .clk       (clk                     ), //i
    .rstn      (resetn                  ), //i
    .add_a     (fpadd_2_adder_out[15:0] ), //i
    .add_b     (fpadd_3_adder_out[15:0] ), //i
    .adder_out (fpadd_17_adder_out[15:0])  //o
  );
  fp_add_single_cycle #(
    .EXP_WIDTH      (8 ),
    .MANTISSA_WIDTH (7 ),
    .SIGN_WIDTH     (1 ),
    .FP_WIDTH       (16)
  ) fpadd_18 (
    .clk       (clk                     ), //i
    .rstn      (resetn                  ), //i
    .add_a     (fpadd_4_adder_out[15:0] ), //i
    .add_b     (fpadd_5_adder_out[15:0] ), //i
    .adder_out (fpadd_18_adder_out[15:0])  //o
  );
  fp_add_single_cycle #(
    .EXP_WIDTH      (8 ),
    .MANTISSA_WIDTH (7 ),
    .SIGN_WIDTH     (1 ),
    .FP_WIDTH       (16)
  ) fpadd_19 (
    .clk       (clk                     ), //i
    .rstn      (resetn                  ), //i
    .add_a     (fpadd_6_adder_out[15:0] ), //i
    .add_b     (fpadd_7_adder_out[15:0] ), //i
    .adder_out (fpadd_19_adder_out[15:0])  //o
  );
  fp_add_single_cycle #(
    .EXP_WIDTH      (8 ),
    .MANTISSA_WIDTH (7 ),
    .SIGN_WIDTH     (1 ),
    .FP_WIDTH       (16)
  ) fpadd_20 (
    .clk       (clk                     ), //i
    .rstn      (resetn                  ), //i
    .add_a     (fpadd_8_adder_out[15:0] ), //i
    .add_b     (fpadd_9_adder_out[15:0] ), //i
    .adder_out (fpadd_20_adder_out[15:0])  //o
  );
  fp_add_single_cycle #(
    .EXP_WIDTH      (8 ),
    .MANTISSA_WIDTH (7 ),
    .SIGN_WIDTH     (1 ),
    .FP_WIDTH       (16)
  ) fpadd_21 (
    .clk       (clk                     ), //i
    .rstn      (resetn                  ), //i
    .add_a     (fpadd_10_adder_out[15:0]), //i
    .add_b     (fpadd_11_adder_out[15:0]), //i
    .adder_out (fpadd_21_adder_out[15:0])  //o
  );
  fp_add_single_cycle #(
    .EXP_WIDTH      (8 ),
    .MANTISSA_WIDTH (7 ),
    .SIGN_WIDTH     (1 ),
    .FP_WIDTH       (16)
  ) fpadd_22 (
    .clk       (clk                     ), //i
    .rstn      (resetn                  ), //i
    .add_a     (fpadd_12_adder_out[15:0]), //i
    .add_b     (fpadd_13_adder_out[15:0]), //i
    .adder_out (fpadd_22_adder_out[15:0])  //o
  );
  fp_add_single_cycle #(
    .EXP_WIDTH      (8 ),
    .MANTISSA_WIDTH (7 ),
    .SIGN_WIDTH     (1 ),
    .FP_WIDTH       (16)
  ) fpadd_23 (
    .clk       (clk                     ), //i
    .rstn      (resetn                  ), //i
    .add_a     (fpadd_14_adder_out[15:0]), //i
    .add_b     (fpadd_15_adder_out[15:0]), //i
    .adder_out (fpadd_23_adder_out[15:0])  //o
  );
  fp_add_single_cycle #(
    .EXP_WIDTH      (8 ),
    .MANTISSA_WIDTH (7 ),
    .SIGN_WIDTH     (1 ),
    .FP_WIDTH       (16)
  ) fpadd_24 (
    .clk       (clk                     ), //i
    .rstn      (resetn                  ), //i
    .add_a     (fpadd_16_adder_out[15:0]), //i
    .add_b     (fpadd_17_adder_out[15:0]), //i
    .adder_out (fpadd_24_adder_out[15:0])  //o
  );
  fp_add_single_cycle #(
    .EXP_WIDTH      (8 ),
    .MANTISSA_WIDTH (7 ),
    .SIGN_WIDTH     (1 ),
    .FP_WIDTH       (16)
  ) fpadd_25 (
    .clk       (clk                     ), //i
    .rstn      (resetn                  ), //i
    .add_a     (fpadd_18_adder_out[15:0]), //i
    .add_b     (fpadd_19_adder_out[15:0]), //i
    .adder_out (fpadd_25_adder_out[15:0])  //o
  );
  fp_add_single_cycle #(
    .EXP_WIDTH      (8 ),
    .MANTISSA_WIDTH (7 ),
    .SIGN_WIDTH     (1 ),
    .FP_WIDTH       (16)
  ) fpadd_26 (
    .clk       (clk                     ), //i
    .rstn      (resetn                  ), //i
    .add_a     (fpadd_20_adder_out[15:0]), //i
    .add_b     (fpadd_21_adder_out[15:0]), //i
    .adder_out (fpadd_26_adder_out[15:0])  //o
  );
  fp_add_single_cycle #(
    .EXP_WIDTH      (8 ),
    .MANTISSA_WIDTH (7 ),
    .SIGN_WIDTH     (1 ),
    .FP_WIDTH       (16)
  ) fpadd_27 (
    .clk       (clk                     ), //i
    .rstn      (resetn                  ), //i
    .add_a     (fpadd_22_adder_out[15:0]), //i
    .add_b     (fpadd_23_adder_out[15:0]), //i
    .adder_out (fpadd_27_adder_out[15:0])  //o
  );
  fp_add_single_cycle #(
    .EXP_WIDTH      (8 ),
    .MANTISSA_WIDTH (7 ),
    .SIGN_WIDTH     (1 ),
    .FP_WIDTH       (16)
  ) fpadd_28 (
    .clk       (clk                     ), //i
    .rstn      (resetn                  ), //i
    .add_a     (fpadd_24_adder_out[15:0]), //i
    .add_b     (fpadd_25_adder_out[15:0]), //i
    .adder_out (fpadd_28_adder_out[15:0])  //o
  );
  fp_add_single_cycle #(
    .EXP_WIDTH      (8 ),
    .MANTISSA_WIDTH (7 ),
    .SIGN_WIDTH     (1 ),
    .FP_WIDTH       (16)
  ) fpadd_29 (
    .clk       (clk                     ), //i
    .rstn      (resetn                  ), //i
    .add_a     (fpadd_26_adder_out[15:0]), //i
    .add_b     (fpadd_27_adder_out[15:0]), //i
    .adder_out (fpadd_29_adder_out[15:0])  //o
  );
  fp_add_single_cycle #(
    .EXP_WIDTH      (8 ),
    .MANTISSA_WIDTH (7 ),
    .SIGN_WIDTH     (1 ),
    .FP_WIDTH       (16)
  ) fpadd_30 (
    .clk       (clk                     ), //i
    .rstn      (resetn                  ), //i
    .add_a     (fpadd_28_adder_out[15:0]), //i
    .add_b     (fpadd_29_adder_out[15:0]), //i
    .adder_out (fpadd_30_adder_out[15:0])  //o
  );
  assign io_inlet_fire = (io_inlet_valid && io_inlet_ready);
  assign io_inlet_ready = (! (io_outlet_valid && (! io_outlet_ready)));
  assign vecBuf_0 = buf_1[15 : 0];
  assign vecBuf_1 = buf_1[31 : 16];
  assign vecBuf_2 = buf_1[47 : 32];
  assign vecBuf_3 = buf_1[63 : 48];
  assign vecBuf_4 = buf_1[79 : 64];
  assign vecBuf_5 = buf_1[95 : 80];
  assign vecBuf_6 = buf_1[111 : 96];
  assign vecBuf_7 = buf_1[127 : 112];
  assign vecBuf_8 = buf_1[143 : 128];
  assign vecBuf_9 = buf_1[159 : 144];
  assign vecBuf_10 = buf_1[175 : 160];
  assign vecBuf_11 = buf_1[191 : 176];
  assign vecBuf_12 = buf_1[207 : 192];
  assign vecBuf_13 = buf_1[223 : 208];
  assign vecBuf_14 = buf_1[239 : 224];
  assign vecBuf_15 = buf_1[255 : 240];
  assign vecBuf_16 = buf_1[271 : 256];
  assign vecBuf_17 = buf_1[287 : 272];
  assign vecBuf_18 = buf_1[303 : 288];
  assign vecBuf_19 = buf_1[319 : 304];
  assign vecBuf_20 = buf_1[335 : 320];
  assign vecBuf_21 = buf_1[351 : 336];
  assign vecBuf_22 = buf_1[367 : 352];
  assign vecBuf_23 = buf_1[383 : 368];
  assign vecBuf_24 = buf_1[399 : 384];
  assign vecBuf_25 = buf_1[415 : 400];
  assign vecBuf_26 = buf_1[431 : 416];
  assign vecBuf_27 = buf_1[447 : 432];
  assign vecBuf_28 = buf_1[463 : 448];
  assign vecBuf_29 = buf_1[479 : 464];
  assign vecBuf_30 = buf_1[495 : 480];
  assign vecBuf_31 = buf_1[511 : 496];
  assign io_outlet_valid = vPipe;
  assign io_outlet_payload = fpadd_30_adder_out;
  always @(posedge clk) begin
    if(io_inlet_fire) begin
      buf_1 <= io_inlet_payload;
    end
  end

  always @(posedge clk or negedge resetn) begin
    if(!resetn) begin
      io_inlet_fire_delay_1 <= 1'b0;
      io_inlet_fire_delay_2 <= 1'b0;
      io_inlet_fire_delay_3 <= 1'b0;
      io_inlet_fire_delay_4 <= 1'b0;
      io_inlet_fire_delay_5 <= 1'b0;
      vPipe <= 1'b0;
    end else begin
      io_inlet_fire_delay_1 <= io_inlet_fire;
      io_inlet_fire_delay_2 <= io_inlet_fire_delay_1;
      io_inlet_fire_delay_3 <= io_inlet_fire_delay_2;
      io_inlet_fire_delay_4 <= io_inlet_fire_delay_3;
      io_inlet_fire_delay_5 <= io_inlet_fire_delay_4;
      vPipe <= io_inlet_fire_delay_5;
    end
  end


endmodule
