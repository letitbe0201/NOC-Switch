module edge_det (
	input logic clk,
	input logic rst,
	input logic rising_or_falling, // 1: Rising / 0: Falling
	input logic sig,               // Tracked signal
	output logic edge_detected     // Edge detected -> 1
);
	logic sig_d;

	always_ff @ (posedge clk or posedge rst) begin
		if (rst)
			sig_d <= #1 0;
		else
			sig_d <= #1 sig;
	end

	assign edge_detected = (rising_or_falling) ? ((!sig_d)&&sig) : (sig_d&&(!sig));
endmodule
