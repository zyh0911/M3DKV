module fp_add_single_cycle #(
	parameter EXP_WIDTH = 4,
	parameter MANTISSA_WIDTH = 3,
	parameter SIGN_WIDTH = 1,
	parameter FP_WIDTH = 8
)(
    input clk,
	input rstn,
	
	input [EXP_WIDTH+MANTISSA_WIDTH:0] add_a,
	input [EXP_WIDTH+MANTISSA_WIDTH:0] add_b,
	output [EXP_WIDTH+MANTISSA_WIDTH:0] adder_out
);
parameter E_ref = {(EXP_WIDTH-1){1'b1}};
parameter E_max = {(EXP_WIDTH){1'b1}};

reg a_s0,b_s0,add_s1,add_s2;
reg sub_eq1;

reg[EXP_WIDTH-1:0] add_e0;				
reg[EXP_WIDTH-1:0] add_e1;
reg[EXP_WIDTH-1:0] add_e2;

reg[2*MANTISSA_WIDTH+1:0] a_f0,b_f0;			
reg[2*MANTISSA_WIDTH+1:0] add_f1;									
reg[MANTISSA_WIDTH-1:0] add_f2;

reg[EXP_WIDTH-1:0] sub_shift;
wire[2*MANTISSA_WIDTH+1:0] sub_shift_f1 = (add_f1 << (sub_shift-1'b1));


wire [EXP_WIDTH-1:0] a_e = add_a[EXP_WIDTH+MANTISSA_WIDTH-1:MANTISSA_WIDTH];
wire [EXP_WIDTH-1:0] b_e = add_b[EXP_WIDTH+MANTISSA_WIDTH-1:MANTISSA_WIDTH];
wire [2*MANTISSA_WIDTH+1:0] a_f = {2'b01,add_a[MANTISSA_WIDTH-1:0],{MANTISSA_WIDTH{1'b0}}};	//规范化转非规范化，尾数高位扩充为1，低位扩充用于移位
wire [2*MANTISSA_WIDTH+1:0] b_f = {2'b01,add_b[MANTISSA_WIDTH-1:0],{MANTISSA_WIDTH{1'b0}}};	//规范化转非规范化，尾数高位扩充为1，低位扩充用于移位
wire 				  a_s = add_a[EXP_WIDTH+MANTISSA_WIDTH];
wire 				  b_s = add_b[EXP_WIDTH+MANTISSA_WIDTH];
 
assign adder_out = {add_s2,add_e2,add_f2};

always @(*) begin
	if(add_a == 0 && add_b == 0)begin
		a_s0 = 0;
		b_s0 = 0;
		add_e0 = 'd0;
		a_f0 = 0;
		b_f0 = 0;
	end
	else begin
		if((a_e < b_e)|| (a_e == b_e && a_f < b_f)) begin			
			a_s0 = b_s;				
			b_s0 = a_s;				
			add_e0 = b_e;				
			a_f0 = b_f;				
			b_f0 = a_f>>(b_e-a_e);	
		end
		else begin
			a_s0 = a_s;			
			b_s0 = b_s;
			add_e0 = a_e;
			a_f0 = a_f;
			b_f0 = b_f>>(a_e-b_e);
		end
	end
end

always @(*) begin
	sub_eq1 = 0;
	if(a_s0 == b_s0) begin		
		add_f1 = a_f0 + b_f0;
	end
	else begin
		add_f1 = a_f0 - b_f0;
		if(a_f0 == b_f0) begin	
			sub_eq1 = 1;
		end
	end
	add_s1 = a_s0;
	add_e1 = add_e0;
end

always @(posedge clk or negedge rstn) begin
    if (~rstn) begin
        add_s2 <= 'd0;
        add_f2 <= 'd0;
        add_e2 <= 'd0;
    end
    else begin
        add_s2 <= add_s1;
        if(add_e1 == E_max) begin		
            add_f2 <= 1;
            add_e2 <= {EXP_WIDTH{1'b1}};
        end
        else begin					
            if(add_f1[2*MANTISSA_WIDTH+1]) begin		
                add_f2 <= add_f1[2*MANTISSA_WIDTH:MANTISSA_WIDTH+1]+add_f1[MANTISSA_WIDTH];
                add_e2 <= add_e1+1'b1;
            end
            else begin
                if(sub_eq1 == 1) begin			
                    add_s2 <= 0;
                    add_e2 <= 0;
                    add_f2 <= 0;
                end
                else begin
                    // add_f2 <= sub_shift_f1[2*MANTISSA_WIDTH-1:MANTISSA_WIDTH]+sub_shift_f1[MANTISSA_WIDTH-1];
                    add_f2 <= sub_shift_f1[2*MANTISSA_WIDTH-1:MANTISSA_WIDTH];
                    add_e2 <= add_e1 - (sub_shift-1'b1);
                end
            end
        end
    end
end

always @(add_f1) begin
	casex(add_f1[2*MANTISSA_WIDTH+1:MANTISSA_WIDTH+1])
		8'b1xxxxxxx: sub_shift=8'd0;
		8'b01xxxxxx: sub_shift=8'd1;
		8'b001xxxxx: sub_shift=8'd2;
		8'b0001xxxx: sub_shift=8'd3;
		8'b00001xxx: sub_shift=8'd4;
		8'b000001xx: sub_shift=8'd5;
		8'b0000001x: sub_shift=8'd6;
		8'b00000001: sub_shift=8'd7;
		default: sub_shift = 8'd8;
	endcase
end


endmodule