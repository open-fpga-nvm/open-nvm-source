`timescale 1ns/1ns

//Select Real or Sim
//`define PAGE_SIZE 14'd8192    //Real NAND
`define PAGE_SIZE 14'd9168    //Real NAND ... Full Page
//`define PAGE_SIZE 4       //Simluation

//`define PATTERN_WOM 8'h01
`define PATTERN_WOM cnt_data[7:0]

module NAND_RWE(
    input CLKM,
    input RST,

    input [1:0]  pOPER,
    input [39:0] pADDR,
    input  inverse_pattern,
    input  start,
    output done_wire,
    output [31:0] latency,
    output [31:0] badbits,
    output [7:0] Led,

    input pattern_usr_0, // 0=addr, 1=usr
    input [7:0] pattern_0,
    input pattern_usr_1, // 0=addr, 1=usr
    input [7:0] pattern_1,

// NAND Wires
    output CE_wire,       // Chip Enable
    output RE_wire,       // Rd Enable
    output WE_wire,       // Wr Enable
    output CLE_wire,      // Cmd Latch Enable
    output ALE_wire,      // Adr Latch Enable
    output WP_wire,       // Wr Protect
    input  RB_wire,       // Ready/Busy        : 0=BUSY, 1=READY
    inout  [7:0] DQ_wire  // Data
);

wire CLK;
assign CLK = (pOPER[1:0]==oRS[1:0]) ? CLKx5: CLKM;
wire CLKx5;
assign CLKx5 = (cnt_reset<3 ? 1'b1: 1'b0);

always@(posedge CLKM)
    begin
        if(RST)
            cnt_reset    <= 0;
        else if ( cnt_reset < 4 )
            cnt_reset    <= cnt_reset + 1'b1;
        else
            cnt_reset    <= 0;
    end

// FSM
parameter
    INIT       = 30, INIT_T     = 31, STOP       = 00,
    CMDA_0     = 01, CMDA_1     = 02, CMDA_2     = 03,
    ADDR_0     = 04, ADDR_1     = 05, ADDR_2     = 06, ADDR_3     = 07,
    CMDB_0     = 08, CMDB_1     = 09, CMDB_2     = 10,
    WAIT_CYL   = 11,
    WAIT_RB_0  = 12, WAIT_RB_1  = 13,
    DATA_IN_0  = 14, DATA_IN_1  = 15, DATA_IN_2  = 16, DATA_IN_3  = 17, DATA_IN_4  = 18,  //WRITE
    DATA_OUT_0 = 19, DATA_OUT_1 = 20, DATA_OUT_2 = 21, DATA_OUT_3 = 22, DATA_OUT_4 = 23, DATA_OUT_5 = 24,  //READ
    RESET_0    = 25, RESET_1    = 26, RESET_2    = 27, RESET_3    = 28, RESET_4    = 29;
parameter
    oWR = 0,
    oRD = 1,
    oER = 2,
    oRS = 3;


// Internal Variables
    reg [ 2:0] cnt_addr;
    reg [ 3:0] cnt_wait;
    reg [31:0] cnt_latency;
    reg [13:0] cnt_data; //8192=13bit, 9168=14bit
    reg [ 2:0] cnt_reset;
    reg [31:0] cnt_badbits;

    reg  [4:0] NSTAT;

    wire [13:0] inv_cnt_data;
    assign inv_cnt_data = ~cnt_data;

// Address Mux
// 4 4 3 3 2 2 1 1 0 0
// 4[39:32] 3[31:24] 2[23:16] 1[15:8] 0[7:0]
    wire [7:0] vADDR;
    assign vADDR[7:0]= (pOPER==oRS)?8'h01:(   (cnt_addr == 0) ? pADDR[39:32] :
                                           (  (cnt_addr == 1) ? pADDR[31:24] :
                                            ( (cnt_addr == 2) ? pADDR[23:16] :
                                             ((cnt_addr == 3) ? pADDR[15: 8] :
                                                                pADDR[ 7: 0]
                                             )
                                            )
                                           )
                                          );

// NAND Reg & Wires
//    reg CE;       // Chip Enable
    reg RE;       // Rd Enable
    reg WE;       // Wr Enable
    reg CLE;      // Cmd Latch Enable
    reg ALE;      // Adr Latch Enable
//    reg WP;       // Wr Protect
    wire RB;       // Ready/Busy        : 0=BUSY, 1=READY
    reg [7:0] DQ, DQ_comp; // Data
    reg DQ_input_en;
    reg RdSt_en;   //Status Register Read
    assign CE_wire  = 0;//CE;
    assign RE_wire  = RE;
    assign WE_wire  = WE;
    assign CLE_wire = CLE;
    assign ALE_wire = ALE;
    assign WP_wire  = 1;//WP;
    assign RB = RB_wire;
//    assign DQ_wire[7:0]  = (ALE)? vADDR[7:0] : DQ[7:0];
    assign DQ_wire[7:0]  = (DQ_input_en)? 8'bzzzzzzzz: DQ[7:0];

    assign latency[31:0] = cnt_latency[31:0];
    assign badbits[31:0] = cnt_badbits[31:0];

//debug led
    assign Led[7:0] = {start,done_wire,CLK,NSTAT[4:0]};


assign done_wire = (NSTAT == STOP) ? 1'b1 : 1'b0;

// ASSUME CE = 0 (enabled) already
always@(posedge CLK)
    begin
    if(RST)
        begin
            //CE           <= 0;
            NSTAT <= INIT;
        end
    else
        begin
            case (NSTAT)
                INIT_T:
                    begin
                        NSTAT <= INIT;
                    end
                INIT:
                    begin
                        //CE           <= 0;

                        cnt_addr     <= 0;
                        cnt_wait     <= 0;
                        cnt_latency  <= 0;
                        cnt_data     <= 0;
                        cnt_badbits  <= 0;

                        DQ_input_en  <= 0;
                        RdSt_en      <= 0;

                        if( start == 0 )
                            NSTAT <= INIT_T;
                        else if( start == 1 )
                            NSTAT <= CMDA_0;
                        else
                            NSTAT <= INIT_T;
                    end

        // FSM: RESET =======================================================
        //      SEQ: CMDA(FF), RESET_0(tWB+tRST), CMDB(EF), ADDR(01), RESET_1(SET Mode DATA)
                RESET_0: // Sent CMD FF, after that...
                    begin
                        // NEXT STATE
                        if( cnt_data < 110-1) // wait tWB+tRST = 5200ns
                            begin
                                cnt_data <= cnt_data + 1'b1;
                                NSTAT <= RESET_0;
                            end
                        else if( RB == 1 )
                            begin
                                cnt_data <= 0;
                                NSTAT <= CMDB_0; // Send CMD EF¨
                            end
                        else
                            begin
                                cnt_data <= 0;
                                NSTAT <= RESET_0; //wait tRST
                            end
                    end

                RESET_1:  //SET_SET-FEAT : DATA x 4
                    begin
                        // ACTION
                        WE  <= 0;
                        ALE <= 0;
                        CLE <= 0;
                        RE  <= 1;

                        cnt_data <= 0;    // Reset Data Counter

                        // NEXT STATE
                        NSTAT <= RESET_2;
                    end
                RESET_2:
                    begin
                        WE <= 0;
                        DQ <= ( (cnt_data==0) ? 8'h05 : 8'h00 ); //Set MODE 5
                        NSTAT <= RESET_3;
                    end
                RESET_3:
                    begin
                        WE <= 1; //Rising Edge of WE
                        if (cnt_data < 4-1)
                            begin
                                cnt_data <= cnt_data + 1'b1;
                                NSTAT <= RESET_2;
                            end
                        else
                            begin
                                cnt_data <= 0;     //Stop Data Counter
                                NSTAT <= RESET_4;
                            end
                    end
                RESET_4:
                    begin
                        //WE  <= 0;
                        //NSTAT <= WAIT_RB_0;// Do NOT wait RB, instead¸more than 1200ns would be precise !
                        if (cnt_data < 25-1)
                            begin
                                cnt_data <= cnt_data + 1'b1;
                                NSTAT <=RESET_4;
                            end
                        else
                            begin
                                cnt_data <= 0;
                                NSTAT <=STOP;
                            end
                    end


        // FSM: CMDA =======================================================
                CMDA_0:
                    begin
                        // ACTION
                        WE  <= 0;
                        ALE <= 0;
                        CLE <= 1; // Command Latch Open
                        RE  <= 1;
                        if(RdSt_en)           DQ <= 8'h70; //Read Status
                        else if(pOPER == oRD) DQ <= 8'h00;
                        else if(pOPER == oWR) DQ <= 8'h80;
                        else if(pOPER == oER) DQ <= 8'h60;
                        else DQ <=8'hFF; // RESET CMD
                        // NEXT STATE
                        if(RB)
                            NSTAT <= CMDA_1;
                        else
                            NSTAT <= CMDA_0;
                    end

                CMDA_1:
                    begin
                        // ACTION
                        WE   <= 1;   //Rising edge of WE
                        // NEXT STATE
                        NSTAT <= CMDA_2;
                    end

                CMDA_2:
                    begin
                        // ACTION
                        //WE  <= 0;
                        CLE <= 0; // Command Latch Close
                        // NEXT STATE
                        if(RdSt_en)
                            NSTAT <= WAIT_CYL;
                        else if(pOPER != oRS)
                            NSTAT <= ADDR_0;
                        else
                            NSTAT <= RESET_0;
                    end

        // FSM: ADDR =======================================================
                ADDR_0:
                    begin
                        // ACTION
                        WE  <= 0;
                        ALE <= 1; //Address Latch Open
                        CLE <= 0;
                        RE  <= 1;
                        // DQ  <= vADDR;
                        //WP  <= 1; // LOW = WrPrct

                        // Counter Config
                        cnt_wait <= 0;
                        if (pOPER == oER)
                            cnt_addr <= 2;
                        else
                            cnt_addr <= 0;

                        // NEXT STATE
                        NSTAT <= ADDR_1;
                    end

                //cnt_addr trick:
                ADDR_1:
                    begin
                        WE  <= 0;
                        DQ  <= vADDR;
                        NSTAT <= ADDR_2;
                    end
                ADDR_2:
                    begin
                        WE  <= 1; //Rising edge of WE
                        if (pOPER == oRS) // SET-FEAT : only 1 address
                            begin
                                NSTAT <= ADDR_3;
                            end
                        else //if pOPER == oWR or oRD or oER
                            begin
                                if(cnt_addr < 5-1) // ... ( 00 01 ) 02 03 04
                                    begin
                                        cnt_addr <= cnt_addr + 1'b1;
                                        NSTAT <= ADDR_1;
                                    end
                                else
                                    begin
                                        NSTAT <= ADDR_3;
                                    end
                            end
                    end
                ADDR_3:
                    begin
                        //WE  <= 0;
                        ALE <= 0; //Address Latch Close
                        
                        if(pOPER == oRD) NSTAT <= CMDB_0;
                        else if (pOPER == oER) NSTAT <= CMDB_0;
                        else NSTAT <= WAIT_CYL; //oWR and oRS(SET-FEAT)
                    end

        // FSM: CMDB =======================================================
                CMDB_0:
                    begin
                        // ACTION
                        WE  <= 0;
                        ALE <= 0;
                        CLE <= 1; // Command Latch Open
                        RE  <= 1;

                        //cnt_latency <= 0; //Reset Latency Counter

                        if(pOPER == oRD) DQ <= 8'h30;
                        else if (pOPER == oWR) DQ <= 8'h10;
                        else if (pOPER == oER) DQ <= 8'hD0;
                        else DQ <= 8'hEF; // SET-FEATURE
                        // NEXT STATE
                        NSTAT <= CMDB_1;
                    end
                CMDB_1:
                    begin
                        // ACTION
                        WE   <= 1;   //Rising edge of WE

                        //cnt_latency  <= cnt_latency+1;

                        // NEXT STATE
                        NSTAT <= CMDB_2;
                    end
                CMDB_2:
                    begin
                        // ACTION
                        //WE  <= 1;
                        CLE <= 0; // Command Latch Close
                        // NEXT STATE
                        if (pOPER != oRS)
                            NSTAT <= WAIT_RB_0;
                        else
                            NSTAT <= ADDR_0; // SET-FEAT ADDRESS
                        //if (pOPER == oRD) NSTAT <= WAIT_RB_0;
                        //else if (pOPER == oWR) NSTAT <= WAIT_RB_0;
                        //else if (pOPER == oER) NSTAT <= WAIT_RB_0;
                    end

        // FSM: WAIT_CYL =======================================================
                WAIT_CYL: // only for oWR, tADL / oRS(SET-FEAT), tADL / RdSt_en, tWHR
                    begin
                        if (cnt_wait < 4'd10-1)
                            begin
                                cnt_wait  <= cnt_wait + 1'b1;
                                NSTAT <= WAIT_CYL;
                            end
                        else if(RdSt_en)       //Rd Status
                            begin
                                cnt_wait <= 0;
                                NSTAT <= DATA_OUT_0;
                            end
                        else if(pOPER == oWR)  //oWR
                            begin
                                cnt_wait <= 0;
                                NSTAT <= DATA_IN_0;
                            end
                        else // RESET - SET-FEAT
                            begin
                                cnt_wait <= 0;
                                NSTAT <= RESET_1;
                            end
                    end

        // FSM: WAIT_RDY =======================================================
                WAIT_RB_0:
                    begin
                        //NEXT STATE
                        if (RB == 0) //while BUSY
                            begin
                                cnt_latency <= cnt_latency + 1'b1;
                                NSTAT <= WAIT_RB_1;
                            end
                        else if ( cnt_latency[31:0] < 32'd10 ) //wait RB, but consider tWB (100ns)
                            begin
                                cnt_latency <= cnt_latency + 1'b1;
                                NSTAT <= WAIT_RB_0;
                            end
                        else
                            begin
                                NSTAT <= WAIT_RB_1;
                            end
                    end

                WAIT_RB_1:
                    begin
                        //NEXT STATE
                        if (RB == 0) //while BUSY
                            begin
                                cnt_latency <= cnt_latency + 1'b1;
                                NSTAT <= WAIT_RB_1;
                            end
                        else
                            begin
                                //cnt_latency <= 0; //Stop Latency counter
                                if (pOPER == oWR || pOPER == oER)
                                    begin
                                        RdSt_en  <= 1;
                                        NSTAT <= CMDA_0; //Read Status
                                    end
                                else if (pOPER == oRD)
                                    begin
                                        cnt_wait <= 0;
                                        NSTAT <= DATA_OUT_0;
                                    end
                                else
                                    begin
                                        NSTAT <= STOP;
                                    end
                            end
                    end

        // ToDo: ERROR check on status bit !!!!!

        // FSM: DATA_IN =======================================================
                //WRITE (think you're NAND) : only for oWR, Use WE(Write Enable)
                DATA_IN_0:
                    begin
                        // ACTION
                        WE  <= 0;
                        ALE <= 0;
                        CLE <= 0;
                        RE  <= 1;
                        DQ_input_en <= 0;

                        cnt_data <= 0;    // Reset Data Counter

                        // NEXT STATE
                        NSTAT <= DATA_IN_1;
                    end
                DATA_IN_1:
                    begin
                        WE <= 0;

                        if (      inverse_pattern==0 && pattern_usr_0==0 ) //norm address
                            DQ <= cnt_data[7:0];
                        else if ( inverse_pattern==1 && pattern_usr_1==0 ) //inv  address
                            DQ <= inv_cnt_data[7:0];
                        else if ( inverse_pattern==0 && pattern_usr_0==1 ) //norm =ptrn_0
                            DQ <= pattern_0;
                        else//if( inverse_pattern==1 && pattern_usr_1==1 ) //inv =ptrn_1
                            DQ <= pattern_1;

                        /*
                        if(inverse_pattern)
                            DQ <= inv_cnt_data[7:0]; //use addr as data
                        else
                            DQ <= cnt_data[7:0];
                        */
                        
                        // DQ <= `PATTERN_WOM; //WOM-CODE Test Baseline
                        //DQ <= cnt_data[7:0];

                        NSTAT <= DATA_IN_2;
                    end
                DATA_IN_2:
                    begin
                        WE <= 1; //Rising Edge of WE
                        if (cnt_data < `PAGE_SIZE-1)
                            begin
                                cnt_data <= cnt_data + 1'b1;
                                NSTAT <= DATA_IN_3;
                            end
                        else
                            begin
                                cnt_data <= 0;     //Stop Data Counter
                                NSTAT <= DATA_IN_4;
                            end
                    end
                DATA_IN_3: //add one more clock for stability
                    begin
                        NSTAT <= DATA_IN_1;
                    end
                DATA_IN_4:
                    begin
                        //WE  <= 1;
                        NSTAT <= CMDB_0;
                    end

        // FSM: DATA_OUT =======================================================
                //READ (think you're NAND) : only for oRD, Use RE(Read Enable)
                DATA_OUT_0: // tRR wait
                    begin
                        if (cnt_wait < 4'd10-1)
                            begin
                                cnt_wait  <= cnt_wait + 1'b1;
                                NSTAT <= DATA_OUT_0;
                            end
                        else
                            begin
                                cnt_wait <= 0;
                                NSTAT <= DATA_OUT_1;
                            end
                    end
                DATA_OUT_1:
                    begin
                        // ACTION
                        cnt_wait <= 0;
                        RE  <= 1;
                        ALE <= 0;
                        CLE <= 0;
                        WE  <= 1;

                        cnt_data    <= 0;    // Reset Data Counter
                        cnt_badbits <= 0;
                        DQ          <= 0;
                        DQ_comp     <= 0;
                        DQ_input_en <= 1;

                        // NEXT STATE
                        NSTAT <= DATA_OUT_2;
                    end
                DATA_OUT_2:
                    begin
                        RE  <= 1;

/* //DEBUG
                        if( cnt_data == 14'h201 )
                            begin
                                cnt_badbits <= {DQ_comp[7:0], DQ_wire[7:0]};
                            end
*/


//COUNT BIT

                        if(RdSt_en && cnt_data==1) //when Rd Status register
                            begin
                                cnt_badbits[15:0] <= { 8'd0, DQ_wire[7:0] };
                            end
                        else if(cnt_data != 0) //when normal read
                            begin
                                cnt_badbits <= cnt_badbits + ( DQ_comp[7] ^ DQ_wire[7] ) + ( DQ_comp[6] ^ DQ_wire[6] )
                                                           + ( DQ_comp[5] ^ DQ_wire[5] ) + ( DQ_comp[4] ^ DQ_wire[4] )
                                                           + ( DQ_comp[3] ^ DQ_wire[3] ) + ( DQ_comp[2] ^ DQ_wire[2] )
                                                           + ( DQ_comp[1] ^ DQ_wire[1] ) + ( DQ_comp[0] ^ DQ_wire[0] );
                            end



                        if (cnt_data == `PAGE_SIZE)
                            begin
                                NSTAT <= DATA_OUT_5;
                            end
                        else if(RdSt_en && cnt_data==1)
                            begin
                                NSTAT <= DATA_OUT_5;
                            end
                        else
                            begin
                                NSTAT <= DATA_OUT_3;
                            end
                    end
                DATA_OUT_3:
                    begin
                        RE  <= 0; // falling edge of RE#


                        if (      inverse_pattern==0 && pattern_usr_0==0 ) //norm address
                            DQ_comp[7:0] <= cnt_data[7:0];
                        else if ( inverse_pattern==1 && pattern_usr_1==0 ) //inv  address
                            DQ_comp[7:0] <= inv_cnt_data[7:0];
                        else if ( inverse_pattern==0 && pattern_usr_0==1 ) //norm =ptrn_0
                            DQ_comp[7:0] <= pattern_0;
                        else//if( inverse_pattern==1 && pattern_usr_1==1 ) //inv =ptrn_1
                            DQ_comp[7:0] <= pattern_1;

                        //DQ_comp[7:0] <= `PATTERN_WOM; //Compare-data : WOM-CODE Test Baseline
                        //DQ_comp <= cnt_data[7:0]; //Compare-data

                        /*
                        if(inverse_pattern)
                            DQ_comp <= inv_cnt_data[7:0]; //Compare-data
                        else
                            DQ_comp <= cnt_data[7:0]; //Compare-data
                        */

                        cnt_data <= cnt_data + 1'b1;
                        NSTAT    <= DATA_OUT_4;
                        /*
                        if (cnt_data < `PAGE_SIZE-1)
                            begin
                                cnt_data <= cnt_data + 1'b1;
                                NSTAT <= DATA_OUT_4;
                            end
                        else
                            begin
                                cnt_data <= 0;
                                NSTAT <= DATA_OUT_5;
                            end
                        */
                    end
                DATA_OUT_4: //add more clocks for stable DQ sensing
                    begin
                        if (cnt_wait < 4'd6-1)
                            begin
                                cnt_wait  <= cnt_wait + 1'b1;
                                NSTAT <= DATA_OUT_4;
                            end
                        else
                            begin
                                cnt_wait <= 0;
                                NSTAT <= DATA_OUT_2;
                            end
                    end
                DATA_OUT_5:
                    begin
                        RE  <= 1;
                        DQ_input_en <= 0;
                        RdSt_en <= 0;
                        NSTAT <= STOP;
                    end

        //ToDo: Data Verification

        // FSM: STOP =======================================================
                STOP:
                    begin
                        if(start==1)
                            NSTAT <= STOP;
                        else if(start==0)
                            NSTAT <= INIT;
                        else
                            NSTAT <= STOP;
                    end
                default:
                    begin
                        NSTAT <= INIT_T;
                    end
            endcase
        end
    end

endmodule
