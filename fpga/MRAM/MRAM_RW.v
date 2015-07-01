`timescale 1ns / 1ps

//`define DATA_PATTERN_0 16'hA635
//`define DATA_PATTERN_1 16'h59CA // inverse of DATA_PATTERN_0
`define DATA_PATTERN_0 16'h35A9
`define DATA_PATTERN_1 16'hCA56 // inverse of DATA_PATTERN_0

`define MRAM_LATENCY 10

module MRAM_RW(
    input CLKM,
    input RST,

    input  start,
    output done_wire,
    input inverse_pattern,

    input [1:0]  pOPER,
    input [17:0] pADDR,
    output [31:0] latency,
    output [15:0] badbits,
    output [7:0] Led,

    //MRAM wires
	output e_n,
	output w_n,
	output g_n,
	output ub_n,
	output lb_n,
	output [17:0] addr,
	inout  [15:0] dq
);

//debug led
    assign Led[7:0] = {start,done_wire,CLKM,NSTAT[4:0]};

// FSM
parameter
    INIT       = 30, OPER_CHECK = 29,
    DATA_IN_0  =  1, DATA_IN_1  =  2, DATA_IN_2  =  3, DATA_IN_3  =  4,  //WRITE
    DATA_OUT_0 =  5, DATA_OUT_1 =  6, DATA_OUT_2 =  7, DATA_OUT_3 =  8, DATA_OUT_4 =  9, DATA_OUT_5 = 10,  //READ
    RESET_0    = 11, RESET_1    = 12,
    END_0      = 13,
    STOP       = 00;

parameter
    oWR = 0,
    oRD = 1,
    oER = 2,
    oRS = 3;

assign e_n = e_n_reg;
assign w_n = w_n_reg;
assign g_n = g_n_reg;
assign ub_n = ub_n_reg;
assign lb_n = lb_n_reg;

assign addr[17:0] = addr_reg[17:0];
assign dq[15:0]  = (DQ_input_en)? 16'bzzzz_zzzz_zzzz_zzzz : dq_reg[15:0];

assign badbits[15:0] = cnt_badbits[15:0];

assign latency[31:0] = cnt_latency[31:0];

reg e_n_reg;
reg w_n_reg;
reg g_n_reg;
reg ub_n_reg;
reg lb_n_reg;
reg [17:0] addr_reg;
reg [15:0] dq_reg;

reg [15:0] dq_comp;
reg DQ_input_en;

reg [7:0] cnt_wait;
reg [31:0] cnt_latency;
reg [15:0] cnt_badbits;

reg [4:0] NSTAT;

assign done_wire = (NSTAT == STOP) ? 1'b1 : 1'b0;

always@(posedge CLKM)
    begin
    if(RST)
        begin
            //CE           <= 0;
            NSTAT <= INIT;
        end
    else
        begin
            case (NSTAT)
                INIT:
                    begin
                        cnt_wait <= 0;
                        cnt_latency <= 32'h0;
                        cnt_badbits <= 16'h0;

                        DQ_input_en <= 0;

                        e_n_reg <= 1;
                        w_n_reg <= 1;
                        g_n_reg <= 1;
                        ub_n_reg <= 1;
                        lb_n_reg <= 1;

                		addr_reg <= pADDR[17:0];
                        if (inverse_pattern)
                            dq_reg <= `DATA_PATTERN_1;
                        else
                            dq_reg <= `DATA_PATTERN_0;

                        if( start == 0 )
                            NSTAT <= INIT;
                        else
                            NSTAT <= OPER_CHECK;
                    end
                OPER_CHECK:
                    begin
                        if(pOPER == oRS)
                            NSTAT <= RESET_0;
                        else if(pOPER == oWR)
                            NSTAT <= DATA_IN_0;
                        else
                            NSTAT <= DATA_OUT_0;
                    end
            // FSM: RESET ==========================================
                RESET_0:
                    begin
                        cnt_latency <= 0;
                        NSTAT <= RESET_1;
                    end
                RESET_1:
                    begin
                        if ( cnt_latency != 32'd200_000) //2ms => 2,000,000 ns  => (10ns/cycle) 200_000 cycle
                            begin
                                cnt_latency <= cnt_latency + 1'b1;
                                NSTAT <= RESET_1;
                            end
                        else
                            begin
                                cnt_latency <= 0;
                                NSTAT <= END_0;
                            end
                    end
            // FSM: WRITE ==========================================
                DATA_IN_0: // WR_START
                    begin
                        DQ_input_en <= 0;

    					e_n_reg <= 0;
                        w_n_reg <= 0;
                        g_n_reg <= 1;
                        ub_n_reg <= 0;
                        lb_n_reg <= 0;

	    				addr_reg <= pADDR[17:0];
                        if (inverse_pattern)
                            dq_reg <= `DATA_PATTERN_1;
                        else
                            dq_reg <= `DATA_PATTERN_0;

                        NSTAT <= DATA_IN_1;
                    end

                DATA_IN_1: // WR_WAIT
                    begin
                        if(cnt_wait<`MRAM_LATENCY)
                            begin
                                cnt_wait <= cnt_wait + 1'b1;
                                NSTAT <= DATA_IN_1;
                            end
                        else
                            begin
                                cnt_wait <= 0;
                                NSTAT <= DATA_IN_2;
                            end
                    end

                DATA_IN_2: // WR_END
                    begin
                        //dbg
                        cnt_badbits <= dq_reg[15:0];

                        cnt_wait <= 0;

    					e_n_reg <= 0;
                        w_n_reg <= 1;
                        g_n_reg <= 0;
                        ub_n_reg <= 0;
                        lb_n_reg <= 0;

	    				//addr_reg <= data_host[39:24];
                        //data_reg <=data_reg;

                        //NSTAT <= DATA_IN_3;
								
								if(addr_reg[0]==0) addr_reg[0] <=1;
								else addr_reg[0] <=0;
								NSTAT <= DATA_IN_0; //force power-test -write
                    end

                DATA_IN_3:
                    begin
                        if(cnt_wait<5)
                            begin
                                cnt_wait <= cnt_wait + 1'b1;
                                NSTAT <= DATA_IN_3;
                            end
                        else
                            begin
                                cnt_wait <= 0;
                                NSTAT <= END_0;
                            end
                    end

            // FSM: READ ==========================================
                DATA_OUT_0:
                    begin // RD_START
                        DQ_input_en <= 1;
                        cnt_badbits <= 0;

    					e_n_reg <= 0;
                        w_n_reg <= 1;
                        g_n_reg <= 0;
                        ub_n_reg <= 0;
                        lb_n_reg <= 0;

                        if (inverse_pattern)
                            dq_comp <= `DATA_PATTERN_1;
                        else
                            dq_comp <= `DATA_PATTERN_0;

  	    				addr_reg <= pADDR[15:0];
                        //data_reg <= data_host[23:8];

                        NSTAT <= DATA_OUT_1;
                    end

                DATA_OUT_1: // RD_WAIT
                    begin
                        if(cnt_wait<`MRAM_LATENCY)
                            begin
                                cnt_wait <= cnt_wait + 1'b1;
                                NSTAT <= DATA_OUT_1;
                            end
                        else
                            begin
                                NSTAT <= DATA_OUT_2;
                                cnt_wait <= 0;
                            end
                    end

                DATA_OUT_2: // RD_END
                    begin

    					e_n_reg <= 0;
                        w_n_reg <= 1;
                        g_n_reg <= 0;
                        ub_n_reg <= 0;
                        lb_n_reg <= 0;

	    				//addr_reg <= data_host[39:24];
                        //data_reg <= data_host[23:8];
                        //NSTAT <= DATA_OUT_3;
								
								if(addr_reg[0]==0) addr_reg[0] <=1;
								else addr_reg[0] <=0;
								NSTAT <= DATA_OUT_0; //force - power - test
                    end

                DATA_OUT_3: //RD_VERIFY
                    begin
                        if(cnt_wait<5)
                            begin
                                cnt_wait <= cnt_wait + 1'b1;
                                NSTAT <= DATA_OUT_3;
                            end
                        else
                            begin
                                cnt_wait <= 0;
                                NSTAT <= DATA_OUT_4;
                            end
                    end
                DATA_OUT_4:
                    begin
                        //dbg
                        cnt_latency <= { dq_comp[15:0], dq[15:0] };
                        
                        cnt_badbits <= ( dq[15] ^ dq_comp[15] ) + ( dq[14] ^ dq_comp[14] ) +
                                       ( dq[13] ^ dq_comp[13] ) + ( dq[12] ^ dq_comp[12] ) +
                                       ( dq[11] ^ dq_comp[11] ) + ( dq[10] ^ dq_comp[10] ) +
                                       ( dq[ 9] ^ dq_comp[ 9] ) + ( dq[ 8] ^ dq_comp[ 8] ) +
                                       ( dq[ 7] ^ dq_comp[ 7] ) + ( dq[ 6] ^ dq_comp[ 6] ) +
                                       ( dq[ 5] ^ dq_comp[ 5] ) + ( dq[ 4] ^ dq_comp[ 4] ) +
                                       ( dq[ 3] ^ dq_comp[ 3] ) + ( dq[ 2] ^ dq_comp[ 2] ) +
                                       ( dq[ 1] ^ dq_comp[ 1] ) + ( dq[ 0] ^ dq_comp[ 0] );
                        
                        NSTAT <= DATA_OUT_5;
                    end
                DATA_OUT_5:
                    begin
                        NSTAT <= END_0;
                    end
            // FSM: RW_END ==========================================
                END_0:
                    begin
                        DQ_input_en <= 0;

			            e_n_reg <= 1;
                        w_n_reg <= 1;
                        g_n_reg <= 1;
                        ub_n_reg <= 1;
                        lb_n_reg <= 1;

            			//addr_reg <= addr_reg;
                        //data_reg <= data_reg;

                        NSTAT <= STOP;
                    end
                STOP:
                    begin
                        if( start==1 )
                            NSTAT <= STOP;
                        else
                            NSTAT <= INIT;
                    end
                default:
                    begin
                        NSTAT <= INIT;
                    end
            endcase
        end
    end


endmodule
