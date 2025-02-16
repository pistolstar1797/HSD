module pe_ctrl#(
       parameter VECTOR_SIZE = 4, // vector size
	   parameter L_RAM_SIZE = 6 //4
    )
    (
        input start,
        output done,
        input aclk,
        input aresetn,
        output [2*L_RAM_SIZE:0] rdaddr,
	    input [31:0] rddata,
	    output reg [31:0] wrdata
);
    reg [31:0] wrdata_i [2**VECTOR_SIZE-1:0];
   // PE
    wire [31:0] ain;
    wire [31:0] din;
    wire [L_RAM_SIZE-1:0] addr;
    wire we_local;
    wire we_global;
    //wire we;
    wire valid;
    wire dvalid;
    wire [31:0] dout;
    wire [2*L_RAM_SIZE:0] rdaddr;

   
   // global block ram
    reg [31:0] gdout;
    (* ram_style = "block" *) reg [31:0] globalmem [0:2**VECTOR_SIZE-1];
    always @(posedge aclk)
//        if (we_local)
//            din <= rddata;
        if (we_global)
            globalmem[addr] <= rddata;
        else
            gdout <= globalmem[addr];

    // down counter
    reg [31:0] counter;
    wire [31:0] ld_val = (load_flag_en)? CNTLOAD1 :
                         (calc_flag_en)? CNTCALC1 : 
                         (done_flag_en)? CNTDONE  : 'd0;
    wire counter_ld = load_flag_en || calc_flag_en || done_flag_en;
    wire counter_en = (curr_state == S_LOAD && next_state == S_LOAD) || dvalid || (curr_state == S_DONE && next_state == S_DONE);
    wire counter_reset = !aresetn || load_done || calc_done || done_done;
    always @(posedge aclk)
        if (counter_reset)
            counter <= 'd0;
        else
            if (counter_ld)
                counter <= ld_val;
            else if (counter_en)
                counter <= counter - 1;
   
	//FSM
    // transition triggering flags
    wire load_done;
    wire calc_done;
    wire done_done;
        
    // state register
    reg [3:0] curr_state, next_state;
    localparam S_IDLE = 4'd0;
    localparam S_LOAD = 4'd1;
    localparam S_CALC = 4'd2;
    localparam S_DONE = 4'd3;

	//part 1: state transition
    always @(posedge aclk)
        if (!aresetn)
            next_state <= S_IDLE;
        else
            case (next_state)
                S_IDLE:
                    next_state <= (start)? S_LOAD : S_IDLE;
                S_LOAD: // LOAD PERAM
                    next_state <= (load_done)? S_CALC : S_LOAD;
                S_CALC: // CALCULATE RESULT
                    next_state <= (calc_done)? S_DONE : S_CALC;
                S_DONE:
                    next_state <= (done_done)? S_IDLE : S_DONE;
                default:
                    next_state <= S_IDLE;
            endcase
    
    always @(posedge aclk)
        if (!aresetn)
            curr_state   <= S_IDLE;
        else
            curr_state <= next_state;

	//part 2: determine state
    // S_LOAD
    reg load_flag;
    wire load_flag_reset = !aresetn || load_done;
    wire load_flag_en = (curr_state == S_IDLE) && (next_state == S_LOAD);
    localparam CNTLOAD1 = (2*(2**VECTOR_SIZE + 1)*(2**VECTOR_SIZE)) -1;
    always @(posedge aclk)
        if (load_flag_reset)
            load_flag <= 'd0;
        else
            if (load_flag_en)
                load_flag <= 'd1;
            else
                load_flag <= load_flag;

    // S_CALC
    reg calc_flag;
    wire calc_flag_reset = !aresetn || calc_done;
    wire calc_flag_en = (curr_state == S_LOAD) && (next_state == S_CALC);
    localparam CNTCALC1 = (2**VECTOR_SIZE) - 1;
    always @(posedge aclk)
        if (calc_flag_reset)
            calc_flag <= 'd0;
        else
            if (calc_flag_en)
                calc_flag <= 'd1;
            else
                calc_flag <= calc_flag;
    
    // S_DONE
    reg done_flag;
    wire done_flag_reset = !aresetn || done_done;
    wire done_flag_en = (curr_state == S_CALC) && (next_state == S_DONE);
    localparam CNTDONE = 5;
    always @(posedge aclk)
        if (done_flag_reset)
            done_flag <= 'd0;
        else
            if (done_flag_en)
                done_flag <= 'd1;
            else
                done_flag <= done_flag;
    
    //part3: update output and internal register
    //S_LOAD: we
	assign we_local = (curr_state == S_LOAD && next_state == S_LOAD && counter[31:L_RAM_SIZE+1] && !counter[0]) ? 'd1 : 'd0;
	assign we_global = (curr_state == S_LOAD && next_state == S_LOAD && !counter[31:L_RAM_SIZE+1] && !counter[0]) ? 'd1 : 'd0;
	
	//S_CALC: wrdata
	genvar i;
	for(i = 0; i < 2**VECTOR_SIZE; i = i + 1) begin: wrreg
	
       always @(posedge aclk)
            if (!aresetn)
                    wrdata_i[i] <= 'd0;
            else
                if (calc_done)
                        wrdata_i[i] <= pe[i].dout_i;
                else
                        wrdata_i[i] <= wrdata_i[i];
    end
	   
	//S_CALC: valid
    reg valid_pre, valid_reg;
    always @(posedge aclk)
        if (!aresetn)
            valid_pre <= 'd0;
        else
            if (counter_ld || counter_en)
                valid_pre <= 'd1;
            else
                valid_pre <= 'd0;
    
    always @(posedge aclk)
        if (!aresetn)
            valid_reg <= 'd0;
        else if (curr_state == S_CALC && next_state == S_CALC)
            valid_reg <= valid_pre;
     
    assign valid = (curr_state == S_CALC && next_state == S_CALC) && valid_reg;
    
	//S_CALC: ain
	assign ain = (curr_state == S_CALC && next_state == S_CALC)? gdout : 'd0;

	//S_LOAD&&CALC
    assign addr = (curr_state == S_LOAD && next_state == S_LOAD)? counter[L_RAM_SIZE:1]:
                  (curr_state == S_CALC && next_state == S_CALC)? counter[L_RAM_SIZE-1:0]: 'd0;

	//S_LOAD
	assign din = (curr_state == S_LOAD && next_state == S_LOAD)? rddata : 'd0;
    assign rdaddr = (next_state == S_LOAD)? counter[2*L_RAM_SIZE+1:1] : 'd0;

	//done signals
    assign load_done = (curr_state == S_LOAD && next_state == S_LOAD) && (counter == 'd0);
    assign calc_done = (curr_state == S_CALC && next_state == S_CALC) && (counter == 'd0) && dvalid;
    assign done_done = (curr_state == S_DONE && next_state == S_DONE) && (counter == 'd0);
    assign done = (next_state == S_DONE) && done_done;
    
    wire [2**VECTOR_SIZE-1:0] dvalid_i;
    
    assign dvalid = &dvalid_i;
        generate for(i = 0; i < 2**VECTOR_SIZE; i = i + 1) begin: pe
            wire [31:0] dout_i;
            my_pe #(
                .L_RAM_SIZE(L_RAM_SIZE)
            ) u_pe (
                .aclk(aclk),
                .aresetn(aresetn && (next_state != S_DONE)),
                .ain(ain),
                .din(din),
                .addr(addr),
                .we(we_local && (counter[2*L_RAM_SIZE+1:L_RAM_SIZE+1] == i + 1)),
                .valid(valid),
                .dvalid(dvalid_i[i]),
                .dout(dout_i)
            );
        end endgenerate
endmodule