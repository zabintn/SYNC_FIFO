`timescale 1ns/1ps

module sync_fifo #(
	parameter DEPTH=8,
	parameter DATA_WIDTH=16,
	parameter ADDR_WIDTH=$clog2(DEPTH)
	)(
		input clk, rstn,
		input wr_en, rd_en,
		input [DATA_WIDTH-1:0] wdata,
		output reg [DATA_WIDTH-1:0] rdata,
		output full, empty

	);

		reg [DATA_WIDTH-1:0] mem[0:DEPTH-1];
		reg [ADDR_WIDTH:0] wptr, rptr;

		//write logic
	
	always @(posedge clk or negedge rstn) begin
		if (!rstn)
			wptr<=0;
		else if (wr_en && (!full||rd_en)) begin
			mem[wptr[ADDR_WIDTH-1:0]]<=wdata;
			wptr<=wptr+1;
		end
	end

		//read logic
	
	always @(posedge clk or negedge rstn) begin
		if (!rstn) begin
			rptr<=0;
			rdata<=0;
		end
		else if (rd_en && (!empty||wr_en)) begin
			rdata<=mem[rptr[ADDR_WIDTH-1:0]];
			rptr<=rptr+1;
		end
		else if (rd_en && empty && !wr_en) begin
			rdata<=0;
		end
	end

	//assign full and empty flag
	

	assign empty= (wptr==rptr);
	assign full= (wptr[ADDR_WIDTH] != rptr[ADDR_WIDTH] && wptr[ADDR_WIDTH-1:0]==rptr[ADDR_WIDTH-1:0]);
	endmodule
	
			
