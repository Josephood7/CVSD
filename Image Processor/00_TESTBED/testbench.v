`timescale 1ns/1ps
`define CYCLE       5.0         // specified by command line > ./0._run tb0 5.0
`define HCYCLE      (`CYCLE/2)
`define MAX_CYCLE   10000000
`define RST_DELAY   2
`define INDATA_MEM_SIZE 2048
`define OPMODE_MEM_SIZE 1024
`define GOLDEN_MEM_SIZE 4096

`ifdef tb1
    `define INFILE "../00_TESTBED/PATTERN/indata1.dat"
    `define OPFILE "../00_TESTBED/PATTERN/opmode1.dat"
    `define GOLDEN "../00_TESTBED/PATTERN/golden1.dat"
`elsif tb2
    `define INFILE "../00_TESTBED/PATTERN/indata2.dat"
    `define OPFILE "../00_TESTBED/PATTERN/opmode2.dat"
    `define GOLDEN "../00_TESTBED/PATTERN/golden2.dat"
`else
    `define INFILE "../00_TESTBED/PATTERN/indata0.dat"
    `define OPFILE "../00_TESTBED/PATTERN/opmode0.dat"
    `define GOLDEN "../00_TESTBED/PATTERN/golden0.dat"
`endif

// Modify your sdf file name
`define SDFFILE "../02_SYN/Netlist/core_syn.sdf"


module testbed;

reg         clk, rst_n;
wire        op_valid;
wire [ 3:0] op_mode;
wire        op_ready;
wire        in_valid;
wire [ 7:0] in_data;
wire        in_ready;
wire        out_valid;
wire [13:0] out_data;

reg  [ 7:0] indata_mem [0:2047];
reg  [ 3:0] opmode_mem [0:1023];
reg  [13:0] golden_mem [0:4095];

// ==============================================
// TODO: Declare regs and wires you need
// ==============================================
// flags
reg         op_done;
integer i, j, k;
integer correct_mem, error_mem;

// registers
reg [ 3:0] op_mode_r;
reg        op_valid_r;
reg        in_valid_r;
reg [ 7:0] in_data_r;
reg [ 7:0] o_mem_r;
reg [11:0] addr_mem_r;
// Assignments
assign op_mode = op_mode_r;
assign op_valid = op_valid_r;
assign in_valid = in_valid_r;
assign in_data = in_data_r;

// For gate-level simulation only
`ifdef SDF
    initial $sdf_annotate(`SDFFILE, u_core);
    initial #1 $display("SDF File %s were used for this simulation.", `SDFFILE);
`endif

// Write out waveform file
initial begin
  $fsdbDumpfile("core.fsdb");
  $fsdbDumpvars(0, "+mda");
end


core u_core (
	.i_clk       (clk),
	.i_rst_n     (rst_n),
	.i_op_valid  (op_valid),
	.i_op_mode   (op_mode),
    .o_op_ready  (op_ready),
	.i_in_valid  (in_valid),
	.i_in_data   (in_data),
	.o_in_ready  (in_ready),
	.o_out_valid (out_valid),
	.o_out_data  (out_data)
);

// Read in test pattern and golden pattern
initial $readmemb(`INFILE, indata_mem);
initial $readmemb(`OPFILE, opmode_mem);
initial $readmemb(`GOLDEN, golden_mem);

// Clock generation
initial clk = 1'b0;
always #(`HCYCLE) clk = ~clk;

// Reset generation
initial begin
    rst_n = 1; # (               0.25 * `CYCLE);
    rst_n = 0; # ((`RST_DELAY - 0.25) * `CYCLE);
    rst_n = 1; # (         `MAX_CYCLE * `CYCLE);
    $display("Error! Runtime exceeded!");
    $finish;
end

initial begin
    op_done = 0; i = 0; op_valid_r = 0; op_mode_r = 0; in_valid_r = 0; in_data_r = 0;
    wait(!rst_n); wait(rst_n);  // start process after reset
    @(posedge clk);       // start

    while(opmode_mem[i] !== 4'bx) begin
        @(negedge clk);
        if(op_ready) begin
            @(negedge clk);
            if(!out_valid) begin
                $display("input: %d, op: %b", i, opmode_mem[i]);
                op_valid_r = 1; op_mode_r = opmode_mem[i];
                
                @(negedge clk);
                op_valid_r = 0; op_mode_r = 0;

                if(opmode_mem[i] === 0 && in_ready) begin   // input image
                    in_valid_r <= 1; k = 0;
                    $display("opmode == 0");
                    while(k < 2048) begin
                        in_data_r = indata_mem[k];
                        k = k + 1;
                        @(negedge clk);
                    end
                    $display("k >= 2048");
                    in_valid_r <= 0;
                end

                i = i + 1;
            end
        end
        @(posedge clk);
    end

    $display("Inputs done @@@@@@@@@@@@@@@@@");

    @(posedge clk);       // end
    op_done = 1;
end

// ==============================================
// TODO: Check pattern after process finish
// ==============================================
initial begin
    j = 0; correct_mem = 0; error_mem = 0;
    @(posedge clk);
    while(golden_mem[j] !== 14'bx) begin
        @(negedge clk);
        if(out_valid) begin
            if(out_data === golden_mem[j]) begin
                correct_mem = correct_mem + 1;
                $display("Test[%d]: Correct! MyData: %b, Golden: %b", j, out_data, golden_mem[j]);
            end else begin
                error_mem = error_mem + 1;
                $display("Test[%d]: Error! MyData: %b, Golden: %b", j, out_data, golden_mem[j]);
            end
            j = j + 1;
        end
        @(posedge clk);
    end
    $display("Outputs check done ##############");
    
    if(error_mem === 0) begin
        $display("----------------------------------------------");
        $display("-            ALL PASSSSSSSSSSSS!             -");
        $display("-                 (˶ᵔ ᵕ ᵔ˶)                  -");
        $display("----------------------------------------------");
    end else begin
        $display("----------------------------------------------");
        $display("  Wrong! Total Error: %d        (╥﹏╥)         ", error_mem);
        $display("----------------------------------------------");
    end

    @(posedge clk); $finish;
end

endmodule
