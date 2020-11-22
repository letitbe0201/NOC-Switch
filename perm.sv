`timescale 1ns / 1ps

`define add_1(x)            (x == 4 ? 0 : x + 1)
`define add_2(x)            (x == 3 ? 0 : x == 4 ? 1 : x + 2)
`define sub_1(x)            (x == 0 ? 4 : x - 1)
`define sub64(x)            {x[62:0], x[63]}
`define sub64_n(x, n)       {x[63-n:0], x[63:63-n+1]}

module perm_blk(input clk, input rst, input pushin, output reg stopin,
	input firstin, input [63:0] din,
	output reg [2:0] m1rx, output reg [2:0] m1ry,
	input [63:0] m1rd,
	output reg [2:0] m1wx, output reg [2:0] m1wy,output reg m1wr,
	output reg [63:0] m1wd,
	output reg [2:0] m2rx, output reg [2:0] m2ry,
	input [63:0] m2rd,
	output reg [2:0] m2wx, output reg [2:0] m2wy,output reg m2wr,
	output reg [63:0] m2wd,
	output reg [2:0] m3rx, output reg [2:0] m3ry,
	input [63:0] m3rd,
	output reg [2:0] m3wx, output reg [2:0] m3wy,output reg m3wr,
	output reg [63:0] m3wd,
	output reg [2:0] m4rx, output reg [2:0] m4ry,
	input [63:0] m4rd,
	output reg [2:0] m4wx, output reg [2:0] m4wy,output reg m4wr,
	output reg [63:0] m4wd,
	output reg pushout, input stopout, output reg firstout, output reg [63:0] dout
	);
	
	
	enum [3:0] {
	IDLE,
	INPUT_D,
	THETA_1,
	BUFFER_12,
	THETA_2,
	BUFFER,
	THETA_3,
	RHO_PI,
	CHI,
	IOTA,
	RND_END,
	BUFFER_OUT
	} cs, ns;
	
	reg [2:0] x, y, cx, cy;
	reg write_rdy;		//write ready
	reg [1:0] buffer;
	reg buffer1;
	reg [4:0] rnd;		//round 0 to 23
	
	reg [63:0] temp_c, temp_c_acc, temp_c2, temp_chi;
	
	
	//update cx, cy 5 by 5, y0-5 then x+1
	function cxy55;
		if(cx >= 4 && cy >= 4) begin
			cx = 0;
			cy = 0;
		end else if (cy >= 4) begin
			cx = x + 1;
			cy = 0;
		end else begin
			cy = y + 1;
		end
	endfunction
	
	//update cx, cy 5 by 5, x0-5 then y+1
	function cyx55;
		if(cx >= 4 && cy >= 4) begin
			cx = 0;
			cy = 0;
		end else if (cx >= 4) begin
			cy = y + 1;
			cx = 0;
		end else begin
			cx = x + 1;
		end
	endfunction
	
	//state logic
	always_comb begin
		ns = cs;
		case(cs)
			IDLE: begin
				if(write_rdy) begin
					ns = INPUT_D;
				end else begin
					ns = IDLE;
				end
			end
			
			INPUT_D: begin
				if(x == 4 && y == 4 && pushin) begin
					ns = THETA_1;
				end else begin
					ns = INPUT_D;
				end
			end
			
			THETA_1: begin
				if(x == 4 && y == 4 && buffer == 1) begin
					//$display("FINISHED THETA_1 %t", $time);
					ns = BUFFER_12;
				end else begin
					ns = THETA_1;
				end
			end

			BUFFER_12: ns = THETA_2;
			
			THETA_2: begin		//stored in m2(y=0)
				if(x == 4 && y == 0 && !buffer1) begin
					//$display("FINISHED THETA_2 %t", $time);
					ns = BUFFER;
				end else begin
					ns = THETA_2;
				end
			end
			
			BUFFER: begin
				//$display("\nBUFFER%t\n", $time);
				ns = THETA_3;
			end
			
			THETA_3: begin
				if(x == 4 && y == 4) begin
					//$display("FINISHED THETA_3 %t", $time);
					ns = RHO_PI;
				end else begin
					ns = THETA_3;
				end
			end
			
			RHO_PI: begin
				if(x == 4 && y == 4) begin
					//$display("FINISHED RHO_PI %t", $time);
					ns = CHI;
				end else begin
					ns = RHO_PI;
				end
			end
			
			CHI: begin
				if(x == 4 && y == 4) begin
					//$display("FINISHED CHI %t", $time);				//maybe add a buffer
					ns = IOTA;
				end else begin
					ns = CHI;
				end
			end
			
			IOTA: begin
				ns = RND_END;
			end
			
			RND_END: begin		//m3 -> m1 -> out(when rnd24), cyx
				if(x == 4 && y == 4) begin
					//$display("\nFINISHED RND%d %t\n", rnd, $time);
					ns = BUFFER_OUT;
					if(rnd == 23) begin
						if(!stopout) ns = BUFFER_OUT;
						else ns = RND_END;
						//ns = BUFFER_OUT;
					end else ns = BUFFER_OUT;
				end else begin
					ns = RND_END;
				end
			end

			BUFFER_OUT: begin
				if(rnd == 23) ns = IDLE;
				else ns = THETA_1;
			end

			default: begin
				ns = IDLE;
			end
		endcase
	end
	
	/* assign m4rx = 0;
	assign m4ry = 0;
	assign m4wx = 0;
	assign m4wy = 0;
	assign m4wr = 0;
	assign m4wd = 0; */
	
	//m1 write
	always_comb begin
		case(cs)
			IDLE: begin
				if(pushin && !stopin) begin
					//$display("INPUT(IDLE),x%dy%d, first%d, push%d, stop%d, din=%h, %t", x, y, firstin, pushin, stopin, din, $time);
					m1wx = x;
					m1wy = y;
					m1wr = 1;
					m1wd = din;
				end else begin
					m1wx = 0;
					m1wy = 0;
					m1wr = 0;
					m1wd = 0;
				end
			end
			INPUT_D: begin
				//$display("INPUT,x%dy%d, first%d, push%d, stop%d, din=%h, %t", x, y, firstin, pushin, stopin, din, $time);
				m1wx = x;
				m1wy = y;
				m1wr = 1;
				m1wd = din;
			end
			
			RHO_PI: begin
				m1wr = 1;
				case({1'b0,x,1'b0,y})
					8'h00: begin
						m1wx = 0;
						m1wy = 0;
						m1wd = m3rd;
					end
					8'h10: begin
						m1wx = 0;
						m1wy = 2;
						m1wd = `sub64(m3rd);
					end
					8'h20: begin
						m1wx = 0;
						m1wy = 4;
						m1wd = `sub64_n(m3rd, 62);
					end
					8'h30: begin
						m1wx = 0;
						m1wy = 1;
						m1wd = `sub64_n(m3rd, 28);
					end
					8'h40: begin
						m1wx = 0;
						m1wy = 3;
						m1wd = `sub64_n(m3rd, 27);
					end
					
					8'h01: begin
						m1wx = 1;
						m1wy = 3;
						m1wd = `sub64_n(m3rd, 36);
					end
					8'h11: begin
						m1wx = 1;
						m1wy = 0;
						m1wd = `sub64_n(m3rd, 44);
					end
					8'h21: begin
						m1wx = 1;
						m1wy = 2;
						m1wd = `sub64_n(m3rd, 6);
					end
					8'h31: begin
						m1wx = 1;
						m1wy = 4;
						m1wd = `sub64_n(m3rd, 55);
					end
					8'h41: begin
						m1wx = 1;
						m1wy = 1;
						m1wd = `sub64_n(m3rd, 20);
					end
					
					8'h02: begin
						m1wx = 2;
						m1wy = 1;
						m1wd = `sub64_n(m3rd, 3);
					end
					8'h12: begin
						m1wx = 2;
						m1wy = 3;
						m1wd = `sub64_n(m3rd, 10);
					end
					8'h22: begin
						m1wx = 2;
						m1wy = 0;
						m1wd = `sub64_n(m3rd, 43);
					end
					8'h32: begin
						m1wx = 2;
						m1wy = 2;
						m1wd = `sub64_n(m3rd, 25);
					end
					8'h42: begin
						m1wx = 2;
						m1wy = 4;
						m1wd = `sub64_n(m3rd, 39);
					end
					
					8'h03: begin
						m1wx = 3;
						m1wy = 4;
						m1wd = `sub64_n(m3rd, 41);
					end
					8'h13: begin
						m1wx = 3;
						m1wy = 1;
						m1wd = `sub64_n(m3rd, 45);
					end
					8'h23: begin
						m1wx = 3;
						m1wy = 3;
						m1wd = `sub64_n(m3rd, 15);
					end
					8'h33: begin
						m1wx = 3;
						m1wy = 0;
						m1wd = `sub64_n(m3rd, 21);
					end
					8'h43: begin
						m1wx = 3;
						m1wy = 2;
						m1wd = `sub64_n(m3rd, 8);
					end
					
					8'h04: begin
						m1wx = 4;
						m1wy = 2;
						m1wd = `sub64_n(m3rd, 18);
					end
					8'h14: begin
						m1wx = 4;
						m1wy = 4;
						m1wd = `sub64_n(m3rd, 2);
					end
					8'h24: begin
						m1wx = 4;
						m1wy = 1;
						m1wd = `sub64_n(m3rd, 61);
					end
					8'h34: begin
						m1wx = 4;
						m1wy = 3;
						m1wd = `sub64_n(m3rd, 56);
					end
					8'h44: begin
						m1wx = 4;
						m1wy = 0;
						m1wd = `sub64_n(m3rd, 14);
					end
					
					default: begin
						m1wx = 0;
						m1wy = 0;
						m1wd = 0;
					end
				endcase
			end
			
			RND_END: begin
				m1wx = x;
				m1wy = y;
				m1wr = 1;
				m1wd = m3rd;
			end
			
			default: begin
				m1wx = 0;
				m1wy = 0;
				m1wd = 0;
				m1wr = 0;
			end
		endcase
	end
	
	//m1, read
	always_comb begin
		case(cs)
			THETA_1: begin
				m1rx = x;
				m1ry = y;
			end
			
			THETA_3: begin
				m1rx = x;
				m1ry = y;
			end
			
			CHI: begin
				m1rx = x;
				m1ry = y;
			end
			
			RND_END: begin
				m1rx = x;
				m1ry = y;
			end
			
			default: begin
				m1rx = 0;
				m1ry = 0;
			end
		endcase
	end
	
	//m2, write
	always_comb begin
		case(cs)
			THETA_1: begin
				m2wx = x;
				m2wy = 0;
				m2wd = temp_c_acc;
				m2wr = 1;
			end
			
			THETA_2: begin
				m2wy = 1;
				m2wx = x;
				m2wd = temp_c;
				m2wr = 1;
				if(cx > 4) begin
					m2wy = 0;
					m2wx = 0;
					m2wd = 0;
					m2wr = 0;
				end
			end
			
			RHO_PI: begin
				m2wr = 1;
				
				//m2wy
				case({1'b0,x,1'b0,y})
					8'h00: begin
						m2wx = 0;
						m2wy = 0;
						m2wd = m3rd;
					end
					8'h10: begin
						m2wx = 0;
						m2wy = 2;
						m2wd = `sub64(m3rd);
					end
					8'h20: begin
						m2wx = 0;
						m2wy = 4;
						m2wd = `sub64_n(m3rd, 62);
					end
					8'h30: begin
						m2wx = 0;
						m2wy = 1;
						m2wd = `sub64_n(m3rd, 28);
					end
					8'h40: begin
						m2wx = 0;
						m2wy = 3;
						m2wd = `sub64_n(m3rd, 27);
					end
					
					8'h01: begin
						m2wx = 1;
						m2wy = 3;
						m2wd = `sub64_n(m3rd, 36);
					end
					8'h11: begin
						m2wx = 1;
						m2wy = 0;
						m2wd = `sub64_n(m3rd, 44);
					end
					8'h21: begin
						m2wx = 1;
						m2wy = 2;
						m2wd = `sub64_n(m3rd, 6);
					end
					8'h31: begin
						m2wx = 1;
						m2wy = 4;
						m2wd = `sub64_n(m3rd, 55);
					end
					8'h41: begin
						m2wx = 1;
						m2wy = 1;
						m2wd = `sub64_n(m3rd, 20);
					end
					
					8'h02: begin
						m2wx = 2;
						m2wy = 1;
						m2wd = `sub64_n(m3rd, 3);
					end
					8'h12: begin
						m2wx = 2;
						m2wy = 3;
						m2wd = `sub64_n(m3rd, 10);
					end
					8'h22: begin
						m2wx = 2;
						m2wy = 0;
						m2wd = `sub64_n(m3rd, 43);
					end
					8'h32: begin
						m2wx = 2;
						m2wy = 2;
						m2wd = `sub64_n(m3rd, 25);
					end
					8'h42: begin
						m2wx = 2;
						m2wy = 4;
						m2wd = `sub64_n(m3rd, 39);
					end
					
					8'h03: begin
						m2wx = 3;
						m2wy = 4;
						m2wd = `sub64_n(m3rd, 41);
					end
					8'h13: begin
						m2wx = 3;
						m2wy = 1;
						m2wd = `sub64_n(m3rd, 45);
					end
					8'h23: begin
						m2wx = 3;
						m2wy = 3;
						m2wd = `sub64_n(m3rd, 15);
					end
					8'h33: begin
						m2wx = 3;
						m2wy = 0;
						m2wd = `sub64_n(m3rd, 21);
					end
					8'h43: begin
						m2wx = 3;
						m2wy = 2;
						m2wd = `sub64_n(m3rd, 8);
					end
					
					8'h04: begin
						m2wx = 4;
						m2wy = 2;
						m2wd = `sub64_n(m3rd, 18);
					end
					8'h14: begin
						m2wx = 4;
						m2wy = 4;
						m2wd = `sub64_n(m3rd, 2);
					end
					8'h24: begin
						m2wx = 4;
						m2wy = 1;
						m2wd = `sub64_n(m3rd, 61);
					end
					8'h34: begin
						m2wx = 4;
						m2wy = 3;
						m2wd = `sub64_n(m3rd, 56);
					end
					8'h44: begin
						m2wx = 4;
						m2wy = 0;
						m2wd = `sub64_n(m3rd, 14);
					end
					
					default: begin
						m2wx = 0;
						m2wy = 0;
						m2wd = 0;
					end
				endcase
			end
			
			default: begin
				m2wx = 0;
				m2wy = 0;
				m2wd = 0;
				m2wr = 0;
			end
		endcase
	end
	
	//m2 read
	always_comb begin
		case(cs)
			THETA_2: begin
				m2rx = `sub_1(x);
				m2ry = 0;
			end
			
			THETA_3: begin
				m2rx = x;
				m2ry = 1;
			end
			
			CHI: begin
				m2ry = y;
				m2rx = `add_1(x);
			end
			
			default: begin
				m2rx = 0;
				m2ry = 0;
			end
		endcase
	end
	
	//m3 write
	always_comb begin
		case(cs)
			THETA_1: begin
				m3wx = x;
				m3wy = 0;
				m3wd = temp_c_acc;
				m3wr = 1;
			end
			
			THETA_3: begin
				m3wx = x;
				m3wy = y;
				m3wd = m1rd ^ m2rd;
				m3wr = 1;
			end
			
			CHI: begin
				m3wx = x;
				m3wy = y;
				m3wr = 1;
				m3wd = temp_chi;
			end
			
			IOTA: begin
				m3wx = 0;
				m3wy = 0;
				m3wr = 1;
				case(rnd)
					0: m3wd = m3rd ^ 64'h0000000000000001;
                    1: m3wd = m3rd ^ 64'h0000000000008082;
                    2: m3wd = m3rd ^ 64'h800000000000808a;
                    3: m3wd = m3rd ^ 64'h8000000080008000;
                    4: m3wd = m3rd ^ 64'h000000000000808b;
                    5: m3wd = m3rd ^ 64'h0000000080000001;
                    6: m3wd = m3rd ^ 64'h8000000080008081;
                    7: m3wd = m3rd ^ 64'h8000000000008009;
                    8: m3wd = m3rd ^ 64'h000000000000008a;
                    9: m3wd = m3rd ^ 64'h0000000000000088;
                    10: m3wd = m3rd ^ 64'h0000000080008009;
                    11: m3wd = m3rd ^ 64'h000000008000000a;
                    12: m3wd = m3rd ^ 64'h000000008000808b;
                    13: m3wd = m3rd ^ 64'h800000000000008b;
                    14: m3wd = m3rd ^ 64'h8000000000008089;
                    15: m3wd = m3rd ^ 64'h8000000000008003;
                    16: m3wd = m3rd ^ 64'h8000000000008002;
                    17: m3wd = m3rd ^ 64'h8000000000000080;
                    18: m3wd = m3rd ^ 64'h000000000000800a;
                    19: m3wd = m3rd ^ 64'h800000008000000a;
                    20: m3wd = m3rd ^ 64'h8000000080008081;
                    21: m3wd = m3rd ^ 64'h8000000000008080;
                    22: m3wd = m3rd ^ 64'h0000000080000001;
                    23: m3wd = m3rd ^ 64'h8000000080008008;
                    default: m3wd = m3rd;
				endcase
			end
			
			default: begin
				m3wx = 0;
				m3wy = 0;
				m3wd = 0;
				m3wr = 0;
			end
		endcase
	end
	
	//m3 read
	always_comb begin
		case(cs)
			THETA_2: begin
				m3rx = `add_1(x);
				m3ry = 0;
			end
			
			RHO_PI: begin
				m3rx = x;
				m3ry = y;
			end
			
			RND_END: begin
				m3rx = x;
				m3ry = y;
			end
			
			default: begin
				m3rx = 0;
				m3ry = 0;
			end
		endcase
	end
	
	//m4 write
	always_comb begin
		case(cs)
			RHO_PI: begin
				m4wr = 1;
				case({1'b0,x,1'b0,y})
					8'h00: begin
						m4wx = 0;
						m4wy = 0;
						m4wd = m3rd;
					end
					8'h10: begin
						m4wx = 0;
						m4wy = 2;
						m4wd = `sub64(m3rd);
					end
					8'h20: begin
						m4wx = 0;
						m4wy = 4;
						m4wd = `sub64_n(m3rd, 62);
					end
					8'h30: begin
						m4wx = 0;
						m4wy = 1;
						m4wd = `sub64_n(m3rd, 28);
					end
					8'h40: begin
						m4wx = 0;
						m4wy = 3;
						m4wd = `sub64_n(m3rd, 27);
					end
					
					8'h01: begin
						m4wx = 1;
						m4wy = 3;
						m4wd = `sub64_n(m3rd, 36);
					end
					8'h11: begin
						m4wx = 1;
						m4wy = 0;
						m4wd = `sub64_n(m3rd, 44);
					end
					8'h21: begin
						m4wx = 1;
						m4wy = 2;
						m4wd = `sub64_n(m3rd, 6);
					end
					8'h31: begin
						m4wx = 1;
						m4wy = 4;
						m4wd = `sub64_n(m3rd, 55);
					end
					8'h41: begin
						m4wx = 1;
						m4wy = 1;
						m4wd = `sub64_n(m3rd, 20);
					end
					
					8'h02: begin
						m4wx = 2;
						m4wy = 1;
						m4wd = `sub64_n(m3rd, 3);
					end
					8'h12: begin
						m4wx = 2;
						m4wy = 3;
						m4wd = `sub64_n(m3rd, 10);
					end
					8'h22: begin
						m4wx = 2;
						m4wy = 0;
						m4wd = `sub64_n(m3rd, 43);
					end
					8'h32: begin
						m4wx = 2;
						m4wy = 2;
						m4wd = `sub64_n(m3rd, 25);
					end
					8'h42: begin
						m4wx = 2;
						m4wy = 4;
						m4wd = `sub64_n(m3rd, 39);
					end
					
					8'h03: begin
						m4wx = 3;
						m4wy = 4;
						m4wd = `sub64_n(m3rd, 41);
					end
					8'h13: begin
						m4wx = 3;
						m4wy = 1;
						m4wd = `sub64_n(m3rd, 45);
					end
					8'h23: begin
						m4wx = 3;
						m4wy = 3;
						m4wd = `sub64_n(m3rd, 15);
					end
					8'h33: begin
						m4wx = 3;
						m4wy = 0;
						m4wd = `sub64_n(m3rd, 21);
					end
					8'h43: begin
						m4wx = 3;
						m4wy = 2;
						m4wd = `sub64_n(m3rd, 8);
					end
					
					8'h04: begin
						m4wx = 4;
						m4wy = 2;
						m4wd = `sub64_n(m3rd, 18);
					end
					8'h14: begin
						m4wx = 4;
						m4wy = 4;
						m4wd = `sub64_n(m3rd, 2);
					end
					8'h24: begin
						m4wx = 4;
						m4wy = 1;
						m4wd = `sub64_n(m3rd, 61);
					end
					8'h34: begin
						m4wx = 4;
						m4wy = 3;
						m4wd = `sub64_n(m3rd, 56);
					end
					8'h44: begin
						m4wx = 4;
						m4wy = 0;
						m4wd = `sub64_n(m3rd, 14);
					end
					
					default: begin
						m4wx = 0;
						m4wy = 0;
						m4wd = 0;
					end
				endcase
			end
			
			default: begin
				m4wx = 0;
				m4wy = 0;
				m4wr = 0;
				m4wd = 0;
			end
		endcase
	end
	
	//m4 read
	always_comb begin
		case(cs)
			CHI: begin
				m4ry = y;
				m4rx = `add_2(x);
			end
			
			default: begin
				m4rx = 0;
				m4ry = 0;
			end
		endcase
	end
	
	//cx, cy, always use x, y for assignment
	always_comb begin
		cx = x;
		cy = y;
		case(cs)
			IDLE: begin
				if(pushin && !stopin) begin
					cx = x + 1;
				end
			end

			INPUT_D: begin			//5x5
				//$display("cx = %d, cy = %d, %t", cx, cy, $time);
				if(pushin && !stopin) cyx55();
				else begin
					cx = x;
					cy = y;
				end
			end
			
			THETA_1: begin			//5x5
				if(y == 4) begin
					if(buffer == 1) begin
						cxy55();
					end else begin
						cx = x;
						cy = y;
					end
				end else cxy55();
			end
			
			THETA_2: begin
				cy = 0;
				if(x < 4 && (buffer == 0 && buffer1)) begin
					cx = x + 1;
				end else if (x == 4) begin
					if(y == 4) cx = 0;
				end
			end
			
			THETA_3: begin
				cxy55();
			end
			
			RHO_PI: begin
				cyx55();
			end
			
			CHI: begin		//x then y
				cyx55();
				/* if(buffer == 2) cyx55();
				else begin
					cx = x;
					cy = y;
				end */
			end
			
			RND_END: begin
				if(rnd == 23) begin
					//cyx55();
					if(stopout) begin
						cx = x;
						cy = y;
					end else cyx55();
				end else cyx55();
			end
			
			default: begin
				cx = 0;
				cy = 0;
			end
		endcase
	end
	
	//dout
	assign dout = m3rd;
	
	//temp_chi
	assign temp_chi = ((m2rd ^ 64'hffffffffffffffff) & m4rd) ^ m1rd;
	
	//firstout
	always_comb begin
		firstout <= #1 ((cs == RND_END && rnd == 23) && (x == 0 && y == 0));
	end
	
	//pushout
	always_comb begin
		pushout <= #1 (cs == RND_END && rnd == 23);
	end
	
	//rnd
	always_ff @(posedge clk or posedge rst) begin
		if(rst) begin
			rnd <= #1 0;
		end else begin
			if(cs == BUFFER_OUT) begin
				if(rnd < 23) rnd <= #1 rnd + 1;
				else rnd <= #1 0;
			end else begin
				rnd <= #1 rnd;
			end
		end
	end
	
	//buffer1
	always_ff @(posedge clk or posedge rst) begin
		if(rst) begin
			buffer1 <= #1 0;
		end else begin
			case(cs)
				THETA_2: begin
					if(x < 4) begin
						if(buffer) buffer1 <= #1 1;
					end else begin
						if(y == 0) buffer1 <= #1 0;
						else buffer1 <= #1 1;
					end
				end

				default: buffer1 <= #1 0;
			endcase
		end
	end

	//buffer (not now)
	always_ff @(posedge clk or posedge rst) begin
		if(rst) begin
			buffer <= #1 0;
		end else begin
			case(cs)
				THETA_1: begin
					if(y == 4) buffer <= #1 1;
					else buffer <= #1 0;
				end

				THETA_2: begin
					if(buffer == 0) buffer <= #1 1;
					else buffer <= #1 0;
				end
				
				/* CHI: begin
					case(buffer)
						0: buffer <= #1 1;
						1: buffer <= #1 2;
						2: buffer <= #1 0;
						default: buffer <= #1 0;
					endcase
				end */
				
				default: buffer <= #1 0;
			endcase
		end
	end
	
	//temp_c2
	always_ff @(posedge clk or posedge rst) begin
		if(rst) begin
			temp_c2 <= #1 0;
		end else begin
			case(cs)
				CHI: begin
					case(buffer)
						0: temp_c2 <= #1 (m2rd ^ 64'hffffffffffffffff) & m4rd;
						1: temp_c2 <= #1 temp_c2 ^ m2rd;
						2: temp_c2 <= #1 temp_c2;
						//2: temp_c2 <= #1 temp_c2;
						//1: temp_c2 <= #1 temp_c2 & m2rd;
						//2: temp_c2 <= #1 temp_c2 ^ m2rd;
						default: temp_c2 <= #1 0;
					endcase
				end
				
				
				default: temp_c2 <= #1 0;
			endcase
		end
	end
	
	//temp_c
	always_ff @(posedge clk or posedge rst) begin
		if(rst) begin
			temp_c <= #1 0;
		end else begin
			case(cs)
				THETA_1: begin
					if(y == 0) temp_c <= #1 m1rd;
					else if (y < 4 || (y == 4 && buffer == 0)) temp_c <= #1 temp_c ^ m1rd;
					else begin 
						temp_c <= #1 0;
					end
				end
				THETA_2: begin
					if(buffer == 1 && y == 0) begin
						temp_c <= #1 (m2rd ^ `sub64(m3rd));
					end
				end
				
				/* CHI: begin
					case(buffer)
						0: temp_c <= #1 m4rd;
						1: temp_c <= #1 temp_c;
						2: temp_c <= #1 temp_c;
						default: temp_c <= #1 0;
					endcase
				end */
				
				default: temp_c <= #1 0;
			endcase
		end
	end
	
	//temp_c_acc
	always_ff @(posedge clk or posedge rst) begin
		if(rst) begin
			temp_c_acc <= #1 0;
		end else begin
			if (y < 4 || (y == 4 && buffer == 0)) temp_c_acc <= #1 m1rd ^ temp_c;
			else temp_c_acc <= #1 0;
		end
	end
	
	//rdy
	always_ff @(posedge clk or posedge rst) begin
		if(rst) begin
			write_rdy <= #1 0;
		end else begin
			if(pushin && !stopin) begin
				//$display("pushin received!! push data is %h %t", din, $time);
				write_rdy <= #1 1;
			end else begin
				write_rdy <= #1 0;
			end
		end
	end
	
	//cs, ns, rst
	always_ff @(posedge clk or posedge rst) begin
		if(rst) begin
			cs <=#1 IDLE;
		end else begin
			cs <=#1 ns;
		end
	end
	
	//stopin, change all !rst to rst
	always_ff @(posedge clk or posedge rst) begin
		if(rst) begin
			stopin <= #1 0;
		end else begin
			case(cs)
				IDLE: stopin <= #1 0;
				//INPUT_D: stopin <= #1 0;
				INPUT_D: begin
					if(x == 4 && y == 4 && pushin) stopin <= #1 1;
					else stopin <= #1 0;
				end
				BUFFER_OUT: begin
					if(rnd == 23) stopin <= #1 0;
					else stopin <= #1 1;
				end
				default: stopin <= #1 1;
			endcase
		end
	end
	
	//ds
	always_ff @(posedge clk or posedge rst) begin
		if(rst) begin
			x <= #1 0;
			y <= #1 0;
		end else begin
			x <= #1 cx;
			y <= #1 cy;
		end
	end
	
	//always @(negedge pushin) $display("cs = %s,PUSHIN 1 -> 0, pushin%d %t", cs, pushin, $time);
	//always @(posedge stopin) $display("cs = %s, STOPIN 0 ->1 %t", cs, $time);
	//always @(negedge stopin) $display("cs = %s, STOPIN 1->0 %t", cs, $time);
	//always @(cs) $display("cs = %s, rnd=%d %t", cs, rnd, $time);
	
endmodule



















