module M3D_unshared_block1 #(
    parameter MACRO_COLUMN = 4,
    parameter MACRO_ROW = 32,
    parameter BANK_COLUMN = 64,
    parameter BANK_ROW = 1024,

    parameter EXP_WIDTH = 8,
	parameter MANTISSA_WIDTH = 7,
	parameter SIGN_WIDTH = 1,
	parameter FP_WIDTH = 16,

    parameter Q_BUF_ADDR_WIDTH = $clog2(MACRO_COLUMN), //2
    parameter COMPUTE_CYCLE = SIGN_WIDTH + MANTISSA_WIDTH + 1, //9
    parameter BANK_NUM = SIGN_WIDTH + MANTISSA_WIDTH + 1, //9
    parameter log2_MACRO_ROW = $clog2(MACRO_ROW), // 5
    parameter log2_MACRO_COLUMN = $clog2(MACRO_COLUMN), //2

    parameter PARALLEL_ROW  = (BANK_ROW/MACRO_ROW), //32
    parameter MACRO_DATA_WIDTH = (BANK_COLUMN/MACRO_COLUMN),//16
    parameter MACROS_ADDR_WIDTH = (log2_MACRO_COLUMN + log2_MACRO_ROW)
)(
    input                                                           clk,
    input                                                           rst_n, 
    input                                                           we,
    input                                                           cme,
    input [PARALLEL_ROW*EXP_WIDTH-1:0]                              data_in_exp_max, 
    input [PARALLEL_ROW*MACRO_DATA_WIDTH*COMPUTE_CYCLE-1:0]         data_in_mantissa_plus_aligned, 
    input                                                           data_in_vld,
    output                                                          data_in_rdy,

    output [PARALLEL_ROW * MACRO_DATA_WIDTH * BANK_NUM-1:0]         nmc_cmOut,
    output                                                          nmc_cmOut_vld,
    input                                                           nmc_cmOut_rdy,

    input [$clog2(MACRO_ROW * MACRO_COLUMN)-1 : 0 ]                 data_wr_exp_max_addr,
    input                                                           data_wr_exp_max_buf_out_rdy,
    output [PARALLEL_ROW * EXP_WIDTH - 1 : 0]                       data_wr_exp_max_buf_out,
    output                                                          data_wr_exp_max_buf_out_vld,

    input                                                           nmc_exp_max_buf_out_rdy,
    input [Q_BUF_ADDR_WIDTH - 1:0]                                  nmc_exp_max_addr,
    output                                                          nmc_exp_max_buf_out_vld,
    output [EXP_WIDTH - 1 : 0]                                      nmc_exp_max_buf_out
 

);

genvar i;

wire data_wr_rdy;
wire data_q_rdy;
wire [EXP_WIDTH - 1 : 0] exp_max_out;
wire [MACRO_DATA_WIDTH * (SIGN_WIDTH + MANTISSA_WIDTH + 1) - 1: 0] mantissa_plus_aligned_out,mantissa_plus_aligned_cmIn;
wire q_buf_wr_en,q_buf_rd_en;
wire [Q_BUF_ADDR_WIDTH - 1: 0] q_buf_wr_addr,q_buf_rd_addr;
wire mantissa_plus_aligned_cmIn_vld,mantissa_plus_aligned_cmIn_rdy;
wire q_buf_rd_addr_rdy;
wire [PARALLEL_ROW - 1: 0] data_wr_exp_max_buf_out_vld_temp;

wire [MACROS_ADDR_WIDTH-1: 0] nmc_addr, nmc_addr_wr;
wire nmc_addr_wr_vld;

wire [PARALLEL_ROW * MACRO_DATA_WIDTH * BANK_NUM-1:0] nmc_d;
wire [PARALLEL_ROW * MACRO_DATA_WIDTH * BANK_NUM-1:0] nmc_cmIn;
wire nmc_cmIn_vld;
wire nmc_cmIn_rdy;

//-----------------------------------------cmin & data_wr control-------------------------------------//

weight_write_control #(
    .BANK_DATA_WIDTH                                          (PARALLEL_ROW * MACRO_DATA_WIDTH),
    .BANK_NUM                                                 (BANK_NUM),
    .MACROS_ADDR_WIDTH                                        (MACROS_ADDR_WIDTH),
    .MACRO_COLUMN                                             (MACRO_COLUMN),
    .MACRO_ROW                                                (MACRO_ROW)
) u_weight_write_control (                               
    .clk                                                      (clk),          
    .rst_n                                                    (rst_n),        
                                                
    .data_wr                                                  (data_in_mantissa_plus_aligned),      
    .data_wr_vld                                              (data_in_vld & we),  
    .data_wr_rdy                                              (data_wr_rdy),  
                                            
    .nmc_addr_wr                                              (nmc_addr_wr), 
    .nmc_addr_wr_vld                                          (nmc_addr_wr_vld), 
    .nmc_d                                                    (nmc_d)         
);

cmIn_control # (
    .MACRO_DATA_WIDTH                                         (MACRO_DATA_WIDTH),
    .COMPUTE_CYCLE                                            (COMPUTE_CYCLE),
    .MACROS_ADDR_WIDTH                                        (MACROS_ADDR_WIDTH),
    .BANK_DATA_WIDTH                                          (PARALLEL_ROW * MACRO_DATA_WIDTH),
    .BANK_NUM                                                 (BANK_NUM),
    .MACRO_ROW                                                (MACRO_ROW),
    .MACRO_COLUMN                                             (MACRO_COLUMN),
    .COL_BLOCK_SIZE                                           (PARALLEL_ROW),
    .Q_BUF_ADDR_WIDTH                                         (Q_BUF_ADDR_WIDTH)
  )cmIn_control_inst (
    .clk                                                      (clk),
    .rst_n                                                    (rst_n),
    .data_in                                                  (mantissa_plus_aligned_cmIn),
    .data_in_vld                                              (mantissa_plus_aligned_cmIn_vld & cme),
    .data_in_rdy                                              (mantissa_plus_aligned_cmIn_rdy),
    .data_in_update                                           (q_buf_rd_addr_rdy),
    .nmc_addr                                                 (nmc_addr),
    .nmc_cmIn                                                 (nmc_cmIn),
    .nmc_cmIn_vld                                             (nmc_cmIn_vld),
    .nmc_cmIn_rdy                                             (nmc_cmIn_rdy)
  );


//-----------------------------------------weight_exp_max_store-------------------------------------//
generate
    for (i = 0; i < PARALLEL_ROW; i = i + 1) begin
        center_buf # (
            .DATA_WIDTH                                       (EXP_WIDTH),
            .DEPTH                                            (MACRO_ROW * MACRO_COLUMN),
            .log2_DEPTH                                       ($clog2(MACRO_ROW * MACRO_COLUMN))
        )u_data_wr_exp_max_buf (
            .clk                                              (clk),
            .rst_n                                            (rst_n),
            .wr_en                                            (nmc_addr_wr_vld),
            .wr_addr                                          (nmc_addr_wr),
            .wr_dat                                           (data_in_exp_max[i*EXP_WIDTH +: EXP_WIDTH]),
            .rd_en                                            (data_wr_exp_max_buf_out_rdy),
            .rd_addr                                          (data_wr_exp_max_addr),
            .rd_dat_vld                                       (data_wr_exp_max_buf_out_vld_temp[i]),
            .rd_dat                                           (data_wr_exp_max_buf_out[i*EXP_WIDTH +: EXP_WIDTH])
        );
    end
endgenerate
assign data_wr_exp_max_buf_out_vld = &data_wr_exp_max_buf_out_vld_temp;
//-----------------------------------------q cache---------------------------------------------------//
q_cache_control # (
    .Q_BUF_ADDR_WIDTH                                        (Q_BUF_ADDR_WIDTH),
    .MACRO_DATA_WIDTH                                        (MACRO_DATA_WIDTH),
    .MACRO_ROW                                               (MACRO_ROW),
    .EXP_WIDTH                                               (EXP_WIDTH),
    .MANTISSA_WIDTH                                          (MANTISSA_WIDTH),
    .SIGN_WIDTH                                              (SIGN_WIDTH),
    .FP_WIDTH                                                (FP_WIDTH),
    .COL_BLOCK_SIZE                                          (PARALLEL_ROW),
    .log2_COL_BLOCK_SIZE                                     ($clog2(PARALLEL_ROW))
)q_cache_control_inst (
    .clk                                                     (clk),
    .rst_n                                                   (rst_n),
    .exp_max                                                 (data_in_exp_max[EXP_WIDTH-1:0]),
    .mantissa_plus_aligned                                   (data_in_mantissa_plus_aligned[MACRO_DATA_WIDTH*COMPUTE_CYCLE-1:0]),
    .mantissa_plus_aligned_vld                               (data_in_vld & cme),
    .mantissa_plus_aligned_rdy                               (data_q_rdy),

    .exp_max_out                                             (exp_max_out),
    .mantissa_plus_aligned_out                               (mantissa_plus_aligned_out),
    .q_buf_wr_en                                             (q_buf_wr_en),
    .q_buf_wr_addr                                           (q_buf_wr_addr),
    .q_buf_rd_en                                             (q_buf_rd_en),
    .q_buf_rd_addr                                           (q_buf_rd_addr),
    .q_buf_rd_addr_rdy                                       (q_buf_rd_addr_rdy)
);

center_buf # (
    .DATA_WIDTH                                               (MACRO_DATA_WIDTH * (SIGN_WIDTH + MANTISSA_WIDTH + 1)),
    .DEPTH                                                    (MACRO_COLUMN),
    .log2_DEPTH                                               (Q_BUF_ADDR_WIDTH)
)u_q_buf_mantissa (        
    .clk                                                      (clk),
    .rst_n                                                    (rst_n),
    .wr_en                                                    (q_buf_wr_en & (cme)),
    .wr_addr                                                  (q_buf_wr_addr),
    .wr_dat                                                   (mantissa_plus_aligned_out),
    .rd_en                                                    (q_buf_rd_en & mantissa_plus_aligned_cmIn_rdy),
    .rd_addr                                                  (q_buf_rd_addr),
    .rd_dat_vld                                               (mantissa_plus_aligned_cmIn_vld),
    .rd_dat                                                   (mantissa_plus_aligned_cmIn)
);

center_buf # (
    .DATA_WIDTH                                               (EXP_WIDTH),
    .DEPTH                                                    (MACRO_COLUMN),
    .log2_DEPTH                                               ($clog2(MACRO_COLUMN))
)u_q_buf_exp (        
    .clk                                                      (clk),
    .rst_n                                                    (rst_n),
    .wr_en                                                    (q_buf_wr_en & (cme)),
    .wr_addr                                                  (q_buf_wr_addr),
    .wr_dat                                                   (exp_max_out),
    .rd_en                                                    (nmc_exp_max_buf_out_rdy),
    .rd_addr                                                  (nmc_exp_max_addr),
    .rd_dat_vld                                               (nmc_exp_max_buf_out_vld),
    .rd_dat                                                   (nmc_exp_max_buf_out)
);


//-----------------------------------------DRAM------------------------------------------------//

//channel <=> macros
DRAM_banks #(
    .MACROS_ADDR_WIDTH                                        (MACROS_ADDR_WIDTH), 
    .BANK_DATA_WIDTH                                          (PARALLEL_ROW * MACRO_DATA_WIDTH),   
    .BANK_NUM                                                 (BANK_NUM),          
    .COL_BLOCK_SIZE                                           (PARALLEL_ROW),          
    .MACRO_DATA_WIDTH                                         (MACRO_DATA_WIDTH),          
    .MACRO_COLUMN                                             (MACRO_COLUMN),           
    .MACRO_ROW                                                (MACRO_ROW)       
) u_dram_banks(                        
    .clk                                                      (clk),
    .rst_n                                                    (rst_n),
                
    .nmc_addr                                                 (cme? nmc_addr : nmc_addr_wr),
    .nmc_we                                                   (nmc_addr_wr_vld),
    .nmc_cme                                                  (cme),
                
    .nmc_d                                                    (nmc_d),
                    
    .nmc_cmIn                                                 (nmc_cmIn),
    .nmc_cmIn_vld                                             (nmc_cmIn_vld),
    .nmc_cmIn_rdy                                             (nmc_cmIn_rdy),
                
    .nmc_q                                                    (),
    .nmc_cmOut                                                (nmc_cmOut),
    .nmc_cmOut_vld                                            (nmc_cmOut_vld),
    .nmc_cmOut_rdy                                            (nmc_cmOut_rdy)
);  

assign data_in_rdy = (we) ? data_wr_rdy : data_q_rdy;
endmodule