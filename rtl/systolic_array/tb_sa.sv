`timescale 1ns/1ps

module tb_systolic_array;
    parameter DATA_WIDTH = 8;
    parameter WIDTH = 3;
    parameter HEIGHT = 2;

    logic i_clk;
    logic i_nrst;
    logic i_reg_clear;
    logic i_pe_en;
    logic i_psum_out_en;
    logic i_scan_en;
    logic [1:0] i_mode;
    logic [0:HEIGHT-1][DATA_WIDTH-1:0] i_ifmap;
    logic [0:WIDTH-1][DATA_WIDTH-1:0] i_weight;
    logic [0:HEIGHT-1][DATA_WIDTH*2-1:0] o_ofmap;

    // DUT
    systolic_array #(
        .DATA_WIDTH(DATA_WIDTH),
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT)
    ) dut (
        .i_clk(i_clk),
        .i_nrst(i_nrst),
        .i_reg_clear(i_reg_clear),
        .i_pe_en(i_pe_en),
        .i_psum_out_en(i_psum_out_en),
        .i_scan_en(i_scan_en),
        .i_mode(i_mode),
        .i_ifmap(i_ifmap),
        .i_weight(i_weight),
        .o_ofmap(o_ofmap)
    );

    // Clock generation
    initial begin
        i_clk = 0;
        forever #5 i_clk = ~i_clk; // 100MHz clock
    end

    // Stimulus
    initial begin
        // Initialize VCD dump
        $dumpfile("tb.vcd");
        $dumpvars;

        // Reset and defaults
        i_nrst = 0;
        i_reg_clear = 0;
        i_pe_en = 0;
        i_psum_out_en = 0;
        i_scan_en = 0;
        i_mode = 2'b00; // 8-bit mode
        i_ifmap = 0;
        i_weight = 0;

        #20;
        i_nrst = 1;
        i_reg_clear = 1;
        #10;
        i_reg_clear = 0;
        i_pe_en = 1;

        // Static weights
        i_weight[0] = 8'd1;
        i_weight[1] = 8'd2;
        i_weight[2] = 8'd3;

        // Inject IFMAP rows
        #10;
        i_ifmap[0] = 8'd4;
        i_ifmap[1] = 8'd5;

        #10;
        i_ifmap[0] = 8'd0;
        i_ifmap[1] = 8'd0;

        #10;
        i_pe_en = 0;

        #10;
        i_psum_out_en = 1; // Enable output of psum
        #10
        i_scan_en = 1; // Enable scan mode
        i_psum_out_en = 0;
        // Allow the systolic array to propagate data
        #50;

        $finish;
    end

endmodule
