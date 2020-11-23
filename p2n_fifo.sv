module p2n_fifo (clk, rst, data_in, rd_en, wr_en, data_out, empty, full); 

parameter DATA_WIDTH = 9;
parameter ADDR_WIDTH = 8;
parameter RAM_DEPTH = (1 << ADDR_WIDTH);

input   logic                  clk      ; // Clock input
input   logic                  rst      ; // Active high reset
input   logic [DATA_WIDTH-1:0] data_in  ; // Data input
input   logic                  rd_en    ; // Read enable
input   logic                  wr_en    ; // Write Enable
output  logic [DATA_WIDTH-1:0] data_out ; // Data Output
output  logic                  empty    ; // FIFO empty
output  logic                  full     ; // FIFO full

//-----------Internal variables-------------------
reg [ADDR_WIDTH-1:0] wr_pointer;
reg [ADDR_WIDTH-1:0] rd_pointer;
reg [ADDR_WIDTH :0] status_cnt;
wire [DATA_WIDTH-1:0] data_ram;
reg [DATA_WIDTH-1:0] fifo_mem [RAM_DEPTH-1:0];
integer i;
//-----------Variable assignments---------------
assign full = (status_cnt == (RAM_DEPTH-1));
assign empty = (status_cnt == 0);
//-----------Code Start---------------------------
always_ff @ (posedge clk or posedge rst)
begin : WRITE_POINTER
  if (rst) begin
    wr_pointer <= #1 0;
  end else if (wr_en) begin
    wr_pointer <= #1 wr_pointer + 1;
  end
end

always_ff @ (posedge clk or posedge rst)
begin : READ_POINTER
  if (rst) begin
    rd_pointer <= #1 0;
  end else if (rd_en) begin
    rd_pointer <= #1 rd_pointer + 1;
  end
end

always_ff @ (posedge clk or posedge rst) begin: WRITE_DATA
	if (rst) begin
		for (i=0; i<RAM_DEPTH; i=i+1)
			fifo_mem[i] <= #1 0;
	end
	else begin
		if (wr_en && !full)
			fifo_mem[wr_pointer] <= #1 data_in;
//		else
//			fifo_mem[wr_pointer] <= #1 
	end
end

always_ff  @ (posedge clk or posedge rst)
begin : READ_DATA
  if (rst) begin
    data_out <= #1 9'b100000000;
  end else if (rd_en) begin
    data_out <= #1 fifo_mem[rd_pointer];
  end else if (~rd_en) begin
    data_out <= #1 9'b100000000;
  end
end

always_ff @ (posedge clk or posedge rst)
begin : STATUS_COUNTER
  if (rst) begin
    status_cnt <= #1 0;
  // Read but no write.
  end else if ((rd_en) && (!wr_en) 
                && (status_cnt != 0)) begin
    status_cnt <= #1 status_cnt - 1;
  // Write but no read.
  end else if ((wr_en) && (!rd_en) 
               && (status_cnt != RAM_DEPTH)) begin
    status_cnt <= #1 status_cnt + 1;
  end
end  

endmodule
