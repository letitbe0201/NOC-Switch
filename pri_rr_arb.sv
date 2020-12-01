module arb (input reg clk, input reg reset, input reg [3:0] req, output reg[3:0] grant, input reg lock);
	reg [3:0] int_grant, int_grant_d;
	reg [1:0] last, last_d;
	reg [7:0] pri_in;
	reg [3:0] rot_pri;
	reg [1:0] rot_winner, act_winner;
	reg request;

	always @(*) begin
		// Rotate priorities
		int_grant_d = 0;
		last_d = last;
		grant = int_grant;
		pri_in = {req,4'h0};
		pri_in >>= last;
		rot_pri = pri_in[3:0] | pri_in[7:4];

		request = rot_pri!=0;
		rot_winner = 0;
		case(1)
			rot_pri[0]: rot_winner = 0;
			rot_pri[1]: rot_winner = 1;
			rot_pri[2]: rot_winner = 2;
			rot_pri[3]: rot_winner = 3;
		endcase
		act_winner = rot_winner + last;
		if(request) begin
			int_grant_d = 1 << act_winner;
			last_d = act_winner + 1;
		end
	end

	always @(posedge(clk) or posedge(reset)) begin
		if(reset) begin
			int_grant <= 0;
			last <= 0;
		end else begin
			if (!lock) begin
				int_grant <= #1 int_grant_d;
				last <= #1 last_d;
			end
		end
	end	
endmodule : arb
