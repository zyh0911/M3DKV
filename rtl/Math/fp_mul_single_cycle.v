module fp_mul_single_cycle #(
  parameter EXP_WIDTH       = 8,
  parameter MANTISSA_WIDTH  = 7,
  parameter FP_WIDTH        = 1 + EXP_WIDTH + MANTISSA_WIDTH
)(
  input  clk,
  input  rstn,
  input  [FP_WIDTH-1:0] mul_a,
  input  [FP_WIDTH-1:0] mul_b,
  output [FP_WIDTH-1:0] mul_out
);

parameter E_ref = {(EXP_WIDTH-1){1'b1}};			
parameter E_add_max = {(EXP_WIDTH){1'b1}}+E_ref-1;

reg[MANTISSA_WIDTH*2+1:0] f0;	
reg[MANTISSA_WIDTH+1:0] f1;
reg[MANTISSA_WIDTH-1:0] f2;
reg[EXP_WIDTH:0] e0;
reg[EXP_WIDTH:0] e1;
reg[EXP_WIDTH-1:0] e2;
reg S0;
wire[EXP_WIDTH:0] mul_a_e,mul_b_e;	
wire[MANTISSA_WIDTH:0] mul_a_f,mul_b_f;
assign mul_a_e = {1'b0,mul_a[EXP_WIDTH+MANTISSA_WIDTH-1:MANTISSA_WIDTH]};		
assign mul_b_e = {1'b0,mul_b[EXP_WIDTH+MANTISSA_WIDTH-1:MANTISSA_WIDTH]};		
assign mul_a_f = {1'b1,mul_a[MANTISSA_WIDTH-1:0]};						
assign mul_b_f = {1'b1,mul_b[MANTISSA_WIDTH-1:0]};

always @(*) begin
  if(mul_a_e == {1'b0,{(EXP_WIDTH){1'b1}}} || mul_b_e == {1'b0,{(EXP_WIDTH){1'b1}}})begin		
      f0 = 1;
      e0 = E_add_max;
  end
  else begin
      f0 = mul_a_f*mul_b_f;
      e0 = mul_a_e+mul_b_e;
  end
end

always @(*) begin
  if(e0 > E_ref) begin
    if(e0 >= E_add_max) begin		
      e1 = {(EXP_WIDTH+1){1'b1}};	
      f1 = 1;
    end
    else begin
      e1 = (e0 - E_ref);
      f1 = f0[MANTISSA_WIDTH*2+1:MANTISSA_WIDTH]+f0[MANTISSA_WIDTH-1];
    end
  end
  else begin
    e1 = 0;
    f1 = 0;
  end
end

always @(posedge clk or negedge rstn) begin
  if (~rstn) begin
    f2 <= 0;
		e2 <= 0;
    S0 <= 0;
  end
  else begin
    S0 <= mul_a[EXP_WIDTH+MANTISSA_WIDTH]^mul_b[EXP_WIDTH+MANTISSA_WIDTH];	
    if(f1[MANTISSA_WIDTH+1]) begin	
      f2[MANTISSA_WIDTH-1:0] <= f1[MANTISSA_WIDTH:1];
      e2 <= e1[EXP_WIDTH-1:0]+1'b1;
    end
    else begin
      f2[MANTISSA_WIDTH-1:0] <= f1[MANTISSA_WIDTH-1:0];
      e2 <= e1[EXP_WIDTH-1:0];
    end
  end
end

assign mul_out = {S0,e2[EXP_WIDTH-1:0],f2[MANTISSA_WIDTH-1:0]};	

endmodule
