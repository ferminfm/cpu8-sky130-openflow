module ALU #( 
	parameter WIDTH = 8 
	) ( 
	input  [WIDTH-1:0] in1, in2, 
	input  [3:0] op,
	input  nvalid_data,
	output logic [2*WIDTH-1:0] out, 
	output logic zero, 
	output logic error 
	);

	always_comb begin
		out = '0; // default assignment to avoid an inferred latch (see scripts/prep_rtl.sh)
		zero = 1'b1;
		error = 1'b1;
		if (nvalid_data) begin
			zero = 1'b0;
			error = 1'b1;
			out = -1;
		end else begin
			case (op)
				4'b0000: begin
					out = in1 + in2;
					error = 1'b0;
				end
				4'b0010: begin
					out = in1 - in2;
					error = 1'b0;
				end
				4'b0100: begin
					out = in1 * in2;
					error = 1'b0;
				end
				4'b1000: begin
					if (in2 != 0) begin
						out = in1 / in2;
						error = 1'b0;
					end else begin
						out = -1;
						error = 1'b1;
					end
				end
			endcase
			if (out == 0) zero = 1'b1;
			else zero = 1'b0;
		end
	end

endmodule

module alu #(
	parameter WIDTH = 8
	) (
	input  [WIDTH-1:0] in1, in2, 
	input  [3:0] op,
	input  nvalid_data,
	output logic [2*WIDTH-1:0] out, 
	output logic zero, 
	output logic error 
	);

	ALU #(.WIDTH(WIDTH)) ALU_inst (.*);

endmodule
