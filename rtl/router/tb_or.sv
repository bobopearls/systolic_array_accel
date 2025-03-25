`timescale 1ns/1ps

module tb_output_router;

    // Parameters
    parameter int SPAD_WIDTH = 64;
    parameter int DATA_WIDTH = 8;
    parameter int SPAD_N = SPAD_WIDTH / DATA_WIDTH;
    parameter int ADDR_WIDTH = 8;
    parameter int ROWS = 4;
    parameter int COLUMNS = 4;

    // Inputs
    logic i_clk;
    logic i_nrst;
    logic i_reg_clear;
    logic i_en;

    logic [0:ROWS-1][DATA_WIDTH*2-1:0] i_ifmap;
    logic [ROWS-1:0] i_valid;
    
    logic [ADDR_WIDTH-1:0] i_i_size;
    logic [ADDR_WIDTH-1:0] i_c_size;
    logic [ADDR_WIDTH-1:0] i_o_x_start;
    logic [ADDR_WIDTH-1:0] i_o_x_end;
    logic [ADDR_WIDTH-1:0] i_o_y_start;
    logic [ADDR_WIDTH-1:0] i_o_y_end;
    logic [ADDR_WIDTH-1:0] i_o_c_start;
    logic [ADDR_WIDTH-1:0] i_o_c_end;

    logic o_done;

    // Outputs
    logic [ADDR_WIDTH-1:0] o_addr;
    logic [SPAD_WIDTH-1:0] o_data_out;
    logic [SPAD_N-1:0] o_write_mask;
    logic o_valid;
    logic o_shift_en;

    // Instantiate the DUT
    output_router #(
        .SPAD_WIDTH(SPAD_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .SPAD_N(SPAD_N),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ROWS(ROWS),
        .COLUMNS(COLUMNS)
    ) dut (
        .i_clk(i_clk),
        .i_nrst(i_nrst),
        .i_reg_clear(i_reg_clear),
        .i_en(i_en),
        .i_ifmap(i_ifmap),
        .i_valid(i_valid),
        .o_shift_en(o_shift_en),
        .i_i_size(i_i_size),
        .i_c_size(i_c_size),
        .i_o_x_start(i_o_x_start),
        .i_o_x_end(i_o_x_end),
        .i_o_y_start(i_o_y_start),
        .i_o_y_end(i_o_y_end),
        .i_o_c_start(i_o_c_start),
        .i_o_c_end(i_o_c_end),
        .o_addr(o_addr),
        .o_data_out(o_data_out),
        .o_write_mask(o_write_mask),
        .o_valid(o_valid),
        .o_done(o_done)
    );

    // Clock generation
    always #5 i_clk = ~i_clk;

    // Initialization
    initial begin
        // Dump waveform
        $dumpfile("tb.vcd");
        $dumpvars;

        // Initialize
        i_clk = 0;
        i_nrst = 0;
        i_reg_clear = 0;
        i_en = 0;
        i_ifmap = '0;
        i_valid = '0;
        i_i_size = 6;
        i_c_size = 6;

        i_o_x_start = 0;
        i_o_x_end = 1;
        i_o_y_start = 4;
        i_o_y_end = 2;
        i_o_c_start = 0;
        i_o_c_end = 5;

        // Reset
        #10;
        i_nrst = 1;

        // Set valid ifmap test data once
        @(posedge i_clk);
        i_ifmap[0] = 16'h00A1;
        i_ifmap[1] = 16'h00B2;
        i_ifmap[2] = 16'h00C3;
        i_ifmap[3] = 16'h00D4;

        i_valid = 4'b1111;
        i_en = 1;

        // Hold for one cycle, then deassert valid & en
        @(posedge i_clk);
        i_valid = 4'b0000;
        i_en = 0;

        // Wait until done
        wait(o_done);

        // Hold a few more cycles to observe outputs
        repeat(5) @(posedge i_clk);

        $finish;
    end

endmodule
