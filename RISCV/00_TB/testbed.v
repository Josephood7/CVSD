`timescale 1ns/100ps
`define CYCLE       10.0
`define HCYCLE      (`CYCLE/2)
`define MAX_CYCLE   120000

`ifdef p0
    `define Inst   "../00_TB/PATTERN_v3/p0/inst.dat"
	`define Data   "../00_TB/PATTERN_v3/p0/data.dat"
	`define Status "../00_TB/PATTERN_v3/p0/status.dat"
	`define PAT_LEN 47
`elsif p1
    `define Inst   "../00_TB/PATTERN_v3/p1/inst.dat"
	`define Data   "../00_TB/PATTERN_v3/p1/data.dat"
	`define Status "../00_TB/PATTERN_v3/p1/status.dat"
	`define PAT_LEN 12
`else
	`define Inst   "../00_TB/PATTERN_v3/p0/inst.dat"
	`define Data   "../00_TB/PATTERN_v3/p0/data.dat"
	`define Status "../00_TB/PATTERN_v3/p0/status.dat"
	`define PAT_LEN 47
`endif

module testbed();

	reg  rst_n;
	reg  clk = 0;
	wire            dmem_we;
	wire [ 31 : 0 ] dmem_addr;
	wire [ 31 : 0 ] dmem_wdata;
	wire [ 31 : 0 ] dmem_rdata;
	wire [  2 : 0 ] mips_status;
	wire            mips_status_valid;

	reg  [31:0]     golden_mem		[0:2047];
	reg  [2:0]		golden_status	[0:`PAT_LEN-1];

	
	integer i, j, k;
	integer finish_status;
	integer correct_mem, error_mem;
	integer correct_status, error_status;
	integer test_end, status_end;

	core u_core (
		.i_clk(clk),
		.i_rst_n(rst_n),
		.o_status(mips_status),
		.o_status_valid(mips_status_valid),
		.o_we(dmem_we),
		.o_addr(dmem_addr),
		.o_wdata(dmem_wdata),
		.i_rdata(dmem_rdata)
	);

	data_mem  u_data_mem (
		.i_clk(clk),
		.i_rst_n(rst_n),
		.i_we(dmem_we),
		.i_addr(dmem_addr),
		.i_wdata(dmem_wdata),
		.o_rdata(dmem_rdata)
	);

	initial begin
       $fsdbDumpfile("core.fsdb");
       $fsdbDumpvars(0, testbed, "+mda");
    end
	initial begin
		$readmemb (`Data, golden_mem);
		$readmemb (`Status, golden_status);

	end

	always #(`HCYCLE) clk = ~clk;

	// load data memory
	initial begin 
		rst_n = 1;
		#(0.25 * `CYCLE) rst_n = 0;
		#(`CYCLE) rst_n = 1;
		$readmemb (`Inst, u_data_mem.mem_r);
		#(         `MAX_CYCLE * `CYCLE);
        $display("Error! Runtime exceeded!");
        $finish;
	end

	initial begin
		status_end = 0;
		correct_status = 0;
		error_status = 0;
		finish_status = 0;

		// reset
        wait (rst_n === 1'b0);
        wait (rst_n === 1'b1);

		// start
        @(posedge clk);

		j = 0;

		while (finish_status === 0) begin
            @(negedge clk);
            if (mips_status_valid) begin
                if (mips_status === golden_status[j]) begin
                    correct_status = correct_status + 1;
					$display(
                        "Test[%d]: Success! Golden=%b, Yours=%b",
                        j,
                        golden_status[j],
                        mips_status
                    );
                end
                else begin
                    error_status = error_status + 1;
                    $display(
                        "Test[%d]: Error! Golden=%b, Yours=%b",
                        j,
                        golden_status[j],
                        mips_status
                    );
                end
                j = j+1;
            end

			if (mips_status_valid && (mips_status === 3'b101 || mips_status === 3'b100)) begin
				finish_status = 1;
			end

            @(posedge clk);
        end

		status_end = 1;

	end

	initial begin
		test_end = 0;
		correct_mem = 0;
		error_mem = 0;
		wait(status_end);
		for ( i=0 ; i<2048 ; i=i+1 ) begin
			if (u_data_mem.mem_r[i] === golden_mem[i]) begin
				correct_mem = correct_mem + 1;
			end
			else begin
				error_mem = error_mem + 1;
				$display(
                        "MEM[%d]: Error! Golden=%b, Yours=%b",
                        i,
                        golden_mem[i],
                        u_data_mem.mem_r[i]
                    );
			end
		end
		test_end = 1;
	end

	initial begin
		wait (test_end);

        if (error_status === 0 && correct_status === `PAT_LEN) begin
            $display("----------------------------------------------");
            $display("-             STATUS ALL PASS!               -");
            $display("----------------------------------------------");
        end
        else begin
            $display("----------------------------------------------");
            $display("  Wrong! Status Total Error: %d               ", error_status);
            $display("----------------------------------------------");
        end

		if (error_mem === 0 && correct_mem === 2048) begin
            $display("----------------------------------------------");
            $display("-             MEMORY ALL PASS!               -");
            $display("----------------------------------------------");
        end
        else begin
            $display("----------------------------------------------");
            $display("  Wrong! Memory Total Error: %d               ", error_mem);
            $display("----------------------------------------------");
        end

        # (2 * `CYCLE);
        $finish;
    end

endmodule