module alu #(
    parameter INST_W = 4,
    parameter INT_W  = 6,
    parameter FRAC_W = 10,
    parameter DATA_W = INT_W + FRAC_W
)(
    input                      i_clk,
    input                      i_rst_n,

    input                      i_in_valid,
    output                     o_busy,
    input         [INST_W-1:0] i_inst,
    input  signed [DATA_W-1:0] i_data_a,
    input  signed [DATA_W-1:0] i_data_b,

    output                     o_out_valid,
    output        [DATA_W-1:0] o_data
);

    // Local Parameters
    localparam ADD = 4'b0000,
	       	   SUB = 4'b0001,
	           MUL = 4'b0010,
	           ACC = 4'b0011,
	           SOFTPLUS = 4'b0100,
	       	   XOR = 4'b0101,
	       	   RS = 4'b0110,
	           LR = 4'b0111,
	           CNTZERO = 4'b1000,
	           RMATCH = 4'b1001,

			   DIV3 = 16'b0101_0101_0101_0101, // int_w = 2, frac_w = 14
			   DIV9 = 16'b0001_1100_0111_0001,
			   BUSY = 1;

    // Wires and Regs
	reg signed [DATA_W-1:0] i_data_a_R;
	reg signed [DATA_W-1:0] i_data_b_R;
	reg signed [DATA_W-1:0] o_data_R;
	reg		   [DATA_W-1:0] o_data_lock;
	reg	       [INST_W-1:0]	op;
	reg		   				o_busy_R;
	reg						valid_R;
	reg					    valid_lock;
	reg	signed [31:0]       mul_o;
	reg						mul_busy;
	reg						mul_valid;
	reg						mem_rst;
	reg						acc_valid;
	
	reg signed [DATA_W:0] add_ext1;
	reg signed [DATA_W:0] sub_ext1;
	reg signed [DATA_W*2-1:0] tmp;
	reg mul_cnt;
	reg 	   [3:0] idx;
	reg signed [DATA_W+3:0] acc_mem[15:0];
	reg signed [DATA_W+3:0] acc_tmp;
	reg 	   [DATA_W-1:0] tmp_lr;
	reg		   [4:0] zcnt;
	reg					fnd;
	reg 	   [DATA_W-4:0] match4;
	
	integer i;
	integer k;
	
    // Continuous Assignments
	assign o_data = o_data_lock;
	assign o_busy = o_busy_R;
	assign o_out_valid = valid_lock;

	function automatic [DATA_W-1:0] rnd32_sat16;
		input [DATA_W*2-1:0] x;
		
		reg carry;
		reg [DATA_W*2-FRAC_W+1:0] round;		
		
		begin
			carry = x[FRAC_W-1];
			round = $signed({x[DATA_W*2-1], x[(DATA_W*2-1)-:22]}) + carry;
			rnd32_sat16 = (round[(DATA_W*2-FRAC_W)-:8] == {8{1'b0}} || round[(DATA_W*2-FRAC_W)-:8] == {8{1'b1}})? round[0+:16]: {round[DATA_W*2-FRAC_W], {15{!round[DATA_W*2-FRAC_W]}}};
		end	
	endfunction
	
	function automatic [DATA_W-1:0] rnd32_sat16_sh4;
		input [DATA_W*2-1:0] x;
		
		reg carry;
		reg [DATA_W*2-FRAC_W:0] round;
		reg [DATA_W*2-1:0] shift;		
		
		begin
			shift = x >> 6;
			carry = shift[FRAC_W-1];
			round = $signed({shift[DATA_W*2-1], shift[(DATA_W*2-1)-:22]}) + carry;
			rnd32_sat16_sh4 = (round[(DATA_W*2-FRAC_W)-:8] == {8{1'b0}} || round[(DATA_W*2-FRAC_W)-:8] == {8{1'b1}})? round[0+:16]: {round[DATA_W*2-FRAC_W], {15{!round[DATA_W*2-FRAC_W]}}};
		end	
	endfunction

	function automatic [DATA_W-1:0] sat_ext1;
		input [DATA_W:0] ext1;
		begin
			sat_ext1 = (ext1[DATA_W:DATA_W-1] == 2'b00 || ext1[DATA_W:DATA_W-1] == 2'b11)? ext1[DATA_W-1:0]: {ext1[DATA_W], {15{!ext1[DATA_W]}}};
		end
	endfunction
	
	function automatic [DATA_W-1:0] softplus;
		input signed [DATA_W-1:0] x;
		
		reg signed [DATA_W*2-1:0] sf_tmp;
		begin
			if(x >= 2048) begin
				softplus = x;
			end else if((x >= 0) && (x < 2048)) begin
				sf_tmp = $signed($signed({{x[DATA_W-1]}, x[0+:14], {1'b0}}) + 2048) * DIV3;
				softplus = rnd32_sat16_sh4(sf_tmp);
			end else if((x >= -1024) && (x < 0)) begin
				sf_tmp = $signed(x + 2048) * DIV3;
				softplus = rnd32_sat16_sh4(sf_tmp);
			end else if((x >= -2048) && (x < -1024)) begin
				sf_tmp = $signed($signed({{x[DATA_W-1]}, x[0+:14], {1'b0}}) + 5120) * DIV9;
				softplus = rnd32_sat16_sh4(sf_tmp);
			end else if((x >= -3072) && (x < -2048)) begin
				sf_tmp = $signed(x + 3072) * DIV9;
				softplus = rnd32_sat16_sh4(sf_tmp);
			end else if(x < -3072) begin
				softplus = 0;
			end else begin
				softplus = 0;
			end
		end
	endfunction
	
    // Combinatorial Blocks
	always@(*) begin		
		case(op)
			ADD: begin
				add_ext1 = {i_data_a_R[DATA_W-1], i_data_a_R} + {i_data_b_R[DATA_W-1], i_data_b_R};
				o_data_R = sat_ext1(add_ext1);
			end
			SUB: begin
				sub_ext1 = {i_data_a_R[DATA_W-1], i_data_a_R} - {i_data_b_R[DATA_W-1], i_data_b_R};
				o_data_R = sat_ext1(sub_ext1);
			end
			MUL: begin
				mul_o = i_data_a_R * i_data_b_R;
				o_data_R = rnd32_sat16(mul_o);
			end
			ACC: begin 			
				//idx = i_data_a_R[0+:4];
				acc_tmp = {{1'b0}, acc_mem[idx]} + {{4{i_data_b_R[DATA_W-1]}}, i_data_b_R};
				o_data_R = (acc_tmp[(DATA_W+3)-:5] == {5{1'b0}} || acc_tmp[(DATA_W+3)-:5] == {5{1'b1}})? acc_tmp[(DATA_W-1)-:16]: {acc_tmp[DATA_W+3], {15{!acc_tmp[DATA_W+3]}}};
			end
			SOFTPLUS: o_data_R = softplus(i_data_a_R);
			XOR: o_data_R = i_data_a_R ^ i_data_b_R;
			RS: o_data_R = i_data_a_R >>> i_data_b_R;
			LR: o_data_R = (i_data_a_R >> (DATA_W - i_data_b_R)) ^ (i_data_a_R << i_data_b_R);
			CNTZERO: begin
				zcnt = 0;
				for(i = 0; i < DATA_W; i = i + 1) begin
					if(i_data_a_R[i] && 1) zcnt = ((DATA_W-1) - i);
				end
				o_data_R = {{11{1'b0}}, zcnt};
			end
			RMATCH: begin
				for(i = 0; i <= DATA_W-4; i = i + 1) begin
					match4[i] = (i_data_a_R[i+:4] == i_data_b_R[(DATA_W-1-i)-:4]);
				end
				o_data_R = {{3{1'b0}}, match4};
			end
			default: o_data_R = 0;
		endcase
	end
	
	always@(*) begin
		idx = i_data_a_R[0+:4];
	end
	
    // Sequential Blocks    
    always@(posedge i_clk or negedge i_rst_n) begin
    	if(!i_rst_n) begin
			for(k = 0; k < 16; k = k + 1) begin
				acc_mem[k] <= 0;
			end
		end else if(op == ACC) begin
			acc_mem[idx] <= acc_mem[idx] + {{4{i_data_b_R[DATA_W-1]}}, i_data_b_R};
		end
	end

    always@(posedge i_clk or negedge i_rst_n) begin
    	if(!i_rst_n) begin
			i_data_a_R <= 0;
			i_data_b_R <= 0;
			op <= 0;		
		end else if(i_in_valid) begin
			i_data_a_R <= i_data_a;
			i_data_b_R <= i_data_b;
			op <= i_inst;
		end else begin
			i_data_a_R <= 0;
			i_data_b_R <= 0;
			op <= op;
		end           
    end
	
	always@(posedge i_clk or negedge i_rst_n) begin
    	if(!i_rst_n) begin
    		o_busy_R <= 0;
    	end else if(i_in_valid) begin
    		o_busy_R <= 1;
    	end else if(valid_R) begin
    		o_busy_R <= 0;
    	end else begin
    		o_busy_R <= 0;
    	end
    end
	
	always@(posedge i_clk or negedge i_rst_n) begin
    	if(!i_rst_n) begin
    		valid_R <= 0;
    	end else if(i_in_valid) begin
    		valid_R <= 1;
    	end else begin
    		valid_R <= 0;
    	end
    end
	
	always@(posedge i_clk or negedge i_rst_n) begin
    	if(!i_rst_n) begin
			o_data_lock <= 0;
		end else if(valid_R) begin
			o_data_lock <= o_data_R;
		end else begin
			o_data_lock <= 0;
		end           
    end
    
    always@(posedge i_clk or negedge i_rst_n) begin
    	if(!i_rst_n) begin
    		valid_lock <= 0;
    	end else if(valid_R) begin
    		valid_lock <= 1;
    	end else begin
    		valid_lock <= 0;
    	end
    end

endmodule
