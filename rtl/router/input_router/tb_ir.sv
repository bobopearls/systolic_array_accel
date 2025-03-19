`timescale 1ns/1ps

module tb_input_router;

    // Parameters
    parameter DATA_WIDTH = 8;
    parameter SPAD_DATA_WIDTH = 64;
    parameter SPAD_N = SPAD_DATA_WIDTH / DATA_WIDTH;
    parameter ADDR_WIDTH = 8;
    parameter COUNT = 4;
    parameter MISO_DEPTH = 16; // You had 8, but DUT has 16

    // DUT signals
    logic i_clk, i_nrst, i_en, i_reg_clear, i_fifo_pop_en, i_fifo_ptr_reset;
    logic [1:0] i_p_mode;
    logic i_conv_mode;
    logic [ADDR_WIDTH-1:0] i_i_size, i_o_size, i_i_c_size, i_i_c;
    logic i_spad_write_en;
    logic [SPAD_DATA_WIDTH-1:0] i_spad_data_in;
    logic [ADDR_WIDTH-1:0] i_spad_write_addr;
    logic [ADDR_WIDTH-1:0] i_start_addr, i_addr_end;

    // DUT outputs
    logic o_read_done;
    logic [COUNT-1:0][DATA_WIDTH-1:0] o_data;
    logic [COUNT-1:0] o_data_valid;
    logic o_ready, o_context_done, o_done, o_tile_done;

    integer file, r;
    reg [SPAD_DATA_WIDTH-1:0] file_data;
    int addr_cnt;

    // DUT instance
    input_router #(
        .DATA_WIDTH(DATA_WIDTH),
        .SPAD_DATA_WIDTH(SPAD_DATA_WIDTH),
        .SPAD_N(SPAD_N),
        .ADDR_WIDTH(ADDR_WIDTH),
        .COUNT(COUNT),
        .MISO_DEPTH(MISO_DEPTH)
    ) dut (
        .*
    );

    // Clock generation
    always #5 i_clk = ~i_clk;

    initial begin
        $dumpfile("tb.vcd");
        $dumpvars;

        i_clk = 0;
        i_nrst = 0;
        i_en = 0;
        i_reg_clear = 0;
        i_fifo_pop_en = 0;
        i_fifo_ptr_reset = 0;
        i_p_mode = 0; 
        i_conv_mode = 0;
        i_i_size = 0;
        i_o_size = 0;
        i_i_c_size = 0;
        i_i_c = 0;
        i_spad_write_en = 0;
        i_spad_data_in = 0;
        i_spad_write_addr = 0;
        i_start_addr = 0;
        i_addr_end = 0;

        // Reset pulse
        #20 i_nrst = 1;

        // Write to SPAD
        file = $fopen("d_ifmap.txt", "r");
        if (file == 0) begin
            $display("Error opening file");
            $finish;
        end

        addr_cnt = 0;
        while (!$feof(file)) begin
            r = $fscanf(file, "%h\n", file_data);
            i_spad_write_en = 1;
            i_spad_data_in = file_data;
            i_spad_write_addr = addr_cnt;
            #10;
            addr_cnt = addr_cnt + 1;
        end
        @(posedge i_clk);
        i_spad_write_en = 0;
        $fclose(file);

        // DWise Conv
        i_conv_mode = 0;// Pwise - 0, DWise - 1
                // Setup routing parameters
        i_i_size = 5; // Example values
        i_o_size = 5; // i_i_size - 3 + 1
        i_i_c_size = 5;
        i_i_c = 0; // For this test, assume it's channel 0
        i_start_addr = 7;
        i_addr_end = 22;


        // Enable routing
        @(posedge i_clk);
        i_en = 1;

        // Let the router work until finished
        wait (o_done == 1);
        i_en = 0;
        #10;
        i_reg_clear = 1;
        #10;
        i_reg_clear = 0;
        @(posedge i_clk);
        i_en = 1;
        // Setup routing parameters
        i_conv_mode = 1;// Pwise - 0, DWise - 1
        i_i_size = 5; // Example values
        i_o_size = 3; // i_i_size - 3 + 1
        i_i_c_size = 2;
        i_i_c = 0; // For this test, assume it's channel 0
        i_start_addr = 0;
        i_addr_end = 6;
        // Pwise Conv
        wait (o_done == 1);
        $display("Routing done");

        // // Optional: dump final outputs
        // $display("Output Data:");
        // for (int i = 0; i < COUNT; i++) begin
        //     $display("Lane %0d: %h (valid: %b)", i, o_data[i], o_data_valid[i]);
        // end

        $finish;
    end

    // Terminate simulation when o_done is high
    always @(posedge i_clk) begin
        if (o_ready) begin
            i_fifo_pop_en <= 1;
        end else begin
            i_fifo_pop_en <= 0;
        end
    end
endmodule
