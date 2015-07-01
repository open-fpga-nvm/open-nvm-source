//////////////////////////////////////////////////////////////////////////////////
// Engineer: Sukmin Kang
// Email: sukmin@camelab.org
// Create Date:    08:14:41 12/23/2014 
// Design Name:  uart_rx
// Module Name:    uart_rx 
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps
		//__________________________________________________uart_rx
		`define IDLE 1'd0
		`define RECV_BIT 1'd1
		//__________Test Bench
		`define BIT_TMR_MAX 10'd869 // #10240           <-- 115200  : tb #1738
		//`define BIT_TMR_MAX 14'd10417//14'b10100010110000 // 14'd10416 #10417 
		//______________________________________________________________________
//		`define BIT_INDEX_MAX 4'd9

module uart_rx(
	input clk,
	input rst,
	input rxd,
	output [7:0] data_rx,
	
	output busy
);
//____________________________________________________________Global

reg [8:0] rxdata;
assign data_rx[7:0] = rxdata[8:1];

reg busy_reg;
assign busy = busy_reg;

reg [9:0] bitTmr;
reg [3:0] bitIndex;
reg rxState;

reg [9:0] bitCnt_0;
reg [9:0] bitCnt_1;

/*
wire rxBit;
assign rxBit =(  (rxState != `RECV_BIT) ? dummy :
               (        (bitIndex == 1) ? rxdata[0] :
                (       (bitIndex == 2) ? rxdata[1] :
                 (      (bitIndex == 3) ? rxdata[2] :
                  (     (bitIndex == 4) ? rxdata[3] :
                   (    (bitIndex == 5) ? rxdata[4] :
                    (   (bitIndex == 6) ? rxdata[5] :
                     (  (bitIndex == 7) ? rxdata[6] :
                        (bitIndex == 8) ? rxdata[7] :
                                          dummy        //when bitIndex == 0 : start signal(0) is not data
                     )
                    )
                   )
                  )
                 )
                )
               )
              );
*/

always@(posedge clk) begin
    if(rst)
        begin
            rxState  <= `IDLE;
            busy_reg <= 0;
        end
    else
        begin
            case(rxState)
                `IDLE :
                    begin
                        bitIndex <= 0;
                        bitTmr   <= 0;
                        bitCnt_0 <= 0;
                        bitCnt_1 <= 0;
                        if( rxd == 0 )
                            begin
                                rxState <= `RECV_BIT;
                            end
                        else
                            rxState <= `IDLE;
                    end

                `RECV_BIT :
                    begin
    					if (bitTmr == `BIT_TMR_MAX-1)
                            begin
                                bitTmr   <= 0;
                                bitCnt_0 <= 0;
                                bitCnt_1 <= 0;
                                if (bitIndex == 4'd9-1)
                                    begin
                                        // done!
                                        busy_reg <= 1;
                                        rxState <= `IDLE;
                                    end
                                else
                                    begin
                                        busy_reg <= 0;
                                        bitIndex <= bitIndex + 1'b1;
                                        rxState <= `RECV_BIT;
                                    end
                            end
    					else
                            begin

                                if(rxd == 0)
                                    bitCnt_0 <= bitCnt_0 + 1'b1;
                                else
                                    bitCnt_1 <= bitCnt_1 + 1'b1;

                                if( bitCnt_0 > bitCnt_1 )
                                    rxdata[bitIndex] <= 0;
                                else
                                    rxdata[bitIndex] <= 1;

                                bitTmr <= bitTmr + 1'b1;
        						rxState <= `RECV_BIT;
                            end
                    end
                default :
                    begin
                        rxState  <= `IDLE;
                        busy_reg <= 0;
                    end
        	endcase
        end
end

endmodule
