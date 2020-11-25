//`include "m55.sv"
//`include "perm.sv"
//`include "nochw2.sv"
`include "perm_pkg.sv"
`include "n2p_fifo.sv"
`include "p2n_fifo.sv"
`include "pri_rr_arb.sv"

module ps (NOCI.TI t, NOCI.FO f);
	// Signal from and to TB
	wire noc_to_dev_ctl;
	wire [7:0] noc_to_dev_data;
	wire noc_from_dev_ctl;
	wire [7:0] noc_from_dev_data;
	assign noc_to_dev_ctl = t.noc_to_dev_ctl;
	assign noc_to_dev_data = t.noc_to_dev_data;
	assign noc_from_dev_ctl = f.noc_from_dev_ctl;
	assign noc_from_dev_data = f.noc_from_dev_data;

	NOCI s2p_1 (t.clk, t.reset);
	NOCI s2p_2 (t.clk, t.reset);
	NOCI s2p_3 (t.clk, t.reset);
	NOCI s2p_4 (t.clk, t.reset);
	perm_pkg p1(s2p_1.TI, s2p_1.FO);
	perm_pkg p2(s2p_2.TI, s2p_2.FO);
	perm_pkg p3(s2p_3.TI, s2p_3.FO);
	perm_pkg p4(s2p_4.TI, s2p_4.FO);
	 
	logic [8:0] n2p_fifo_out;
	logic n2p_fifo_en_w; // Write Enable for FIFO
	logic n2p_fifo_en_r;
	logic read_en_r; // Rising edge of NOC to perm FIFO's READ enable
	logic [8:0] n2ps_temp; 
	logic [3:0] Alen;
	logic [9:0] Dlen;
	enum [1:0] {
		NONE,
		WR_CMD,
		RD_CMD
	} rcv_cmd; // Read/Write Command
	enum [1:0] {
		NONE_RSP,
		WR_RSP,
		RD_RSP,
		MG_RSP
	} rcv_rsp; // Read/Write/Message Response
	logic [7:0] cmd_Des; // Rd/Wr command DESTINATION
	logic [9:0] cmd_cnt;
	logic [9:0] cmd_cnt_fifo; 

	// FIFO receiving command from NOC
	n2p_fifo n2p_fifo(.clk(t.clk), .rst(t.reset), .data_in(n2ps_temp), .rd_en(n2p_fifo_en_r), .wr_en(n2p_fifo_en_w), .data_out(n2p_fifo_out), .empty(n2p_fifo_empty), .full(n2p_fifo_full));
	edge_det n2pfifo_read_en_r (.clk(t.clk), .rst(t.reset), .rising_or_falling(1'b1), .sig(n2p_fifo_en_r), .edge_detected(read_en_r));
	edge_det ctl_edge_f (.clk(t.clk), .rst(t.reset), .rising_or_falling(1'b0), .sig(t.noc_to_dev_ctl), .edge_detected(ctl_f));

	// Signal from and to perm intf 1
	assign s2p_1.noc_to_dev_ctl = (cmd_Des==8'h40) ? n2p_fifo_out[8] : 1;
	assign s2p_1.noc_to_dev_data = (cmd_Des==8'h40) ? n2p_fifo_out[7:0] : 0;
	assign s2p_2.noc_to_dev_ctl = (cmd_Des==8'h41) ? n2p_fifo_out[8] : 1;
	assign s2p_2.noc_to_dev_data = (cmd_Des==8'h41) ? n2p_fifo_out[7:0] : 0;
	assign s2p_3.noc_to_dev_ctl = (cmd_Des==8'h42) ? n2p_fifo_out[8] : 1;
	assign s2p_3.noc_to_dev_data = (cmd_Des==8'h42) ? n2p_fifo_out[7:0] : 0;
	assign s2p_4.noc_to_dev_ctl = (cmd_Des==8'h43) ? n2p_fifo_out[8] : 1;
	assign s2p_4.noc_to_dev_data = (cmd_Des==8'h43) ? n2p_fifo_out[7:0] : 0;
//	assign f.noc_from_dev_ctl = s2p_1.noc_from_dev_ctl;
//	assign f.noc_from_dev_data = s2p_1.noc_from_dev_data;

	// Write/Read command
	always_ff @ (posedge t.clk or posedge t.reset) begin
		if (t.reset) begin
			Alen <= #1 0;
			Dlen <= #1 0;
			rcv_cmd <= #1 NONE;
			cmd_Des <= #1 0;
			cmd_cnt <= #1 0;
		end
		else begin
			if (ctl_f) begin
				Alen <= #1 (1 << n2ps_temp[7:6]);
				Dlen <= #1 (1 << n2ps_temp[5:3]);
				cmd_Des <= #1 t.noc_to_dev_data;
				if (n2ps_temp[2:0] == 3'b010) begin // Write command
					rcv_cmd <= #1 WR_CMD;
					cmd_cnt <= #1 (1<<n2ps_temp[7:6]) + (1<<n2ps_temp[5:3]) + 2;
				end
				else if (n2ps_temp[2:0] == 3'b001) begin // Read command
					rcv_cmd <= #1 RD_CMD;
					cmd_cnt <= #1 (1<<n2ps_temp[7:6]) + 2;
				end
			end
			else if (cmd_cnt)
				cmd_cnt <= #1 cmd_cnt - 1;
		end
	end
	
	// Store the input data before ctl -> 0
	always_ff @ (posedge t.clk or posedge t.reset) begin
		if (t.reset)
			n2ps_temp <= #1 0;
		else begin
			n2ps_temp <= #1 {t.noc_to_dev_ctl, t.noc_to_dev_data};
		end
	end

	// Write Enable of FIFO
	assign n2p_fifo_en_w = ctl_f || cmd_cnt;
	// Read Enalbe of FIFO
	assign n2p_fifo_en_r = (~n2p_fifo_empty) && (cmd_Des);
	
	// Cmd cnt for n2p fifo read
	always_ff @ (posedge t.clk or posedge t.reset) begin
		if (t.reset)
			cmd_cnt_fifo <= #1 0;
		else begin
			if (ctl_f) begin
				if (n2ps_temp[2:0] == 3'b010) begin // Write command
					cmd_cnt_fifo <= #1 (1<<n2ps_temp[7:6]) + (1<<n2ps_temp[5:3]) + 4;
				end
				else if (n2ps_temp[2:0] == 3'b001) begin // Read command
					cmd_cnt_fifo <= #1 (1<<n2ps_temp[7:6]) + 4;
				end
			end
			else if (n2p_fifo_en_r && cmd_cnt_fifo)
				cmd_cnt_fifo <= #1 cmd_cnt_fifo - 1;
			else if (cmd_cnt_fifo == 1)
				cmd_cnt_fifo <= #1 0;
		end
	end

	///////////////////////////////////////
	logic p2n_fifo1_en_r, p2n_fifo2_en_r, p2n_fifo3_en_r, p2n_fifo4_en_r;
	logic p2n_fifo1_en_w, p2n_fifo2_en_w, p2n_fifo3_en_w, p2n_fifo4_en_w;
	logic p2n_fifo1_empty, p2n_fifo2_empty, p2n_fifo3_empty, p2n_fifo4_empty;
	logic p2n_fifo1_full, p2n_fifo2_full, p2n_fifo3_full, p2n_fifo4_full;
	logic [8:0] p2n_fifo1_out, p2n_fifo2_out, p2n_fifo3_out, p2n_fifo4_out;
	logic [8:0] p2n_fifo1_in, p2n_fifo2_in, p2n_fifo3_in, p2n_fifo4_in;
	logic [3:0] pfifo_req; // Request list
	logic [3:0] pfifo_grt; // Grant list
	logic [7:0] p2n_cnt_1; // Command counter for p2n FIFO
	logic [7:0] p2n_cnt_2;
	logic [7:0] p2n_cnt_3;
	logic [7:0] p2n_cnt_4;
	logic [2:0] al_cnt_1; // Count the 4th noc_from_dev_data for read responses
	logic [2:0] al_cnt_2;
	logic [2:0] al_cnt_3;
	logic [2:0] al_cnt_4;
	logic lock_grt; // Lock the arbitor when a device is operating
	assign p2n_fifo1_in = {s2p_1.noc_from_dev_ctl, s2p_1.noc_from_dev_data};
	assign p2n_fifo2_in = {s2p_2.noc_from_dev_ctl, s2p_2.noc_from_dev_data};
	assign p2n_fifo3_in = {s2p_3.noc_from_dev_ctl, s2p_3.noc_from_dev_data};
	assign p2n_fifo4_in = {s2p_4.noc_from_dev_ctl, s2p_4.noc_from_dev_data};
	p2n_fifo p2n_fifo1 (.clk(t.clk), .rst(t.reset), .data_in(p2n_fifo1_in), .rd_en(p2n_fifo1_en_r), .wr_en(p2n_fifo1_en_w), .data_out(p2n_fifo1_out), .empty(p2n_fifo1_empty), .full(p2n_fifo1_full));
	p2n_fifo p2n_fifo2 (.clk(t.clk), .rst(t.reset), .data_in(p2n_fifo2_in), .rd_en(p2n_fifo2_en_r), .wr_en(p2n_fifo2_en_w), .data_out(p2n_fifo2_out), .empty(p2n_fifo2_empty), .full(p2n_fifo2_full));
	p2n_fifo p2n_fifo3 (.clk(t.clk), .rst(t.reset), .data_in(p2n_fifo3_in), .rd_en(p2n_fifo3_en_r), .wr_en(p2n_fifo3_en_w), .data_out(p2n_fifo3_out), .empty(p2n_fifo3_empty), .full(p2n_fifo3_full));
	p2n_fifo p2n_fifo4 (.clk(t.clk), .rst(t.reset), .data_in(p2n_fifo4_in), .rd_en(p2n_fifo4_en_r), .wr_en(p2n_fifo4_en_w), .data_out(p2n_fifo4_out), .empty(p2n_fifo4_empty), .full(p2n_fifo4_full));
	// Arbitrator for input from 4 perm devices
	arb arb(.clk(t.clk), .reset(t.reset), .req(pfifo_req), .grant(pfifo_grt), .lock(lock_grt));

	assign p2n_fifo1_en_r = pfifo_grt[0] && (!p2n_fifo1_empty);
	assign p2n_fifo2_en_r = pfifo_grt[1] && (!p2n_fifo2_empty);
	assign p2n_fifo3_en_r = pfifo_grt[2] && (!p2n_fifo3_empty);
	assign p2n_fifo4_en_r = pfifo_grt[3] && (!p2n_fifo4_empty);

	assign lock_grt = ~f.noc_from_dev_ctl;

/*	always_ff @ (posedge t.clk or posedge t.reset) begin
		if (t.reset)
			lock_grt <= #1 1;
		else begin
			if (s2p_1.noc_from_dev_ctl && s2p_2.noc_from_dev_ctl && s2p_3.noc_from_dev_ctl && s2p_4.noc_from_dev_ctl)
				lock_grt <= #1 0;
			else
				lock_grt <= #1 1;
		end
	end	
*/
	always_comb begin
		case (pfifo_grt)
			4'b0001: begin
				f.noc_from_dev_ctl = p2n_fifo1_out[8];
				f.noc_from_dev_data = p2n_fifo1_out[7:0];
			end
			4'b0010: begin
				f.noc_from_dev_ctl = p2n_fifo2_out[8];
				f.noc_from_dev_data = p2n_fifo2_out[7:0];
			end
			4'b0100: begin
				f.noc_from_dev_ctl = p2n_fifo3_out[8];
				f.noc_from_dev_data = p2n_fifo3_out[7:0];
			end
			4'b1000: begin
				f.noc_from_dev_ctl = p2n_fifo4_out[8];
				f.noc_from_dev_data = p2n_fifo4_out[7:0];
			end
			default: begin
				f.noc_from_dev_ctl = 1;
				f.noc_from_dev_data = 0;
			end
		endcase
	end

	assign p2n_fifo1_en_w = (s2p_1.noc_from_dev_ctl&&(s2p_1.noc_from_dev_data!=0)) || (~s2p_1.noc_from_dev_ctl);
	assign p2n_fifo2_en_w = (s2p_2.noc_from_dev_ctl&&(s2p_2.noc_from_dev_data!=0)) || (~s2p_2.noc_from_dev_ctl);
	assign p2n_fifo3_en_w = (s2p_3.noc_from_dev_ctl&&(s2p_3.noc_from_dev_data!=0)) || (~s2p_3.noc_from_dev_ctl);
	assign p2n_fifo4_en_w = (s2p_4.noc_from_dev_ctl&&(s2p_4.noc_from_dev_data!=0)) || (~s2p_4.noc_from_dev_ctl);

	always_ff @ (posedge t.clk or posedge t.reset) begin
		if (t.reset) begin
			pfifo_req <= #1 0;
			p2n_cnt_1 <= #1 0;
			p2n_cnt_2 <= #1 0;
			p2n_cnt_3 <= #1 0;
			p2n_cnt_4 <= #1 0;
			al_cnt_1 <= #1 0;
			al_cnt_2 <= #1 0;
			al_cnt_3 <= #1 0;
			al_cnt_4 <= #1 0;
			rcv_rsp <= #1 NONE_RSP;
		end
		else begin
			case (pfifo_grt)
				4'b0001: begin
					if (p2n_cnt_1 > 1)
						p2n_cnt_1 <= #1 p2n_cnt_1 - 1;
					else if (p2n_cnt_1 == 1) begin
						if ((rcv_rsp==RD_RSP) && (f.noc_from_dev_ctl))
							p2n_cnt_1 <= #1 s2p_1.noc_from_dev_data + 2;
						else begin
							p2n_cnt_1 <= #1 0;
						end
					end
					else
						pfifo_req[0] <= #1 0;
				end
				4'b0010: begin
					if (p2n_cnt_2 > 1)
						p2n_cnt_2 <= #1 p2n_cnt_2 - 1;
					else if (p2n_cnt_2 == 1) begin
						if ((rcv_rsp==RD_RSP) && (f.noc_from_dev_ctl))
							p2n_cnt_2 <= #1 s2p_2.noc_from_dev_data + 2;
						else begin
							p2n_cnt_2 <= #1 0;
						end
					end
					else
						pfifo_req[1] <= #1 0;
				end
				4'b0100: begin
					if (p2n_cnt_3 > 1)
						p2n_cnt_3 <= #1 p2n_cnt_3 - 1;
					else if (p2n_cnt_3 == 1) begin
						if ((rcv_rsp==RD_RSP) && (f.noc_from_dev_ctl))
							p2n_cnt_3 <= #1 s2p_3.noc_from_dev_data + 2;
						else begin
							p2n_cnt_3 <= #1 0;
						end
					end
					else
						pfifo_req[2] <= #1 0;
				end
				4'b1000: begin
					if (p2n_cnt_4 > 1)
						p2n_cnt_4 <= #1 p2n_cnt_4 - 1;
					else if (p2n_cnt_4 == 1) begin
						if ((rcv_rsp==RD_RSP) && (f.noc_from_dev_ctl))
							p2n_cnt_4 <= #1 s2p_4.noc_from_dev_data + 2;
						else begin
							p2n_cnt_4 <= #1 0;
						end
					end
					else
						pfifo_req[3] <= #1 0;
				end
			endcase
			if (s2p_1.noc_from_dev_ctl && (s2p_1.noc_from_dev_data!=0)) begin
				pfifo_req[0] <= #1 1;
				case (s2p_1.noc_from_dev_data[2:0])
					3'b011: begin
						rcv_rsp <= #1 RD_RSP;
						p2n_cnt_1 <= #1 2;
					end
					3'b100: begin
						rcv_rsp <= #1 WR_RSP;
						p2n_cnt_1 <= #1 5;
					end
					3'b101: begin
						rcv_rsp <= #1 MG_RSP;
						p2n_cnt_1 <= #1 6;
					end
				endcase
			end
			if (s2p_2.noc_from_dev_ctl && (s2p_2.noc_from_dev_data!=0)) begin
				pfifo_req[1] <= #1 1;
				case (s2p_2.noc_from_dev_data[2:0])
					3'b011: begin
						rcv_rsp <= #1 RD_RSP;
						p2n_cnt_2 <= #1 2;
					end
					3'b100: begin
						rcv_rsp <= #1 WR_RSP;
						p2n_cnt_2 <= #1 5;
					end
					3'b101: begin
						rcv_rsp <= #1 MG_RSP;
						p2n_cnt_2 <= #1 6;
					end
				endcase
			end
			if (s2p_3.noc_from_dev_ctl && (s2p_3.noc_from_dev_data!=0)) begin
				pfifo_req[2] <= #1 1;
				case (s2p_3.noc_from_dev_data[2:0])
					3'b011: begin
						rcv_rsp <= #1 RD_RSP;
						p2n_cnt_3 <= #1 2;
					end
					3'b100: begin
						rcv_rsp <= #1 WR_RSP;
						p2n_cnt_3 <= #1 5;
					end
					3'b101: begin
						rcv_rsp <= #1 MG_RSP;
						p2n_cnt_3 <= #1 6;
					end
				endcase
			end
			if (s2p_4.noc_from_dev_ctl && (s2p_4.noc_from_dev_data!=0)) begin
				pfifo_req[3] <= #1 1;
				case (s2p_4.noc_from_dev_data[2:0])
					3'b011: begin
						rcv_rsp <= #1 RD_RSP;
						p2n_cnt_4 <= #1 2;
					end
					3'b100: begin
						rcv_rsp <= #1 WR_RSP;
						p2n_cnt_4 <= #1 5;
					end
					3'b101: begin
						rcv_rsp <= #1 MG_RSP;
						p2n_cnt_4 <= #1 6;
					end
				endcase
			end
		end
	end
endmodule
