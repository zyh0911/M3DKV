module reciprocal#(
    parameter EXP_WIDTH      = 8,
    parameter MANTISSA_WIDTH = 7,
    parameter SIGN_WIDTH     = 1,
    parameter FP_WIDTH       = 16
)(
    input                   clk,
    input                   rst_n,

    input  [FP_WIDTH-1:0]   input_data,
    input                   input_data_valid,
    output                  input_data_ready,

    output reg [FP_WIDTH-1:0] output_data,
    output reg               output_data_valid,
    input                    output_data_ready
);

    localparam [EXP_WIDTH-1:0] BIAS = ({EXP_WIDTH{1'b1}} >> 1);
    localparam [FP_WIDTH-1:0] CONST1 = 16'h4034; //  48/17
    localparam [FP_WIDTH-1:0] CONST2 = 16'hBFF1; // −32/17

    localparam ST_IDLE    = 3'd0,
               ST_X0MUL   = 3'd1,
               ST_X0ADD   = 3'd2,
               ST_ITER    = 3'd3,
               ST_DONE    = 3'd4;

    reg [2:0] state, next_state;

    reg [MANTISSA_WIDTH-1:0] M_in;
    reg [EXP_WIDTH-1:0] E_in;
    reg sign_in;
    wire [FP_WIDTH-1:0] D = {1'b0, 8'b01111110, M_in};
    wire  [FP_WIDTH-1:0] X0_temp;

    //X0 = 48/17 – (32/17)*D
    wire [FP_WIDTH-1:0] mul_out;
    wire                add_rdy = 1'b1;
    wire [FP_WIDTH-1:0] X0;

    reg [1:0] iter_cnt;

    wire [FP_WIDTH-1:0] Xn1;
    wire                Xn1_valid;
    reg                 Xn_valid;
    reg  [FP_WIDTH-1:0] Xn_reg;

    wire [EXP_WIDTH:0] E_tmp = BIAS - (E_in - (BIAS- 1'b1)) ; 
    wire [EXP_WIDTH:0] E_out = E_tmp + Xn1[MANTISSA_WIDTH+EXP_WIDTH-1:MANTISSA_WIDTH] - BIAS; 

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            state <= 0;
        end
        else begin
            state <= next_state;
        end
    end	
    
    always @(*) begin
        case (state)
            ST_IDLE: begin
                if (input_data_valid) begin
                    next_state   = ST_X0MUL;
                end else begin
                    next_state   = ST_IDLE;
                end
            end
            ST_X0MUL: begin
                next_state       = ST_X0ADD;
            end

            ST_X0ADD: begin
                next_state       = ST_ITER;
            end

            ST_ITER: begin
                if (iter_cnt == 2'd3 & Xn1_valid) begin
                    next_state         = ST_DONE;
                end else begin
                    next_state         = ST_ITER;
                end
            end

            ST_DONE: begin
                if (output_data_ready) begin
                    next_state   = ST_IDLE;
                end else begin
                    next_state   = ST_DONE;
                end
            end

            default: next_state = ST_IDLE;
        endcase
    end


    assign  X0_temp = mul_out;
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            output_data_valid <= 1'b0;
            output_data       <= 0;
            Xn_valid          <= 1'b0;
            iter_cnt          <= 2'd0;
            Xn_reg            <= 0;
        end
        else begin
            case (state)
                ST_IDLE: begin
                    output_data_valid <= 1'b0;
                    Xn_valid          <= 1'b0;
                    M_in              <= input_data[MANTISSA_WIDTH-1:0];
                    E_in              <= input_data[FP_WIDTH-2 -: EXP_WIDTH];
                    sign_in           <= input_data[FP_WIDTH-1];
                end
                ST_X0MUL: begin
                    
                end
                ST_X0ADD: begin
                    iter_cnt        <= 2'd0;
                end
                ST_ITER: begin
                    if (iter_cnt == 2'd0) begin
                        Xn_reg          <= X0;
                        Xn_valid        <= 1'b1;
                        iter_cnt        <= iter_cnt + 1;
                    end else begin
                        if (Xn1_valid) begin
                            if (iter_cnt == 2'd3) begin
                                output_data       <= {sign_in,E_out[EXP_WIDTH-1:0],Xn1[MANTISSA_WIDTH-1:0] };
                                output_data_valid <= 1'b1;
                                Xn_valid          <= 1'b0;
                            end else begin
                                Xn_reg            <= Xn1;
                                Xn_valid          <= 1'b1;
                                iter_cnt          <= iter_cnt + 1;
                            end
                        end else begin
                            Xn_valid <= 1'b0;
                        end
                    end
                end
                ST_DONE: begin
                    if (output_data_ready) begin
                        output_data_valid <= 1'b0;
                    end
                end
                default: begin
                    
                end
            endcase
        end
    end

    fp_mul_single_cycle #(
        .EXP_WIDTH                          (EXP_WIDTH),
        .MANTISSA_WIDTH                     (MANTISSA_WIDTH),
        .FP_WIDTH                           (FP_WIDTH)
    ) fp_mul_single_cycle_inst_0 (
        .clk                                (clk),
        .rstn                               (rst_n),
        .mul_a                              (D),
        .mul_b                              (CONST2),
        .mul_out                            (mul_out)
    );

    fp_add_single_cycle #(
        .EXP_WIDTH                          (EXP_WIDTH),
        .MANTISSA_WIDTH                     (MANTISSA_WIDTH),
        .SIGN_WIDTH                         (SIGN_WIDTH),
        .FP_WIDTH                           (FP_WIDTH)
    ) add_inst (
        .clk                                (clk),
        .rstn                               (rst_n),
        .add_a                              (CONST1),
        .add_b                              (X0_temp),
        .adder_out                          (X0)
    );

    // —— NEWTON  Xn1 = Xn*(2–D*Xn) ——
    Xn_cal #(
        .EXP_WIDTH                          (EXP_WIDTH),
        .MANTISSA_WIDTH                     (MANTISSA_WIDTH),
        .SIGN_WIDTH                         (SIGN_WIDTH),
        .FP_WIDTH                           (FP_WIDTH)
    ) xn_cal_inst (
        .clk                                (clk),
        .rst_n                              (rst_n),
        .D                                  (D),
        .Xn                                 (Xn_reg),
        .Xn_valid                           (Xn_valid),
        .Xn_ready                           (),
        .Xn1                                (Xn1),
        .Xn1_valid                          (Xn1_valid),
        .Xn1_ready                          (1'b1)
    );
    

    assign input_data_ready = (state == ST_IDLE);

endmodule
