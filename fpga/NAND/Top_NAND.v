`timescale 1ns / 1ps

//ADDR[12+9bit] Seq: 00_0000~00_017F 00_0200~00_037F ... 15_5E00~15_5F7F [END]
`define MAX_PAGE_ADDR   9'h17F

//`define MIN_BLOCK_ADDR 12'h000 //all blocks
//`define MAX_BLOCK_ADDR 12'hAAF //all blocks
//`define MIN_BLOCK_ADDR 12'h000 //128 blocks --- power test
//`define MAX_BLOCK_ADDR 12'h07F //128 blocks
//`define MIN_BLOCK_ADDR 12'h089 //8 blocks --- endurance test #1 --- 089~08F
//`define MAX_BLOCK_ADDR 12'h08F //8 blocks
//`define MIN_BLOCK_ADDR 12'h0C8 //8 blocks --- endurance test #3 --- 090~088
//`define MAX_BLOCK_ADDR 12'h0CF //8 blocks
//`define MIN_BLOCK_ADDR 12'h1D0 //8 blocks --- WOM test - FF
//`define MAX_BLOCK_ADDR 12'h1D7 //8 blocks
//`define MIN_BLOCK_ADDR 12'h0F8 //8 blocks --- WOM test - 00
//`define MAX_BLOCK_ADDR 12'h0FF //8 blocks

//Select Real or Sim
`define RB_SHARP_PORT RB_port // Real NAND
//`define RB_SHARP_PORT 1       // Simulation

//Select Oper Enable
//`define OPER_ENABLE_WR 1'b0  //1) WRITE
//`define OPER_ENABLE_RD 1'b0  //2) READ
//`define OPER_ENABLE_ER 1'b1  //3) ERASE

//Select PageType Enable
//`define PAGETYPE_ENABLE_LSB 1'b1  //1) LSB
//`define PAGETYPE_ENABLE_CSB 1'b1  //2) CSB
//`define PAGETYPE_ENABLE_MSB 1'b1  //3) MSB

//Full-Loop for PE cycle test(Min. = 0)
//`define REPEAT_FULL_LOOP 1

module Top_NAND(
    input clkm,
    input rst,
    input pause,

    //NAND VHDCI
    output CE_port,       // Chip Enable
    output CE2_port,       // Chip Enable
    output RE_port,       // Rd Enable
    output WE_port,       // Wr Enable
    output CLE_port,      // Cmd Latch Enable
    output ALE_port,      // Adr Latch Enable
    output WP_port,       // Wr Protect
    input  RB_port,       // Ready/Busy        : 0=BUSY, 1=READY
    output /*input*/  RB2_port, // -- temporarily set as as output for 1 PLANE chip --
    inout  [7:0] DQ_port, // Data

    //UART
    output RsTx_port,
    input  RsRx_port,

    //Debug Lights
    output [7:0] Led,
    output [7:0] seg,
    output [3:0] an
);


    // FSM Global Variables
    reg [1:0] Oper;    //Oper reg
    reg [4:0] State;

// =========================================================================================
// ===================================== Debugging =========================================
// =========================================================================================
    wire clk;
    assign clk = (pause) ? 1'b0 : clkm;

    //reg [7:0] Led_reg;
    //assign Led[7:0] = addr_page[7:0];
    //assign Led[7:0] = {Oper[1:0],addr_page[8:3]};
    //assign Led[7:0] = {rst,done_sig,CurState[5:0]};


    /*
    reg [7:0] seg_reg;
    assign an[3:0] = 4'b1110;
    assign seg[7:0] = seg_reg[7:0];


    always@(posedge clk)
        begin  // Debug 7seg
            seg_reg[7:0] = { 1'b1, ~State[5:0], ~tx_send_sig };
        end
    */



    reg [7:0] seg_reg;
    reg [3:0] an_reg;
    assign seg[7:0] = seg_reg[7:0];
    assign an[3:0] = an_reg[3:0];

    reg [5:0] dbg_data;
    reg [7:0] cnt_seg;

    always@(posedge clkm)
        begin
            if (cnt_seg >= 200)
                begin
                    cnt_seg <= 0;
                    case(an_reg)
                        4'b1110:
                            begin
                                an_reg <= 4'b0111;

                                //Prepare next Digit _x__
                                dbg_data <= {(rx_idx == 00), rx_data[3:0]};
                            end
                        4'b0111:
                            begin
                                an_reg <= 4'b1011;

                                //Prepare next Digit __x_
                                dbg_data <= { START_MAIN_LOOP, rx_cnt[3:0] };
                            end
                        4'b1011:
                            begin
                                an_reg <= 4'b1101;

                                //Prepare next Digit ___x
                                dbg_data <={ 1'b0, State[4:0] };
                            end
                        4'b1101:
                            begin
                                an_reg <= 4'b1110;

                                //Prepare next Digit x___
                                dbg_data <= {(rx_idx == 08), rx_data[7:4]};
                            end
                        default:
                            an_reg <= 4'b1011;
                    endcase

                    case( dbg_data )
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
                      default:
                        begin
                            seg_reg <= 8'b1111_1111;
                        end
                    endcase
                end
            else if(cnt_seg < 200)
                begin
                    cnt_seg <= cnt_seg + 1'b1;
                end
            else
                begin
                    cnt_seg <= 0;
                end
        end


// =========================================================================================
// ======================================= UART Control ====================================
// =========================================================================================
    // UART Data Wire
    // Output Wire
    wire [31:0] latency;
    wire [31:0] badbits;

    wire [31:0] badbits_wire;

    assign badbits_wire = (Oper==oRS) ? cnt_full_loop : badbits;

    // UART Comm TX/RX Wire
    reg       tx_send_sig;
    reg [3:0] tx_idx;

    wire [7:0] tx_data;
    wire [7:0] rx_data;

    //SEND to PC
    uart_tx uart_tx(
        .clk(clkm),
        .rst(rst),
        .send(tx_send_sig),
        .data_tx(tx_data),

        .done(tx_done),
        .txd(RsTx_port)
    );

    //RECV from PC
    uart_rx uart_rx(
        .clk(clkm),
        .rst(rst),
    	.data_rx(rx_data),

    	.busy(rx_busy),
    	.rxd(RsRx_port)
    );


    reg [6:0] rx_idx;
    reg [3:0] rx_cnt;

    wire [ 7:0] rx_cmd_00, rx_cmd_01, rx_cmd_02, rx_cmd_03, rx_cmd_04, rx_cmd_05,
                rx_cmd_06, rx_cmd_07, rx_cmd_08, rx_cmd_09, rx_cmd_10;            //11 would not be stored

    reg  [95:0] rx_cmd;
    assign { rx_cmd_10[7:0], rx_cmd_09[7:0], rx_cmd_08[7:0], rx_cmd_07[7:0], rx_cmd_06[7:0], rx_cmd_05[7:0],
             rx_cmd_04[7:0], rx_cmd_03[7:0], rx_cmd_02[7:0], rx_cmd_01[7:0], rx_cmd_00[7:0] } = rx_cmd[87:0];

    wire rst_uart;
    reg rst_uart_sig;
    assign rst_uart = rst_uart_sig;

    reg START_MAIN_LOOP;

    // Parameters from serial
    reg OPER_ENABLE_WR, OPER_ENABLE_RD , OPER_ENABLE_ER, OPER_ENABLE_RST;
    reg PAGETYPE_ENABLE_LSB, PAGETYPE_ENABLE_CSB, PAGETYPE_ENABLE_MSB;
    reg [11:0] MIN_BLOCK_ADDR, MAX_BLOCK_ADDR;
    reg [31:0] REPEAT_FULL_LOOP, REPORT_LOG_FREQ;
    reg [16:0] PATTERN_0, PATTERN_1; // type 1bit [16] + data 16bit[15:0]

    parameter uADDR = 8'h00, uOPER = 8'h01, uLOOP = 8'h02, uLOG = 8'h03,
              uNAND = 8'h04, uMRAM = 8'h05,
              uSTART= 8'hF0, uHALT = 8'hF1;

    always@(posedge rx_busy or posedge rst_uart)
        begin
            if (rst_uart)
                begin
                    rx_idx <= 0;
                    rx_cnt <= 0;
                    rx_cmd <= 0;

                    START_MAIN_LOOP <= 0;

                    MIN_BLOCK_ADDR <= 0;
                    MAX_BLOCK_ADDR <= 1;

                    OPER_ENABLE_WR <= 1;
                    OPER_ENABLE_RD <= 1;
                    OPER_ENABLE_ER <= 1;
                    OPER_ENABLE_RST<= 1;

                    PAGETYPE_ENABLE_LSB <= 1;
                    PAGETYPE_ENABLE_CSB <= 1;
                    PAGETYPE_ENABLE_MSB <= 1;

                    REPEAT_FULL_LOOP <= 1;
                    REPORT_LOG_FREQ  <= 0;
                end
            else
                begin
                    // Byte 0  1  2  3  4  5  6  7  8  9 10 11
                    // Bit 00 08 16 24 32 45 48 56 64 72 80 88 96
                    // Dat Op                               EE

                    if(rx_idx == 88 && rx_data == 8'hEE)
                        begin
                            rx_idx <= 0;
                            rx_cnt <= rx_cnt + 1'b1;
                            case(rx_cmd_00)
                                uADDR :
                                    begin
                                        //ToDo: for future code
                                        //MIN_BLOCK_ADDR <= {rx_cmd_01[7:0], rx_cmd_02[7:0], rx_cmd_03[7:0], rx_cmd_04[7:0]};
                                        //MAX_BLOCK_ADDR <= {rx_cmd_05[7:0], rx_cmd_06[7:0], rx_cmd_07[7:0], rx_cmd_08[7:0]};

                                        MIN_BLOCK_ADDR <= {16'd0, rx_cmd_03[3:0], rx_cmd_04[7:0]};
                                        MAX_BLOCK_ADDR <= {16'd0, rx_cmd_07[3:0], rx_cmd_08[7:0]};
                                    end

                                uOPER :
                                    begin
                                        OPER_ENABLE_WR <= rx_cmd_01[0];
                                        OPER_ENABLE_RD <= rx_cmd_01[1];
                                        OPER_ENABLE_ER <= rx_cmd_01[2];
                                        OPER_ENABLE_RST<= rx_cmd_01[3];
                                    end

                                uLOOP :
                                    begin
                                        REPEAT_FULL_LOOP <= {rx_cmd_01[7:0], rx_cmd_02[7:0], rx_cmd_03[7:0], rx_cmd_04[7:0]};
                                    end

                                uLOG :
                                    begin
                                        REPORT_LOG_FREQ <= {rx_cmd_01[7:0], rx_cmd_02[7:0], rx_cmd_03[7:0], rx_cmd_04[7:0]};
                                    end

                                uNAND :
                                    begin
                                        PAGETYPE_ENABLE_LSB <= rx_cmd_01[0];
                                        PAGETYPE_ENABLE_CSB <= rx_cmd_01[1];
                                        PAGETYPE_ENABLE_MSB <= rx_cmd_01[2];

                                        PATTERN_0[16]   <= rx_cmd_03[0];
                                        PATTERN_0[15:0] <= {rx_cmd_05[7:0], rx_cmd_06[7:0]};

                                        PATTERN_1[16]   <= rx_cmd_04[0];
                                        PATTERN_1[15:0] <= {rx_cmd_07[7:0], rx_cmd_08[7:0]};
                                    end

                                uMRAM :
                                    begin
                                        PATTERN_0[16]   <= rx_cmd_03[0];
                                        PATTERN_0[15:0] <= {rx_cmd_05[7:0], rx_cmd_06[7:0]};

                                        PATTERN_1[16]   <= rx_cmd_04[0];
                                        PATTERN_1[15:0] <= {rx_cmd_07[7:0], rx_cmd_08[7:0]};
                                    end

                                uSTART :
                                    begin
                                        START_MAIN_LOOP <= 1;
                                    end

                                uHALT :
                                    begin
                                        START_MAIN_LOOP <= 0;
                                    end

                                default:
                                    begin
                                        ;
                                    end
                            endcase
                        end
                    else if(rx_idx == 88)
                        begin
                            rx_idx <= 0;
                        end
                    else
                        begin
                            //rx_cmd[rx_idx+7:rx_idx] = rx_data[7:0];

                            rx_cmd[rx_idx + 3'd0] <= rx_data[0];
                            rx_cmd[rx_idx + 3'd1] <= rx_data[1];
                            rx_cmd[rx_idx + 3'd2] <= rx_data[2];
                            rx_cmd[rx_idx + 3'd3] <= rx_data[3];
                            rx_cmd[rx_idx + 3'd4] <= rx_data[4];
                            rx_cmd[rx_idx + 3'd5] <= rx_data[5];
                            rx_cmd[rx_idx + 3'd6] <= rx_data[6];
                            rx_cmd[rx_idx + 3'd7] <= rx_data[7];

                            rx_idx <= rx_idx + 4'd8;
                        end
                end
        end


// =========================================================================================
// ================================= NAND Connection =======================================
// =========================================================================================

    // port-wire connection
    //wire CE_wire;
    wire RE_wire;
    wire WE_wire;
    wire CLE_wire;
    wire ALE_wire;
    wire WP_wire;
    wire RB_wire;
    wire [7:0] DQ_wire;
    wire inverse_pattern;
    assign CE_port  = CE_wire;
    assign CE2_port = 0;
    assign RE_port  = RE_wire;
    assign WE_port  = WE_wire;
    assign CLE_port = CLE_wire;
    assign ALE_port = ALE_wire;
    assign WP_port  = WP_wire;
    assign RB_wire  = `RB_SHARP_PORT;
    assign RB2_port = 0;//reversed in/out for 1 PLANE chip
    assign DQ_port[7:0] = DQ_wire[7:0];
    assign inverse_pattern = cnt_full_loop[0];


    // address lane setup
    // 0[39:32]= CA7  6     5    4  3  2 1    0  --> all zero for us!
    // 1[31:24]= 0    0  CA13   12 11 10 9    8  --> all zero for us!
    // 2[23:16]= PA7  6     5    4  3  2 1    0
    // 3[15: 8]= BA15 14   13   12 11 10 9  PA8
    // 4[ 7: 0]= 0    0   LA0 BA20 19 18 17  16

    //addr reg
    //reg addr_page_rst, addr_page_inc;
    reg [8:0] addr_page;   //  9bit 000~17F
    //reg addr_block_rst, addr_block_inc;
    reg [11:0] addr_block; // 12bit 000~AAF

    reg [31:0] cnt_full_loop;
    reg [31:0] cnt_log_freq;

    parameter tLSB = 0, tCSB = 1, tMSB = 2;
    reg [2:0] addr_type; // addr_type[2:0] 00x = LSB, 01x = CSB, 10x = MSB, 11x = RSVD

    //addr connection
    wire [39:0] addr;
    assign  addr[39:32] = 8'h0; //Addr Cycle 0 --> all 0
    assign  addr[31:24] = 8'h0; //Addr Cycle 1 --> all 0
    assign {addr[ 8],   addr[23:16]} = addr_page;
    assign {addr[ 4: 0],addr[15: 9]} = addr_block;
    assign  addr[ 7: 5] = 0; //all 0

    //start_nvm/stopper
    reg  start_nvm_sig;
    wire done_sig;


    //how about setting other unused to 0?

    /*
    assign tx_data[7:0]=(         (tx_idx == 0) ? { 8'hAA } :                  //Oper
                         (        (tx_idx == 1) ? { 8'h1 } :                             //ADDR[3]
                          (       (tx_idx == 2) ? { 8'h2 } :            //ADDR[2]
                           (      (tx_idx == 3) ? { 8'h3 } :    //ADDR[1]
                            (     (tx_idx == 4) ? { 8'h4 } :                   //ADDR[0]
                             (    (tx_idx == 5) ? { 8'h5 } :
                              (   (tx_idx == 6) ? { 8'h6 } :
                               (  (tx_idx == 7) ? { 8'h7 } :
                                ( (tx_idx == 8) ? { 8'h8 } :
                                                  { 8'hEE }
                                )
                               )
                              )
                             )
                            )
                           )
                          )
                         )
                        );
    */

    assign tx_data[7:0]=(           (tx_idx ==  0) ? { 6'h0, Oper[1:0] } :                  //Oper
                         (          (tx_idx ==  1) ? { 8'h0 } :                             //ADDR[3]
                          (         (tx_idx ==  2) ? { 3'h0, addr_block[11:7]} :            //ADDR[2]
                           (        (tx_idx ==  3) ? { addr_block[6:0], addr_page[8] } :    //ADDR[1]
                            (       (tx_idx ==  4) ? { addr_page[7:0] } :                   //ADDR[0]
                             (      (tx_idx ==  5) ? { latency[31:24] } :
                              (     (tx_idx ==  6) ? { latency[23:16] } :
                               (    (tx_idx ==  7) ? { latency[15: 8] } :
                                (   (tx_idx ==  8) ? { latency[ 7: 0] } :
                                 (  (tx_idx ==  9) ? { badbits_wire[31:24] } :
                                  ( (tx_idx == 10) ? { badbits_wire[23:16] } :
                                    (tx_idx == 11) ? { badbits_wire[15: 8] } :
                                    (tx_idx == 12) ? { badbits_wire[ 7: 0] } :
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



    //NAND
    NAND_RWE NAND_RWE(
        .CLKM(clk),
        .RST(rst),
        .pOPER(Oper),
        .pADDR(addr),
        .inverse_pattern(inverse_pattern),
        .start(start_nvm_sig),
        .done_wire(done_sig),
        .latency(latency),
        .badbits(badbits),
        .Led(Led),

        .pattern_usr_0(PATTERN_0[16]),
        .pattern_0(PATTERN_0[7:0]),
        .pattern_usr_1(PATTERN_1[16]),
        .pattern_1(PATTERN_1[7:0]),

    // NAND Wires
        .CE_wire(CE_wire),
        .RE_wire(RE_wire),
        .WE_wire(WE_wire),
        .CLE_wire(CLE_wire),
        .ALE_wire(ALE_wire),
        .WP_wire(WP_wire),
        .RB_wire(RB_wire),
        .DQ_wire(DQ_wire)
    );

// =========================================================================================
// ====================================== Main FSM LOOP ====================================
// =========================================================================================
    // FSM states
    parameter
        INIT_0     = 30, INIT_1     = 29, INIT_2     = 28,
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


    // FSM Loop
    always@(posedge clk)
        begin
        if (rst==1)
            begin
                State <= INIT_0;
            end
        else
            begin
                case(State)
                    INIT_0:
                        begin
                            rst_uart_sig  <= 0;
                            State <= INIT_1;
                        end

                    INIT_1:
                        begin
                            rst_uart_sig  <= 1;
                            State <= INIT_2;
                        end

                    INIT_2:
                        begin
                            rst_uart_sig  <= 0;

                            start_nvm_sig  <= 0;
                            addr_page  <= 0;
                            addr_block <= MIN_BLOCK_ADDR;
                            tx_idx     <= 0;
                            tx_send_sig<= 0;
                            addr_type  <= 0; //set start_nvm as MSB
                            cnt_full_loop <= 0;
                            cnt_log_freq  <= 0;

                            Oper <= oRS;

                            if(START_MAIN_LOOP)
                                State <= LOOP_ADDR_0;
                            else
                                State <= INIT_2;
                        end

                    INIT_FULL_LOOP:
                        begin
                            start_nvm_sig  <= 0;
                            addr_page  <= 0;
                            addr_block <= MIN_BLOCK_ADDR;
                            tx_idx     <= 0;
                            tx_send_sig<= 0;
                            addr_type  <= 0; //set start_nvm as MSB
                            cnt_full_loop <= cnt_full_loop + 1'b1;

                            Oper <= oRS;

                            State <= LOOP_ADDR_0;

                            if(cnt_log_freq[31:0] == REPORT_LOG_FREQ[31:0]) //log freq checker
                                cnt_log_freq <= 0;
                            else
                                cnt_log_freq <= cnt_log_freq + 1'b1;
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
                            else if(addr_type[2:1] == tLSB && PAGETYPE_ENABLE_LSB==0) //Check LCMsb filtering and skip
                                begin
                                    State <= LOOP_ADDR_2;
                                end
                            else if(addr_type[2:1] == tCSB && PAGETYPE_ENABLE_CSB==0)
                                begin
                                    State <= LOOP_ADDR_2;
                                end
                            else if(addr_type[2:1] == tMSB && PAGETYPE_ENABLE_MSB==0)
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
                            start_nvm_sig <= 1;   // NAND reset
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
                            if(OPER_ENABLE_WR)
                                begin
                                    start_nvm_sig <= 1;
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
                            if(OPER_ENABLE_RD)
                                begin
                                    start_nvm_sig <= 1;
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
                            if(OPER_ENABLE_ER)
                                begin
                                    start_nvm_sig <= 1;
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
                            if(cnt_log_freq[31:1] == REPORT_LOG_FREQ[31:1])  // consider even/odd for printing in pair [31:0]
                                begin
                                    State <= UART_1;
                                end
                            else
                                begin
                                    State <= LOOP_ADDR_2;
                                end
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
                            if( tx_idx[3:0] == 4'd14-1 )
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
                            start_nvm_sig <= 0;
                            //page 9bit 000~17F
                            if( addr_page[8:0] == `MAX_PAGE_ADDR )  // if finished sweep addr_page
                                begin
                                    State <= LOOP_ADDR_3;
                                end
                            else                      // if more to go
                                    if (Oper[1] == 1) // oER_10, oRS_11 : but, if Erase --> only once! ... block
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
                            if (START_MAIN_LOOP == 0) //halt?
                                begin
                                    State <= INIT_2;
                                end
                            //block 12bit 000~AAF
                            else if( addr_block[11:0] == MAX_BLOCK_ADDR ) // if finished sweep addr_block
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
                            start_nvm_sig  <= 0;
                            addr_block <= 12'hFFF; //this is for preventing warning of ISE.

                            if (cnt_full_loop == REPEAT_FULL_LOOP-1)
                                begin
                                    State <= INIT_0;
                                end
                            else
                                begin
                                    State <= INIT_FULL_LOOP;
                                end
                        end

                    default:
                        begin
                            State <= INIT_0;
                        end
                endcase
            end
        end

endmodule
