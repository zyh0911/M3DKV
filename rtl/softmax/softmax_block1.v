module softmax_block1 #(
    parameter FP_WIDTH         = 16,   
    parameter MANT_WIDTH       = 7,
    parameter EXP_WIDTH        = 8,
    parameter PARALLEL_ROW     = 32,   
    parameter K_MACRO_ROW      = 32, 
    parameter FP_EXP_WIDTH     = 8,  

    parameter V_BANK_COLUMN    = 1024,
    parameter V_MACRO_COLUMN   = 32,
    parameter PARALLEL_COL = V_BANK_COLUMN / V_MACRO_COLUMN
)(
    input  wire                                 clk,
    input  wire                                 rst_n,
    input  wire                                 si_fp_col_block_result_vld,
    output wire                                 si_fp_col_block_result_rdy,
    input  wire [PARALLEL_ROW*FP_WIDTH-1:0]     si_fp_col_block_result, 
    
    output wire                                 pi_vld,
    input  wire                                 pi_rdy,
    output wire [PARALLEL_COL*FP_WIDTH-1:0]     pi
);
    localparam CMP_ELEM = PARALLEL_ROW + 1;  
    wire [CMP_ELEM*FP_WIDTH-1:0] cmp_vec;
    reg  [FP_WIDTH-1:0]          global_max_q;
    wire                         local_max_valid;
    wire [FP_WIDTH-1:0]          local_max;
    reg [5:0] round_cnt;                     
    wire round_cnt_is_max_now = (round_cnt == K_MACRO_ROW - 1) ? 1'b1 : 1'b0;
    reg state;
    reg [PARALLEL_COL*FP_WIDTH-1:0] cmp_fifo_data_in_reg;
    reg cmp_fifo_data_in_reg_vld;
    reg cmp_fifo_cnt;
    wire [PARALLEL_COL*FP_WIDTH-1:0] cmp_fifo_data_in;
    wire cmp_fifo_push;
    wire cmp_fifo_pull;
    wire cmp_fifo_full;
    wire [PARALLEL_COL*FP_WIDTH-1:0] cmp_fifo_data_out;
    wire cmp_fifo_empty;

    wire [PARALLEL_COL*FP_WIDTH-1:0] si_norm;
    wire si_norm_rdy;

    wire [PARALLEL_COL*FP_WIDTH-1:0] pi_temp;
    wire [PARALLEL_COL-1:0]          pi_valid_temp;

    assign cmp_vec = {global_max_q, si_fp_col_block_result};
    FpRoundMax u_round_max (
        .clk               (clk),
        .resetn            (rst_n),
        .inVec_valid       (si_fp_col_block_result_vld),
        .inVec_ready       (si_fp_col_block_result_rdy),
        .inVec_payload     (cmp_vec),
        .outMax_valid      (local_max_valid ),
        .outMax_ready      (1'b1       ),            
        .outMax_payload    (local_max  )
    );

    always @(posedge clk or negedge rst_n) begin
        if(~rst_n) begin
            global_max_q <= {FP_WIDTH{1'b0}};       
            round_cnt    <= 6'd0;
        end
        else begin
            if (local_max_valid) begin
                global_max_q <= local_max;
                round_cnt    <= round_cnt_is_max_now ? 0 : round_cnt + 1'b1;
            end
            else begin
                global_max_q <= global_max_q;
                round_cnt    <= round_cnt;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            state <= 1'b0; 
        end else begin
            if (round_cnt_is_max_now & local_max_valid) begin
                state <= 1'b1;
            end else if (cmp_fifo_empty) begin
                state <= 1'b0;
            end else begin
                state <= state;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            cmp_fifo_cnt <= 1'b0;
        end
        else begin
            if (si_fp_col_block_result_vld) begin
                cmp_fifo_cnt <= cmp_fifo_cnt + 1'b1;
            end else begin
                cmp_fifo_cnt <= cmp_fifo_cnt;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            cmp_fifo_data_in_reg <= {PARALLEL_COL*FP_WIDTH{1'b0}};
        end
        else begin
            if (si_fp_col_block_result_vld) begin
                cmp_fifo_data_in_reg[cmp_fifo_cnt*FP_WIDTH +: PARALLEL_ROW*FP_WIDTH] <= si_fp_col_block_result[PARALLEL_ROW*FP_WIDTH-1:0];
            end else begin
                cmp_fifo_data_in_reg <= cmp_fifo_data_in_reg;
            end
        end
    end

    assign cmp_fifo_data_in = cmp_fifo_data_in_reg;
    assign cmp_fifo_push = (cmp_fifo_cnt == 1'b1 & si_fp_col_block_result_vld) & ~cmp_fifo_full;
    assign cmp_fifo_pull = si_norm_rdy & (~cmp_fifo_empty) & state;

    sync_fifo # (
        .ADDR_WIDTH         ($clog2(V_MACRO_COLUMN)),
        .DATA_WIDTH         (PARALLEL_COL*FP_WIDTH)
    )sync_fifo_inst (
        .aclk               (clk),
        .aresetn            (rst_n),
        .data_in            (cmp_fifo_data_in),
        .push               (cmp_fifo_push),
        .full               (cmp_fifo_full),
        .data_out           (cmp_fifo_data_out),
        .pull               (cmp_fifo_pull),
        .empty              (cmp_fifo_empty)
    );
        
    genvar i;
    generate
        for(i = 0; i < PARALLEL_COL; i = i + 1) begin : SUB
            fp_add_single_cycle # (
                .EXP_WIDTH                               (EXP_WIDTH),
                .MANTISSA_WIDTH                          (MANT_WIDTH),
                .SIGN_WIDTH                              (1),
                .FP_WIDTH                                (FP_WIDTH)
            )fp_add_single_cycle_safe_softmax (
                .clk                                     (clk),
                .rstn                                    (rst_n),
                .add_a                                   (cmp_fifo_data_out[i*FP_WIDTH +: FP_WIDTH]),
                .add_b                                   ({~global_max_q[FP_WIDTH-1], global_max_q[FP_WIDTH-2:0]}),
                .adder_out                               (si_norm[i*FP_WIDTH +: FP_WIDTH])
            );
        end
    endgenerate

    generate
        for (i = 0; i < PARALLEL_COL; i = i + 1) begin : pij_exp
            exp # (
                .FP_WIDTH                               (FP_WIDTH),
                .FP_EXP_WIDTH                           (EXP_WIDTH),
                .FP_MAN_WIDTH                           (MANT_WIDTH)
            )exp_inst ( 
                .clk                                    (clk),
                .reset_n                                (rst_n),
                .input_data                             (si_norm[i*FP_WIDTH +: FP_WIDTH]),
                .input_data_valid                       (cmp_fifo_pull),
                .input_data_ready                       (si_norm_rdy),
                .output_data                            (pi_temp[i*FP_WIDTH +: FP_WIDTH]),
                .output_data_valid                      (pi_valid_temp[i]),
                .output_data_ready                      (pi_rdy)
            );
        end
    endgenerate

    assign pi_vld = &pi_valid_temp;
    generate
        for (i = 0; i < PARALLEL_COL; i = i + 1) begin : pi_assign
            assign pi[i*FP_WIDTH +: FP_WIDTH] = pi_temp[i*FP_WIDTH +: FP_WIDTH];
        end
    endgenerate
endmodule
