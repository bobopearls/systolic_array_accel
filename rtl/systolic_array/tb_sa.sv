`timescale 1ns/1ps

module tb_systolic_array;
    parameter DATA_WIDTH = 8;
    parameter WIDTH = 4;  // # of cols ; length of row
    parameter HEIGHT = 3; // # of rows

    logic i_clk;
    logic i_nrst;
    logic i_reg_clear;
    logic i_pe_en;
    logic i_psum_out_en;
    logic i_scan_en;
    logic [1:0] i_mode;
    logic [0:HEIGHT-1][DATA_WIDTH-1:0] i_ifmap;
    logic [0:WIDTH-1][DATA_WIDTH-1:0] i_weight;
    logic [0:WIDTH-1][DATA_WIDTH*2-1:0] o_ofmap;  //o_ofmap is the 1st row in the array

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
        #10;
        
        // #cycles = i + j + k - 2
        // #cycles = 3 + 2 + 4 - 2 = 7 cycles
        
        // Inject IFMAP rows and WEIGHT cols
        i_pe_en = 1;
        i_ifmap = {8'd3, {2{8'd0}}};
        i_weight = {{8'd2}, {3{8'd0}}};

        #10; // cycle 1
        i_ifmap = {8'd1, 8'd4, 8'd0};
        i_weight = {8'd8, 8'd5, {2{8'd0}}};
        
        #10;
        i_ifmap = {{2{8'd0}}, 8'd1};
        i_weight = {8'd0, 8'd3, 8'd2, 8'd0};
        
        #10;
        i_ifmap = {{2{8'd0}}, 8'd6};
        i_weight = {{2{8'd0}}, 8'd2, 8'd0};
        
        #10;
        i_ifmap = {3{8'd0}};    // zero input
        i_weight = {{3{8'd0}}, 8'd7};
        
        #10;
        i_weight = {4{8'd0}};;  // zero input
        
        #10;
        #10; // cycle 7, stop routing
        
        i_pe_en = 0;
        i_psum_out_en = 1; // Enable output of psum -> show first row of systolic array
        
        #10
        i_scan_en = 1; // Enable scan mode -> rows bubble up. Row 3 becomes row 2, row 2 becomes row 1, etc.
        i_psum_out_en = 0;
        // Allow the systolic array to propagate data
        #30;

        $finish;
    end
    
    
    // TCL Logging
    integer cycle;

    always_ff @(posedge i_clk) begin
        if (!i_nrst)
            cycle <= 0;
        else
            cycle <= cycle + 1;
    end
    
    
    always_ff @(posedge i_clk) begin
        if (i_pe_en) begin
            $write("[cycle %0d] i_ifmap:", cycle);
            for (int h = 0; h < HEIGHT; h++) begin
                $write(" %0d", i_ifmap[h]);
            end
    
            $write(" | i_weight:");
            for (int w = 0; w < WIDTH; w++) begin
                $write(" %0d", i_weight[w]);
            end
    
            $write("\n");
        end
    end

    always_ff @(posedge i_clk) begin
        if (i_scan_en) begin
            $write("[cycle %0d] o_ofmap:", cycle);
            for (int w = 0; w < WIDTH; w++) begin
                $write(" %0d", o_ofmap[w]);
            end
            $write("\n");
        end
    end
        

endmodule
