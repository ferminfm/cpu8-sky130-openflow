`timescale 1ns/1ps

module tb_cpu;

  localparam int WIDTH     = 8;
  localparam real CLK_HALF  = 2.5;

  localparam logic [2:0] ISA_ADD   = 3'b000;
  localparam logic [2:0] ISA_SUB   = 3'b001;
  localparam logic [2:0] ISA_MUL   = 3'b010;
  localparam logic [2:0] ISA_DIV   = 3'b011;
  localparam logic [2:0] ISA_LOAD  = 3'b101;
  localparam logic [2:0] ISA_STORE = 3'b110;
  localparam logic [2:0] ISA_NOP0  = 3'b100;
  localparam logic [2:0] ISA_NOP1  = 3'b111;

  localparam logic [1:0] SEL_DIN1 = 2'b00;
  localparam logic [1:0] SEL_DIN2 = 2'b01;
  localparam logic [1:0] SEL_DIN3 = 2'b10;
  localparam logic [1:0] SEL_DOUT = 2'b11;

  logic                    clk = 0;
  logic                    rst;
  logic [6:0]              cmdin;
  logic [WIDTH-1:0]        din_1, din_2, din_3;
  logic [WIDTH-1:0]        dout_low, dout_high;
  logic                    cpu_rdy, zero, error;

  logic [2*WIDTH-1:0]      dout;
  int                      n_tests, n_errors;

  assign dout = {dout_high, dout_low};

  top #(.WIDTH(WIDTH)) dut (
    .clk      (clk),
    .rst      (rst),
    .cmdin    (cmdin),
    .din_1    (din_1),
    .din_2    (din_2),
    .din_3    (din_3),
    .dout_low (dout_low),
    .dout_high(dout_high),
    .cpu_rdy  (cpu_rdy),
    .zero     (zero),
    .error    (error)
  );

  always #CLK_HALF clk = ~clk;

  initial begin
    if ($test$plusargs("vcd")) begin
      $dumpfile("tb_cpu.vcd");
      $dumpvars(0, tb_cpu);
    end
  end

  // Call only while the CPU is in RST or STORE (cpu_rdy == 1),
  // before the clock edge that captures cmdin.
  task automatic run_op(
    input logic [2:0]          isa,
    input logic [1:0]          sel_a,
    input logic [1:0]          sel_b,
    input logic [WIDTH-1:0]    d1,
    input logic [WIDTH-1:0]    d2,
    input logic [WIDTH-1:0]    d3,
    input logic [2*WIDTH-1:0]  exp_dout,
    input logic                exp_zero,
    input logic                exp_error,
    input string               name
  );
    if (cpu_rdy !== 1'b1)
      $error("[%s] cpu_rdy is not 1 at the start of the instruction", name);

    cmdin = {sel_a, sel_b, isa};
    din_1 = d1;
    din_2 = d2;
    din_3 = d3;

    @(posedge clk); // RST/STORE -> FETCH, captures cmdin
    @(negedge clk);
    if (cpu_rdy !== 1'b0)
      $error("[%s] cpu_rdy should be 0 in FETCH", name);

    @(posedge clk); // FETCH -> EXECUTE, captures operands
    @(negedge clk);
    if (cpu_rdy !== 1'b0)
      $error("[%s] cpu_rdy should be 0 in EXECUTE", name);

    @(posedge clk); // EXECUTE -> STORE, captures the result
    @(negedge clk);
    if (cpu_rdy !== 1'b1)
      $error("[%s] cpu_rdy should be 1 in STORE", name);

    n_tests++;
    if (dout !== exp_dout || zero !== exp_zero || error !== exp_error) begin
      n_errors++;
      $error("[%s] dout=%d zero=%b error=%b  expected dout=%d zero=%b error=%b",
             name, dout, zero, error, exp_dout, exp_zero, exp_error);
    end else begin
      $display("[PASS] %s  dout=%h zero=%b error=%b", name, dout, zero, error);
    end
  endtask

  initial begin
    n_tests  = 0;
    n_errors = 0;
    rst      = 1'b1;
    cmdin    = '0;
    din_1    = '0;
    din_2    = '0;
    din_3    = '0;

    repeat (2) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    n_tests++;
    if (cpu_rdy !== 1'b1 || dout !== '0 || zero !== 1'b0 || error !== 1'b0) begin
      n_errors++;
      $error("[reset] dout=%h zero=%b error=%b cpu_rdy=%b", dout, zero, error, cpu_rdy);
    end else begin
      $display("[PASS] reset  dout=0 zero=0 error=0 cpu_rdy=1");
    end

    // A = din_1, B = din_2
    run_op(ISA_ADD, SEL_DIN1, SEL_DIN2, 8'd10,  8'd20,  8'd0,
           16'd30, 1'b0, 1'b0, "ADD 10+20");

    run_op(ISA_SUB, SEL_DIN1, SEL_DIN2, 8'd20,  8'd20,  8'd0,
           16'd0,  1'b1, 1'b0, "SUB 20-20");

    // A = din_3, to exercise select 2'b10
    run_op(ISA_ADD, SEL_DIN3, SEL_DIN1, 8'd1,   8'd0,   8'd7,
           16'd8,  1'b0, 1'b0, "ADD din3+din1");

    run_op(ISA_MUL, SEL_DIN1, SEL_DIN2, 8'd200, 8'd200, 8'd0,
           16'd40000, 1'b0, 1'b0, "MUL 200*200");

    run_op(ISA_DIV, SEL_DIN1, SEL_DIN2, 8'd100, 8'd5,   8'd0,
           16'd20, 1'b0, 1'b0, "DIV 100/5");

    run_op(ISA_DIV, SEL_DIN1, SEL_DIN2, 8'd10,  8'd0,   8'd0,
           16'hFFFF, 1'b0, 1'b1, "DIV 10/0");

    // 255+1 = 256 occupies dout_high. Also clears error after divide-by-zero.
    run_op(ISA_ADD, SEL_DIN1, SEL_DIN2, 8'd255, 8'd1,   8'd0,
           16'd256, 1'b0, 1'b0, "ADD 255+1");

    // A = dout_high (1), B = din_1 (5) -> 6
    run_op(ISA_ADD, SEL_DOUT, SEL_DIN1, 8'd5,   8'd0,   8'd0,
           16'd6,  1'b0, 1'b0, "ADD dout_high+5");

    // Value with both bytes nonzero, used for the store/load checks.
    run_op(ISA_MUL, SEL_DIN1, SEL_DIN2, 8'd200, 8'd200, 8'd0,
           16'd40000, 1'b0, 1'b0, "MUL before STORE");

    // STORE does not update dout. Address = din_1 = 5 (memory has 8 entries).
    run_op(ISA_STORE, SEL_DIN1, SEL_DIN2, 8'd5, 8'd0, 8'd0,
           16'd40000, 1'b0, 1'b0, "STORE addr 5");

    // The write takes effect on leaving STORE. LOAD reads it two cycles later.
    // error is 1: a LOAD EXECUTE sets nvalid_data=1 and the flags are registered.
    run_op(ISA_LOAD, SEL_DIN1, SEL_DIN2, 8'd5, 8'd0, 8'd0,
           16'd40000, 1'b0, 1'b1, "LOAD addr 5");

    run_op(ISA_MUL, SEL_DIN3, SEL_DIN1, 8'd4, 8'd200, 8'd90,
           16'd360, 1'b0, 1'b0, "MUL din1 din3");

    run_op(ISA_STORE, SEL_DIN1, SEL_DIN2, 8'd3, 8'd0, 8'd0,
           16'd360, 1'b0, 1'b0, "STORE addr 3");

    run_op(ISA_LOAD, SEL_DIN1, SEL_DIN2, 8'd5, 8'd0, 8'd0,
           16'd40000, 1'b0, 1'b1, "LOAD addr 5");

    run_op(ISA_LOAD, SEL_DIN1, SEL_DIN2, 8'd3, 8'd0, 8'd0,
           16'd360, 1'b0, 1'b1, "LOAD addr 3");

    run_op(ISA_NOP0, SEL_DIN1, SEL_DIN2, 8'd1, 8'd2, 8'd0,
           16'hFFFF, 1'b0, 1'b1, "NOP 3'b100");

    run_op(ISA_NOP1, SEL_DIN1, SEL_DIN2, 8'd1, 8'd2, 8'd0,
           16'hFFFF, 1'b0, 1'b1, "NOP 3'b111");

    run_op(ISA_LOAD, SEL_DIN1, SEL_DIN2, 8'd5, 8'd0, 8'd0,
           16'd40000, 1'b0, 1'b1, "LOAD addr 5 after NOP");

    $display("--------------------------------------------");
    if (n_errors == 0)
      $display("TEST PASS  (%0d checks)", n_tests);
    else
      $display("TEST FAIL  %0d errors of %0d checks", n_errors, n_tests);
    $finish;
  end

  initial begin
    repeat (500) @(posedge clk);
    $display("[WATCHDOG] simulation time exceeded");
    $finish;
  end

endmodule
