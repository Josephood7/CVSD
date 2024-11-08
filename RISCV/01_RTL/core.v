module core #( // DO NOT MODIFY INTERFACE!!!
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
) ( 
    input i_clk,
    input i_rst_n,

    // Testbench IOs
    output [2:0] o_status, 
    output       o_status_valid,

    // Memory IOs
    output [ADDR_WIDTH-1:0] o_addr,
    output [DATA_WIDTH-1:0] o_wdata,
    output                  o_we,
    input  [DATA_WIDTH-1:0] i_rdata
);

// ---------------------------------------------------------------------------
// Local parameters
// ---------------------------------------------------------------------------
// ---- Add your own parameters here if needed ---- //
	// Finite-State Machine (FSM)
	localparam S_IDLE = 3'b000,			// send address while idle
			   S_FETCH = 3'b001,		// fetch instruction
			   S_DECODE = 3'b010,		// decode instruction
			   S_SENDADDR = 3'b011,		// send address
			   S_COMPUTE = 3'b100,		// ALU, load
			   S_WRITEBACK = 3'b101,	// data write-back
			   S_PCP4 = 3'b110,		// program counter point to the next instruction pc = pc + 4
			   S_INSTDONE = 3'b111;	// instruction executed
	
// ---------------------------------------------------------------------------
// Wires and Registers
// ---------------------------------------------------------------------------
// ---- Add your own wires and registers here if needed ---- //
	// Testbench IOs registers
	reg [2:0] o_status_r, status;
	reg		  o_status_valid_r;
	
	// Memory IOs registers
	reg [ADDR_WIDTH-1:0] o_addr_r, addr_r;
	reg [DATA_WIDTH-1:0] o_wdata_r;
	reg 				 o_we_r;
	
	// Instruction
	reg 	   [DATA_WIDTH-1:0] i_inst_r, inst_buffer;
	reg 	   [6:0] 			opcode_r;
	reg signed [12:0] 			imm_r;		// immediate value
	reg		   [12:0]			step;
	reg        [4:0] 			rs1_r, rs2_r, rd_r;	// source/destination register - signed
	reg 	   [4:0] 			fs1_r, fs2_r, fd_r;	// source/destination register - floating-point
	reg 	   [2:0] 			funct3_r;
	reg		   [6:0]			funct7_r;
	reg		   [7:0]			zcnt;
	// Program counter
	reg [ADDR_WIDTH-1:0] pc_r;
	
	// FSM
	reg [2:0] state_r, state_next_r;
	
	// Register file
	reg signed [31:0] rf_s_r    [0:31];		// signed
	reg		   [31:0] rf_spfp_r [0:31];		// single-precision floating-point
	reg	signed [32:0] rf_ext_r;				// sign-extension
	/*reg	signed [25:0] rf_tmp_r;				// compute temp
	reg	signed [26:0] rf_tmp_ext_r, us_tmp;
	reg	signed [26:0] rf_round_r;*/
	reg	signed [87:0] rf_tmp_r;				// compute temp
	reg	signed [88:0] rf_tmp_ext_r, us_tmp;
	reg	signed [88:0] rf_round_r;
	reg [24:0] f1, f2;

	// Integer
	integer i, j;
	
	// Flags
	reg fetch_done, compute_done, decode_done, load_done;
	reg addr_sent, opcode_get;
	reg flag_buffer, inst_arrived;
	reg load_buffer, load;
	reg fadd_valid;
// ---------------------------------------------------------------------------
// Continuous Assignment
// ---------------------------------------------------------------------------
// ---- Add your own wire data assignments here if needed ---- //
	// Testbench outputs
	assign o_status = o_status_r;
	assign o_status_valid = o_status_valid_r;
	// Memory outputs
	assign o_addr = o_addr_r;
	assign o_wdata = o_wdata_r;
	assign o_we = o_we_r;

// ---------------------------------------------------------------------------
// Combinational Blocks
// ---------------------------------------------------------------------------
// ---- Write your conbinational block design here ---- //
	// FSM
	always@(*) begin
		state_next_r = S_IDLE;
		case(state_r)
			S_IDLE: state_next_r = S_FETCH;
			S_FETCH: state_next_r = (fetch_done)? S_DECODE: S_FETCH;
			S_DECODE: state_next_r = (decode_done)? S_SENDADDR: S_DECODE;
			S_SENDADDR: state_next_r = S_COMPUTE;
			S_COMPUTE: state_next_r = (compute_done || load_done)? S_WRITEBACK: S_COMPUTE;
			S_WRITEBACK: state_next_r = S_PCP4;
		    S_PCP4: state_next_r = S_INSTDONE;
			S_INSTDONE: state_next_r = S_IDLE;
		endcase
	end
	
	// Instruction mapping
	always@(*) begin
		if(state_r == S_COMPUTE) begin
			case(opcode_r)
				`OP_ADD, `OP_SUB, `OP_SLT, `OP_SLL, `OP_SRL: begin
					if(funct7_r == `FUNCT7_ADD) begin
						if((rf_ext_r[32-: 2] == 2'b01) || (rf_ext_r[32-: 2] == 2'b10))begin
							status = `INVALID_TYPE;
						end else begin
							status = `R_TYPE;
						end
					end else if(funct7_r == `FUNCT7_SUB) begin
						if((rf_ext_r[32-: 2] == 2'b01) || (rf_ext_r[32-: 2] == 2'b10))begin
							status = `INVALID_TYPE;
						end else begin
							status = `R_TYPE;
						end
					end else begin
						status = `R_TYPE;
					end
				end
				`OP_ADDI: begin
					if((rf_ext_r[32-: 2] == 2'b01) || (rf_ext_r[32-: 2] == 2'b10)) begin
						status = `INVALID_TYPE;
					end else begin
						status = `I_TYPE;
					end
				end
				`OP_LW: begin
					if(addr_r[2+: 11] > 'd2047) begin
						status = `INVALID_TYPE;
					end else begin
						status = `I_TYPE;
					end
				end
				`OP_SW: begin
					if((addr_r[2+: 11] > 'd2047) || (addr_r[2+: 11] < 'd1024)) begin
						status = `INVALID_TYPE;
					end else begin
						status = `S_TYPE;
					end
				end
				`OP_BEQ, `OP_BLT: begin
					if(funct3_r == `FUNCT3_BEQ) begin
						status = `B_TYPE;
					end else if(funct3_r == `FUNCT3_BLT) begin
						status = `B_TYPE;
					end
				end
				`OP_FADD, `OP_FSUB, `OP_FCLASS, `OP_FLT: begin
					if((funct7_r == `FUNCT7_FADD) && ((rf_spfp_r[fs1_r][30-: 8] == 8'd255) || (rf_spfp_r[fs2_r][30-: 8] == 8'd255) || rf_spfp_r[fd_r][30-: 8] == 8'd255)) begin
						status = `INVALID_TYPE;
					end else if((funct7_r == `FUNCT7_FSUB) && ((rf_spfp_r[fs1_r][30-: 8] == 8'd255) || (rf_spfp_r[fs2_r][30-: 8] == 8'd255) || rf_spfp_r[fd_r][30-: 8] == 8'd255)) begin
						status = `INVALID_TYPE;
					end else if((funct7_r == `FUNCT7_FLT) && ((rf_spfp_r[fs1_r][30-: 8] == 8'd255) || (rf_spfp_r[fs2_r][30-: 8] == 8'd255))) begin
						status = `INVALID_TYPE;
					end else if((funct7_r == `FUNCT7_FCLASS) && (rf_spfp_r[fs1_r][30-: 8] == 8'd255)) begin
						status = `INVALID_TYPE;		// signed infinite, not a number(NaN)			
					end else begin
						status = `R_TYPE;			// normal number, signed zero, subnormal number, FLT
					end
				end
				`OP_FLW: begin
					if(addr_r[2+: 11] > 'd2047) begin
						status = `INVALID_TYPE;
					end else begin
						status = `I_TYPE;
					end
				end
				`OP_FSW: begin
					if((addr_r[2+: 11] > 'd2047) || (addr_r[2+: 11] < 'd1024)) begin
						status = `INVALID_TYPE;
					end else begin
						status = `S_TYPE;
					end
				end
				`OP_EOF: status = `EOF_TYPE;
			endcase
		end
	end
	
	//Float_Add fadd(i_clk, i_rst_n, ((state_r == S_COMPUTE) && (opcode_r == `OP_FADD) && (funct7_r == `FUNCT7_FADD)), rf_spfp_r[fs1_r], rf_spfp_r[fs2_r], fadd_valid_w, fadd_out);
// ---------------------------------------------------------------------------
// Sequential Block
// ---------------------------------------------------------------------------
// ---- Write your sequential block design here ---- //
	// fclass
	always@(negedge i_clk or negedge i_rst_n) begin
		if((state_r == S_COMPUTE) && ((opcode_r == `OP_FCLASS) || (opcode_r == `OP_FLT) || (opcode_r == `OP_FADD) || (opcode_r == `OP_FSUB))) begin
			if(funct7_r == `FUNCT7_FCLASS) begin
				if(rf_spfp_r[fs1_r][30-: 8] == 0) begin
					if(rf_spfp_r[fs1_r][0+: 23] == 0) begin
						rf_s_r[rd_r] <= (rf_spfp_r[fs1_r][31])? 32'd3: 32'd4; // signed zero
					end else begin
						rf_s_r[rd_r] <= (rf_spfp_r[fs1_r][31])? 32'd2: 32'd5; // subnormal number
					end
				end else if(rf_spfp_r[fs1_r][30-: 8] == 8'd255) begin
					if(rf_spfp_r[fs1_r][0+: 23] == 0) begin
						rf_s_r[rd_r] <= (rf_spfp_r[fs1_r][31])? 32'd0: 32'd7; // signed infinite
					end else begin
						rf_s_r[rd_r] <= 32'd8;								 // not a number(NaN)
					end
				end else begin
					rf_s_r[rd_r] <= (rf_spfp_r[fs1_r][31])? 32'd1: 32'd6;	 // normal number
				end
			end else if(funct7_r == `FUNCT7_FLT) begin
				//rf_s_r[rd_r] <= (rf_spfp_r[fs1_r] < rf_spfp_r[fs2_r])? 1: 0;
				if((rf_spfp_r[fs1_r][30-: 8]) < (rf_spfp_r[fs2_r][30-: 8])) begin
					if((!rf_spfp_r[fs1_r][31])&&(!rf_spfp_r[fs2_r][31])) begin
						rf_s_r[rd_r] <= 1;
					end else if((rf_spfp_r[fs1_r][31])&&(rf_spfp_r[fs2_r][31])) begin
						rf_s_r[rd_r] <= 0;
					end else if((!rf_spfp_r[fs1_r][31])&&(rf_spfp_r[fs2_r][31])) begin
						rf_s_r[rd_r] <= 1;
					end else if((rf_spfp_r[fs1_r][31])&&(!rf_spfp_r[fs2_r][31])) begin
						rf_s_r[rd_r] <= 0;
					end
				end else if((rf_spfp_r[fs1_r][30-: 8]) > (rf_spfp_r[fs2_r][30-: 8])) begin
					if((!rf_spfp_r[fs1_r][31])&&(!rf_spfp_r[fs2_r][31])) begin
						rf_s_r[rd_r] <= 0;
					end else if((rf_spfp_r[fs1_r][31])&&(rf_spfp_r[fs2_r][31])) begin
						rf_s_r[rd_r] <= 1;
					end else if((!rf_spfp_r[fs1_r][31])&&(rf_spfp_r[fs2_r][31])) begin
						rf_s_r[rd_r] <= 1;
					end else if((rf_spfp_r[fs1_r][31])&&(!rf_spfp_r[fs2_r][31])) begin
						rf_s_r[rd_r] <= 0;
					end
				end else if((rf_spfp_r[fs1_r][30-: 8]) == (rf_spfp_r[fs2_r][30-: 8])) begin
					if((!rf_spfp_r[fs1_r][31])&&(!rf_spfp_r[fs2_r][31])) begin
						rf_s_r[rd_r] <= ((rf_spfp_r[fs1_r][0+: 23]) < (rf_spfp_r[fs2_r][0+: 23]))? 1: 0;
					end else if((rf_spfp_r[fs1_r][31])&&(rf_spfp_r[fs2_r][31])) begin
						rf_s_r[rd_r] <= ((rf_spfp_r[fs1_r][0+: 23]) < (rf_spfp_r[fs2_r][0+: 23]))? 0: 1;
					end else if((!rf_spfp_r[fs1_r][31])&&(rf_spfp_r[fs2_r][31])) begin
						rf_s_r[rd_r] <= 1;
					end else if((rf_spfp_r[fs1_r][31])&&(!rf_spfp_r[fs2_r][31])) begin
						rf_s_r[rd_r] <= 0;
					end
				end
			end
		end
	end
		
	always@(negedge i_clk or negedge i_rst_n) begin
		if((state_r == S_COMPUTE) && (opcode_r == `OP_ADD) && (funct7_r == `FUNCT7_ADD) && (funct3_r == `FUNCT3_ADD)) begin
			rf_ext_r <= $signed({{rf_s_r[rs1_r][31]}, rf_s_r[rs1_r]}) + $signed({{rf_s_r[rs2_r][31]}, rf_s_r[rs2_r]});
			rf_s_r[rd_r] <= {rf_ext_r[32], rf_ext_r[0+: 31]};
		end else if((state_r == S_COMPUTE) && (opcode_r == `OP_SUB) && (funct7_r == `FUNCT7_SUB) && (funct3_r == `FUNCT3_SUB)) begin
			rf_ext_r <= $signed({{rf_s_r[rs1_r][31]}, rf_s_r[rs1_r]}) - $signed({{rf_s_r[rs2_r][31]}, rf_s_r[rs2_r]});
			rf_s_r[rd_r] <= {rf_ext_r[32], rf_ext_r[0+: 31]};
		end else if((state_r == S_COMPUTE) && (opcode_r == `OP_SLT) && (funct7_r == `FUNCT7_SLT) && (funct3_r == `FUNCT3_SLT)) begin
			rf_s_r[rd_r] <= ($signed(rf_s_r[rs1_r]) < $signed(rf_s_r[rs2_r]))? 1: 0;
		end else if((state_r == S_COMPUTE) && (opcode_r == `OP_SLL) && (funct7_r == `FUNCT7_SLL) && (funct3_r == `FUNCT3_SLL)) begin
			rf_s_r[rd_r] <= (rf_s_r[rs1_r] << rf_s_r[rs2_r]);
		end else if((state_r == S_COMPUTE) && (opcode_r == `OP_SRL) && (funct7_r == `FUNCT7_SRL) && (funct3_r == `FUNCT3_SRL)) begin
			rf_s_r[rd_r] <= (rf_s_r[rs1_r] >> rf_s_r[rs2_r]);
		end else begin
			rf_ext_r <= 0;
		end
	end
	
	always@(negedge i_clk or negedge i_rst_n) begin
		if((state_r == S_COMPUTE) && (opcode_r == `OP_ADDI) && (funct3_r == `FUNCT3_ADDI)) begin
			rf_ext_r <= $signed({{rf_s_r[rs1_r][31]}, {rf_s_r[rs1_r]}}) + $signed({{imm_r[11]}, {20{imm_r[11]}}, {imm_r[0+: 12]}});
			rf_s_r[rd_r] <= {rf_ext_r[32], rf_ext_r[0+: 31]};
		end
	end
	
	always@(negedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			compute_done <= 0;
		end else if((state_r == S_COMPUTE) && (opcode_r == `OP_BEQ) && (funct3_r == `FUNCT3_BEQ)) begin
			compute_done <= 1;
		end else if((state_r == S_COMPUTE) && (opcode_r == `OP_BLT) && (funct3_r == `FUNCT3_BLT)) begin
			compute_done <= 1;
		end else if((state_r == S_COMPUTE) && (opcode_r == `OP_SLT) && (funct7_r == `FUNCT7_SLT) && (funct3_r == `FUNCT3_SLT)) begin
			compute_done <= 1;
		end else if((state_r == S_COMPUTE) && (opcode_r == `OP_SLL) && (funct7_r == `FUNCT7_SLL) && (funct3_r == `FUNCT3_SLL)) begin
			compute_done <= 1;
		end else if((state_r == S_COMPUTE) && (opcode_r == `OP_SRL) && (funct7_r == `FUNCT7_SRL) && (funct3_r == `FUNCT3_SRL)) begin
			compute_done <= 1;
		end else if((state_r == S_COMPUTE) && (opcode_r == `OP_FCLASS)) begin
			compute_done <= 1;
		end else if(fadd_valid) begin
			compute_done <= 1;
		end else begin
			compute_done <= 0;
		end
	end
	
	// FSM
	always@(posedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			state_r <= S_IDLE;
		end else begin
			state_r <= state_next_r;
		end
	end
	
	// Instruction fetch
	always@(negedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			addr_sent <= 0;
		end else if((state_r == S_FETCH) && (!addr_sent) && (!fetch_done) && (!flag_buffer) && (!inst_arrived)) begin
			addr_sent <= 1;
		end else begin
			addr_sent <= 0;
		end
	end
	
	always@(posedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			o_we_r <= 0;
		end else if((state_r == S_FETCH) && (!fetch_done) && (!flag_buffer)) begin
			//o_addr_r <= pc_r;	// 32 bits = 4 bytes
			o_we_r <= 0;
		end
	end
	
	always@(negedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			flag_buffer <= 0;
		end else if((state_r == S_FETCH) && addr_sent) begin
			flag_buffer <= 1;
		end else begin
			flag_buffer <= 0;
		end
	end
	
	always@(posedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			i_inst_r <= 0;
		end else if((state_r == S_FETCH) && inst_arrived) begin
			i_inst_r <= i_rdata;
		end
	end
	
	always@(negedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			inst_arrived <= 0;
		end else if((state_r == S_FETCH) && flag_buffer) begin
			inst_arrived <= 1;
		end else begin
			inst_arrived <= 0;
		end
	end

	always@(negedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			fetch_done <= 0;
		end else if((state_r == S_FETCH) && inst_arrived) begin
			fetch_done <= 1;
		end else begin
			fetch_done <= 0;
		end
	end
	
	// Decode instruction
	always@(posedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			opcode_r <= 0;
		end else if((!opcode_get) && (!decode_done) && fetch_done) begin
			opcode_r <= i_inst_r[0+: 7];
		end
	end
	
	always@(negedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			opcode_get <= 0;
		end else if((state_r == S_DECODE) && (!opcode_get) && (!decode_done) && fetch_done) begin
			opcode_get <= 1;
		end else begin
			opcode_get <= 0;
		end
	end
	
	
	always@(negedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			decode_done <= 0;
		end else if((state_r == S_DECODE) && (opcode_get) && (!decode_done)) begin
			decode_done <= 1;
		end else begin
			decode_done <= 0;
		end
	end
	
	
	always@(posedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			imm_r <= 0; funct3_r <= 0; funct7_r <= 0;
			rs1_r <= 0; rs2_r <= 0; rd_r <= 0;
			fs1_r <= 0; fs2_r <= 0; fd_r <= 0;
		end else if((state_r == S_DECODE) && (opcode_get) && (!decode_done)) begin
			case(opcode_r)
				`OP_ADD, `OP_SUB, `OP_SLT, `OP_SLL, `OP_SRL: begin
					// R-type operation
					funct7_r <= i_inst_r[25+: 7];
					rs2_r <= i_inst_r[20+: 5];
					rs1_r <= i_inst_r[15+: 5];
					funct3_r <= i_inst_r[12+: 3];
					rd_r <= i_inst_r[7+: 5]; end
				`OP_FADD, `OP_FSUB, `OP_FCLASS, `OP_FLT: begin
					// R-type floating-point operation
					funct7_r <= i_inst_r[25+: 7];
					fs2_r <= i_inst_r[20+: 5];
					fs1_r <= i_inst_r[15+: 5];
					funct3_r <= i_inst_r[12+: 3];
					fd_r <= i_inst_r[7+: 5];
					rd_r <= i_inst_r[7+: 5]; end
				`OP_ADDI, `OP_LW: begin
					// I-type operation
					imm_r <= {{1'b0}, i_inst_r[20+: 12]};
					rs1_r <= i_inst_r[15+: 5];
					funct3_r <= i_inst_r[12+: 3];
					rd_r <= i_inst_r[7+: 5]; end
				`OP_FLW: begin
					// I-type floating-point destination
					imm_r <= {{1'b0}, i_inst_r[20+: 12]};
					fs1_r <= i_inst_r[15+: 5];
					funct3_r <= i_inst_r[12+: 3];
					fd_r <= i_inst_r[7+: 5]; end
				`OP_SW: begin
					// S-type operation
					imm_r <= {1'b0, i_inst_r[25+: 7], i_inst_r[7+: 5]};
					rs2_r <= i_inst_r[20+: 5];
					rs1_r <= i_inst_r[15+: 5];
					funct3_r <= i_inst_r[12+: 3]; end
				`OP_FSW: begin
					// S-type floating-point destination
					imm_r <= {1'b0, i_inst_r[25+: 7], i_inst_r[7+: 5]};
					fs2_r <= i_inst_r[20+: 5];
					fs1_r <= i_inst_r[15+: 5];
					funct3_r <= i_inst_r[12+: 3]; end
				`OP_BEQ, `OP_BLT: begin
					// B-type operation
					imm_r <= {i_inst_r[31], i_inst_r[7], i_inst_r[25+: 6], i_inst_r[8+: 4], 1'b0};
					rs2_r <= i_inst_r[20+: 5];
					rs1_r <= i_inst_r[15+: 5];
					funct3_r <= i_inst_r[12+: 3]; end
				`OP_EOF:begin end
			endcase
		end
	end
	
	// Reset register file
	always@(posedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			for(i = 0; i < 32; i = i + 1) begin
				rf_s_r[i] <= 0;
				rf_spfp_r[i] <= 0;
			end
		end
	end
			
	// Compute done
	always@(negedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			load_done <= 0;
		end else if((state_r == S_COMPUTE) && load) begin
			load_done <= 1;
		end else begin
			load_done <= 0;
		end
	end		
	
	/*always@(negedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			compute_done <= 0;
		end else if(o_status_r) begin
			compute_done <= 1;
		end else begin
			compute_done <= 0;
		end
	end*/	
	
	// Load word
	always@(posedge i_clk or negedge i_rst_n) begin
		if((state_r == S_COMPUTE) && (opcode_r == `OP_LW) && load && (!load_done)) begin
			rf_s_r[rd_r] <= i_rdata;
		end else if((state_r == S_COMPUTE) && (opcode_r == `OP_FLW) && load && (!load_done)) begin
			rf_spfp_r[fd_r] <= i_rdata;
		end
	end
	
	always@(negedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			load_buffer <= 0;
		end else if(state_r == S_COMPUTE) begin
			load_buffer <= 1;
		end else begin
			load_buffer <= 0;
		end
	end
	
	always@(negedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			load <= 0;
		end else if((state_r == S_COMPUTE) && load_buffer) begin
			load <= 1;
		end else begin
			load <= 0;
		end
	end
	
	// Write back
	always@(posedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			o_wdata_r <= 0;
		end else if((state_r == S_WRITEBACK) && (opcode_r == `OP_SW)) begin
			o_wdata_r <= rf_s_r[rs2_r];
		end else if((state_r == S_WRITEBACK) && (opcode_r == `OP_FSW)) begin
			o_wdata_r <= rf_spfp_r[fs2_r];
		end
	end
	
	// Write enable
	always@(posedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			o_we_r <= 0;
		end else if((state_r == S_WRITEBACK) && ((opcode_r == `OP_SW) || (opcode_r == `OP_FSW)) && ((addr_r[2+: 11] < 'd2048) && (addr_r[2+: 11] > 'd1023))) begin
			o_we_r <= 1;
		end else begin
			o_we_r <= 0;
		end
	end
	
	// Address
	always@(posedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			o_addr_r <= 0;
		end else if((state_r == S_WRITEBACK) && ((opcode_r == `OP_SW) || (opcode_r == `OP_FSW))) begin
			o_addr_r <= rf_s_r[rs1_r] + {{19{1'b0}}, imm_r};	// store word
		end else if((state_r == S_SENDADDR) && ((opcode_r == `OP_LW) || (opcode_r == `OP_FLW))) begin
			o_addr_r <= rf_s_r[rs1_r] + {{19{1'b0}}, imm_r};	// send address to load word
		end else if((state_r == S_FETCH) && (!fetch_done) && (!flag_buffer) && (!inst_arrived)) begin
			o_addr_r <= pc_r;	// send address to fetch instruction
		end else begin
			o_addr_r <= 0;
		end
	end
	
	always@(posedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			addr_r <= 0;
		end else if((state_r == S_SENDADDR) && ((opcode_r == `OP_SW) || (opcode_r == `OP_FSW))) begin
			addr_r <= rf_s_r[rs1_r] + {{19{1'b0}}, imm_r};	// store word
		end else if((state_r == S_SENDADDR) && ((opcode_r == `OP_LW) || (opcode_r == `OP_FLW))) begin
			addr_r <= rf_s_r[rs1_r] + {{19{1'b0}}, imm_r};	// send address to load word
		end
	end
	
	// Reset registers
	always@(posedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			// tmps
			rf_ext_r <= 0;
			rf_round_r <= 0;
			rf_tmp_r <= 0;
			rf_tmp_ext_r <= 0;
			us_tmp <= 0;
			zcnt <= 0;
		end
	end
	
	// BEQ, BLT
	always@(negedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			step <= 4;
		end else if((state_r == S_COMPUTE) && (opcode_r == `OP_BEQ) && (funct3_r == `FUNCT3_BEQ)) begin
			step <= (rf_s_r[rs1_r] == rf_s_r[rs2_r])? imm_r: 4;
		end else if((state_r == S_COMPUTE) && (opcode_r == `OP_BLT) && (funct3_r == `FUNCT3_BLT)) begin
			step <= ($signed(rf_s_r[rs1_r]) < $signed(rf_s_r[rs2_r]))? imm_r: 4;
		end else if(state_r == S_INSTDONE) begin
			step <= 4;
		end
	end
	
	// Program counter
	always@(posedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			pc_r <= 0;
		end else if(state_r == S_PCP4) begin
			pc_r <= pc_r + step;	// 32 bits = 4 bytes
		end 
	end
	
	// Status valid
	always@(posedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			o_status_valid_r <= 0;
		end else if(state_r == S_INSTDONE) begin
			o_status_valid_r <= 1;
		end else begin
			o_status_valid_r <= 0;
		end
	end
	
	// Status output
	always@(posedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			o_status_r <= 0;
			status <= 0;
		end else if(state_r == S_INSTDONE) begin
			o_status_r <= status;
		end else begin
			o_status_r <= 0;
		end
	end

endmodule