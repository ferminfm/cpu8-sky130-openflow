module mux4_registered #( 
	parameter WIDTH= 8 
	) ( 
	input  clk, 
	input  rst, 
	input  [1:0] sel, 
	input  [WIDTH-1:0] in1, in2, in3, in4, 
	output logic [WIDTH-1:0] out 
	);

	wire [WIDTH-1:0] mux_to_reg;

	mux4 #(.WIDTH(WIDTH)) mux4_inst (
		.din1(in1),
		.din2(in2),
		.din3(in3),
		.din4(in4),
		.select(sel),
		.dout(mux_to_reg)
	);

	register_bank #(.WIDTH(8)) register_bank_inst (
		.clk(clk),
		.rst(rst),
		.wr_en(1'b1),
		.in(mux_to_reg),
		.out(out)
	);

endmodule
