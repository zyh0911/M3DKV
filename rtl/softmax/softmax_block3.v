// Generator : SpinalHDL v1.12.2    git head : f25edbcee624ef41548345cfb91c42060e33313f
// Component : softmax_block2

`timescale 1ns/1ps

module softmax_block3 #(
  parameter EXP_WIDTH                                       = 8,
  parameter MANTISSA_WIDTH                                  = 7,
  parameter SIGN_WIDTH                                      = 1,
  parameter FP_WIDTH                                        = 16,
  parameter PARALLEL_ROW                                    = 32
)(
  input  wire                                               clk,
  input  wire                                               rst_n,

  input  wire [PARALLEL_ROW*FP_WIDTH-1:0]                   pi_mul_vi,
  input  wire [FP_WIDTH-1:0]                                pi_sum_recip,
  input  wire                                               idata_valid,
  output reg                                                idata_ready,

  output reg [PARALLEL_ROW*FP_WIDTH-1:0]                    odata,
  output reg                                                odata_valid,
  input wire                                                odata_ready
);

reg [$clog2(PARALLEL_ROW)-1:0] counter;
reg [$clog2(PARALLEL_ROW)-1:0] counter_result;
wire counter_is_max_now = (counter == PARALLEL_ROW-1);
wire counter_result_is_max_now = (counter_result == PARALLEL_ROW-1);
reg [PARALLEL_ROW*FP_WIDTH-1:0] pi_mul_vi_reg;
reg [FP_WIDTH-1:0] pi_sum_recip_reg;
reg [FP_WIDTH-1:0] mul_a;
reg [FP_WIDTH-1:0] mul_b;
wire [FP_WIDTH-1:0] mul_out;
reg [PARALLEL_ROW*FP_WIDTH-1:0] odata_reg;

reg [2:0] state, next_state;
localparam IDLE = 3'b000,
           CALC = 3'b001,
           DONE = 3'b010;

always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        state <= IDLE;
    end
    else begin
        state <= next_state;
    end
end

always @(*) begin
  begin
    case (state)
      IDLE: begin
        if (idata_valid) begin
          next_state = CALC;
        end
        else begin
          next_state = IDLE;
        end
      end

      CALC: begin
        if (counter_result_is_max_now) begin
          next_state = DONE;
        end
        else begin
          next_state = CALC;
        end
      end
      DONE: begin
        if (odata_valid & odata_ready) begin
          next_state = IDLE;
        end
        else begin
          next_state = DONE;
        end
      end

      default: begin
        next_state = IDLE;
      end

    endcase
  end
end

always @(*) begin
  case (state)
    IDLE: begin
      idata_ready = 1'b1;
      odata_valid = 1'b0;
    end

    CALC: begin
      idata_ready = 1'b0;
      odata_valid = 1'b0;
    end
    DONE: begin
      idata_ready = 1'b0;
      odata_valid = 1'b1;
    end
    default: begin
      idata_ready = 1'b0;
      odata_valid = 1'b0;
    end
  endcase
end

always @(posedge clk or negedge rst_n) begin
  if (~rst_n) begin
    pi_mul_vi_reg <= 0;
    pi_sum_recip_reg <= 0;
  end
  else if (state == IDLE & idata_valid) begin
    pi_mul_vi_reg <= pi_mul_vi;
    pi_sum_recip_reg <= pi_sum_recip;
  end 
  else begin
    pi_mul_vi_reg <= pi_mul_vi_reg;
    pi_sum_recip_reg <= pi_sum_recip_reg;
  end
end

always @(posedge clk or negedge rst_n) begin
  if (~rst_n) begin
    counter <= 0;
    counter_result <= 0;
  end
  else if (state == CALC) begin
    if (counter_is_max_now) begin
      counter <= counter;
    end
    else begin
      counter <= counter + 1;
    end
      counter_result <= counter;
  end
  else begin
    counter <= 0;
    counter_result <= 0;
  end
end

always @(*) begin
  mul_a = 0;
  mul_b = 0;
  odata = 0;
  case (state)
    CALC: begin
      mul_a = pi_mul_vi_reg[FP_WIDTH*counter +:FP_WIDTH];
      mul_b = pi_sum_recip_reg;
    end
    DONE: begin
      odata = odata_reg;
    end
    default: begin
      mul_a = 0;
      mul_b = 0;
      odata = 0;
    end 
  endcase
end

always @(posedge clk or negedge rst_n) begin
  if (~rst_n) begin
    odata_reg <= 0;
  end
  else if (state == CALC) begin
    odata_reg[FP_WIDTH*counter_result +: FP_WIDTH] <= mul_out;
  end
end

fp_mul_single_cycle # (
    .EXP_WIDTH                (EXP_WIDTH),
    .MANTISSA_WIDTH           (MANTISSA_WIDTH),
    .FP_WIDTH                 (FP_WIDTH)
  )fp_mul_single_cycle_inst (
    .clk                      (clk),
    .rstn                     (rst_n),
    .mul_a                    (mul_a),
    .mul_b                    (mul_b),
    .mul_out                  (mul_out)
  );

// initial begin
//     $dumpfile("dump.vcd");
//     $dumpvars(0, softmax_block3);
// end
  
endmodule
