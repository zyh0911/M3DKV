// Generator : SpinalHDL v1.12.2    git head : f25edbcee624ef41548345cfb91c42060e33313f
// Component : softmax_block2

`timescale 1ns/1ps

module softmax_block2 #(
  parameter EXP_WIDTH                                       = 8,
  parameter MANTISSA_WIDTH                                  = 7,
  parameter SIGN_WIDTH                                      = 1,
  parameter FP_WIDTH                                        = 16,
  parameter PARALLEL_COL                                    = 16,
  parameter BANK_COL                                        = 1024
)(
  input  wire                                               clk,
  input  wire                                               rst_n,

  input  wire [PARALLEL_COL*FP_WIDTH-1:0]                   pi,
  input  wire                                               pi_valid,
  output wire                                               pi_ready,

  output wire [FP_WIDTH-1:0]                                pi_sum_recip,
  output wire                                               pi_sum_recip_valid,
  input wire                                                pi_sum_recip_ready
);
reg [FP_WIDTH-1:0] local_sum; 
reg local_sum_vld;
wire [FP_WIDTH-1:0] adder_out_0;
wire [FP_WIDTH-1:0] fp_adder_tree_out_payload;
wire fp_adder_tree_out_valid;
reg [$clog2(BANK_COL/PARALLEL_COL):0] counter;
wire counter_is_max;
wire counter_will_update_now;

assign counter_will_update_now = local_sum_vld;
assign counter_is_max = (counter == BANK_COL/PARALLEL_COL - 1);

always @(posedge clk or negedge rst_n) begin
  if (~rst_n) begin
    counter <= 0;
  end 
  else begin
    if (counter_will_update_now) begin
      counter <=  counter_is_max ? 0 : counter + 1;
    end 
    else begin
      counter <= counter;
    end
  end
end

always @(posedge clk or negedge rst_n) begin
  if (~rst_n) begin
    local_sum <= 0;
    local_sum_vld <= 0;
  end else begin
      local_sum_vld <= fp_adder_tree_out_valid;
      local_sum <= (local_sum_vld) ? adder_out_0 : local_sum;
  end
end

fp_adder_tree  fp_adder_tree_inst (
  .io_inlet_valid                 (pi_valid),
  .io_inlet_ready                 (pi_ready),
  .io_inlet_payload               (pi),
  .io_outlet_valid                (fp_adder_tree_out_valid),
  .io_outlet_ready                (1'b1),
  .io_outlet_payload              (fp_adder_tree_out_payload),
  .resetn                         (rst_n),
  .clk                            (clk)
);


fp_add_single_cycle # (
  .EXP_WIDTH                      (EXP_WIDTH),
  .MANTISSA_WIDTH                 (MANTISSA_WIDTH),
  .SIGN_WIDTH                     (SIGN_WIDTH),
  .FP_WIDTH                       (FP_WIDTH)
)u_fp_add_single_cycle_0 (
  .clk                            (clk),
  .rstn                           (rst_n),
  .add_a                          (fp_adder_tree_out_payload),
  .add_b                          (local_sum),
  .adder_out                      (adder_out_0)
);


reciprocal # (
    .EXP_WIDTH                      (EXP_WIDTH),
    .MANTISSA_WIDTH                 (MANTISSA_WIDTH),
    .SIGN_WIDTH                     (SIGN_WIDTH),
    .FP_WIDTH                       (FP_WIDTH)
)reciprocal_inst (              
    .clk                            (clk),
    .rst_n                          (rst_n),
    .input_data                     (local_sum),
    .input_data_valid               ((counter == BANK_COL/PARALLEL_COL - 1)),
    .input_data_ready               (),
    .output_data                    (pi_sum_recip),
    .output_data_valid              (pi_sum_recip_valid),
    .output_data_ready              (pi_sum_recip_ready)
);

// initial begin
//   $dumpfile("dump.vcd");
//   $dumpvars(0, softmax_block2);
// end
endmodule
