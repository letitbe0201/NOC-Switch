`include "fifo.sv"
`include "edge_det.sv"

module noc_intf(
	input clk,
	input rst,
	input noc_to_dev_ctl,
	input [7:0] noc_to_dev_data,
	output reg noc_from_dev_ctl,
	output reg [7:0] noc_from_dev_data,
	output reg pushin,
	output reg firstin,
	input stopin,
	output reg [63:0] din,
	input pushout,
	input firstout,
	output reg stopout,
	input [63:0] dout
);

	// GET (Receiving) command/data
	enum [3:0] {
		G_IDLE,
		G_R0, // READ  | Alen | Dlen | 001
		G_R1,
		G_R2,
		G_R3,
		G_W0, // WRITE | Alen | Dlen | 010
		G_W1,
		G_W2,
		G_W3,
		G_W4_DATA
	} get_curr_state, get_next_state;

	logic [1:0] Alen;
	logic [2:0] Dlen;
	logic [7:0] D_id, S_id;
	logic [3:0] exp_Alen, Al_cnt; // Expected actual address length
	logic [7:0] exp_Dlen, Dl_cnt; // Expected actual data length
	logic [7:0] actual_Dlen; // Count tht writing data from NOC to the interface (0-199)
	logic get_last_addr; // Indicate the last address received in read/write command
	logic get_last_data;
	logic [2:0] intf_perm_index; // Index for writing to the perm (0-7)
	logic [4:0] perm_index; // Index for 25 set (0-24) of 64-bit data
	

	// Response to read/write command
	enum [3:0] {
		R_IDLE,
		R_CMD, // Get command from FIFO
		R_R0, // Read Resp  | RC | 000011
		R_R1,
		R_R2,
		R_R3,
		R_R4_DATA,
		R_W0, // Write Resp | RC | 000100
		R_W1,
		R_W2,
		R_W3,
		R_M0, // Message    | AL | Dlen | 101
		R_M1,
		R_M2,
		R_M3,
		R_M4
	} resp_curr_state, resp_next_state;

	enum [2:0] {
		NOP,
		WR_RSP,
		RD_RSP,
		MG_RSP
	} send_rsp;

	logic partial_wr;
	logic partial_rd;
	logic falling_stopin;
	logic rising_pushout;
	logic [7:0] exp_Dlen_rsp;
	logic [7:0] Dl_cnt_rsp;
	logic [7:0] actual_Dlen_rsp; // 0-200
	logic [63:0] dout_r;
	
	logic [36:0] fifo_out, fifo_in;
	logic wr_en;
	logic fifo_empty;
	logic rd_fifo;
//	logic [3:0] wr_rcv; // Rise if a Write command received. Fall if the output is read

	// WR (30-bit) [cmd:3 | rc:2 | did:8 | sid:8 | al:8 | 0]
	// RD (30-bit) [cmd:3 | rc:2 | did:8 | sid:8 | al:8 | 0]
	// MSG(35-bit) [cmd:3 | 0    | did:8 | sid:8 | msgaddr:8 | msgdata:8]
	sync_fifo f (
		.clk(clk),
		.rst(rst),
		.data_in(fifo_in),
		.rd_en(rd_fifo),
		.wr_en(wr_en), // Writing enable triggered by get_last_data
		.data_out(fifo_out),
		.empty(fifo_empty),
		.full()
	);
	// Falling edge detector for stopin
	edge_det ed_f (
		.clk(clk),
		.rst(rst),
		.rising_or_falling(1'b0),
		.sig(stopin),
		.edge_detected(falling_stopin)
	);
	// Rising edge detector for pushout
	edge_det ed_r (
		.clk(clk),
		.rst(rst),
		.rising_or_falling(1'b1),
		.sig(pushout),
		.edge_detected(rising_pushout)
	);


	always_ff @ (posedge clk or posedge rst) begin
		if (rst)
			get_curr_state <= #1 G_IDLE;
		else
			get_curr_state <= #1 get_next_state;
	end
	// State machine for RECEIVING command
	always_comb begin
		get_next_state = get_curr_state; 
		case (get_curr_state)
			G_IDLE      :
				if (noc_to_dev_ctl && (noc_to_dev_data[2:0]==3'b001))
					get_next_state = G_R0;
				else if (noc_to_dev_ctl && (noc_to_dev_data[2:0]==3'b010))
					get_next_state = G_W0;
			G_R0     : get_next_state = G_R1;
			G_R1     : get_next_state = G_R2;
			G_R2     : get_next_state = G_R3;
			G_R3     : if (get_last_addr) get_next_state = G_IDLE;
			G_W0     : get_next_state = G_W1;
			G_W1     : get_next_state = G_W2;
			G_W2     : get_next_state = G_W3;
			G_W3     : if (get_last_addr) get_next_state = G_W4_DATA;
			G_W4_DATA: if (get_last_data) get_next_state = G_IDLE; 
		endcase
	end
	// Received Address length, data length, destination id, source id
	always_ff @ (posedge clk or posedge rst) begin
		if (rst) begin
			Alen <= #1 0;
			Dlen <= #1 0;
			D_id <= #1 0;
			S_id <= #1 0;
		end
		else begin
			if (noc_to_dev_ctl && (get_curr_state==G_IDLE)) begin
				Alen <= #1 noc_to_dev_data[7:6];
				Dlen <= #1 noc_to_dev_data[5:3];
			end
			else if (get_curr_state==G_R0 || get_curr_state==G_W0)
				D_id <= #1 noc_to_dev_data;
			else if (get_curr_state==G_R1 || get_curr_state==G_W1)
				S_id <= #1 noc_to_dev_data;	
		end
	end
	// Decode address length
	always_comb begin
		exp_Alen = 0;
		case (Alen)
			0: exp_Alen = 1; 
			1: exp_Alen = 2;
			2: exp_Alen = 4;
			3: exp_Alen = 8;
		endcase
	end
	// Decode data length
	always_comb begin
		exp_Dlen = 0;
		case (Dlen)
			0: exp_Dlen = 1;
			1: exp_Dlen = 2;
			2: exp_Dlen = 4;
			3: exp_Dlen = 8;
			4: exp_Dlen = 16;
			5: exp_Dlen = 32;
			6: exp_Dlen = 64;
			7: exp_Dlen = 128;
		endcase
	end
	// Count the address number in one receiving command
	always_ff @ (posedge clk or posedge rst) begin
		if (rst) begin
			Al_cnt <= #1 0;
		end
		else begin
			if (Al_cnt == exp_Alen) 
				Al_cnt <= #1 0;
			else if (get_curr_state==G_R2 || get_curr_state==G_W2 || get_curr_state==G_R3 || get_curr_state==G_W3)
				Al_cnt <= #1 Al_cnt + 1;
		end
	end
	// Get the last address in a single command
	assign get_last_addr = (Al_cnt == exp_Alen);
	// Count the number of data in one receiving command
	always_ff @ (posedge clk or posedge rst) begin
		if (rst) begin
			Dl_cnt <= #1 0; 
		end
		else begin
			if (Dl_cnt == (exp_Dlen-1))
				Dl_cnt <= #1 0;
			else if ((get_curr_state==G_W4_DATA) || ((get_curr_state==G_W3)&&(get_last_addr)))
				Dl_cnt <= #1 Dl_cnt + 1;
		end
	end
	// Get the last data in WRITE command
	assign get_last_data = ((Dl_cnt == (exp_Dlen-1)) && (get_curr_state == G_W4_DATA));
	// 0-199
	always_ff @ (posedge clk or posedge rst) begin
		if (rst)
			actual_Dlen <= #1 0;
		else begin
			if (get_last_data && perm_index==24)
				actual_Dlen <= #1 0;
			else if ((get_curr_state==G_W4_DATA) || ((get_curr_state==G_W3)&&(get_last_addr)))
				actual_Dlen <= #1 actual_Dlen + 1;
		end
	end
	// 0-7
	always_ff @ (posedge clk or posedge rst) begin
		if (rst) begin
			intf_perm_index <= #1 0;
		end
		else begin
			if (intf_perm_index == 7) begin
				intf_perm_index <= #1 0;
			end
			else if ((get_curr_state==G_W4_DATA) || ((get_curr_state==G_W3)&&(get_last_addr)))
				intf_perm_index <= #1 intf_perm_index + 1;
		end
	end

	always_ff @ (posedge clk or posedge rst) begin
		if (rst) begin
			din <= #1 0;
		end
		else if ((get_curr_state==G_W4_DATA) || ((get_curr_state==G_W3)&&(get_last_addr))) begin
			case (intf_perm_index)
				0: din[7:0] <= #1 noc_to_dev_data;
				1: din[15:8] <= #1 noc_to_dev_data;
				2: din[23:16] <= #1 noc_to_dev_data;
				3: din[31:24] <= #1 noc_to_dev_data;
				4: din[39:32] <= #1 noc_to_dev_data;
				5: din[47:40] <= #1 noc_to_dev_data;
				6: din[55:48] <= #1 noc_to_dev_data;
				7: din[63:56] <= #1 noc_to_dev_data;
			endcase
		end
	end

	always_ff @ (posedge clk or posedge rst) begin
		if (rst)
			pushin <= #1 0;
		else begin
			if (intf_perm_index == 7)
				pushin <= #1 1;
			else
				pushin <= #1 0;
		end
	end
	// 0-24
	always_ff @ (posedge clk or posedge rst) begin
		if (rst)
			perm_index <= #1 0;
		else begin
			if (perm_index == 25)
				perm_index <= #1 0;
			else if (pushin)
				perm_index <= #1 perm_index + 1;
		end
	end

	assign firstin = ((intf_perm_index==0) && (perm_index==0) && pushin);// (get_curr_state==G_W4_DATA)); /////////////////////////////
	// 1 when partial write happens
	assign partial_wr = (get_last_data && (actual_Dlen>199));

	assign partial_rd = ((200-actual_Dlen_rsp) < exp_Dlen);

	always_ff @ (posedge clk or posedge rst) begin
		if (rst) begin
			fifo_in <= #1 0;
		end
		else if (((!get_last_data)^(get_last_addr&&(get_curr_state==G_R3))^falling_stopin^rising_pushout) && (get_last_data&&(get_last_addr&&(get_curr_state==G_R3))&&falling_stopin&&rising_pushout))
			$display("\nERROR: Request a falling stopin message and write response at the same time\n");
		else if (get_last_addr&&(get_curr_state==G_R3)) begin
			fifo_in[36:34] <= #1 RD_RSP;
			fifo_in[33:32] <= #1 (partial_rd) ? 2'b10 : 2'b00 ; // RC, without write error
			fifo_in[31:24] <= #1 D_id;
			fifo_in[23:16] <= #1 S_id;
			fifo_in[15:8] <= #1 (partial_rd) ? (200-actual_Dlen_rsp) : exp_Dlen;
			fifo_in[7:0] <= #1 0;
		end
		else if (falling_stopin) begin // Send a message when stopin 1->0
			fifo_in[36:34] <= #1 MG_RSP;
			fifo_in[31:24] <= #1 D_id;
			fifo_in[23:16] <= #1 S_id;
			fifo_in[15:8] <= #1 8'h42;
			fifo_in[7:0] <= #1 8'h78;
		end
		else if (rising_pushout) begin // Send a message when pushout 0->1
			fifo_in[36:34] <= #1 MG_RSP;
			fifo_in[31:24] <= #1 D_id;
			fifo_in[23:16] <= #1 S_id;
			fifo_in[15:8] <= #1 8'h17;
			fifo_in[7:0] <= #1 8'h12;
		end
		else if (get_last_data) begin // Write Response to FIFO triggered by get_last_data
			fifo_in[36:34] <= #1 WR_RSP;
			fifo_in[33:32] <= #1 (partial_wr) ? 2'b10 : 2'b00 ; // RC, without write error
			fifo_in[31:24] <= #1 D_id;
			fifo_in[23:16] <= #1 S_id;
			fifo_in[15:8] <= #1 (partial_wr) ? (200-(Dl_cnt+1-exp_Dlen)) : exp_Dlen;
			fifo_in[7:0] <= #1 0;
		end
	end
	// Write enable to FIFO
	always_ff @ (posedge clk or posedge rst) begin
		if (rst)
			wr_en <= #1 0;
		else begin
			if (get_last_data ^ falling_stopin ^ rising_pushout ^ (get_last_addr&&(get_curr_state==G_R3)))
				wr_en <= #1 1;
			else
				wr_en <= #1 0;
		end
	end
	// State machine for RESPONSE
	always_ff @ (posedge clk or posedge rst) begin
		if (rst)
			resp_curr_state <= #1 R_IDLE;
		else
			resp_curr_state <= #1 resp_next_state;
	end

	always_comb begin
		resp_next_state = resp_curr_state;
		case (resp_curr_state)
			R_IDLE   :
				if (rd_fifo) begin
					resp_next_state = R_CMD;	
				end
			R_CMD    : 
				case (fifo_out[36:34])
//					NOP: $display("\nFIFO ERROR\n", $time);
					WR_RSP: resp_next_state = R_W0;
					RD_RSP: resp_next_state = R_R0;
					MG_RSP: resp_next_state = R_M0;
				endcase
			R_R0     : begin 
//				if (wr_rcv)
					resp_next_state = R_R1;
//				else
//					resp_next_state = R_IDLE;
			end
			R_R1     : resp_next_state = R_R2;
			R_R2     : resp_next_state = R_R3;
			R_R3     : resp_next_state = R_R4_DATA;
			R_R4_DATA:
				if (Dl_cnt_rsp == exp_Dlen_rsp-1)
					resp_next_state = R_IDLE;
			R_W0     : resp_next_state = R_W1;
			R_W1     : resp_next_state = R_W2;
			R_W2     : resp_next_state = R_W3;
			R_W3     : resp_next_state = R_IDLE;
			R_M0     : resp_next_state = R_M1;
			R_M1     : resp_next_state = R_M2;
			R_M2     : resp_next_state = R_M3;
			R_M3     : resp_next_state = R_M4;
			R_M4     : resp_next_state = R_IDLE;
		endcase
	end

	assign rd_fifo = ((!fifo_empty) && (resp_curr_state==R_IDLE));

	always_ff @ (posedge clk or posedge rst) begin
		if (rst)
			noc_from_dev_ctl <= #1 1;
		else begin
			if (resp_curr_state==R_R1 || resp_curr_state==R_R2 || resp_curr_state==R_R3 || resp_curr_state==R_R4_DATA || resp_curr_state==R_W1 || resp_curr_state==R_W2 || resp_curr_state==R_W3 || resp_curr_state==R_M1 || resp_curr_state==R_M2 || resp_curr_state==R_M3 || resp_curr_state==R_M4)
				noc_from_dev_ctl <= #1 0;
			else
				noc_from_dev_ctl <= #1 1;
		end
	end

	always_ff @ (posedge clk or posedge rst) begin
		if (rst)
			noc_from_dev_data <= #1 0;
		else begin
			case (resp_curr_state)
				// WRITE RESPONSE
				R_W0: noc_from_dev_data <= #1 {fifo_out[33:32], 6'b000100}; // RC
				R_W1: noc_from_dev_data <= #1 fifo_out[31:24];              // D ID
				R_W2: noc_from_dev_data <= #1 fifo_out[23:16];              // S ID
				R_W3: noc_from_dev_data <= #1 fifo_out[15:8];               // Actual Length
				// READ RESPONSE
				R_R0: begin
//					if (wr_rcv)
						noc_from_dev_data <= #1 {fifo_out[33:32], 6'b000011};
//					else
//						noc_from_dev_data <= #1 8'bx;
				end
				R_R1: noc_from_dev_data <= #1 fifo_out[31:24];
				R_R2: noc_from_dev_data <= #1 fifo_out[23:16];
				R_R3: noc_from_dev_data <= #1 fifo_out[15:8];
				R_R4_DATA:
					case (Dl_cnt_rsp[2:0])
						0: noc_from_dev_data <= #1 dout[7:0];
						1: noc_from_dev_data <= #1 dout[15:8];
						2: noc_from_dev_data <= #1 dout_r[23:16];
						3: noc_from_dev_data <= #1 dout_r[31:24];
						4: noc_from_dev_data <= #1 dout_r[39:32];
						5: noc_from_dev_data <= #1 dout_r[47:40];
						6: noc_from_dev_data <= #1 dout_r[55:48];
						7: noc_from_dev_data <= #1 dout_r[63:56];
					endcase
				// MESSAGE
				R_M0: noc_from_dev_data <= #1 8'b00000101;
				R_M1: noc_from_dev_data <= #1 fifo_out[31:24];
				R_M2: noc_from_dev_data <= #1 fifo_out[23:16];
				R_M3: noc_from_dev_data <= #1 fifo_out[15:8];
				R_M4: noc_from_dev_data <= #1 fifo_out[7:0];
				default: noc_from_dev_data <= #1 0;
			endcase
		end
	end

	assign exp_Dlen_rsp = fifo_out[15:8]; // Expected data length from read response command

	always_ff @ (posedge clk or posedge rst) begin
		if (rst)
			stopout <= #1 1;
		else begin
			if (Dl_cnt_rsp[2:0]==0 && resp_curr_state==R_R4_DATA)
				stopout <= #1 0;
			else
				stopout <= #1 1;
		end
	end
	// 0-199
	always_ff @ (posedge clk or posedge rst) begin
		if (rst)
			actual_Dlen_rsp <= #1 0;
		else begin
			if (actual_Dlen_rsp == 200)
				actual_Dlen_rsp <= #1 0;
			else if (resp_curr_state == R_R4_DATA)
				actual_Dlen_rsp <= #1 actual_Dlen_rsp + 1;
		end
	end

	always_ff @ (posedge clk or posedge rst) begin
		if (rst)
			dout_r <= #1 64'bx;
		else begin
			if (pushout && !stopout)
				dout_r <= #1 dout;
		end
	end
	// Count the read response data in ONE command
	always_ff @ (posedge clk or posedge rst) begin
		if (rst) begin
			Dl_cnt_rsp <= #1 0; 
		end
		else begin
			if (Dl_cnt_rsp == (exp_Dlen_rsp-1))
				Dl_cnt_rsp <= #1 0;
			else if (resp_curr_state == R_R4_DATA)
				Dl_cnt_rsp <= #1 Dl_cnt_rsp + 1;
		end
	end

/*	always_ff @ (posedge clk or posedge rst) begin
		if (rst)
			wr_rcv <= #1 0;
		else begin
			if (get_curr_state == G_W0)
				wr_rcv <= #1 wr_rcv + 1;
			else if (resp_curr_state == R_R3)
				wr_rcv <= #1 wr_rcv - 1;
		end
	end
*/
endmodule
