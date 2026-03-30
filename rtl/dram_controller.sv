module dram_controller ( // aka memory controller
    // Clock and Reset
    input  logic        clk,
    input  logic        nrst,

    // AXI-Stream Interface from the inside of the DRAM (hypothetical)
    input  logic [63:0] dma_data,
    input  logic        dma_valid,
    output logic        dma_ready,

    // Physical DRAM Interface outside
    output logic [31:0] dram_addr,
    output logic [63:0] dram_data_out,
    output logic        dram_write_en,
    input  logic [63:0] dram_data_in
);

    // 1. Internal Buffers
    logic [63:0] burst_buffer;
    logic        busy_flag;
    
    // 2. The Request Handler (The "Brain")
    always_ff @(posedge clk) begin
        if (!nrst) begin
            busy_flag <= 0;
        end else if (dma_valid && !busy_flag) begin
            // The DMA has sent a request!
            // Start the DRAM write process
            dram_addr     <= calc_next_addr(); 
            dram_data_out <= dma_data;
            dram_write_en <= 1'b1;
            busy_flag     <= 1'b1; // Tell everyone to wait until finished
        end else begin
            dram_write_en <= 1'b0;
            busy_flag     <= 1'b0;
        end
    end
    
    // 3. Flow Control
    assign dma_ready = !busy_flag; // Only tell the DMA to send more when NOT busy
endmodule
