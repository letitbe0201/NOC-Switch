`include "m55.sv"
`include "perm.sv"
`include "nochw2.sv"

module perm_pkg (NOCI.TI t, NOCI.FO f);
	logic pushin,stopin,firstin,firstout;
	logic [63:0] din;
	logic [5:0] dix;	// data index for 1600 bits
	logic [2:0] m1ax,m1ay,m1wx,m1wy,m2ax,m2ay,m2wx,m2wy,m3ax,m3ay,m3wx,m3wy,m4ax,m4ay,m4wx,m4wy;
	logic m1wr,m2wr,m3wr,m4wr;
	logic [63:0] m1rd,m1wd,m2rd,m2wd,m3rd,m3wd,m4rd,m4wd;

	wire pushout;
	logic stopout;
	wire [63:0] dout;

	wire noc_to_dev_ctl;
	wire [7:0] noc_to_dev_data;
	wire noc_from_dev_ctl;
	wire [7:0] noc_from_dev_data;
	assign noc_to_dev_ctl = t.noc_to_dev_ctl;
	assign noc_to_dev_data = t.noc_to_dev_data;
	assign noc_from_dev_ctl = f.noc_from_dev_ctl;
	assign noc_from_dev_data = f.noc_from_dev_data;

	noc_intf n1 (t.clk, t.reset,
		t.noc_to_dev_ctl, t.noc_to_dev_data, f.noc_from_dev_ctl, f.noc_from_dev_data,
		pushin, firstin, stopin, din, pushout, firstout, stopout, dout
	);

	perm_blk p1 (t.clk, t.reset, pushin, stopin, firstin, din,
		m1ax, m1ay, m1rd, m1wx, m1wy, m1wr, m1wd,
	   	m2ax, m2ay, m2rd, m2wx, m2wy, m2wr, m2wd,
	   	m3ax, m3ay, m3rd, m3wx, m3wy, m3wr, m3wd,
	   	m4ax, m4ay, m4rd, m4wx, m4wy, m4wr, m4wd,
    		pushout, stopout, firstout, dout
	);

	m55 m1(t.clk, t.reset, m1ax, m1ay, m1rd, m1wx, m1wy, m1wr, m1wd);
	m55 m2(t.clk, t.reset, m2ax, m2ay, m2rd, m2wx, m2wy, m2wr, m2wd);
	m55 m3(t.clk, t.reset, m3ax, m3ay, m3rd, m3wx, m3wy, m3wr, m3wd);
	m55 m4(t.clk, t.reset, m4ax, m4ay, m4rd, m4wx, m4wy, m4wr, m4wd);
endmodule : perm_pkg
