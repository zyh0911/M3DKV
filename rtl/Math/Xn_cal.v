module Xn_cal #(
    parameter EXP_WIDTH = 8,
    parameter MANTISSA_WIDTH = 7,
    parameter SIGN_WIDTH = 1,
    parameter FP_WIDTH = 16
) (
    input                                  clk, 
    input                                  rst_n,
    input      [FP_WIDTH-1:0]              D,
    input      [FP_WIDTH-1:0]              Xn,    
    input                                  Xn_valid,
    output                                 Xn_ready,
    output reg [FP_WIDTH-1:0]              Xn1,      
    output reg                             Xn1_valid,
    input                                  Xn1_ready
);

localparam constant3 = 16'h4000;

// Xn1 = Xn * (2-D*Xn)
reg [FP_WIDTH-1:0] term1,term2;
reg term1_valid,term2_valid;
reg [FP_WIDTH-1:0] Xn_reg1,Xn_reg2;

wire stall = Xn1_valid && ~Xn1_ready;
//stage1
always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        term1_valid <= 0;
        Xn_reg1 <= 0;
    end else if (stall) begin
        
    end
    else begin
        term1_valid <= Xn_valid;
        Xn_reg1 <= Xn;
    end
end
fp_mul_single_cycle # (
    .EXP_WIDTH                              (EXP_WIDTH),
    .MANTISSA_WIDTH                         (MANTISSA_WIDTH),
    .FP_WIDTH                               (FP_WIDTH)
)fp_mul_single_cycle_0 (
    .clk                                    (clk),
    .rstn                                   (rst_n),
    .mul_a                                  (D),
    .mul_b                                  (Xn),
    .mul_out                                (term1)
);

//stage2
always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        term2_valid <= 0;
        Xn_reg2 <= 0;
    end else if (stall) begin
        
    end
    else begin
        term2_valid <= term1_valid;
        Xn_reg2 <= Xn_reg1;
    end
end
fp_add_single_cycle # (
    .EXP_WIDTH                              (EXP_WIDTH),
    .MANTISSA_WIDTH                         (MANTISSA_WIDTH),
    .SIGN_WIDTH                             (SIGN_WIDTH),
    .FP_WIDTH                               (FP_WIDTH)
)fp_add_single_cycle_0 (
    .clk                                    (clk),
    .rstn                                   (rst_n),
    .add_a                                  (constant3),
    .add_b                                  ({~term1[FP_WIDTH-1],term1[FP_WIDTH-2:0]}),
    .adder_out                              (term2)
);

//stage3
always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      Xn1_valid <= 1'b0;
    end else if (stall) begin
        
    end else begin
      Xn1_valid <= term2_valid;     
    end
  end
fp_mul_single_cycle # (
    .EXP_WIDTH                              (EXP_WIDTH),
    .MANTISSA_WIDTH                         (MANTISSA_WIDTH),
    .FP_WIDTH                               (FP_WIDTH)
)fp_mul_single_cycle_1 (
    .clk                                    (clk),
    .rstn                                   (rst_n),
    .mul_a                                  (term2),
    .mul_b                                  (Xn_reg2),
    .mul_out                                (Xn1)
);

assign Xn_ready = ~stall;


endmodule