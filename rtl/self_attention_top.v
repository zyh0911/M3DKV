module self_attention_top #(
    parameter K_MACRO_COLUMN = 2,
    parameter K_MACRO_ROW = 64,
    parameter K_BANK_COLUMN = 64,
    parameter K_BANK_ROW = 1024,

    parameter V_MACRO_COLUMN = 32,
    parameter V_MACRO_ROW = 4,
    parameter V_BANK_COLUMN = 1024,
    parameter V_BANK_ROW = 64,

    parameter EXP_WIDTH = 8,
	parameter MANTISSA_WIDTH = 7,
	parameter SIGN_WIDTH = 1,
	parameter FP_WIDTH = 16,
    parameter PRE_ALIGN_CMP_STAGES_PER_REG = 2, 
    parameter V_CMP_STAGES_PER_REG = 2,
    parameter BLOCK1_CMP_STAGES_PER_REG = 2, 
    parameter BLOCK3_PARALLELISM = 4, //4
    parameter HIDDEN_SQRT = 8,

    parameter COMPUTE_CYCLE = MANTISSA_WIDTH + SIGN_WIDTH + 1,
    parameter BANK_NUM = MANTISSA_WIDTH + SIGN_WIDTH + 1,
    parameter PARALLEL_ROW = K_BANK_ROW/K_MACRO_ROW,
    parameter HIDDEN_DIM = K_BANK_COLUMN
) (
    input                                                                                          clk,
    input                                                                                          rst_n, 
                                    
    input                                                                                          cme,
    input                                                                                          we,
    input [(K_BANK_COLUMN/K_MACRO_COLUMN)*FP_WIDTH - 1 : 0 ]                                       q_data_in, 
    input                                                                                          q_data_in_vld,
    output reg                                                                                     q_data_in_rdy,

    input  [(K_BANK_COLUMN/K_MACRO_COLUMN)*(K_BANK_ROW/K_MACRO_ROW)*FP_WIDTH - 1:0]                k_data_wr,
    input                                                                                          k_data_wr_vld,
    output reg                                                                                     k_data_wr_rdy,

    input  [(V_BANK_COLUMN/V_MACRO_COLUMN)*(V_BANK_ROW/V_MACRO_ROW)*FP_WIDTH - 1:0]                v_data_wr,
    input                                                                                          v_data_wr_vld,
    output reg                                                                                     v_data_wr_rdy,    

    output [(HIDDEN_DIM*FP_WIDTH) - 1 : 0]                                                         o_out,
    output                                                                                         o_out_vld,
    input                                                                                          o_out_rdy
);
 
//K_BANK_COLUMN/K_MACRO_COLUMN)*(K_BANK_ROW/K_MACRO_ROW) = (V_BANK_COLUMN/V_MACRO_COLUMN)*(V_BANK_ROW/V_MACRO_ROW)
localparam MACRO_DATA_WIDTH = K_BANK_COLUMN/K_MACRO_COLUMN;
localparam ADDER_TREE_WIDTH = BANK_NUM + $clog2(MACRO_DATA_WIDTH);
localparam BIT_SERIAL_ACC_WIDTH = ADDER_TREE_WIDTH + COMPUTE_CYCLE;
/* -------------------------------------------------------------------------
 *  Internal signal declarations 
 * -----------------------------------------------------------------------*/
// Handshake with GEMV_shared_block1
reg [(K_BANK_COLUMN/K_MACRO_COLUMN)*(K_BANK_ROW/K_MACRO_ROW)*FP_WIDTH - 1:0]data_wr;
reg                                                                       data_wr_vld;
wire                                                                      data_wr_rdy;

// Pre‑aligned data buses
wire [PARALLEL_ROW*MACRO_DATA_WIDTH*(SIGN_WIDTH+MANTISSA_WIDTH+1)-1:0]    data_wr_mantissa_plus_aligned;
wire [PARALLEL_ROW*EXP_WIDTH-1:0]                                         data_wr_exp_max;
wire                                                                      data_wr_mantissa_plus_aligned_vld;
reg                                                                       data_wr_mantissa_plus_aligned_rdy;
reg  [PARALLEL_ROW*MACRO_DATA_WIDTH*(SIGN_WIDTH+MANTISSA_WIDTH+1)-1:0]    k_wr_mantissa_plus_aligned;
reg  [PARALLEL_ROW*EXP_WIDTH-1:0]                                         k_wr_exp_max;
reg                                                                       k_wr_mantissa_plus_aligned_vld;
wire                                                                      k_wr_mantissa_plus_aligned_rdy;
reg  [PARALLEL_ROW*MACRO_DATA_WIDTH*(SIGN_WIDTH+MANTISSA_WIDTH+1)-1:0]    v_wr_mantissa_plus_aligned;
reg  [PARALLEL_ROW*EXP_WIDTH-1:0]                                         v_wr_exp_max;
reg                                                                       v_wr_mantissa_plus_aligned_vld;
wire                                                                      v_wr_mantissa_plus_aligned_rdy;

// Shared‑block2 I/F (attention vs similarity)
reg  [PARALLEL_ROW * MACRO_DATA_WIDTH * BANK_NUM-1:0]                     cmOut;
reg                                                                       cmOut_vld;
wire                                                                      cmOut_rdy;

reg                                                                       bit_serial_acc_vld;
wire                                                                      bit_serial_acc_rdy;

reg  [EXP_WIDTH-1:0]                                                      nmc_exp_max;
reg                                                                       nmc_exp_max_vld;
wire                                                                      nmc_exp_max_rdy;

reg  [PARALLEL_ROW*EXP_WIDTH-1:0]                                         data_wr_exp_max_buf_out;
reg                                                                       data_wr_exp_max_buf_out_vld;
wire                                                                      data_wr_exp_max_buf_out_rdy;

reg  [PARALLEL_ROW * FP_WIDTH-1:0]                                        fp_macro_result;
reg                                                                       fp_macro_result_vld;
reg                                                                       fp_macro_result_rdy;

// -------------------- similarity‑path ("si_*") -------------------------
wire [PARALLEL_ROW * MACRO_DATA_WIDTH * BANK_NUM-1:0]                     si_cmOut;
wire                                                                      si_cmOut_vld;
reg                                                                       si_cmOut_rdy;
reg                                                                       si_bit_serial_acc_vld;
reg                                                                       si_bit_serial_acc_rdy;
reg  [PARALLEL_ROW * FP_WIDTH-1:0]                                        si_fp_macro_result;
reg                                                                       si_fp_macro_result_vld;
wire                                                                      si_fp_macro_result_rdy;
reg  [(K_BANK_ROW/PARALLEL_ROW)-1:0]                                      si_fp_macro_result_counter;
wire                                                                      si_fp_macro_result_counter_will_max_now;
wire [PARALLEL_ROW * FP_WIDTH - 1:0]                                      si_fp_col_block_result;
wire                                                                      si_fp_col_block_result_vld;
wire                                                                      si_fp_col_block_result_rdy;

// -------------------- attention‑path ("attn_*") ------------------------
reg  [PARALLEL_ROW * MACRO_DATA_WIDTH * BANK_NUM-1:0]                     attn_cmOut;
reg                                                                       attn_cmOut_vld;
reg                                                                       attn_cmOut_rdy;
reg                                                                       attn_bit_serial_acc_vld;
reg                                                                       attn_bit_serial_acc_rdy;
reg  [PARALLEL_ROW * FP_WIDTH-1:0]                                        attn_fp_macro_result;
reg                                                                       attn_fp_macro_result_vld;
wire                                                                      attn_fp_macro_result_rdy;
wire [PARALLEL_ROW * FP_WIDTH - 1:0]                                      attn_fp_col_block_result;
wire                                                                      attn_fp_col_block_result_vld;
wire                                                                      attn_fp_col_block_result_rdy;

// -------------------- exp‑max buffers & addresses -----------------------
wire [$clog2(K_MACRO_ROW * K_MACRO_COLUMN)-1:0]                           k_exp_max_addr;
reg                                                                       k_exp_max_buf_out_rdy;
wire [PARALLEL_ROW*EXP_WIDTH-1:0]                                         k_exp_max_buf_out;
wire                                                                      k_exp_max_buf_out_vld;

wire [$clog2(V_MACRO_ROW * V_MACRO_COLUMN)-1:0]                           v_exp_max_addr;
reg                                                                       v_exp_max_buf_out_rdy;
wire [PARALLEL_ROW*EXP_WIDTH-1:0]                                         v_exp_max_buf_out;
wire                                                                      v_exp_max_buf_out_vld;

wire [$clog2(K_MACRO_COLUMN)-1:0]                                         q_exp_max_addr;
reg                                                                       q_exp_max_buf_out_rdy;
wire [EXP_WIDTH-1:0]                                                      q_exp_max_buf_out;
wire                                                                      q_exp_max_buf_out_vld;

wire [$clog2(V_MACRO_COLUMN)-1:0]                                         pi_exp_max_addr;
reg                                                                       pi_exp_max_buf_out_rdy;
wire [EXP_WIDTH-1:0]                                                      pi_exp_max_buf_out;
wire                                                                      pi_exp_max_buf_out_vld;

// softmax
wire [(V_BANK_COLUMN/V_MACRO_COLUMN)*FP_WIDTH - 1:0]                      pi;
wire                                                                      pi_vld;
reg                                                                       pi_rdy;
wire                                                                      softmax_block2_pi_rdy;
wire [FP_WIDTH-1:0]                                                       pi_sum_recip;
wire                                                                      pi_sum_recip_valid;
wire                                                                      pi_sum_recip_ready;
// wire                                                                      attn_fp_col_block_result_fifo_empty;
// wire                                                                      attn_fp_col_block_result_fifo_full;
// wire [PARALLEL_ROW * FP_WIDTH - 1:0]                                      attn_fp_col_block_result_fifo_out;
wire [FP_WIDTH*PARALLEL_ROW-1:0]                                          oi;
wire                                                                      oi_vld;
wire                                                                      oi_rdy;


reg [2:0] state,next_state;

localparam  IDLE = 3'b000,
            WRITE_K = 3'b001,
            WRITE_V = 3'b010,
            GEMV1_MAX = 3'b011,
            EXP_GEMV2_RCP = 3'b100,
            DONE = 3'b110;

always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        state <= IDLE;
    end
    else begin
        state <= next_state;
    end
end

always @(*) begin
    case (state)
        IDLE:begin
            if (we) begin
                next_state = WRITE_K;
            end
            else begin
                next_state = IDLE;
            end
        end
        WRITE_K:begin
            if (we) begin
                next_state = WRITE_K;
            end
            else begin
                next_state = WRITE_V;
            end
        end
        WRITE_V:begin
            if (we) begin
                next_state = WRITE_V;
            end
            else begin
                next_state = GEMV1_MAX;
            end
        end
        GEMV1_MAX:begin
            if (si_fp_macro_result_counter_will_max_now & si_fp_col_block_result_vld & si_fp_col_block_result_rdy) begin
                next_state = EXP_GEMV2_RCP;
            end
            else begin
                next_state = GEMV1_MAX;
            end
        end
        EXP_GEMV2_RCP:begin
            if (o_out_vld) begin
                next_state = DONE;
            end
            else begin
                next_state = EXP_GEMV2_RCP;
            end
        end
        DONE:begin
            if (o_out_vld & o_out_rdy) begin
                next_state = IDLE;
            end
            else begin
                next_state = DONE;
            end
        end
        default:begin
            next_state = IDLE;
        end
    endcase
end

always @(*) begin
    data_wr = 'd0;
    data_wr_vld = 1'b0;
    k_data_wr_rdy = 1'b0;
    v_data_wr_rdy = 1'b0;
    q_data_in_rdy = 1'b0;
    pi_rdy = 1'b0;
    case (state)
        WRITE_K: begin
            data_wr = k_data_wr;
            data_wr_vld = k_data_wr_vld;
            k_data_wr_rdy = data_wr_rdy;
        end
        WRITE_V: begin
            data_wr = v_data_wr;
            data_wr_vld = v_data_wr_vld;
            v_data_wr_rdy = data_wr_rdy;
        end
        GEMV1_MAX: begin
            data_wr[(K_BANK_COLUMN/K_MACRO_COLUMN)*FP_WIDTH - 1 : 0] = q_data_in;
            data_wr_vld = q_data_in_vld;
            q_data_in_rdy = data_wr_rdy;
        end
        EXP_GEMV2_RCP: begin
            data_wr[(V_BANK_COLUMN/V_MACRO_COLUMN)*FP_WIDTH - 1 : 0] = pi;
            data_wr_vld = pi_vld;
            pi_rdy = data_wr_rdy & softmax_block2_pi_rdy;

        end
        DONE: begin
            data_wr = 'd0;
            data_wr_vld = 1'b0;
            k_data_wr_rdy = 1'b0;
            v_data_wr_rdy = 1'b0;
            q_data_in_rdy = 1'b0;
        end
        default: begin
            data_wr = 'd0;
            data_wr_vld = 1'b0;
            k_data_wr_rdy = 1'b0;
            v_data_wr_rdy = 1'b0;
            q_data_in_rdy = 1'b0;
            pi_rdy = 1'b0;
        end
    endcase
end

always @(*) begin
    // Default values for all signals
    k_wr_exp_max = 'd0;
    k_wr_mantissa_plus_aligned = 'd0;
    k_wr_mantissa_plus_aligned_vld = 1'b0;
    v_wr_exp_max = 'd0;
    v_wr_mantissa_plus_aligned = 'd0;
    v_wr_mantissa_plus_aligned_vld = 1'b0;
    data_wr_mantissa_plus_aligned_rdy = 1'b0;
    cmOut = 'd0;
    cmOut_vld = 1'b0;
    si_cmOut_rdy = 1'b0;
    attn_cmOut_rdy = 1'b0;
    si_bit_serial_acc_vld = 1'b0;
    attn_bit_serial_acc_vld = 1'b0;
    si_bit_serial_acc_rdy = 1'b0;
    attn_bit_serial_acc_rdy = 1'b0;
    nmc_exp_max = 'd0;
    nmc_exp_max_vld = 1'b0;
    q_exp_max_buf_out_rdy = 1'b0;
    pi_exp_max_buf_out_rdy = 1'b0;
    data_wr_exp_max_buf_out = 'd0;
    data_wr_exp_max_buf_out_vld = 1'b0;
    k_exp_max_buf_out_rdy = 1'b0;
    v_exp_max_buf_out_rdy = 1'b0;
    si_fp_macro_result = 'd0;
    si_fp_macro_result_vld = 1'b0;
    attn_fp_macro_result = 'd0;
    attn_fp_macro_result_vld = 1'b0;
    fp_macro_result_rdy = 1'b0;

    case (state)
        WRITE_K:begin
            //k
            k_wr_exp_max = data_wr_exp_max;
            k_wr_mantissa_plus_aligned = data_wr_mantissa_plus_aligned;
            k_wr_mantissa_plus_aligned_vld = data_wr_mantissa_plus_aligned_vld;
            data_wr_mantissa_plus_aligned_rdy = k_wr_mantissa_plus_aligned_rdy;
        end
        WRITE_V:begin
            //v
            v_wr_exp_max = data_wr_exp_max;
            v_wr_mantissa_plus_aligned = data_wr_mantissa_plus_aligned;
            v_wr_mantissa_plus_aligned_vld = data_wr_mantissa_plus_aligned_vld;
            data_wr_mantissa_plus_aligned_rdy = v_wr_mantissa_plus_aligned_rdy;
        end
        GEMV1_MAX:begin
            //q
            k_wr_mantissa_plus_aligned = data_wr_mantissa_plus_aligned;
            k_wr_exp_max = data_wr_exp_max;
            k_wr_mantissa_plus_aligned_vld = data_wr_mantissa_plus_aligned_vld;
            data_wr_mantissa_plus_aligned_rdy = k_wr_mantissa_plus_aligned_rdy;

            cmOut = si_cmOut;
            cmOut_vld = si_cmOut_vld;
            si_cmOut_rdy = cmOut_rdy;

            si_bit_serial_acc_vld = bit_serial_acc_vld;
            si_bit_serial_acc_rdy = bit_serial_acc_rdy;
            nmc_exp_max = q_exp_max_buf_out;
            nmc_exp_max_vld = q_exp_max_buf_out_vld;
            q_exp_max_buf_out_rdy = nmc_exp_max_rdy;
            data_wr_exp_max_buf_out = k_exp_max_buf_out;
            data_wr_exp_max_buf_out_vld = k_exp_max_buf_out_vld;
            k_exp_max_buf_out_rdy = data_wr_exp_max_buf_out_rdy;
            si_fp_macro_result = fp_macro_result;
            si_fp_macro_result_vld = fp_macro_result_vld;
            fp_macro_result_rdy = si_fp_macro_result_rdy;
        end 
        EXP_GEMV2_RCP:begin
            //pi
            v_wr_exp_max = data_wr_exp_max;
            v_wr_mantissa_plus_aligned = data_wr_mantissa_plus_aligned;
            v_wr_mantissa_plus_aligned_vld = data_wr_mantissa_plus_aligned_vld;
            data_wr_mantissa_plus_aligned_rdy = v_wr_mantissa_plus_aligned_rdy;

            cmOut = attn_cmOut;
            cmOut_vld = attn_cmOut_vld;
            attn_cmOut_rdy = cmOut_rdy;
            attn_bit_serial_acc_vld = bit_serial_acc_vld;
            attn_bit_serial_acc_rdy = bit_serial_acc_rdy;
            nmc_exp_max = pi_exp_max_buf_out;
            nmc_exp_max_vld = pi_exp_max_buf_out_vld;
            pi_exp_max_buf_out_rdy = nmc_exp_max_rdy;
            data_wr_exp_max_buf_out = v_exp_max_buf_out;
            data_wr_exp_max_buf_out_vld = v_exp_max_buf_out_vld;
            v_exp_max_buf_out_rdy = data_wr_exp_max_buf_out_rdy;
            attn_fp_macro_result = fp_macro_result;
            attn_fp_macro_result_vld = fp_macro_result_vld; 
            fp_macro_result_rdy = attn_fp_macro_result_rdy;
        end 
        default: begin 
            k_wr_exp_max = 'd0;
            k_wr_mantissa_plus_aligned = 'd0;
            k_wr_mantissa_plus_aligned_vld = 1'b0;
            v_wr_exp_max = 'd0;
            v_wr_mantissa_plus_aligned = 'd0;
            v_wr_mantissa_plus_aligned_vld = 1'b0;
            data_wr_mantissa_plus_aligned_rdy = 1'b0;
            cmOut = 'd0;
            cmOut_vld = 1'b0;
            si_cmOut_rdy = 1'b0;
            attn_cmOut_rdy = 1'b0;
            si_bit_serial_acc_vld = 1'b0;
            attn_bit_serial_acc_vld = 1'b0;
            si_bit_serial_acc_rdy = 1'b0;
            attn_bit_serial_acc_rdy = 1'b0;
            nmc_exp_max = 'd0;
            nmc_exp_max_vld = 1'b0;
            q_exp_max_buf_out_rdy = 1'b0;
            pi_exp_max_buf_out_rdy = 1'b0;
            data_wr_exp_max_buf_out = 'd0;
            data_wr_exp_max_buf_out_vld = 1'b0;
            k_exp_max_buf_out_rdy = 1'b0;
            v_exp_max_buf_out_rdy = 1'b0;
            si_fp_macro_result = 'd0;
            si_fp_macro_result_vld = 1'b0;
            attn_fp_macro_result = 'd0;
            attn_fp_macro_result_vld = 1'b0;
            fp_macro_result_rdy = 1'b0;
        end 
    endcase 
end

//-----------------------------------------pre_align-------------------------------------//
GEMV_shared_block1 # (
    .EXP_WIDTH                                              (EXP_WIDTH),
    .MANTISSA_WIDTH                                         (MANTISSA_WIDTH),
    .SIGN_WIDTH                                             (SIGN_WIDTH),
    .FP_WIDTH                                               (FP_WIDTH),
    .CMP_STAGES_PER_REG                                     (PRE_ALIGN_CMP_STAGES_PER_REG),
    .PARALLEL_ROW                                           (PARALLEL_ROW),
    .MACRO_DATA_WIDTH                                       (MACRO_DATA_WIDTH)
)GEMV_shared_block1_inst (
    .clk                                                    (clk),
    .rst_n                                                  (rst_n),

    .data_wr                                                (data_wr),
    .data_wr_vld                                            (data_wr_vld),
    .data_wr_rdy                                            (data_wr_rdy),

    .mantissa_plus_aligned                                  (data_wr_mantissa_plus_aligned),
    .exp_max                                                (data_wr_exp_max),
    .mantissa_plus_aligned_vld                              (data_wr_mantissa_plus_aligned_vld),
    .mantissa_plus_aligned_rdy                              (data_wr_mantissa_plus_aligned_rdy)
);


//-----------------------------------------KV Cache-------------------------------------//
//kv,exp_buf,addr
M3D_unshared_block1 # (
    .MACRO_COLUMN                                           (K_MACRO_COLUMN),
    .MACRO_ROW                                              (K_MACRO_ROW),
    .BANK_COLUMN                                            (K_BANK_COLUMN),
    .BANK_ROW                                               (K_BANK_ROW),
    .EXP_WIDTH                                              (EXP_WIDTH),
    .MANTISSA_WIDTH                                         (MANTISSA_WIDTH),
    .SIGN_WIDTH                                             (SIGN_WIDTH),
    .FP_WIDTH                                               (FP_WIDTH),
    .Q_BUF_ADDR_WIDTH                                       ($clog2(K_MACRO_COLUMN)),
    .COMPUTE_CYCLE                                          (COMPUTE_CYCLE),
    .BANK_NUM                                               (BANK_NUM),
    .log2_MACRO_ROW                                         ($clog2(K_MACRO_ROW)),
    .log2_MACRO_COLUMN                                      ($clog2(K_MACRO_COLUMN)),
    .PARALLEL_ROW                                           (PARALLEL_ROW),
    .MACRO_DATA_WIDTH                                       ((K_BANK_COLUMN/K_MACRO_COLUMN)),
    .MACROS_ADDR_WIDTH                                      ($clog2(K_MACRO_ROW) + $clog2(K_MACRO_COLUMN))
  )K_M3D_unshared_block1(
    .clk                                                    (clk),
    .rst_n                                                  (rst_n),
    .we                                                     ((state == WRITE_K)? 1'b1 : 1'b0),
    .cme                                                    ((state == GEMV1_MAX)? 1'b1 : 1'b0),
    .data_in_exp_max                                        (k_wr_exp_max), //q & k
    .data_in_mantissa_plus_aligned                          (k_wr_mantissa_plus_aligned),
    .data_in_vld                                            (k_wr_mantissa_plus_aligned_vld),
    .data_in_rdy                                            (k_wr_mantissa_plus_aligned_rdy),
    .nmc_cmOut                                              (si_cmOut),
    .nmc_cmOut_vld                                          (si_cmOut_vld),
    .nmc_cmOut_rdy                                          (si_cmOut_rdy),
    .data_wr_exp_max_addr                                   (k_exp_max_addr),
    .data_wr_exp_max_buf_out_rdy                            (k_exp_max_buf_out_rdy),
    .data_wr_exp_max_buf_out                                (k_exp_max_buf_out),
    .data_wr_exp_max_buf_out_vld                            (k_exp_max_buf_out_vld),
    .nmc_exp_max_buf_out_rdy                                (q_exp_max_buf_out_rdy),
    .nmc_exp_max_addr                                       (q_exp_max_addr),
    .nmc_exp_max_buf_out_vld                                (q_exp_max_buf_out_vld),
    .nmc_exp_max_buf_out                                    (q_exp_max_buf_out)
);

M3D_unshared_block1 # (
    .MACRO_COLUMN                                           (V_MACRO_COLUMN),
    .MACRO_ROW                                              (V_MACRO_ROW),
    .BANK_COLUMN                                            (V_BANK_COLUMN),
    .BANK_ROW                                               (V_BANK_ROW),
    .EXP_WIDTH                                              (EXP_WIDTH),
    .MANTISSA_WIDTH                                         (MANTISSA_WIDTH),
    .SIGN_WIDTH                                             (SIGN_WIDTH),
    .FP_WIDTH                                               (FP_WIDTH),
    .Q_BUF_ADDR_WIDTH                                       ($clog2(V_MACRO_COLUMN)),
    .COMPUTE_CYCLE                                          (COMPUTE_CYCLE),
    .BANK_NUM                                               (BANK_NUM),
    .log2_MACRO_ROW                                         ($clog2(V_MACRO_ROW)),
    .log2_MACRO_COLUMN                                      ($clog2(V_MACRO_COLUMN)),
    .PARALLEL_ROW                                           (PARALLEL_ROW),
    .MACRO_DATA_WIDTH                                       ((V_BANK_COLUMN/V_MACRO_COLUMN)),
    .MACROS_ADDR_WIDTH                                      ($clog2(V_MACRO_ROW) + $clog2(V_MACRO_COLUMN))
  )V_M3D_unshared_block1(
    .clk                                                    (clk),
    .rst_n                                                  (rst_n),
    .we                                                     ((state == WRITE_V)? 1'b1 : 1'b0),
    .cme                                                    ((state == EXP_GEMV2_RCP)? 1'b1 : 1'b0),
    .data_in_exp_max                                        (v_wr_exp_max), //p & V
    .data_in_mantissa_plus_aligned                          (v_wr_mantissa_plus_aligned),
    .data_in_vld                                            (v_wr_mantissa_plus_aligned_vld),
    .data_in_rdy                                            (v_wr_mantissa_plus_aligned_rdy),
    .nmc_cmOut                                              (attn_cmOut),
    .nmc_cmOut_vld                                          (attn_cmOut_vld),
    .nmc_cmOut_rdy                                          (attn_cmOut_rdy),
    .data_wr_exp_max_addr                                   (v_exp_max_addr),
    .data_wr_exp_max_buf_out_rdy                            (v_exp_max_buf_out_rdy),
    .data_wr_exp_max_buf_out                                (v_exp_max_buf_out),
    .data_wr_exp_max_buf_out_vld                            (v_exp_max_buf_out_vld),
    .nmc_exp_max_buf_out_rdy                                (pi_exp_max_buf_out_rdy),
    .nmc_exp_max_addr                                       (pi_exp_max_addr),
    .nmc_exp_max_buf_out_vld                                (pi_exp_max_buf_out_vld),
    .nmc_exp_max_buf_out                                    (pi_exp_max_buf_out)
);

//-----------------------------------------adder & bit-serial shifter-------------------------------------//
GEMV_shared_block2 # (
    .BANK_DATA_WIDTH                                        (PARALLEL_ROW * MACRO_DATA_WIDTH),
    .BANK_NUM                                               (BANK_NUM),
    .MACRO_DATA_WIDTH                                       (MACRO_DATA_WIDTH),
    .ROUND                                                  (K_MACRO_COLUMN*K_MACRO_ROW),
    .EXP_WIDTH                                              (EXP_WIDTH),
    .MANTISSA_WIDTH                                         (MANTISSA_WIDTH),
    .SIGN_WIDTH                                             (SIGN_WIDTH),
    .FP_WIDTH                                               (FP_WIDTH),
    .PARALLEL_ROW                                           (PARALLEL_ROW),
    .ADDER_TREE_WIDTH                                       (ADDER_TREE_WIDTH),
    .BIT_SERIAL_ACC_WIDTH                                   (BIT_SERIAL_ACC_WIDTH),
    .COMPUTE_CYCLE                                          (COMPUTE_CYCLE)
  )GEMV_shared_block2_inst (
    .clk                                                    (clk),
    .rst_n                                                  (rst_n),
    .nmc_cmOut                                              (cmOut),
    .nmc_cmOut_vld                                          (cmOut_vld),
    .nmc_cmOut_rdy                                          (cmOut_rdy),
    .bit_serial_acc_vld                                     (bit_serial_acc_vld),
    .bit_serial_acc_rdy                                     (bit_serial_acc_rdy),
    .nmc_exp_max                                            (nmc_exp_max),
    .nmc_exp_max_vld                                        (nmc_exp_max_vld),
    .nmc_exp_max_rdy                                        (nmc_exp_max_rdy),
    .data_wr_exp_max                                        (data_wr_exp_max_buf_out),
    .data_wr_exp_max_vld                                    (data_wr_exp_max_buf_out_vld),
    .data_wr_exp_max_rdy                                    (data_wr_exp_max_buf_out_rdy),
    .fp_macro_result                                        (fp_macro_result),
    .fp_macro_result_vld                                    (fp_macro_result_vld),
    .fp_macro_result_rdy                                    (fp_macro_result_rdy)
);

//-----------------------------------------col_accumulation-------------------------------------//
M3D_unshared_block2 # (
    .MACRO_ROW                                              (K_MACRO_ROW),
    .MACRO_COLUMN                                           (K_MACRO_COLUMN),
    .MACROS_ADDR_WIDTH                                      ($clog2(K_MACRO_COLUMN) + $clog2(K_MACRO_ROW)),
    .EXP_WIDTH                                              (EXP_WIDTH),
    .MANTISSA_WIDTH                                         (MANTISSA_WIDTH),
    .SIGN_WIDTH                                             (SIGN_WIDTH),
    .FP_WIDTH                                               (FP_WIDTH),
    .PARALLEL_ROW                                           (PARALLEL_ROW),
    .Q_BUF_ADDR_WIDTH                                       ($clog2(K_MACRO_COLUMN))
)K_M3D_unshared_block2(
    .clk                                                    (clk),
    .rst_n                                                  (rst_n),
    .bit_serial_acc_vld                                     (si_bit_serial_acc_vld),
    .bit_serial_acc_rdy                                     (si_bit_serial_acc_rdy),
    .nmc_exp_max_addr                                       (q_exp_max_addr),
    .data_wr_exp_max_addr                                   (k_exp_max_addr),
    .fp_macro_result                                        (si_fp_macro_result),
    .fp_macro_result_vld                                    (si_fp_macro_result_vld),
    .fp_macro_result_rdy                                    (si_fp_macro_result_rdy),
    .fp_col_block_result                                    (si_fp_col_block_result),
    .fp_col_block_result_vld                                (si_fp_col_block_result_vld),
    .fp_col_block_result_rdy                                (si_fp_col_block_result_rdy)
);

assign si_fp_macro_result_counter_will_max_now = (si_fp_macro_result_counter == (K_BANK_ROW/PARALLEL_ROW) - 1);
always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        si_fp_macro_result_counter <= 0;
    end
    else begin
        if (si_fp_col_block_result_vld && si_fp_col_block_result_rdy) begin
            si_fp_macro_result_counter <= (si_fp_macro_result_counter_will_max_now) ? 0 :si_fp_macro_result_counter + 1'b1;
        end
    end
end

M3D_unshared_block2 # (
    .MACRO_ROW                                              (V_MACRO_ROW),
    .MACRO_COLUMN                                           (V_MACRO_COLUMN),
    .MACROS_ADDR_WIDTH                                      ($clog2(V_MACRO_COLUMN) + $clog2(V_MACRO_ROW)),
    .EXP_WIDTH                                              (EXP_WIDTH),
    .MANTISSA_WIDTH                                         (MANTISSA_WIDTH),
    .SIGN_WIDTH                                             (SIGN_WIDTH),
    .FP_WIDTH                                               (FP_WIDTH),
    .PARALLEL_ROW                                           (PARALLEL_ROW),
    .Q_BUF_ADDR_WIDTH                                       ($clog2(V_MACRO_COLUMN))
)V_M3D_unshared_block2(
    .clk                                                    (clk),
    .rst_n                                                  (rst_n),
    .bit_serial_acc_vld                                     (attn_bit_serial_acc_vld),
    .bit_serial_acc_rdy                                     (attn_bit_serial_acc_rdy),
    .nmc_exp_max_addr                                       (pi_exp_max_addr),
    .data_wr_exp_max_addr                                   (v_exp_max_addr),
    .fp_macro_result                                        (attn_fp_macro_result),
    .fp_macro_result_vld                                    (attn_fp_macro_result_vld),
    .fp_macro_result_rdy                                    (attn_fp_macro_result_rdy),
    .fp_col_block_result                                    (attn_fp_col_block_result),
    .fp_col_block_result_vld                                (attn_fp_col_block_result_vld),
    .fp_col_block_result_rdy                                (pi_sum_recip_ready)
);

//-----------------------------------------softmax-------------------------------------//

softmax_block1 # (
    .FP_WIDTH                                               (FP_WIDTH),
    .MANT_WIDTH                                             (MANTISSA_WIDTH),
    .EXP_WIDTH                                              (EXP_WIDTH),
    .PARALLEL_ROW                                           (PARALLEL_ROW),
    .K_MACRO_ROW                                            (K_MACRO_ROW),
    .FP_EXP_WIDTH                                           (EXP_WIDTH),
    .V_BANK_COLUMN                                          (V_BANK_COLUMN),
    .V_MACRO_COLUMN                                         (V_MACRO_COLUMN),
    .PARALLEL_COL                                           (V_BANK_COLUMN/V_MACRO_COLUMN)
  )softmax_block1_inst (
    .clk                                                    (clk),
    .rst_n                                                  (rst_n),
    .si_fp_col_block_result_vld                             (si_fp_col_block_result_vld),
    .si_fp_col_block_result_rdy                             (si_fp_col_block_result_rdy),
    .si_fp_col_block_result                                 (si_fp_col_block_result),
    .pi_vld                                                 (pi_vld),
    .pi_rdy                                                 (pi_rdy),
    .pi                                                     (pi)
  );

  softmax_block2 # (
    .EXP_WIDTH                                              (EXP_WIDTH),
    .MANTISSA_WIDTH                                         (MANTISSA_WIDTH),
    .SIGN_WIDTH                                             (SIGN_WIDTH),
    .FP_WIDTH                                               (FP_WIDTH),
    .PARALLEL_COL                                           ((V_BANK_COLUMN/V_MACRO_COLUMN)),
    .BANK_COL                                               (V_BANK_COLUMN)
  )softmax_block2_inst (
    .clk                                                    (clk),
    .rst_n                                                  (rst_n),
    .pi                                                     (pi),
    .pi_valid                                               (pi_vld),
    .pi_ready                                               (softmax_block2_pi_rdy),
    .pi_sum_recip                                           (pi_sum_recip),
    .pi_sum_recip_valid                                     (pi_sum_recip_valid),
    .pi_sum_recip_ready                                     (pi_sum_recip_ready)
  );

//   sync_fifo # (
//     .ADDR_WIDTH                                             (1),
//     .DATA_WIDTH                                             (PARALLEL_ROW * FP_WIDTH)
//   )attn_fp_col_block_result_fifo (
//     .aclk                                                   (clk),
//     .aresetn                                                (rst_n),
//     .data_in                                                (attn_fp_col_block_result),
//     .push                                                   (attn_fp_col_block_result_vld & ~attn_fp_col_block_result_fifo_full),
//     .full                                                   (attn_fp_col_block_result_fifo_full),
//     .data_out                                               (attn_fp_col_block_result_fifo_out),
//     .pull                                                   (pi_sum_recip_valid & ~attn_fp_col_block_result_fifo_empty & pi_sum_recip_ready),
//     .empty                                                  (attn_fp_col_block_result_fifo_empty)
//   );

  softmax_block3 # (
    .EXP_WIDTH                                              (EXP_WIDTH),
    .MANTISSA_WIDTH                                         (MANTISSA_WIDTH),
    .SIGN_WIDTH                                             (SIGN_WIDTH),
    .FP_WIDTH                                               (FP_WIDTH),
    .PARALLEL_ROW                                           (PARALLEL_ROW)
  )softmax_block3_inst (
    .clk                                                    (clk),
    .rst_n                                                  (rst_n),
    .pi_mul_vi                                              (attn_fp_col_block_result),
    .pi_sum_recip                                           (pi_sum_recip),
    .idata_valid                                            (attn_fp_col_block_result_vld),
    .idata_ready                                            (pi_sum_recip_ready),
    .odata                                                  (oi),
    .odata_valid                                            (oi_vld),
    .odata_ready                                            (oi_rdy)
  );

//------------------------------------------output-------------------------------------//
  write_controller # (
    .INPUT_WIDTH                                            (PARALLEL_ROW*FP_WIDTH),
    .INPUT_NUM                                              (1),
    .OUTPUT_NUM                                             (V_BANK_ROW/PARALLEL_ROW),
    .OUTPUT_RAM_WIDTH                                       (V_BANK_ROW*FP_WIDTH),
    .OUTPUT_RAM_DEPTH                                       ($clog2(V_BANK_ROW/V_MACRO_ROW))
  )write_controller_inst (
    .clk                                                    (clk),
    .aresetn                                                (rst_n),
    .ovalid                                                 (),
    .oready                                                 (o_out_rdy),
    .idata                                                  (oi),
    .ivalid                                                 (oi_vld),
    .iready                                                 (oi_rdy),
    .wdata                                                  (o_out),
    .waddr                                                  (),
    .wen                                                    (o_out_vld)
  );

initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, self_attention_top);
end

endmodule