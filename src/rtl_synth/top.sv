module top #( 
   parameter WIDTH= 8 
   ) ( 
   input clk, 
   input rst, 
   input [6:0] cmdin, 
   input [WIDTH-1:0] din_1,
   input [WIDTH-1:0] din_2,
   input [WIDTH-1:0] din_3,
   output logic [WIDTH-1:0] dout_low,
   output logic [WIDTH-1:0] dout_high,
   output logic cpu_rdy,
   output logic zero,
   output logic error
 );

  // internal signals
  logic [WIDTH-1:0] alu_A, alu_B;
  logic [WIDTH-1:0] mux_alu_A, mux_alu_B;
  logic [6:0] reg_cmdin;
  logic [3:0] opcode;
  logic aluin_reg_en;
  logic datain_reg_en;
  logic aluout_reg_en;
  logic nvalid_data;
  logic memoryWrite, memoryRead;
  logic selmux2;
  logic [1:0] in_select_a, in_select_b;
  logic [2*WIDTH-1:0] alu_out;
  logic [2*WIDTH-1:0] memoryOutData;
  logic alu_zero;
  logic alu_error;
  logic [2*WIDTH-1:0] dout_after_mux;
  logic [2*WIDTH-1:0] reg_dout;
  logic [WIDTH-1:0] address;

  // assigning adress (ease of read)
  assign address = alu_A;

  // assigning dout_high and dout_low
  assign dout_high = reg_dout[2*WIDTH-1:WIDTH];
  assign dout_low  = reg_dout      [WIDTH-1:0];

  // sel mux (to assign output to either memory or alu)
  assign dout_after_mux = selmux2 ? memoryOutData : alu_out;

  // module instantiations
    // control
  control control_inst (
    .cmd_in(reg_cmdin),
    .*
  );

    // memory 
  memory #(.WIDTH(WIDTH)) memory_inst ( 
    .memoryWriteData(reg_dout),
    .memoryAddress(address),
    .*
  );

    // alu 
  ALU #(.WIDTH(WIDTH)) ALU_inst ( 
    .in1(alu_A),
    .in2(alu_B),
    .op(opcode),
    .out(alu_out), 
    .zero(alu_zero), 
    .error(alu_error),
    .*
  );

    // mux4: A
  mux4 #(.WIDTH(WIDTH)) mux4_inst_A ( 
     .select(in_select_a), 
     .din1(din_1),
     .din2(din_2),
     .din3(din_3),
     .din4(dout_high),
     .dout(mux_alu_A)
  );

    // mux4: B 
  mux4 #(.WIDTH(WIDTH)) mux4_inst_B ( 
     .select(in_select_b), 
     .din1(din_1),
     .din2(din_2),
     .din3(din_3),
     .din4(dout_low),
     .dout(mux_alu_B)
  );

    // regbank: A
  register_bank #(.WIDTH(WIDTH)) regbank_alu_A (
    .wr_en(aluin_reg_en),
    .in(mux_alu_A),
    .out(alu_A),
    .*
  );

    // regbank: B 
  register_bank #(.WIDTH(WIDTH)) regbank_alu_B (
    .wr_en(aluin_reg_en),
    .in(mux_alu_B),
    .out(alu_B),
    .*
  );

    // regbank: cmdin
  register_bank #(.WIDTH(7)) regbank_cmdin (
    .wr_en(datain_reg_en),
    .in(cmdin),
    .out(reg_cmdin),
    .*
  );

    // regbank: zero_error
  register_bank #(.WIDTH(2)) regbank_zero_error (
    .wr_en(aluout_reg_en),
    .in({alu_zero, alu_error}),
    .out({zero, error}),
    .*
  );
  
    // regbank: dout
  register_bank #(.WIDTH(2*WIDTH)) regbank_dout (
    .wr_en(aluout_reg_en),
    .in(dout_after_mux),
    .out(reg_dout),
    .*
  );

endmodule
