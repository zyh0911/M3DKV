
module center_buf #
(
	parameter DATA_WIDTH=256,
	parameter DEPTH = 32,
	parameter log2_DEPTH = 5
)
(
	input clk,
	input rst_n,

	//Wr Port
	input wr_en,
	input [log2_DEPTH-1:0]wr_addr,
	input [DATA_WIDTH-1:0]wr_dat,

	//Rd Port
	input rd_en,
	input [log2_DEPTH-1:0]rd_addr,
	output reg rd_dat_vld,
	output reg [DATA_WIDTH-1:0] rd_dat
);

reg [DATA_WIDTH-1:0] mem [DEPTH-1:0];

integer i;
always @(posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		rd_dat_vld <= 'd0;
		rd_dat <= 'd0;
	end else begin
		if (rd_en) begin
			rd_dat <= mem[rd_addr];
		end
		if (wr_en) begin
			mem[wr_addr] <= wr_dat;
		end
		rd_dat_vld <= rd_en;			
	end
end

endmodule
