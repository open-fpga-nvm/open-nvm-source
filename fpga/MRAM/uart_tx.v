
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    08:14:41 12/23/2014 
// Design Name: 
// Module Name:    uart_tx
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: From FPGA board
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps
		//__________________________________________________uart_tx
		`define RDY 2'b11
		`define LOAD_BIT 2'b01
		`define SEND_BIT 2'b00
        `define STOP 2'b10
		//__________Test Bench 
		`define BIT_TMR_MAX 10'd869 // test bench <-- 115200  : tb #1738
		//`define BIT_TMR_MAX 4'd10417//14'b10100010110000 // 14'd1023
		//______________________________________________________________________
		`define BIT_INDEX_MAX 4'd10

module uart_tx(
	input clk,
	input rst,
	input send,
	input [7:0] data_tx,
	
	output done,
	output txd
);


reg [9:0] bitTmr;
//wire bitDone;
reg [3:0] bitIndex;
wire txBit;
//reg [9:0] txdata_tx;
reg [1:0] txState;


assign done = (txState == `STOP) ? 1'b1 : 1'b0;

assign txd = (txState == `SEND_BIT) ? txBit : 1'b1;

//{1'b1,data_tx[7:0],1'b0}
assign txBit =(         (bitIndex == 0) ? 1'b0 :
               (        (bitIndex == 1) ? data_tx[0] :
                (       (bitIndex == 2) ? data_tx[1] :
                 (      (bitIndex == 3) ? data_tx[2] :
                  (     (bitIndex == 4) ? data_tx[3] :
                   (    (bitIndex == 5) ? data_tx[4] :
                    (   (bitIndex == 6) ? data_tx[5] :
                     (  (bitIndex == 7) ? data_tx[6] :
                      ( (bitIndex == 8) ? data_tx[7] :
                                          1'b1
                      )
                     )
                    )
                   )
                  )
                 )
                )
               )
              );

always@(posedge clk) begin
	if(rst)
		txState<= `RDY;
	else
		case(txState)
			`RDY :
                begin
                    bitIndex <= 0;
                    bitTmr   <= 0;
					if(send == 1'b1)
						txState<=`SEND_BIT;
					else
						txState<=`RDY;
			    end
			`SEND_BIT : begin
					if (bitTmr == `BIT_TMR_MAX-1)
                        begin
                            bitTmr <=0;
                            if (bitIndex == `BIT_INDEX_MAX-1)
                                begin
                                    txState<=`STOP;
                                end
                            else
                                begin
                                    bitIndex <= bitIndex + 1'b1;
                                    txState<=`SEND_BIT;
                                end
                        end
					else
                        begin
                            bitTmr <= bitTmr + 1'b1;
    						txState <= `SEND_BIT;
                        end
			end
            `STOP :
                begin
                    if(send == 1'b1)
                        txState<=txState;
                    else //if(send == 1'b0)
                        txState<=`RDY;
                end
			default : txState <= `RDY;
		endcase
end

/*
always@(posedge clk) begin
	if(rst)
		bitTmr <= 0;
	else
		if(txState[0] == 1) // if(txState == `RDY)
			bitTmr <= 0;
		else
			if(bitDone)
				bitTmr <= 0;
			else
				bitTmr <= bitTmr +1 ;
end

assign bitDone = (bitTmr == `BIT_TMR_MAX) ? 1 : 0;



always@(posedge clk) begin
	if(rst)
		bitIndex <= 0;
	else
		if(txState[1] == 1) // if(txState == `RDY)
			bitIndex <= 0;
		else
			if(txState == `LOAD_BIT)
				bitIndex <= bitIndex +1 ;
			else
				bitIndex <= bitIndex;
end
*/

/*
always@(posedge clk) begin
	if(rst)
		txdata_tx <= 0;
	else
		if(txState[1] == 0) // if(send == 1'b1)
			txdata_tx <= {1'b1,data_tx,1'b0} ;
		else
			txdata_tx <= 10'b1_1111_1111_1;
end

always@(posedge clk) begin
	if(rst)
		txBit <= 1'b1;
	else
		if(txState[1] == 1) // if(txState == `RDY)
			txBit <= 1'b1 ;
		else //if(txState == `LOAD_BIT)
			txBit <= txdata_tx[bitIndex];
end

assign txd = rst ? 1 : txBit;
*/
//assign ready = (txState == `RDY) ? 1'b1 : 1'b0;

endmodule
