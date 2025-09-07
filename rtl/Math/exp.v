module exp #(
    parameter FP_WIDTH = 16,
    parameter FP_EXP_WIDTH = 8,
    parameter FP_MAN_WIDTH = 7
)(
    input                               clk,
    input                               reset_n,
    input      [FP_WIDTH-1:0]           input_data,
    input                               input_data_valid,
    output reg                          input_data_ready,

    output reg [FP_WIDTH-1:0]           output_data,
    output reg                          output_data_valid,
    input                               output_data_ready
);
wire stall = output_data_valid & ~output_data_ready;

//internal signals
reg  [FP_WIDTH-1:0] add_a, add_b;
wire [FP_WIDTH-1:0] adder_out;
reg  [FP_WIDTH-1:0] mul_a_0, mul_b_0;
wire [FP_WIDTH-1:0] mul_out_0;
reg  [FP_WIDTH-1:0] mul_a_1, mul_b_1;
wire [FP_WIDTH-1:0] mul_out_1;
reg  [FP_WIDTH-1:0] term1,exponent;

//e^x = 1 + x + x^2/2! + x^3/3! + x^4/4! 
localparam [FP_WIDTH-1:0] one = 16'h3F80;
localparam [FP_WIDTH-1:0] onehalf = 16'h3F00;
localparam [FP_WIDTH-1:0] onesix = 16'h3E2B;
localparam [FP_WIDTH-1:0] onetforth = 16'h3d2a;
localparam [FP_WIDTH-1:0] one120 = 16'h3C09;

reg [2:0] state, next_state;
localparam IDLE = 3'b000;
localparam STAGE_1 = 3'b001;
localparam STAGE_2 = 3'b010;
localparam STAGE_3 = 3'b011;
localparam STAGE_4 = 3'b100;
localparam STAGE_5 = 3'b101;
localparam STAGE_6 = 3'b110;
localparam DONE = 3'b111;

localparam [FP_EXP_WIDTH-1:0] NEG_UNDERFLOW_TH = 8'hC0;
wire sign_bit                     = input_data[FP_WIDTH-1];                           
wire [FP_EXP_WIDTH-1:0] exp_field = input_data[FP_MAN_WIDTH+FP_EXP_WIDTH-1:FP_MAN_WIDTH];
wire large_negative               = input_data_valid && sign_bit && (exp_field >= NEG_UNDERFLOW_TH);
reg large_neg_lat;
always @(posedge clk or negedge reset_n) begin
    if (!reset_n)
        large_neg_lat <= 1'b0;
    else if (state == IDLE && input_data_valid)
        large_neg_lat <= large_negative;
    else if (state == DONE && output_data_valid && output_data_ready)
        large_neg_lat <= 1'b0;
end

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        state <= IDLE;
    end else begin
        state <= next_state;
    end
end

always @(*) begin
    case (state)
        IDLE:begin
            if (input_data_valid) begin
                next_state = STAGE_1;
            end else begin
                next_state = IDLE;
            end
        end 
        STAGE_1: begin
            next_state = STAGE_2;

        end
        STAGE_2: begin
             next_state = STAGE_3;
        end
        STAGE_3: begin
            next_state = STAGE_4;
        end
        STAGE_4: begin
            next_state = STAGE_5;
        end
        STAGE_5: begin
            next_state = STAGE_6;
        end
        STAGE_6: begin
            next_state = DONE;
        end
        DONE: begin
            if (output_data_valid & output_data_ready) begin
                next_state = IDLE;
            end else begin
                next_state = DONE;
            end
           
        end
        default:begin
            next_state = IDLE;
        end
    endcase
end

//adder
always @(*) begin
    add_a = 0;
    add_b = 0;
    input_data_ready = 0;
    output_data = 0;
    output_data_valid = 0;
    case (state)
        IDLE: begin
            add_a = 0;
            add_b = 0;
            input_data_ready = 1;
        end
        STAGE_1: begin
            input_data_ready = 0;
            add_a = input_data;
            add_b = one;
        end
        STAGE_2: begin
            add_a = 0;
            add_b = 0;
        end
        STAGE_3: begin
            add_a = term1;
            add_b = mul_out_1; //term2
        end
        STAGE_4: begin
            add_a = adder_out;
            add_b = mul_out_1; //term3
        end
        STAGE_5: begin
            add_a = adder_out;
            add_b = mul_out_1; //term4
        end
        STAGE_6: begin
            add_a = adder_out;
            add_b = mul_out_1; //term5
        end
        DONE: begin
            output_data = large_neg_lat ? {FP_WIDTH{1'b0}} : exponent;
            output_data_valid = 1;
        end
        default: begin
            add_a = 0;
            add_b = 0;
            input_data_ready = 0;
            output_data = 0;
            output_data_valid = 0;
        end
    endcase
end

always @(posedge clk or negedge reset_n) begin
    if (~reset_n) begin
        term1 <= 0;
        exponent <= 0;
    end else begin
        if (state == STAGE_2) begin
            term1 <= adder_out;
        end else begin
            term1 <= term1;
        end
        if (state == STAGE_6) begin
            exponent <= adder_out;
        end
    
    end
end


//mul0
always @(*) begin
    case (state)
        IDLE: begin
            mul_a_0 = 0;
            mul_b_0 = 0;
        end
        STAGE_1: begin
            mul_a_0 = input_data;
            mul_b_0 = input_data;
        end
        STAGE_2: begin
            mul_a_0 = mul_out_0;
            mul_b_0 = input_data;
        end
        STAGE_3: begin
            mul_a_0 = mul_out_0;
            mul_b_0 = input_data;
        end
        STAGE_4: begin
            mul_a_0 = mul_out_0;
            mul_b_0 = input_data;
        end
        STAGE_5: begin
            mul_a_0 = 0;
            mul_b_0 = 0;
        end
        STAGE_6: begin
            mul_a_0 = 0;
            mul_b_0 = 0;
        end
        DONE: begin
            mul_a_0 = 0;
            mul_b_0 = 0;
        end
        default: begin
            mul_a_0 = 0;
            mul_b_0 = 0;
        end
    endcase
end

//mul1
always @(*) begin
    case (state)
        IDLE: begin
            mul_a_1 = 0;
            mul_b_1 = 0;
        end
        STAGE_1: begin
            mul_a_1 = 0;
            mul_b_1 = 0;
        end
        STAGE_2: begin
            mul_a_1 = mul_out_0;
            mul_b_1 = onehalf;
        end
        STAGE_3: begin
            mul_a_1 = mul_out_0;
            mul_b_1 = onesix;
        end
        STAGE_4: begin
            mul_a_1 = mul_out_0;
            mul_b_1 = onetforth;
        end
        STAGE_5: begin
            mul_a_1 = mul_out_0;
            mul_b_1 = one120;
        end
        STAGE_6: begin
            mul_a_1 = 0;
            mul_b_1 = 0;
        end
        DONE: begin
            mul_a_1 = 0;
            mul_b_1 = 0;
        end
        default: begin
            mul_a_1 = 0;
            mul_b_1 = 0;
        end
    endcase
end

fp_add_single_cycle # (
    .EXP_WIDTH                               (FP_EXP_WIDTH),
    .MANTISSA_WIDTH                          (FP_MAN_WIDTH),
    .SIGN_WIDTH                              (1),
    .FP_WIDTH                                (FP_WIDTH)
  )
  fp_add_single_cycle_inst (
    .clk                                      (clk),
    .rstn                                     (reset_n),
    .add_a                                    (add_a),
    .add_b                                    (add_b),
    .adder_out                                (adder_out)
  );
  
fp_mul_single_cycle # (
    .EXP_WIDTH                                 (FP_EXP_WIDTH),
    .MANTISSA_WIDTH                            (FP_MAN_WIDTH),
    .FP_WIDTH                                  (FP_WIDTH)
  )
  fp_mul_single_cycle_inst_0 (
    .clk                                       (clk),
    .rstn                                      (reset_n),
    .mul_a                                     (mul_a_0),
    .mul_b                                     (mul_b_0),
    .mul_out                                   (mul_out_0)
  );

fp_mul_single_cycle # (
    .EXP_WIDTH                                 (FP_EXP_WIDTH),
    .MANTISSA_WIDTH                            (FP_MAN_WIDTH),
    .FP_WIDTH                                  (FP_WIDTH)
  )
  fp_mul_single_cycle_inst_1 (
    .clk                                       (clk),
    .rstn                                      (reset_n),
    .mul_a                                     (mul_a_1),
    .mul_b                                     (mul_b_1),
    .mul_out                                   (mul_out_1)
  );
    
endmodule