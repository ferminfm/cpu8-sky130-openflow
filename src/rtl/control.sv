module control (
    input clk,
    input rst,
    input [6:0] cmd_in,
    output logic aluin_reg_en,
    output logic datain_reg_en,
    output logic memoryWrite, memoryRead, selmux2, 
    output logic cpu_rdy,
    output logic aluout_reg_en,
    output logic nvalid_data,
    output logic [1:0] in_select_a,
    output logic [1:0] in_select_b,
    output logic [3:0]  opcode
  );

  // state encodings
  localparam
    RST       =    2'd0,
    FETCH     =    2'd1,
    EXECUTE   =    2'd2,
    STORE     =    2'd3;
  // ALU opcode encodings
  localparam
    ALU_ADD   = 4'b0000,
    ALU_SUB   = 4'b0010,
    ALU_MUL   = 4'b0100,
    ALU_DIV   = 4'b1000;
  // ISA instructions (cmd_in[2:0]), NOP is handled different because it has
  // 2 different encodings
  localparam
    ISA_ADD   =  3'b000,
    ISA_SUB   =  3'b001,
    ISA_MUL   =  3'b010,
    ISA_DIV   =  3'b011,
    ISA_LOAD  =  3'b101,
    ISA_STORE =  3'b110;

  // state signals
  logic [1:0] state, next_state;

  // passtrough for cmdin[6:3] (input muxes), can use assign due to signals
  // being wire
  assign in_select_a = cmd_in[6:5];
  assign in_select_b = cmd_in[4:3];
    
  // alu opcode copy (for avoiding confusion)
  logic [3:0] alu_op;
  always_comb opcode = alu_op;
  // ISA instruction
  logic [2:0] isa_cmd;
  always_comb isa_cmd = cmd_in[2:0];

  // state register
  always_ff @(posedge clk or posedge rst) begin
    if (rst) state <= RST;
    else state <= next_state;
  end

  // next_state and output logic
  always_comb begin
    // default values (same as rst state)
      // outputs
    aluin_reg_en  =    1'b0;
    nvalid_data   =    1'b1;
    alu_op        = ALU_ADD;
    memoryWrite   =    1'b0;
    memoryRead    =    1'b0;
    selmux2       =    1'b0;
    aluout_reg_en =    1'b0;
    datain_reg_en =    1'b1;
    cpu_rdy       =    1'b1;
      // next_state
    next_state = RST;
    // state machine logic
    case (state)
       RST: begin
         // state outputs
         aluin_reg_en  =    1'b0;
         nvalid_data   =    1'b1;
         alu_op        = ALU_ADD;
         memoryWrite   =    1'b0;
         memoryRead    =    1'b0;
         selmux2       =    1'b0;
         aluout_reg_en =    1'b0;
         datain_reg_en =    1'b1;
         cpu_rdy       =    1'b1;
         // next state logic
         next_state = FETCH;
       end
       FETCH: begin
         // state outputs
         aluin_reg_en  =    1'b1;
         nvalid_data   =    1'b1;
         alu_op        = ALU_ADD;
         memoryWrite   =    1'b0;
         memoryRead    =    1'b0;
         selmux2       =    1'b0;
         aluout_reg_en =    1'b0;
         datain_reg_en =    1'b0;
         cpu_rdy       =    1'b0;
         // next state logic
         next_state = EXECUTE;
       end
       EXECUTE: begin
         // state outputs
           // nvalid_data
         if ((isa_cmd == ISA_ADD) || (isa_cmd == ISA_SUB)
         || (isa_cmd == ISA_MUL) || (isa_cmd == ISA_DIV))
           nvalid_data = 1'b0;
         else
           nvalid_data = 1'b1;
           // alu_op
         if      (isa_cmd == ISA_ADD) alu_op = ALU_ADD;
         else if (isa_cmd == ISA_SUB) alu_op = ALU_SUB;
         else if (isa_cmd == ISA_MUL) alu_op = ALU_MUL;
         else if (isa_cmd == ISA_DIV) alu_op = ALU_DIV;
         else                         alu_op = ALU_ADD;
           // memoryRead 
         if (isa_cmd == ISA_LOAD) memoryRead = 1'b1;
         else                     memoryRead = 1'b0;
           // selmux2
         if (isa_cmd == ISA_LOAD)    selmux2 = 1'b1;
         else                        selmux2 = 1'b0;
           //aluout_reg_en
         if (isa_cmd == ISA_STORE) aluout_reg_en = 1'b0;
         else                      aluout_reg_en = 1'b1;
           // constant outputs
         memoryWrite   =    1'b0;
         aluin_reg_en  =    1'b0;
         datain_reg_en =    1'b0;
         cpu_rdy       =    1'b0;
         // next state logic
         next_state = STORE;
       end
       STORE: begin
         // state outputs
         aluin_reg_en  =    1'b0;
         nvalid_data   =    1'b1;
         alu_op        = ALU_ADD;
         aluout_reg_en =    1'b0;
         if (isa_cmd == ISA_STORE) begin
            memoryWrite = 1'b1;
         end else begin
            memoryWrite = 1'b0;
         end
         memoryRead    =    1'b0;
         selmux2       =    1'b0;
         datain_reg_en =    1'b1;
         cpu_rdy       =    1'b1;
         // next state logic
         next_state = FETCH;
       end
    endcase 
    
  end

endmodule
