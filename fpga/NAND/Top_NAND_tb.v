module Top_NAND_tb();

    reg clk;
    reg rst;
    reg RB_reg;

    Top_NAND Top_NAND(
        .clkm(clk),
        .rst(rst),
        .RB_port(RB_reg)
    );

    always begin
        #10 clk = ~clk;
    end     

    initial begin
        #0  rst = 1; RB_reg = 1; clk = 1;
        #30 rst = 0;
		  #2000000000
        $finish;
    end
	 
	 
endmodule