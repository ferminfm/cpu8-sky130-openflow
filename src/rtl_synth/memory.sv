module memory #( 
   parameter WIDTH = 8 
   ) ( 
   input clk, memoryWrite, memoryRead,
   input [2*WIDTH-1:0] memoryWriteData,
   input [WIDTH-1:0] memoryAddress,
   output logic [2*WIDTH-1:0] memoryOutData 
);

	// logic [2*WIDTH-1:0] memoryReg[(2**WIDTH)-1:0];
	logic [2*WIDTH-1:0] memoryReg[7:0];

	// read operation:
	always_comb begin
		// if (memoryWrite) begin
		if (memoryRead) begin
			memoryOutData = memoryReg[memoryAddress];
		end else begin
			memoryOutData = 0;
		end
	end

	// write operation:
	always_ff @(posedge clk) begin
		if (memoryWrite)
			memoryReg[memoryAddress] <= memoryWriteData;
	end

endmodule
