`timescale 1ns / 1ps

//ADDR[12+9bit] Seq: 00_0000~00_017F 00_0200~00_037F ... 15_5E00~15_5F7F [END]
`define MAX_PAGE_ADDR   9'h000 //9'h17F  MRAM == > no page

//MRAM : 0 ~ 0x20000
`define MIN_BLOCK_ADDR 18'h00400 //16 blocks
`define MAX_BLOCK_ADDR 18'h0040F //16 blocks

//Select Real or Sim
`define RB_SHARP_PORT RB_port // Real NAND
//`define RB_SHARP_PORT 1       // Simulation

//Select Oper Enable
`define OPER_ENABLE_WR 1'b0  //1) WRITE
`define OPER_ENABLE_RD 1'b1  //2) READ
`define OPER_ENABLE_ER 1'b0  //3) ERASE

//Select PageType Enable
`define PAGETYPE_ENABLE_LSB 1'b1  //1) LSB
`define PAGETYPE_ENABLE_CSB 1'b1  //2) CSB
`define PAGETYPE_ENABLE_MSB 1'b1  //3) MSB

//Full-Loop for PE cycle test(Min. = 0)
`define REPEAT_FULL_LOOP 32'hFFFF_FFFF //MAX = 32'hFFFF_FFFF = 32'd4_294_967_295
`define ENABLE_UART_OUTPUT 1'b0

module Top_MRAM(
    input clkm,
    input rst,
    input pause,

	//______________________________UART
	//input RsRx_port,
    output RsTx_port,

    //____________________MRAM
    output vdd,
    output e_n_port,
    output w_n_port,
    output g_n_port,
    output ub_n_port,
    output lb_n_port,
    output [17:0] addr_port,
    inout [7:0] dqu_port,
    inout [7:0] dql_port,

    //Debug Lights
    output [7:0] Led,
    output [7:0] seg,
    output [3:0] an
  );


// FSM states
    parameter
        INIT       = 00,
        LOOP_ADDR_0= 01, LOOP_ADDR_1= 02, LOOP_ADDR_2= 03, LOOP_ADDR_3= 04, LOOP_ADDR_4= 05,
        RS_0       = 06, RS_1       = 07, RS_2       = 08, //RS_3       = 09,
        WR_0       = 09, WR_1       = 10, //WR_2       = 12,
        RD_0       = 11, RD_1       = 12, //RD_2       = 15,
        ER_0       = 13, ER_1       = 14, //ER_2       = 18,
        UART_0     = 15, UART_1     = 16, UART_2     = 17, UART_3     = 18,
        INIT_FULL_LOOP = 19,
        LOOP_END   = 31;

    parameter
        oWR = 2'd0,
        oRD = 2'd1,
        oER = 2'd2,
        oRS = 2'd3;



//crazy debugging...
wire clk;
assign clk = (pause) ? 1'b0 : clkm;
reg [7:0] seg_reg;

//reg [3:0] an_reg;
assign seg[7:0] = seg_reg[7:0];
assign an[3:0] = 4'b1110;//an_reg[3:0];



always@(posedge clk)
begin
//    an_reg <= 4'b1110;

    case(State[4:0])
        //                   7654_3210
        5'h00: seg_reg <= 8'b0000_0011; // 00 0
        5'h01: seg_reg <= 8'b1001_1111; // 01 1
        5'h02: seg_reg <= 8'b0010_0101; // 02 2
        5'h03: seg_reg <= 8'b0000_1101; // 03 3
        5'h04: seg_reg <= 8'b1001_1001; // 04 4
        5'h05: seg_reg <= 8'b0100_1001; // 05 5
        5'h06: seg_reg <= 8'b0100_0001; // 06 6
        5'h07: seg_reg <= 8'b0001_1111; // 07 7
        5'h08: seg_reg <= 8'b0000_0001; // 08 8
        5'h09: seg_reg <= 8'b0000_1001; // 09 9
        5'h0A: seg_reg <= 8'b0001_0001; // 10 A
        5'h0B: seg_reg <= 8'b1100_0001; // 11 b
        5'h0C: seg_reg <= 8'b1110_0101; // 12 c
        5'h0D: seg_reg <= 8'b1000_0101; // 13 d
        5'h0E: seg_reg <= 8'b0110_0001; // 14 E
        5'h0F: seg_reg <= 8'b0111_0001; // 15 F

        5'h10: seg_reg <= 8'b0000_0010; // 16 0.
        5'h11: seg_reg <= 8'b1001_1110; // 17 1.
        5'h12: seg_reg <= 8'b0010_0100; // 18 2.
        5'h13: seg_reg <= 8'b0000_1100; // 19 3.
        5'h14: seg_reg <= 8'b1001_1000; // 20 4.
        5'h15: seg_reg <= 8'b0100_1000; // 21 5.
        5'h16: seg_reg <= 8'b0100_0000; // 22 6.
        5'h17: seg_reg <= 8'b0001_1110; // 23 7.
        5'h18: seg_reg <= 8'b0000_0000; // 24 8.
        5'h19: seg_reg <= 8'b0000_1000; // 25 9.
        5'h1A: seg_reg <= 8'b0001_0000; // 26 A.
        5'h1B: seg_reg <= 8'b1100_0000; // 27 B.
        5'h1C: seg_reg <= 8'b1110_0100; // 28 c.
        5'h1D: seg_reg <= 8'b1000_0100; // 29 d.
        5'h1E: seg_reg <= 8'b0110_0000; // 30 E.
        5'h1F: seg_reg <= 8'b0111_0000; // 31 F.
/*
        6'd20: seg_reg <= 8'b0100_0011; // 32 G
        6'd21: seg_reg <= 8'b1101_0001; // 33 h
        6'd22: seg_reg <= 8'b1101_1111; // 34 i
        6'd23: seg_reg <= 8'b1000_1111; // 35 J
        6'd24: seg_reg <= 8'b1001_0001; // 36 K (H)
        6'd25: seg_reg <= 8'b1110_0011; // 37 L
        6'd26: seg_reg <= 8'b0101_0101; // 38 m (~n)
        6'd27: seg_reg <= 8'b1101_0101; // 39 n
        6'd28: seg_reg <= 8'b1100_0101; // 40 o
        6'd29: seg_reg <= 8'b0011_0001; // 41 P
        6'd2A: seg_reg <= 8'b0001_1001; // 42 q
        6'd2B: seg_reg <= 8'b1111_0101; // 43 r
        6'd2C: seg_reg <= 8'b0100_1001; // 44 S
        6'd2D: seg_reg <= 8'b0001_1111; // 45 T ('|)
        6'd2E: seg_reg <= 8'b1000_0011; // 46 U
        6'd2F: seg_reg <= 8'b1100_0111; // 47 v (u)
        6'd30: seg_reg <= 8'b0100_0111; // 48 w (~u)
        6'd31: seg_reg <= 8'b1100_1101; // 49 x (=|)
        6'd32: seg_reg <= 8'b1001_1001; // 50 y
        6'd33: seg_reg <= 8'b1110_1101; // 51 z (=)

        6'd34: seg_reg <= 8'b0100_0010; // 52 G
        6'd35: seg_reg <= 8'b1101_0000; // 53 h
        6'd36: seg_reg <= 8'b1101_1110; // 54 i
        6'd37: seg_reg <= 8'b1000_1110; // 55 J
        6'd38: seg_reg <= 8'b1001_0000; // 56 K (H)
        6'd39: seg_reg <= 8'b1110_0010; // 57 L
        6'd3A: seg_reg <= 8'b0101_0100; // 58 m (~n)
        6'd3B: seg_reg <= 8'b1101_0100; // 59 n
        6'd3C: seg_reg <= 8'b1100_0100; // 60 o
        6'd3D: seg_reg <= 8'b0011_0000; // 61 P
        6'd3E: seg_reg <= 8'b0001_1000; // 62 q
        6'd3F: seg_reg <= 8'b1111_0100; // 63 r
        6'd40: seg_reg <= 8'b0100_1000; // 64 S
        6'd41: seg_reg <= 8'b0001_1110; // 65 T ('|)
        6'd42: seg_reg <= 8'b1000_0010; // 66 U
        6'd43: seg_reg <= 8'b1100_0110; // 67 v (u)
        6'd44: seg_reg <= 8'b0100_0110; // 68 w (~u)
        6'd45: seg_reg <= 8'b1100_1100; // 69 x (=|)
        6'd46: seg_reg <= 8'b1001_1000; // 70 y
        6'd47: seg_reg <= 8'b1110_1100; // 71 z (=)
*/
      default: seg_reg <= 8'b1111_1111;
    endcase
end


//addr reg
//reg addr_page_rst, addr_page_inc;
reg [8:0] addr_page;   // MRAM not use
//reg addr_block_rst, addr_block_inc;
reg [17:0] addr_block; // MRAM addr block

reg [31:0] cnt_full_loop;
parameter tLSB = 0, tCSB = 1, tMSB = 2;
reg [2:0] addr_type; // addr_type[2:0] 00x = LSB, 01x = CSB, 10x = MSB, 11x = RSVD
//start/stopper
reg  start_sig;
wire done_sig;
//Oper
reg [1:0] Oper;    //Oper reg
reg [4:0] State;


//Latency
wire [31:0] latency;
wire [31:0] latency_wire; //latency_field of UART TX
wire [15:0] badbits;
wire [15:0] badbits_wire;

assign badbits_wire = (Oper==oRS) ? 16'h00 : badbits;
//assign latency_wire = (Oper==oRS) ? cnt_full_loop : latency; //NAND
assign latency_wire[31:0] = (Oper==oWR) ? cnt_full_loop[31:0] : latency[31:0];  //MRAM : WR = counter, RD = verify data;

assign inverse_pattern = cnt_full_loop[0];

// Uart
wire RsTx_wire;
assign RsTx_port = RsTx_wire;
reg       tx_send_sig;
//reg tx_idx_rst, tx_idx_inc;
reg [3:0] tx_idx;
//reg [7:0] tx_data;

wire [7:0] tx_data;
assign tx_data[7:0]=(           (tx_idx ==  0) ? { 6'h0, Oper[1:0] } :                  //Oper
                     (          (tx_idx ==  1) ? { 8'h0 } :                             //ADDR[3]
                      (         (tx_idx ==  2) ? { 6'h0, addr_block[17:16]} :           //ADDR[2]
                       (        (tx_idx ==  3) ? { addr_block[15:8] } :                 //ADDR[1]
                        (       (tx_idx ==  4) ? { addr_block[7:0] } :                  //ADDR[0]
                         (      (tx_idx ==  5) ? { latency_wire[31:24] } :
                          (     (tx_idx ==  6) ? { latency_wire[23:16] } :
                           (    (tx_idx ==  7) ? { latency_wire[15: 8] } :
                            (   (tx_idx ==  8) ? { latency_wire[ 7: 0] } :
                             (  (tx_idx ==  9) ? { badbits_wire[15: 8] } :
                              ( (tx_idx == 10) ? { badbits_wire[ 7: 0] } :
                                                 { 8'hEE }
                              )
                             )
                            )
                           )
                          )
                         )
                        )
                       )
                      )
                     )
                    );


uart_tx uart_tx(
    .clk(clkm),
    .rst(rst),
    .send(tx_send_sig),
    .data_tx(tx_data),

    .done(tx_done),
    .txd(RsTx_wire)
);

//MRAM
MRAM_RW MRAM_RW(
    .CLKM(clk),
    .RST(rst),
    .pOPER(Oper),
    .pADDR(addr_block),
    .inverse_pattern(inverse_pattern),
    .start(start_sig),
    .done_wire(done_sig),

    .latency(latency),
    .badbits(badbits),
    .Led(Led),

    //MRAM wires
	.e_n(e_n_port),
	.w_n(w_n_port),
	.g_n(g_n_port),
	.ub_n(ub_n_port),
	.lb_n(lb_n_port),
	.addr(addr_port),
	.dq( {dqu_port[7:0], dql_port[7:0]} )
);







always@(posedge clk)
    begin
    if (rst==1)
        begin
            State <= INIT;
        end
    else
        begin
            case(State)
                INIT:
                    begin
                        start_sig  <= 0;
                        addr_page  <= 0;
                        addr_block <= `MIN_BLOCK_ADDR;
                        tx_idx     <= 0;
                        tx_send_sig<= 0;
                        addr_type  <= 0; //set start as MSB
                        cnt_full_loop <= 0;

                        Oper <= oRS;

                        State <= LOOP_ADDR_0;
                    end

                INIT_FULL_LOOP:
                    begin
                        start_sig  <= 0;
                        addr_page  <= 0;
                        addr_block <= `MIN_BLOCK_ADDR;
                        tx_idx     <= 0;
                        tx_send_sig<= 0;
                        addr_type  <= 0; //set start as MSB
                        cnt_full_loop <= cnt_full_loop + 1'b1;

                        Oper <= oWR;

                        State <= LOOP_ADDR_0;
                    end

        // FSM: LOOP - BEFORE ==========================================
                LOOP_ADDR_0: //outer loop
                    begin
                        //set addr_type of current addr_page (LCMsb)
                        if( (addr_page <= 5) || (addr_page == 8) || ( addr_type == 5 ) )
                            addr_type <= 0;         // addr_type = 00_0;
                        else if( addr_page <= 7 )
                            addr_type <= 2;         // addr_type = 01_0;
                        else
                            addr_type <= addr_type + 1'b1;
                        State  <= LOOP_ADDR_1;
                    end

                LOOP_ADDR_1:
                    begin
                        if (Oper[1:0] == oRS) //RESET --> mandatory!
                            begin
                                State <= RS_0;
                            end
                        else if (Oper[1:0] == oER) //ERASE --> should not care for LCMsb!
                            begin
                                State <= ER_0;
                            end
                        else if(addr_type[2:1] == tLSB && `PAGETYPE_ENABLE_LSB==0) //Check LCMsb filtering and skip
                            begin
                                State <= LOOP_ADDR_2;
                            end
                        else if(addr_type[2:1] == tCSB && `PAGETYPE_ENABLE_CSB==0)
                            begin
                                State <= LOOP_ADDR_2;
                            end
                        else if(addr_type[2:1] == tMSB && `PAGETYPE_ENABLE_MSB==0)
                            begin
                                State <= LOOP_ADDR_2;
                            end
                        else if (Oper[1:0] == oRD)
                            begin
                                State <= RD_0;
                            end
                        else //if (Oper[1:0] == oWR)
                            begin
                                State <= WR_0;
                            end
                    end

        // FSM: RESET & SET-FEAT MODE 5 ==========================================
                RS_0:
                    begin
                        start_sig <= 1;   // NAND reset
                        State <= RS_1;
                    end
                RS_1:
                    begin
                        if (done_sig == 1) // NAND done check
                            begin
                                State <= UART_0;
                            end
                        else State <= RS_1;
                    end
        // FSM: Page WRITE ==========================================
                WR_0:
                    begin
                        if(`OPER_ENABLE_WR)
                            begin
                                start_sig <= 1;
                                State <= WR_1;
                            end
                        else  //if SKIP!
                            begin
                                State <= LOOP_ADDR_2;
                            end
                    end
                WR_1:
                    begin
                        if (done_sig == 1)
                            begin
                                State <= UART_0;
                            end
                        else State <= WR_1;
                    end

        // FSM: Page READ ==========================================
                RD_0:
                    begin
                        if(`OPER_ENABLE_RD)
                            begin
                                start_sig <= 1;
                                State <= RD_1;
                            end
                        else  //if SKIP!
                            begin
                                State <= LOOP_ADDR_2;
                            end
                    end
                RD_1:
                    begin
                        if (done_sig == 1)
                            begin
                                State <= UART_0;
                            end
                        else State <= RD_1;
                    end

        // FSM: Block ERASE ==========================================
                ER_0: // set next Oper
                    begin
                        if(`OPER_ENABLE_ER)
                            begin
                                start_sig <= 1;
                                State <= ER_1;
                            end
                        else  //if SKIP!
                            begin
                                State <= LOOP_ADDR_2;
                            end
                    end
                ER_1:
                    begin
                        if (done_sig == 1)
                            begin
                                State <= UART_0;
                            end
                        else State <= ER_1;
                    end

        // FSM: SEND_SERIAL ==========================================
                UART_0:
                    begin
                        //if(cnt_full_loop[13:0]==14'h3FFF || cnt_full_loop[13:0]==14'h3FFE)  //MRAM: print bit error count on every 1024 loops
								if(`ENABLE_UART_OUTPUT)  //MRAM: print bit error count on every 1024 loops
                            State <= UART_1;
                        else
                            State <= LOOP_ADDR_2;
                    end

                UART_1:
                    begin
                        tx_send_sig <= 1;
                        State <= UART_2;
                    end
                UART_2:
                    begin
                        if(tx_done == 1)
                            begin
                                tx_send_sig <= 0;
                                State <= UART_3;
                            end
                        else
                            begin
                                State <= UART_1;
                            end
                    end
                UART_3:
                    begin
                        if( tx_idx[3:0] == 4'd12-1 )
                            begin
                                tx_idx     <= 0;
                                State <= LOOP_ADDR_2;
                            end
                        else
                            begin
                                tx_idx <= tx_idx + 1'b1;
                                State <= UART_0;
                            end
                    end


        // FSM: LOOP - AFTER ==========================================
                LOOP_ADDR_2: //increase page address
                    begin
                        start_sig <= 0;
                        //page 9bit 000~17F
                        if( addr_page[8:0] == `MAX_PAGE_ADDR )  // if finished sweep addr_page
                            begin
                                State <= LOOP_ADDR_3;
                            end
                        else                      // if more to go
                                if (Oper[1] == 1) // oER_10, oRS_11 : but, if Erase/Reset --> only once! ... block
                                    begin
                                        State <= LOOP_ADDR_3;
                                    end
                                else
                                    begin // loop ... page
                                        addr_page <= addr_page + 1'b1;
                                        State <= LOOP_ADDR_0;
                                    end
                    end

                LOOP_ADDR_3: //change Oper
                    begin
                        addr_page  <= 0;
                        if (Oper == oER) //oER_10
                            begin
                                Oper  <= oWR;
                                State <= LOOP_ADDR_4;
                            end
                        else                   // oWR, oRD, oRS
                            begin
                                Oper  <= Oper + 1'b1;
                                State <= LOOP_ADDR_0;
                            end
                        /*
                        if (Oper[1:0] == oWR)
                            begin
                                Oper[1:0] <= oRD;
                                State <= LOOP_ADDR_0;
                            end
                        else if (Oper[1:0] == oRD)
                            begin
                                Oper[1:0] <= oER;
                                State <= LOOP_ADDR_0;
                            end
                        else //if (Oper[1:0] == oER)
                            begin
                                Oper[1:0] <= oWR;
                                State <= LOOP_ADDR_4;
                            end
                        */
                    end

                LOOP_ADDR_4: //increase block addr
                    begin
                        //block 12bit 000~AAF
                        if( addr_block[17:0] == `MAX_BLOCK_ADDR ) // if finished sweep addr_block
                            begin
                                State <= LOOP_END;
                            end
                        else                      // if more to go
                            begin
                                addr_block <= addr_block + 1'b1;
                                State <= LOOP_ADDR_0;
                            end
                    end


                LOOP_END:
                    begin
                        start_sig  <= 0;
                        addr_block <= 12'hFFF; //this is for preventing warning of ISE.
                        if (cnt_full_loop == `REPEAT_FULL_LOOP-1)
                            begin
                                State <= LOOP_END;
                            end
                        else
                            begin
                                State <= INIT_FULL_LOOP;
                            end
                    end

                default:
                    begin
                        State <= INIT;
                    end
            endcase
        end
    end

endmodule

