`define C_WIDTH  8
`define C_LENGTH 8
`define C_AREA   (`C_WIDTH * `C_LENGTH) // Channel area

`define D_WIDTH  2
`define D_LENGTH 2
`define D_AREA   (`D_WIDTH * `D_LENGTH) // Display area

`define PAD_AREA 16 
`define KERNEL_AREA 9 
`define KERNEL_WIDTH 3 

`define MEDIAN_DEPTH 4
`define SOBEL_DEPTH 4

module core (                       //Don't modify interface
	input         i_clk,
	input         i_rst_n,
	input         i_op_valid,
	input  [ 3:0] i_op_mode,
    output        o_op_ready,
	input         i_in_valid,
	input  [ 7:0] i_in_data,
	output        o_in_ready,
	output        o_out_valid,
	output [13:0] o_out_data
);

// ---------------------------------------------------------------------------
// Wires and Registers
// ---------------------------------------------------------------------------
// ---- Add your own wires and registers here if needed ---- //
	// inputs
reg  [ 3:0] op_mode_r;
	// outputs
reg 	    o_op_ready_r, o_in_ready_r, o_out_valid_r, o_out_valid_buffer, o_out_valid_buffer0, out_valid_buffer_r1, out_valid_buffer_r2, out_valid_buffer_r3, out_valid_buffer_r4;
reg  [13:0] o_out_data_r;
	// flags
reg		    op_busy_r, op_done_r, pulse_out_r, busy_buffer1, busy_buffer2;
reg		    input_finish_r;
	// sram
reg  	    wen_sram_r, cen_sram_r;
reg  [ 7:0] i_data_sram_r;
reg  [11:0] i_addr_sram_r;
reg  [11:0] pc_sram_r;

wire	    wen_sram, cen_sram;
wire [ 7:0] i_data_sram, o_data_sram;
wire [11:0] i_addr_sram;

	// display
	// |    (origin + 64 * i)      [(origin + 64 * i) + 1] |
	// | [(origin + 64 * i)] + 8]  [(origin + 64 * i) + 9] |, 
reg	 [ 5:0] display_depth;
reg  [ 7:0] display_channel [0:31][0: 3];
reg	 [ 5:0] origin;
reg	 [10:0] pc_display_r, conv_pc_buffer1, conv_pc_buffer2, conv_pc_buffer3;
wire [10:0] c_d_9;

	// convolution
reg  [ 3:0] conv_pad;
reg  [ 3:0] conv_kernel [0: 8];
reg  [13:0] filter_out_r;
reg  [31:0] conv_acc [0: 3][0: 8];
reg  [ 5:0] conv_center;
reg  [ 3:0] ii;

	// median
reg   [ 7:0] median_r [0: 3][0: 3][0: 8];	// [channel][display][kernel]
wire  [ 7:0] median_out;
reg   [ 4:0] output_cnt;

	// sobel
reg   [ 7:0] sobel_r [0: 3][0: 3][0: 8];	// [channel][display][kernel]
wire  [ 7:0] sobel_w [0: 3][0: 3][0: 8];
wire  [ 7:0] sobel_out;
reg   [13:0] grad_r [0: 3][0: 3][0: 2];
wire  [13:0] grad_w [0: 3][0: 3][0: 2];
wire  [13:0] grad_x, grad_y, grad;
wire  [13:0] o_nms;

//Local parameters
localparam MAP_LOAD  = 4'b0000, 
		   OS_R      = 4'b0001,
		   OS_L		 = 4'b0010,
		   OS_U		 = 4'b0011,
		   OS_D		 = 4'b0100,
		   CD_R		 = 4'b0101,
		   CD_I		 = 4'b0110,
		   DISPLAY	 = 4'b0111,
		   CONV		 = 4'b1000,
		   MEDIAN	 = 4'b1001,
		   SOBEL_NMS = 4'b1010,

		   DEPTH_32  = 6'd32,
		   DEPTH_16  = 6'd16,
		   DEPTH_8   = 6'd8,
		   
		   // convolution kernel
		   CONV_KERNEL0 = (1 / 16), CONV_KERNEL2 = (1 / 16), CONV_KERNEL6 = (1 / 16), CONV_KERNEL8 = (1 / 16),		//  | 1/16  1/8  1/16 |
		   CONV_KERNEL1 = (1 / 8), CONV_KERNEL3 = (1 / 8), CONV_KERNEL5 = (1 / 8), CONV_KERNEL7 = (1 / 8),			//  |  1/8  1/4   1/8 |
		   CONV_KERNEL4 = (1 / 4),																					//  | 1/16  1/8  1/16 |

		   t0_1 = 14'b0000000_0110101,
	       t0_2 = 14'b0000001_0000000,
	       t0_3 = 14'b0000010_0110101,
	       t0_4 = 14'b1111101_1001011,
	       t0_5 = 14'b1111111_0000000,
	       t0_6 = 14'b1111111_1001011;
// Module
sram_4096x8 sram(
   .Q(o_data_sram),
   .CLK(i_clk),
   .CEN(cen_sram),
   .WEN(wen_sram),
   .A(i_addr_sram),
   .D(i_data_sram)
);


median median_get(
	.clk(i_clk),
	.rst(i_rst_n),
	.median_r(median_r),
	.ii(ii),
	.out(median_out)
);

sobel sobel_get(
	.clk(i_clk),
	.rst(i_rst_n),
	.sobel_r(sobel_w),
	.ii(c_d_9),
	.o_x(grad_x),
	.o_y(grad_y),
	.o_grad(grad)
);

/*
nms nms_get(
	.clk(i_clk),
	.rst(i_rst_n),
	.grad_r(grad_w),
	.ii(ii),
	.o_nms(o_nms)
);*/

// ---------------------------------------------------------------------------
// Continuous Assignment
// ---------------------------------------------------------------------------
// ---- Add your own wire data assignments here if needed ---- //
assign o_op_ready = o_op_ready_r;
assign o_in_ready = o_in_ready_r;
assign o_out_valid = o_out_valid_r;
assign o_out_data = o_out_data_r;

assign cen_sram = cen_sram_r;
assign wen_sram = wen_sram_r;
assign i_addr_sram = i_addr_sram_r;
assign i_data_sram = i_data_sram_r;

assign c_d_9 = (conv_pc_buffer3 / `KERNEL_AREA);
assign sobel_w = sobel_r;
assign grad_w = grad_r;

// ---------------------------------------------------------------------------
// Functions
// ---------------------------------------------------------------------------

	// convolution
function automatic [13:0] weighting;
	input [31:0] conv_acc [0: 3][0: 8];
	input [ 1:0] ii;
	
	reg [31:0] tmp;

	begin
	tmp = 	          (conv_acc[ii][0])
					+ (conv_acc[ii][1])
					+ (conv_acc[ii][2])
					+ (conv_acc[ii][3])
					+ (conv_acc[ii][4])
					+ (conv_acc[ii][5])
					+ (conv_acc[ii][6])
					+ (conv_acc[ii][7])
					+ (conv_acc[ii][8]); 

	weighting = tmp[10+: 14] + tmp[9];
	end
endfunction


// ---------------------------------------------------------------------------
// Combinational Blocks
// ---------------------------------------------------------------------------
// ---- Write your conbinational block design here ---- //
	// convolution kernel

always@(*) begin
	if(!i_rst_n) begin
		conv_center = 0;
	end else if((op_mode_r == 4'b1000) && (conv_pc_buffer2 < (display_depth * `D_AREA * `KERNEL_AREA)) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin		// convolution
		case((conv_pc_buffer2 / `KERNEL_AREA) % `D_AREA)
			'd0: conv_center = origin                            ;
			'd1: conv_center = origin +            (`D_WIDTH - 1);
			'd2: conv_center = origin + `C_WIDTH                 ;
			'd3: conv_center = origin + `C_WIDTH + (`D_WIDTH - 1);
		endcase
	end else if((op_mode_r == 4'b1001) && (conv_pc_buffer2 < (`MEDIAN_DEPTH * `D_AREA * `KERNEL_AREA)) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin		// convolution
		case((conv_pc_buffer2 / `KERNEL_AREA) % `D_AREA)
			'd0: conv_center = origin                            ;
			'd1: conv_center = origin +            (`D_WIDTH - 1);
			'd2: conv_center = origin + `C_WIDTH                 ;
			'd3: conv_center = origin + `C_WIDTH + (`D_WIDTH - 1);
		endcase
	end else if((op_mode_r == 4'b1010) && (conv_pc_buffer2 < (`SOBEL_DEPTH * `D_AREA * `KERNEL_AREA)) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin		// convolution
		case((conv_pc_buffer2 / `KERNEL_AREA) % `D_AREA)
			'd0: conv_center = origin                            ;
			'd1: conv_center = origin +            (`D_WIDTH - 1);
			'd2: conv_center = origin + `C_WIDTH                 ;
			'd3: conv_center = origin + `C_WIDTH + (`D_WIDTH - 1);
		endcase
	end
end

// ---------------------------------------------------------------------------
// Sequential Block
// ---------------------------------------------------------------------------
// ---- Write your sequential block design here ---- //

// Flags
	// operation busy
always@(posedge i_clk or negedge i_rst_n) begin
	if(!i_rst_n) begin
		op_busy_r <= 0;
		busy_buffer1 <= 0;
		busy_buffer2 <= 0;
	end else if(i_op_valid) begin
		op_busy_r <= 1;		
	end else begin
		case(op_mode_r)
			MAP_LOAD: begin
				if(i_in_valid) begin
					op_busy_r <= 1;
				end else if(pc_sram_r >= 2048) begin
					op_busy_r <= 0;
				end
			end
			OS_R: op_busy_r <= 0;
			OS_L: op_busy_r <= 0;
			OS_U: op_busy_r <= 0;
			OS_D: op_busy_r <= 0;
			CD_R: op_busy_r <= 0;
			CD_I: op_busy_r <= 0;
		   	DISPLAY: begin
				if((pc_display_r < (display_depth * `D_AREA)) || out_valid_buffer_r2) begin
					op_busy_r <= 1;
				end else begin
					op_busy_r <= 0;
				end
			end
			CONV: begin
				if((conv_pc_buffer2 < (display_depth * `D_AREA * `KERNEL_AREA))) begin
					op_busy_r <= 1;
					busy_buffer1 <= op_busy_r;
					busy_buffer2 <= busy_buffer1;
				end else begin
					op_busy_r <= 0;
					busy_buffer1 <= 0;
					busy_buffer2 <= 0;
				end
			end
		   	MEDIAN: begin
				if((conv_pc_buffer2 < (`MEDIAN_DEPTH * `D_AREA * `KERNEL_AREA))) begin
					op_busy_r <= 1;
					busy_buffer1 <= op_busy_r;
					busy_buffer2 <= busy_buffer1;
				end else begin
					op_busy_r <= 0;
					busy_buffer1 <= 0;
					busy_buffer2 <= 0;
				end
			end
		   	SOBEL_NMS: begin
				if((conv_pc_buffer2 < (`SOBEL_DEPTH * `D_AREA * `KERNEL_AREA))) begin
					op_busy_r <= 1;
					busy_buffer1 <= op_busy_r;
					busy_buffer2 <= busy_buffer1;
				end else begin
					op_busy_r <= 0;
					busy_buffer1 <= 0;
					busy_buffer2 <= 0;
				end
			end
		endcase
	end
end

// SRAM
	// clock enable
always@(posedge i_clk or negedge i_rst_n) begin
	if(!i_rst_n) begin
		cen_sram_r <= 1;
	end else if((op_mode_r == 0) && i_in_valid && o_in_ready) begin
		cen_sram_r <= 0;
	end else if((op_mode_r == 4'b0111) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin
		cen_sram_r <= 0;
	end else if((op_mode_r == 4'b1000) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin		// convolution
		cen_sram_r <= 0;
	end else if((op_mode_r == 4'b1001) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin		// median
		cen_sram_r <= 0;
	end else if((op_mode_r == 4'b1010) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin		// sobel
		cen_sram_r <= 0;
	end else begin
		cen_sram_r <= 1;
	end
end

	// write enable
always@(posedge i_clk or negedge i_rst_n) begin
	if(!i_rst_n) begin
		wen_sram_r <= 1;
	end else if((op_mode_r == 0) && i_in_valid && o_in_ready) begin
		wen_sram_r <= 0;
	end else if((op_mode_r == 4'b0111) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin
		wen_sram_r <= 1;
	end else if((op_mode_r == 4'b1000) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin		// convolution
		wen_sram_r <= 1;
	end else if((op_mode_r == 4'b1001) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin		// median
		wen_sram_r <= 1;
	end else if((op_mode_r == 4'b1010) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin		// sobel
		wen_sram_r <= 1;
	end else begin
		wen_sram_r <= 1;
	end
end

	// address
always@(posedge i_clk or negedge i_rst_n) begin
	if(!i_rst_n) begin
		i_addr_sram_r <= 0;
	end else if((op_mode_r == 0) && i_in_valid && o_in_ready) begin
		i_addr_sram_r <= pc_sram_r;
	end else if((op_mode_r == 4'b0111) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin
		case(pc_display_r % `D_AREA)
			'd0: i_addr_sram_r <= origin + (`C_AREA * (pc_display_r / `D_AREA)                            );
			'd1: i_addr_sram_r <= origin + (`C_AREA * (pc_display_r / `D_AREA) +            (`D_WIDTH - 1));
			'd2: i_addr_sram_r <= origin + (`C_AREA * (pc_display_r / `D_AREA) + `C_WIDTH                 );
			'd3: i_addr_sram_r <= origin + (`C_AREA * (pc_display_r / `D_AREA) + `C_WIDTH + (`D_WIDTH - 1));
		endcase
	end else if((op_mode_r == 4'b1000) && (pc_display_r < (display_depth * `D_AREA * `KERNEL_AREA)) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin		// convolution
		case((pc_display_r / `KERNEL_AREA) % `D_AREA)
			'd0: i_addr_sram_r <= origin + (`C_AREA * (pc_display_r / (`KERNEL_AREA * `D_AREA))                            ) + (((pc_display_r % `KERNEL_AREA) / `KERNEL_WIDTH)? (((((pc_display_r % `KERNEL_AREA) / `KERNEL_WIDTH) == 1)? 0: `C_WIDTH)): (-`C_WIDTH)) + (((pc_display_r % `KERNEL_AREA) % `KERNEL_WIDTH)? ((((pc_display_r % `KERNEL_AREA) % `KERNEL_WIDTH) == 1)? 0: 1): (-1));
			'd1: i_addr_sram_r <= origin + (`C_AREA * (pc_display_r / (`KERNEL_AREA * `D_AREA)) +            (`D_WIDTH - 1)) + (((pc_display_r % `KERNEL_AREA) / `KERNEL_WIDTH)? (((((pc_display_r % `KERNEL_AREA) / `KERNEL_WIDTH) == 1)? 0: `C_WIDTH)): (-`C_WIDTH)) + (((pc_display_r % `KERNEL_AREA) % `KERNEL_WIDTH)? ((((pc_display_r % `KERNEL_AREA) % `KERNEL_WIDTH) == 1)? 0: 1): (-1));
			'd2: i_addr_sram_r <= origin + (`C_AREA * (pc_display_r / (`KERNEL_AREA * `D_AREA)) + `C_WIDTH                 ) + (((pc_display_r % `KERNEL_AREA) / `KERNEL_WIDTH)? (((((pc_display_r % `KERNEL_AREA) / `KERNEL_WIDTH) == 1)? 0: `C_WIDTH)): (-`C_WIDTH)) + (((pc_display_r % `KERNEL_AREA) % `KERNEL_WIDTH)? ((((pc_display_r % `KERNEL_AREA) % `KERNEL_WIDTH) == 1)? 0: 1): (-1));
			'd3: i_addr_sram_r <= origin + (`C_AREA * (pc_display_r / (`KERNEL_AREA * `D_AREA)) + `C_WIDTH + (`D_WIDTH - 1)) + (((pc_display_r % `KERNEL_AREA) / `KERNEL_WIDTH)? (((((pc_display_r % `KERNEL_AREA) / `KERNEL_WIDTH) == 1)? 0: `C_WIDTH)): (-`C_WIDTH)) + (((pc_display_r % `KERNEL_AREA) % `KERNEL_WIDTH)? ((((pc_display_r % `KERNEL_AREA) % `KERNEL_WIDTH) == 1)? 0: 1): (-1));
		endcase
	end else if((op_mode_r == 4'b1001) && (pc_display_r < (`MEDIAN_DEPTH * `D_AREA * `KERNEL_AREA)) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin		// median
		case((pc_display_r / `KERNEL_AREA) % `D_AREA)
			'd0: i_addr_sram_r <= origin + (`C_AREA * (pc_display_r / (`KERNEL_AREA * `D_AREA))                            ) + (((pc_display_r % `KERNEL_AREA) / `KERNEL_WIDTH)? (((((pc_display_r % `KERNEL_AREA) / `KERNEL_WIDTH) == 1)? 0: `C_WIDTH)): (-`C_WIDTH)) + (((pc_display_r % `KERNEL_AREA) % `KERNEL_WIDTH)? ((((pc_display_r % `KERNEL_AREA) % `KERNEL_WIDTH) == 1)? 0: 1): (-1));
			'd1: i_addr_sram_r <= origin + (`C_AREA * (pc_display_r / (`KERNEL_AREA * `D_AREA)) +            (`D_WIDTH - 1)) + (((pc_display_r % `KERNEL_AREA) / `KERNEL_WIDTH)? (((((pc_display_r % `KERNEL_AREA) / `KERNEL_WIDTH) == 1)? 0: `C_WIDTH)): (-`C_WIDTH)) + (((pc_display_r % `KERNEL_AREA) % `KERNEL_WIDTH)? ((((pc_display_r % `KERNEL_AREA) % `KERNEL_WIDTH) == 1)? 0: 1): (-1));
			'd2: i_addr_sram_r <= origin + (`C_AREA * (pc_display_r / (`KERNEL_AREA * `D_AREA)) + `C_WIDTH                 ) + (((pc_display_r % `KERNEL_AREA) / `KERNEL_WIDTH)? (((((pc_display_r % `KERNEL_AREA) / `KERNEL_WIDTH) == 1)? 0: `C_WIDTH)): (-`C_WIDTH)) + (((pc_display_r % `KERNEL_AREA) % `KERNEL_WIDTH)? ((((pc_display_r % `KERNEL_AREA) % `KERNEL_WIDTH) == 1)? 0: 1): (-1));
			'd3: i_addr_sram_r <= origin + (`C_AREA * (pc_display_r / (`KERNEL_AREA * `D_AREA)) + `C_WIDTH + (`D_WIDTH - 1)) + (((pc_display_r % `KERNEL_AREA) / `KERNEL_WIDTH)? (((((pc_display_r % `KERNEL_AREA) / `KERNEL_WIDTH) == 1)? 0: `C_WIDTH)): (-`C_WIDTH)) + (((pc_display_r % `KERNEL_AREA) % `KERNEL_WIDTH)? ((((pc_display_r % `KERNEL_AREA) % `KERNEL_WIDTH) == 1)? 0: 1): (-1));
		endcase
	end else if((op_mode_r == 4'b1010) && (pc_display_r < (`SOBEL_DEPTH * `D_AREA * `KERNEL_AREA)) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin		// median
		case((pc_display_r / `KERNEL_AREA) % `D_AREA)
			'd0: i_addr_sram_r <= origin + (`C_AREA * (pc_display_r / (`KERNEL_AREA * `D_AREA))                            ) + (((pc_display_r % `KERNEL_AREA) / `KERNEL_WIDTH)? (((((pc_display_r % `KERNEL_AREA) / `KERNEL_WIDTH) == 1)? 0: `C_WIDTH)): (-`C_WIDTH)) + (((pc_display_r % `KERNEL_AREA) % `KERNEL_WIDTH)? ((((pc_display_r % `KERNEL_AREA) % `KERNEL_WIDTH) == 1)? 0: 1): (-1));
			'd1: i_addr_sram_r <= origin + (`C_AREA * (pc_display_r / (`KERNEL_AREA * `D_AREA)) +            (`D_WIDTH - 1)) + (((pc_display_r % `KERNEL_AREA) / `KERNEL_WIDTH)? (((((pc_display_r % `KERNEL_AREA) / `KERNEL_WIDTH) == 1)? 0: `C_WIDTH)): (-`C_WIDTH)) + (((pc_display_r % `KERNEL_AREA) % `KERNEL_WIDTH)? ((((pc_display_r % `KERNEL_AREA) % `KERNEL_WIDTH) == 1)? 0: 1): (-1));
			'd2: i_addr_sram_r <= origin + (`C_AREA * (pc_display_r / (`KERNEL_AREA * `D_AREA)) + `C_WIDTH                 ) + (((pc_display_r % `KERNEL_AREA) / `KERNEL_WIDTH)? (((((pc_display_r % `KERNEL_AREA) / `KERNEL_WIDTH) == 1)? 0: `C_WIDTH)): (-`C_WIDTH)) + (((pc_display_r % `KERNEL_AREA) % `KERNEL_WIDTH)? ((((pc_display_r % `KERNEL_AREA) % `KERNEL_WIDTH) == 1)? 0: 1): (-1));
			'd3: i_addr_sram_r <= origin + (`C_AREA * (pc_display_r / (`KERNEL_AREA * `D_AREA)) + `C_WIDTH + (`D_WIDTH - 1)) + (((pc_display_r % `KERNEL_AREA) / `KERNEL_WIDTH)? (((((pc_display_r % `KERNEL_AREA) / `KERNEL_WIDTH) == 1)? 0: `C_WIDTH)): (-`C_WIDTH)) + (((pc_display_r % `KERNEL_AREA) % `KERNEL_WIDTH)? ((((pc_display_r % `KERNEL_AREA) % `KERNEL_WIDTH) == 1)? 0: 1): (-1));
		endcase
	end else begin
		i_addr_sram_r <= 0;
	end
end

	// kernel
integer s;
always@(posedge i_clk or negedge i_rst_n) begin
	if(!i_rst_n) begin
		for(s = 0; s < `KERNEL_AREA; s = s + 1) begin
			if(s % 2) begin
				conv_kernel[s] = 3;
			end else if(s == 4) begin
				conv_kernel[s] = 2;
			end else begin
				conv_kernel[s] = 4;
			end
		end
	end
end

	// accumulation
	integer v;
always@(posedge i_clk or negedge i_rst_n) begin
	if(!i_rst_n) begin
		for(v = 0; v < (`KERNEL_AREA * `D_AREA); v = v + 1) begin
			conv_acc[v / `KERNEL_AREA][v % `KERNEL_AREA] <= 0;
		end
	end else if((op_mode_r == 4'b1000) && (busy_buffer2) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin		// convolution
		conv_acc[(conv_pc_buffer2 / `KERNEL_AREA) % `D_AREA][conv_pc_buffer2 % `KERNEL_AREA] <= conv_acc[(conv_pc_buffer2 / `KERNEL_AREA) % `D_AREA][conv_pc_buffer2 % `KERNEL_AREA] + ({{8{1'b0}}, o_data_sram, {10{1'b0}}} >> conv_kernel[conv_pc_buffer2 % `KERNEL_AREA]);
		if((conv_center / `C_WIDTH) == 0) begin							// Top
			if(((conv_pc_buffer2 % `KERNEL_AREA) / `KERNEL_WIDTH) == 0) conv_acc[(conv_pc_buffer2 / `KERNEL_AREA) % `D_AREA][conv_pc_buffer2 % `KERNEL_AREA] <= 0;
		end else if((conv_center / `C_WIDTH) == (`C_WIDTH - 1)) begin	// Bottom
			if(((conv_pc_buffer2 % `KERNEL_AREA) / `KERNEL_WIDTH) == (`KERNEL_WIDTH - 1)) conv_acc[(conv_pc_buffer2 / `KERNEL_AREA) % `D_AREA][conv_pc_buffer2 % `KERNEL_AREA] <= 0;
		end

		if((conv_center % `C_WIDTH) == 0) begin							// Left
			if(((conv_pc_buffer2 % `KERNEL_AREA) % `KERNEL_WIDTH) == 0) conv_acc[(conv_pc_buffer2 / `KERNEL_AREA) % `D_AREA][conv_pc_buffer2 % `KERNEL_AREA] <= 0;
		end else if((conv_center % `C_WIDTH) == (`C_WIDTH - 1)) begin	// Right
			if(((conv_pc_buffer2 % `KERNEL_AREA) % `KERNEL_WIDTH) == (`KERNEL_WIDTH - 1)) conv_acc[(conv_pc_buffer2 / `KERNEL_AREA) % `D_AREA][conv_pc_buffer2 % `KERNEL_AREA] <= 0;
		end
	end else if(i_op_valid) begin
		for(v = 0; v < (`KERNEL_AREA * `D_AREA); v = v + 1) begin
			conv_acc[v / `KERNEL_AREA][v % `KERNEL_AREA] <= 0;
		end
	end
end

// Median
	integer e;
always@(posedge i_clk or negedge i_rst_n) begin
	if(!i_rst_n) begin
		for(e = 0; e < (`MEDIAN_DEPTH * `KERNEL_AREA * `D_AREA); e = e + 1) begin
			median_r[e / (`KERNEL_AREA * `D_AREA)][(e / `KERNEL_AREA) % `D_AREA][e % `KERNEL_AREA] <= 0;
		end
	end else if((op_mode_r == 4'b1001) && (busy_buffer2) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin
		median_r[conv_pc_buffer2 / (`KERNEL_AREA * `D_AREA)][(conv_pc_buffer2 / `KERNEL_AREA) % `D_AREA][conv_pc_buffer2 % `KERNEL_AREA] <= o_data_sram;
		if((conv_center / `C_WIDTH) == 0) begin							// Top
			if(((conv_pc_buffer2 % `KERNEL_AREA) / `KERNEL_WIDTH) == 0) median_r[conv_pc_buffer2 / (`KERNEL_AREA * `D_AREA)][(conv_pc_buffer2 / `KERNEL_AREA) % `D_AREA][conv_pc_buffer2 % `KERNEL_AREA] <= 0;
		end else if((conv_center / `C_WIDTH) == (`C_WIDTH - 1)) begin	// Bottom
			if(((conv_pc_buffer2 % `KERNEL_AREA) / `KERNEL_WIDTH) == (`KERNEL_WIDTH - 1)) median_r[conv_pc_buffer2 / (`KERNEL_AREA * `D_AREA)][(conv_pc_buffer2 / `KERNEL_AREA) % `D_AREA][conv_pc_buffer2 % `KERNEL_AREA] <= 0;
		end

		if((conv_center % `C_WIDTH) == 0) begin							// Left
			if(((conv_pc_buffer2 % `KERNEL_AREA) % `KERNEL_WIDTH) == 0) median_r[conv_pc_buffer2 / (`KERNEL_AREA * `D_AREA)][(conv_pc_buffer2 / `KERNEL_AREA) % `D_AREA][conv_pc_buffer2 % `KERNEL_AREA] <= 0;
		end else if((conv_center % `C_WIDTH) == (`C_WIDTH - 1)) begin	// Right
			if(((conv_pc_buffer2 % `KERNEL_AREA) % `KERNEL_WIDTH) == (`KERNEL_WIDTH - 1)) median_r[conv_pc_buffer2 / (`KERNEL_AREA * `D_AREA)][(conv_pc_buffer2 / `KERNEL_AREA) % `D_AREA][conv_pc_buffer2 % `KERNEL_AREA] <= 0;
		end
	end else if(i_op_valid) begin
		for(e = 0; e < (`MEDIAN_DEPTH * `KERNEL_AREA * `D_AREA); e = e + 1) begin
			median_r[e / (`KERNEL_AREA * `D_AREA)][(e / `KERNEL_AREA) % `D_AREA][e % `KERNEL_AREA] <= 0;
		end
	end
end

// Sobel
	integer b;
always@(posedge i_clk or negedge i_rst_n) begin
	if(!i_rst_n) begin
		for(b = 0; b < (`SOBEL_DEPTH * `KERNEL_AREA * `D_AREA); b = b + 1) begin
			sobel_r[b / (`KERNEL_AREA * `D_AREA)][(b / `KERNEL_AREA) % `D_AREA][b % `KERNEL_AREA] <= 0;
		end
	end else if((op_mode_r == 4'b1010) && (busy_buffer2) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin
		sobel_r[conv_pc_buffer2 / (`KERNEL_AREA * `D_AREA)][(conv_pc_buffer2 / `KERNEL_AREA) % `D_AREA][conv_pc_buffer2 % `KERNEL_AREA] <= o_data_sram;
		if((conv_center / `C_WIDTH) == 0) begin							// Top
			if(((conv_pc_buffer2 % `KERNEL_AREA) / `KERNEL_WIDTH) == 0) sobel_r[conv_pc_buffer2 / (`KERNEL_AREA * `D_AREA)][(conv_pc_buffer2 / `KERNEL_AREA) % `D_AREA][conv_pc_buffer2 % `KERNEL_AREA] <= 0;
		end else if((conv_center / `C_WIDTH) == (`C_WIDTH - 1)) begin	// Bottom
			if(((conv_pc_buffer2 % `KERNEL_AREA) / `KERNEL_WIDTH) == (`KERNEL_WIDTH - 1)) sobel_r[conv_pc_buffer2 / (`KERNEL_AREA * `D_AREA)][(conv_pc_buffer2 / `KERNEL_AREA) % `D_AREA][conv_pc_buffer2 % `KERNEL_AREA] <= 0;
		end

		if((conv_center % `C_WIDTH) == 0) begin							// Left
			if(((conv_pc_buffer2 % `KERNEL_AREA) % `KERNEL_WIDTH) == 0) sobel_r[conv_pc_buffer2 / (`KERNEL_AREA * `D_AREA)][(conv_pc_buffer2 / `KERNEL_AREA) % `D_AREA][conv_pc_buffer2 % `KERNEL_AREA] <= 0;
		end else if((conv_center % `C_WIDTH) == (`C_WIDTH - 1)) begin	// Right
			if(((conv_pc_buffer2 % `KERNEL_AREA) % `KERNEL_WIDTH) == (`KERNEL_WIDTH - 1)) sobel_r[conv_pc_buffer2 / (`KERNEL_AREA * `D_AREA)][(conv_pc_buffer2 / `KERNEL_AREA) % `D_AREA][conv_pc_buffer2 % `KERNEL_AREA] <= 0;
		end
	end else if(i_op_valid) begin
		for(b = 0; b < (`SOBEL_DEPTH * `KERNEL_AREA * `D_AREA); b = b + 1) begin
			sobel_r[b / (`KERNEL_AREA * `D_AREA)][(b / `KERNEL_AREA) % `D_AREA][b % `KERNEL_AREA] <= 0;
		end
	end
end
	// grad
	integer g;
always@(posedge i_clk or negedge i_rst_n) begin
	if(!i_rst_n) begin
		for(g = 0; g < (`SOBEL_DEPTH * `D_AREA); g = g + 1) begin
			grad_r[g / `D_AREA][g % `D_AREA][0] <= 0;
			grad_r[g / `D_AREA][g % `D_AREA][1] <= 0;
			grad_r[g / `D_AREA][g % `D_AREA][2] <= 0;
		end
	end else if((op_mode_r == 4'b1010) && (busy_buffer2) && ((conv_pc_buffer3 % `KERNEL_AREA) == 'd8) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin
		grad_r[conv_pc_buffer3 / (`KERNEL_AREA * `D_AREA)][((conv_pc_buffer3 / `KERNEL_AREA) % `D_AREA)][0] <= grad;
		grad_r[conv_pc_buffer3 / (`KERNEL_AREA * `D_AREA)][((conv_pc_buffer3 / `KERNEL_AREA) % `D_AREA)][1] <= grad_x;
		grad_r[conv_pc_buffer3 / (`KERNEL_AREA * `D_AREA)][((conv_pc_buffer3 / `KERNEL_AREA) % `D_AREA)][2] <= grad_y;
	end else if(i_op_valid) begin
		for(g = 0; g < (`SOBEL_DEPTH * `D_AREA); g = g + 1) begin
			grad_r[g / `D_AREA][g % `D_AREA][0] <= 0;
			grad_r[g / `D_AREA][g % `D_AREA][1] <= 0;
			grad_r[g / `D_AREA][g % `D_AREA][2] <= 0;
		end
	end
end

// Operations
	// Input image
always@(posedge i_clk or negedge i_rst_n) begin
	if(!i_rst_n) begin
		o_in_ready_r <= 1;
	end else if(op_mode_r == 0) begin
		o_in_ready_r <= 1;
	end else if(pc_sram_r >= 2048) begin
		o_in_ready_r <= 0;
	end
end

always@(posedge i_clk or negedge i_rst_n) begin
	if(!i_rst_n) begin
		i_data_sram_r <= 0;
	end else if((op_mode_r == 0) && i_in_valid && o_in_ready) begin
		i_data_sram_r <= i_in_data;
	end else begin
		i_data_sram_r <= 0;
	end
end

always@(posedge i_clk or negedge i_rst_n) begin
	if(!i_rst_n) begin
		pc_sram_r <= 0;
	end else if((op_mode_r == 0) && i_in_valid && o_in_ready) begin
		pc_sram_r <= pc_sram_r + 1;						// 4096-word by 8-bit
	end
end

	// origin shift
always@(posedge i_clk or negedge i_rst_n) begin
	if(!i_rst_n) begin
		origin <= 0;
	end else begin
		case(op_mode_r)
			OS_R: origin <= (((origin % `C_WIDTH) < (`C_WIDTH  - 1)) && (op_busy_r))? (origin +     1   ): origin;
			OS_L: origin <= (((origin % `C_WIDTH) >        0       ) && (op_busy_r))? (origin -     1   ): origin;
			OS_U: origin <= (((origin / `C_WIDTH) >        0       ) && (op_busy_r))? (origin - `C_WIDTH): origin;
			OS_D: origin <= (((origin / `C_WIDTH) < (`C_LENGTH - 1)) && (op_busy_r))? (origin + `C_WIDTH): origin;
		endcase
	end
end

	// change channel depth
always@(posedge i_clk or negedge i_rst_n) begin
	if(!i_rst_n) begin
		display_depth <= DEPTH_32;
	end else if((op_mode_r == 4'b0101) && (op_busy_r)) begin		// reduce
		case(display_depth)
			DEPTH_32: display_depth <= DEPTH_16;
			DEPTH_16: display_depth <= DEPTH_8;
			DEPTH_8: display_depth <= DEPTH_8;
		endcase
	end else if((op_mode_r == 4'b0110) && (op_busy_r)) begin		// increase
		case(display_depth)
			DEPTH_32: display_depth <= DEPTH_32;
			DEPTH_16: display_depth <= DEPTH_32;
			DEPTH_8: display_depth <= DEPTH_16;
		endcase
	end
end

// IOs
	// operation ready
always@(posedge i_clk or negedge i_rst_n) begin
	if(!i_rst_n) begin
		o_op_ready_r <= 0;
	end else if((!op_busy_r) && (!o_out_valid_r) && (!i_in_valid) && (!i_op_valid) && (!o_out_valid_buffer0)) begin
		o_op_ready_r <= 1;
	end else begin
		o_op_ready_r <= 0;	// raised for only 1 cycle
	end
end

	// fetch op mode
always@(posedge i_clk or negedge i_rst_n) begin
	if(!i_rst_n) begin
		op_mode_r <= 0;
	end else if(i_op_valid) begin
		op_mode_r <= i_op_mode;
	end
end

	// ouput data
always@(posedge i_clk or negedge i_rst_n) begin
	if(!i_rst_n) begin
		o_out_valid_buffer0 <= 0;
		o_out_valid_buffer <= 0;
		o_out_valid_r <= 0;
	end else if((op_mode_r == 4'b0111) && (out_valid_buffer_r2) && (op_busy_r) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin
		o_out_valid_r <= 1;
	end else if((op_mode_r == 4'b1000) && (conv_pc_buffer2 == (display_depth * `D_AREA * `KERNEL_AREA)) && (!out_valid_buffer_r4) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin		// convolution
		o_out_valid_r <= 1;
	end else if((op_mode_r == 4'b1001) && (conv_pc_buffer2 == (`MEDIAN_DEPTH * `D_AREA * `KERNEL_AREA)) && (output_cnt < (`MEDIAN_DEPTH * `D_AREA + 2)) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin		// convolution
		o_out_valid_buffer0 <= 1;
		o_out_valid_buffer <= o_out_valid_buffer0;
		o_out_valid_r <= o_out_valid_buffer;
	end else if((op_mode_r == 4'b1010) && (pc_display_r == (`SOBEL_DEPTH * `D_AREA * `KERNEL_AREA)) && (output_cnt < (`SOBEL_DEPTH * `D_AREA)) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin		// convolution
		o_out_valid_buffer0 <= 1;
		o_out_valid_buffer <= o_out_valid_buffer0;
		o_out_valid_r <= o_out_valid_buffer;
	end else begin
		o_out_valid_buffer0 <= 0;
		o_out_valid_buffer <= 0;
		o_out_valid_r <= 0;
	end
end

always@(posedge i_clk or negedge i_rst_n) begin
	if(!i_rst_n) begin
		out_valid_buffer_r1 <= 0;
		out_valid_buffer_r2 <= 0;
		out_valid_buffer_r3 <= 0;
		out_valid_buffer_r4 <= 0;
	end else if((op_mode_r == 4'b0111) && (pc_display_r < (display_depth * `D_AREA)) && (op_busy_r) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin
		out_valid_buffer_r1 <= 1;
		out_valid_buffer_r2 <= out_valid_buffer_r1;
	end else if((op_mode_r == 4'b1000) && (conv_pc_buffer2 == (display_depth * `D_AREA * `KERNEL_AREA)) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin		// convolution
		out_valid_buffer_r1 <= 1;
		out_valid_buffer_r2 <= out_valid_buffer_r1;
		out_valid_buffer_r3 <= out_valid_buffer_r2;
		out_valid_buffer_r4 <= out_valid_buffer_r3;
	end else if((op_mode_r == 4'b1001) && (conv_pc_buffer2 == (`MEDIAN_DEPTH * `D_AREA * `KERNEL_AREA)) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin		// convolution
		out_valid_buffer_r1 <= 1;
		out_valid_buffer_r2 <= out_valid_buffer_r1;
		out_valid_buffer_r3 <= out_valid_buffer_r2;
		out_valid_buffer_r4 <= out_valid_buffer_r3;
	end else if((op_mode_r == 4'b1010) && (conv_pc_buffer2 == (`SOBEL_DEPTH * `D_AREA * `KERNEL_AREA)) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin		// convolution
		out_valid_buffer_r1 <= 1;
		out_valid_buffer_r2 <= out_valid_buffer_r1;
		out_valid_buffer_r3 <= out_valid_buffer_r2;
		out_valid_buffer_r4 <= out_valid_buffer_r3;
	end else begin
		out_valid_buffer_r1 <= 0;
		out_valid_buffer_r2 <= out_valid_buffer_r1;
		out_valid_buffer_r3 <= out_valid_buffer_r2;
		out_valid_buffer_r4 <= out_valid_buffer_r3;
	end
end

always@(posedge i_clk or negedge i_rst_n) begin
	if(!i_rst_n) begin
		output_cnt <= 0;
	end else if((op_mode_r == 4'b1001) && (conv_pc_buffer2 == (`MEDIAN_DEPTH * `D_AREA * `KERNEL_AREA)) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin		// convolution
		output_cnt <= output_cnt + 1;
	end else if((op_mode_r == 4'b1010) && (conv_pc_buffer2 == (`SOBEL_DEPTH * `D_AREA * `KERNEL_AREA)) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin		// convolution
		output_cnt <= output_cnt + 1;
	end else begin
		output_cnt <= 0;
	end
end

always@(posedge i_clk or negedge i_rst_n) begin
	if(!i_rst_n) begin
		o_out_data_r <= 0;
	end else if((op_mode_r == 4'b0111) && (out_valid_buffer_r2) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin			// display
		o_out_data_r <= {{6{1'b0}}, o_data_sram};
	end else if((op_mode_r == 4'b1000) && (conv_pc_buffer2 == (display_depth * `D_AREA * `KERNEL_AREA)) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin		// convolution
		o_out_data_r <= weighting(conv_acc, ii);
	end else if((op_mode_r == 4'b1001) && (conv_pc_buffer2 == (`MEDIAN_DEPTH * `D_AREA * `KERNEL_AREA)) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin		// median
		o_out_data_r <= {{6{1'b0}}, median_out};
	end else if((op_mode_r == 4'b1010) && (conv_pc_buffer2 == (`SOBEL_DEPTH * `D_AREA * `KERNEL_AREA)) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin		// sobel
		o_out_data_r <= nms(grad_r, ii);
	end else begin
		o_out_data_r <= 0;
	end
end

always@(posedge i_clk or negedge i_rst_n) begin
	if(!i_rst_n) begin
		pulse_out_r <= 0;
	end else if(o_out_valid_r) begin
		pulse_out_r <= 1;
	end else begin
		pulse_out_r <= 0;
	end
end

	// display
always@(posedge i_clk or negedge i_rst_n) begin
	if(!i_rst_n) begin
		pc_display_r <= 0;
	end else if((op_mode_r == 4'b0111) && (pc_display_r < (display_depth * `D_AREA)) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin	// display
		pc_display_r <= pc_display_r + 1;
	end else if((op_mode_r == 4'b1000) && (pc_display_r < (display_depth * `D_AREA * `KERNEL_AREA)) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin		// convolution
		pc_display_r <= pc_display_r + 1;
	end else if((op_mode_r == 4'b1001) && (pc_display_r < (`MEDIAN_DEPTH * `D_AREA * `KERNEL_AREA)) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin		// median
		pc_display_r <= pc_display_r + 1;
	end else if((op_mode_r == 4'b1010) && (pc_display_r < (`SOBEL_DEPTH * `D_AREA * `KERNEL_AREA)) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin		// sobel
		pc_display_r <= pc_display_r + 1;
	end else if(i_op_valid) begin
		pc_display_r <= 0;
	end
end
	// pc buffer for convolution
always@(posedge i_clk or negedge i_rst_n) begin
	if(!i_rst_n) begin
		conv_pc_buffer1 <= 0;
		conv_pc_buffer2 <= 0;
		conv_pc_buffer3 <= 0;
	end else if((op_mode_r == 4'b1000) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin		// convolution
		conv_pc_buffer1 <= pc_display_r;
		conv_pc_buffer2 <= conv_pc_buffer1;
	end else if((op_mode_r == 4'b1001) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin		// median
		conv_pc_buffer1 <= pc_display_r;
		conv_pc_buffer2 <= conv_pc_buffer1;
		conv_pc_buffer3 <= conv_pc_buffer2;
	end else if((op_mode_r == 4'b1010) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin		// sobel
		conv_pc_buffer1 <= pc_display_r;
		conv_pc_buffer2 <= conv_pc_buffer1;
		conv_pc_buffer3 <= conv_pc_buffer2;
	end else if(i_op_valid) begin
		conv_pc_buffer1 <= 0;
		conv_pc_buffer2 <= 0;
		conv_pc_buffer3 <= 0;
	end
end

always@(posedge i_clk or negedge i_rst_n) begin
	if(!i_rst_n) begin
		ii <= 0;
	end else if((op_mode_r == 4'b1000) && (conv_pc_buffer2 == (display_depth * `D_AREA * `KERNEL_AREA)) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin
		ii <= ii + 1;
	end else if((op_mode_r == 4'b1001) && (conv_pc_buffer2 == (`MEDIAN_DEPTH * `D_AREA * `KERNEL_AREA)) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin
		ii <= ii + 1;
	end else if((op_mode_r == 4'b1010) && (conv_pc_buffer2 == (`SOBEL_DEPTH * `D_AREA * `KERNEL_AREA)) && (!i_in_valid) && (!i_op_valid) && (!o_op_ready_r)) begin
		ii <= ii + 1;
	end else begin
		ii <= 0;
	end
end	

endmodule



module median(
	input 		  clk,
	input 		  rst,
	input  [ 7:0] median_r [0: 3][0: 3][0: 8],
	input  [ 3:0] ii,
	output [ 7:0] out
);

localparam L3 = 3'd3,
		   L5 = 3'd5;

wire [ 7:0] l1_a_max, l1_a_med, l1_a_min, l1_b_max, l1_b_med, l1_b_min, l1_c_max, l1_c_med, l1_c_min;
wire [ 7:0] l2_a_max, l2_a_med, l2_a_min, l2_b_max, l2_b_med, l2_b_min, l2_c_max, l2_c_med, l2_c_min;
wire [ 7:0] l3_a_max, l3_a_med, l3_a_min, l3_c_max, l3_c_med, l3_c_min;
wire [ 7:0] l4_a_max, l4_a_min, l4_c_max, l4_c_med, l4_c_min;
wire [ 7:0] l5_a_max, l5_a_min, l5_c_max, l5_c_min;
wire [ 7:0] l6_b_max, l6_b_med, l6_b_min;

wire [ 7:0] l3_a_med_, l3_a_min_, R3_, l3_c_max_, l3_c_med_;
wire [ 7:0] l5_a_min_, R5_, l5_c_max_;

reg  [ 7:0] l3_a_med_r, l3_a_min_r, R3, l3_c_max_r, l3_c_med_r;
reg  [ 7:0] l5_a_min_r, R5, l5_c_max_r;

reg  [ 3:0] state, state_n;

assign l3_a_med_ = l3_a_med_r;
assign l3_a_min_ = l3_a_min_r;
assign R3_       = R3 		 ;
assign l3_c_max_ = l3_c_max_r;
assign l3_c_med_ = l3_c_med_r;

assign l5_a_min_ = l5_a_min_r;
assign R5_		 = R5		 ;
assign l5_c_max_ = l5_c_max_r;

always@(*) begin
	state_n = state;
	case(state)
		L3: state_n = L5;
		L5: state_n = L3;
	endcase
end

always@(posedge clk or negedge rst) begin
	if(!rst) begin
		state <= 3'd3; 
	end else begin
		state <= state_n;
	end
end

comp3 Level1_a(
	.n1(median_r[ii / `D_AREA][ii % `D_AREA][0]),
	.n2(median_r[ii / `D_AREA][ii % `D_AREA][1]),
	.n3(median_r[ii / `D_AREA][ii % `D_AREA][2]),
	.max(l1_a_max),
	.med(l1_a_med),
	.min(l1_a_min)
);

comp3 Level1_b(
	.n1(median_r[ii / `D_AREA][ii % `D_AREA][3]),
	.n2(median_r[ii / `D_AREA][ii % `D_AREA][4]),
	.n3(median_r[ii / `D_AREA][ii % `D_AREA][5]),
	.max(l1_b_max),
	.med(l1_b_med),
	.min(l1_b_min)
);

comp3 Level1_c(
	.n1(median_r[ii / `D_AREA][ii % `D_AREA][6]),
	.n2(median_r[ii / `D_AREA][ii % `D_AREA][7]),
	.n3(median_r[ii / `D_AREA][ii % `D_AREA][8]),
	.max(l1_c_max),
	.med(l1_c_med),
	.min(l1_c_min)
);

comp3 Level2_a(
	.n1(l1_a_max),
	.n2(l1_b_max),
	.n3(l1_c_max),
	.max(l2_a_max),
	.med(l2_a_med),
	.min(l2_a_min)
);

comp3 Level2_b(
	.n1(l1_a_med),
	.n2(l1_b_med),
	.n3(l1_c_med),
	.max(l2_b_max),
	.med(l2_b_med),
	.min(l2_b_min)
);

comp3 Level2_c(
	.n1(l1_a_min),
	.n2(l1_b_min),
	.n3(l1_c_min),
	.max(l2_c_max),
	.med(l2_c_med),
	.min(l2_c_min)
);

comp3 Level3_a(
	.n1(l2_a_med),
	.n2(l2_b_max),
	.n3(l2_c_max),
	.max(),
	.med(l3_a_med),
	.min(l3_a_min)
);

comp3 Level3_b(
	.n1(l2_a_min),
	.n2(l2_b_min),
	.n3(l2_c_med),
	.max(l3_c_max),
	.med(l3_c_med),
	.min()
);

comp2 Level4_a(
	.n1(l3_a_med_),
	.n2(l3_a_min_),
	.max(l4_a_max),
	.min(l4_a_min)
);

comp3 Level4_b(
	.n1(R3_),
	.n2(l3_c_max_),
	.n3(l3_c_med_),
	.max(l4_c_max),
	.med(l4_c_med),
	.min(l4_c_min)
);

comp2 Level5_a(
	.n1(l4_a_max),
	.n2(l4_c_max),
	.max(),
	.min(l5_a_min)
);

comp2 Level5_b(
	.n1(l4_a_min),
	.n2(l4_a_min),
	.max(l5_c_max),
	.min()
);

comp3 Level6(
	.n1(l5_a_min_),
	.n2(R5_),
	.n3(l5_c_max_),
	.max(),
	.med(out),
	.min()
);

always@(posedge clk or negedge rst) begin
	if(!rst) begin
		l3_a_med_r <= 0;
		l3_a_min_r <= 0;
		R3 		   <= 0;
		l3_c_max_r <= 0;
		l3_c_med_r <= 0;
	end else begin
		l3_a_med_r <= l3_a_med;
		l3_a_min_r <= l3_a_min;
		R3 		   <= l2_b_med;
		l3_c_max_r <= l3_c_max;
		l3_c_med_r <= l3_c_med;
	end
end

always@(posedge clk or negedge rst) begin
	if(!rst) begin
		l5_a_min_r <= 0;
		R5		   <= 0;
		l5_c_max_r <= 0;
	end else begin
		l5_a_min_r <= l5_a_min;
		R5		   <= l4_c_med;
		l5_c_max_r <= l5_c_max;
	end
end

endmodule

module comp3 (
	input  [ 7:0] n1,
	input  [ 7:0] n2,
	input  [ 7:0] n3,
	output [ 7:0] max,
	output [ 7:0] med,
	output [ 7:0] min
);

assign max = (n1 >= n2)? ((n1 >= n3)? n1: n3): ((n2 >= n3)? n2: n3);
assign min = (n1 <= n2)? ((n1 <= n3)? n1: n3): ((n2 <= n3)? n2: n3);
assign med = ((n1 >= n2) && (n1 <= n3) || (n1 <= n2) && (n1 >= n3))? n1: (((n2 >= n1) && (n2 <= n3) || (n2 <= n1) && (n2 >= n3))? n2: n3);

endmodule

module comp2 (
	input         clk,
	input         rst,
	input  [ 7:0] n1,
	input  [ 7:0] n2,
	output [ 7:0] max,
	output [ 7:0] min
);

assign max = (n1 >= n2)? n1: n2;
assign min = (n1 <= n2)? n1: n2;

endmodule

module sobel (
	input         clk,
	input         rst,
	input  [ 7:0] sobel_r [0: 3][0: 3][0: 8],
	input  [10:0] ii,
	output signed [13:0] o_x,
	output signed [13:0] o_y,
	output [13:0] o_grad
);

	wire   signed [13:0] tmp_x, tmp_y;
	wire          [13:0] x, y, grad;

	assign o_x = tmp_x;
	assign o_y = tmp_y;
	assign o_grad = grad;

	assign	tmp_x = $signed( 
						$signed((sobel_r[ii / `D_AREA][ii % `D_AREA][2]) - (sobel_r[ii / `D_AREA][ii % `D_AREA][0]))
						+ $signed(((sobel_r[ii / `D_AREA][ii % `D_AREA][5]) - (sobel_r[ii / `D_AREA][ii % `D_AREA][3])) * 2)
						+ $signed((sobel_r[ii / `D_AREA][ii % `D_AREA][8]) - (sobel_r[ii / `D_AREA][ii % `D_AREA][6]))
		); 

	assign	tmp_y = $signed( 
						$signed((sobel_r[ii / `D_AREA][ii % `D_AREA][6]) - (sobel_r[ii / `D_AREA][ii % `D_AREA][0]))
						+ $signed(((sobel_r[ii / `D_AREA][ii % `D_AREA][7]) - (sobel_r[ii / `D_AREA][ii % `D_AREA][1])) * 2)
						+ $signed((sobel_r[ii / `D_AREA][ii % `D_AREA][8]) - (sobel_r[ii / `D_AREA][ii % `D_AREA][2]))
		); 

	assign	x = (tmp_x < 0)? (~tmp_x + 1): tmp_x;
	assign	y = (tmp_y < 0)? (~tmp_y + 1): tmp_y;
	assign	grad = x + y;

endmodule