
module output_router #(
    parameter int SPAD_WIDTH = 64,
    parameter int DATA_WIDTH = 8,
    parameter int SPAD_N = SPAD_WIDTH / DATA_WIDTH,
    parameter int ADDR_WIDTH = 8,
    parameter int ROWS = 4,
    parameter int COLUMNS = 4
) (
    input  logic i_clk,
    input  logic i_nrst,
    input  logic i_reg_clear,
    input  logic i_en,
    input logic i_conv_mode,

    // Systolic Array inputs
    input  logic [0:COLUMNS-1][4*DATA_WIDTH-1:0] i_ifmap,
    input  logic [0:COLUMNS-1]                   i_valid,       // not used in top.sv
    output logic                                 o_shift_en,
    // Qunatization parameters
    input  logic              [  DATA_WIDTH-1:0] i_quant_sh,
    input  logic              [2*DATA_WIDTH-1:0] i_quant_m0,
    input  logic signed       [4*DATA_WIDTH-1:0] i_quant_bias,
    // Address generation
    // Top module inputs
    input logic  [ADDR_WIDTH-1:0] i_o_size,
    input logic  [ADDR_WIDTH-1:0] i_o_c_size,
    input logic  [ADDR_WIDTH-1:0] i_i_c,
    input logic  [ADDR_WIDTH-1:0] i_depth_mult, // Only used for DW. Ignored for PW.
    // Input router inputs (tile xy dimensions) — TILING: commented out; software manages tile boundaries
    // input  logic [ADDR_WIDTH-1:0] i_x_s,      // TILING
    // input  logic [ADDR_WIDTH-1:0] i_x_e,      // TILING
    // input  logic [ADDR_WIDTH-1:0] i_y_s,      // TILING
    // input  logic [ADDR_WIDTH-1:0] i_y_e,      // TILING
    // input  logic [ADDR_WIDTH-1:0] i_xy_length, // TILING
    // input  logic                  i_xy_valid,  // TILING
    // Weight router inputs (tile c dimension) — TILING: commented out
    // input  logic [ADDR_WIDTH-1:0] i_c_s,      // TILING
    // input  logic [ADDR_WIDTH-1:0] i_c_e,      // TILING
    // input  logic                  i_c_valid,   // TILING
    // SPAD 
    output logic [ADDR_WIDTH-1:0] o_addr,
    output logic [SPAD_WIDTH-1:0] o_data_out,
    output logic [SPAD_N-1:0]     o_write_mask,
    output logic                  o_valid,
    output logic                  o_done,
    // For bias, scale, shift spads
    output logic o_quant_read_en,
    output logic [$clog2(COLUMNS)-1:0] o_quant_addr,
    // For debug
    output logic [SPAD_WIDTH-1:0] o_word,
    output logic                  o_word_valid,
    output logic [ADDR_WIDTH-1:0] o_o_x,
    output logic [ADDR_WIDTH-1:0] o_o_y,
    output logic [ADDR_WIDTH-1:0] o_o_c
);
    logic [$clog2(COLUMNS*ROWS):0] num_input_valid;
    logic [$clog2(COLUMNS)-1:0] quant_idx; // which quant unit to store reg for
    // Parallel quant
    logic                                 quant_en;
    logic                                 quant_store_reg;
    logic [0:COLUMNS-1][4*DATA_WIDTH-1:0] quant_i_act;
    logic [0:COLUMNS-1][  DATA_WIDTH-1:0] quant_o_act;
    logic [0:COLUMNS-1]                   quant_valid;
    logic                                 quant_all_valid;
    // data buffer to SPAD
    logic        [SPAD_WIDTH-1:0]         data_buffer;  // buffer data to be written to spad
    logic        [COLUMNS*DATA_WIDTH-1:0] data_left;    // leftover data not written to spad
    logic signed [$clog2(COLUMNS)+1:0]    data_left_cnt;
    logic        [$clog2(SPAD_N):0]       bytes_to_write;
    logic        [$clog2(SPAD_N):0]       bytes_in_buffer;
    // 
    // logic [ADDR_WIDTH-1:0] current_x, current_y, current_c, output_c, counter;  // TILING: x/y/c tile trackers
    logic [ADDR_WIDTH-1:0] current_c, output_c, counter;  // current_c and counter still needed for quant indexing
    // logic [ADDR_WIDTH-1:0] prev_x, prev_y;              // TILING
    // logic [ADDR_WIDTH-1:0] start_x, start_y, start_c;  // TILING: tile start coordinates
    logic [ADDR_WIDTH-1:0] start_c;                        // start_c still needed for quant preload loop
    // logic [ADDR_WIDTH-1:0] limit_x, limit_y, limit_c, limit_xy;  // TILING: tile end coordinates
    logic [ADDR_WIDTH-1:0] limit_c;                        // limit_c still needed for quant preload loop
    // logic [ADDR_WIDTH-1:0] xy_count;                    // TILING: counts output pixels written within tile
    // SPAD address
    logic [$clog2(SPAD_N)+ADDR_WIDTH-1:0] byte_addr;   // which byte in the SPAD
    logic [ADDR_WIDTH-1:0] word_addr;   // which word in the SPAD
    logic [SPAD_N-1:0] byte_offset;     // which byte in the word
    // TILING: NHWC address formula using current_x/current_y removed.
    // Software provides i_or_start_addr as the base word address for this tile's output.
    // address = n*HWC + h*WC + w*C + c
    always_comb begin
        output_c    = i_i_c * i_depth_mult + current_c;
        // byte_addr   = (current_x * i_o_size + current_y) * i_o_c_size + output_c;  // TILING
        // word_addr   = byte_addr >> $clog2(SPAD_N);   // TILING: replaced by i_or_start_addr + linear offset
        // byte_offset = byte_addr % SPAD_N;            // TILING
        byte_addr   = output_c;                         // simplified: linear within tile (software sets base addr)
        word_addr   = byte_addr >> $clog2(SPAD_N);
        byte_offset = byte_addr % SPAD_N;
    end

    genvar q;
    generate
        for (q=0; q<COLUMNS; q=q+1) begin: quat_parallel_gen
            quant #(
                .DATA_WIDTH(DATA_WIDTH)
            ) quant_inst (
                .i_clk      (i_clk),
                .i_nrst     (i_nrst),
                .i_en       (quant_en),
                .i_store_reg(quant_store_reg && (q == quant_idx)), 
                .i_sh       (i_quant_sh),
                .i_m0       (i_quant_m0),
                .i_act      (quant_i_act[q]),
                .i_zero_point(-128),
                .o_act      (quant_o_act[q]),
                .o_valid    (quant_valid[q])
            );
        end
    endgenerate
    // quant data is only valid when all data is valid;
    assign quant_all_valid = &quant_valid;

    always_comb begin
        bytes_in_buffer = SPAD_N - byte_offset;
        bytes_to_write = (data_left_cnt < bytes_in_buffer) ? data_left_cnt : bytes_in_buffer;
    end

    always_comb begin
        // o_addr     = word_addr;
        o_data_out = data_buffer;
    end

    // debug
    always_comb begin
        o_word       = o_data_out;
        o_word_valid = o_valid;
        // o_o_x        = current_x;  // TILING: current_x commented out
        // o_o_y        = current_y;  // TILING: current_y commented out
        o_o_x        = '0;
        o_o_y        = '0;
        o_o_c        = current_c;
    end

    parameter int IDLE_STATE = 0;
    parameter int PRELOAD_QUANT = 1;
    parameter int QUANT_DATA = 2;
    parameter int COLLECT_IN = 3;
    parameter int SPAD_WRITE = 4;
    parameter int NEXT_ADDR  = 5;
    parameter int DONE_STATE = 6;

    logic [2:0] state;

    always_ff @(posedge i_clk or negedge i_nrst) begin
        if (~i_nrst) begin
            state           <= IDLE_STATE;
            
            num_input_valid <= 0;

            quant_en        <= 0;
            quant_store_reg <= 0;
            quant_i_act     <= 0;

            data_buffer     <= 0;
            data_left       <= 0;
            data_left_cnt   <= 0;

            // current_x       <= 0;  // TILING
            // current_y       <= 0;  // TILING
            // prev_x          <= 0;  // TILING
            // prev_y          <= 0;  // TILING
            // start_x         <= 0;  // TILING
            // start_y         <= 0;  // TILING
            // limit_x         <= 0;  // TILING
            // limit_y         <= 0;  // TILING
            // xy_count        <= 0;  // TILING
            // limit_xy        <= 0;  // TILING
            current_c       <= 0;
            start_c         <= 0;
            limit_c         <= 0;

            o_addr          <= 0;
            o_write_mask    <= 0;
            o_valid         <= 0;
            o_shift_en      <= 0;
            o_done          <= 0;

            quant_idx       <= 0;
            o_quant_read_en <= 0;
            o_quant_addr    <= 0;
            counter         <= 0;
        end else if(i_reg_clear) begin
            state           <= IDLE_STATE;
            
            num_input_valid <= 0;

            quant_en        <= 0;
            quant_store_reg <= 0;
            quant_i_act     <= 0;

            data_buffer     <= 0;
            data_left       <= 0;
            data_left_cnt   <= 0;

            // current_x       <= 0;  // TILING
            // current_y       <= 0;  // TILING
            // prev_x          <= 0;  // TILING
            // prev_y          <= 0;  // TILING
            // start_x         <= 0;  // TILING
            // start_y         <= 0;  // TILING
            // limit_x         <= 0;  // TILING
            // limit_y         <= 0;  // TILING
            // xy_count        <= 0;  // TILING
            // limit_xy        <= 0;  // TILING
            current_c       <= 0;
            start_c         <= 0;
            limit_c         <= 0;

            o_addr          <= 0;
            o_write_mask    <= 0;
            o_valid         <= 0;
            o_shift_en      <= 0;
            o_done          <= 0;

            quant_idx       <= 0;
            o_quant_read_en <= 0;
            o_quant_addr    <= 0;
            counter         <= 0;
        end else begin
            case (state)
                IDLE_STATE: begin
                    // TILING: x/y tile boundary capture from input router removed
                    // if (i_xy_valid) begin           // TILING
                    //     current_x <= i_x_s;         // TILING
                    //     current_y <= i_y_s;         // TILING
                    //     prev_x    <= i_x_s;         // TILING
                    //     prev_y    <= i_y_s;         // TILING
                    //     start_x   <= i_x_s;         // TILING
                    //     start_y   <= i_y_s;         // TILING
                    //     limit_x   <= i_x_e;         // TILING
                    //     limit_y   <= i_y_e;         // TILING
                    //     limit_xy  <= i_xy_length;   // TILING
                    //     xy_count  <= 0;             // TILING
                    // end                             // TILING

                    // TILING: channel tile boundary capture from weight router removed
                    // if (i_c_valid) begin            // TILING
                    //     current_c <= i_c_s;         // TILING
                    //     start_c   <= i_c_s;         // TILING
                    //     limit_c   <= i_c_e;         // TILING
                    // end                             // TILING

                    if (i_en && !o_done) begin
                        state           <= PRELOAD_QUANT;
                        // o_quant_addr    <= i_c_s;  // TILING: software sets start channel via CSR
                        o_quant_addr    <= start_c;
                        o_quant_read_en <= 1;

                        // num_input_valid <= (limit_xy+1) * (limit_c - start_c + 1);  // TILING
                        num_input_valid <= (limit_c - start_c + 1); // software sizes the tile; only c dimension remains
                    end
                    else
                        o_done <= 0;
                end

                PRELOAD_QUANT: begin
                    // For n columns, iterate idx from 0 to n-1, each time store the data for that column into the quant reg
                    if (counter <= limit_c - start_c) begin
                        quant_idx <= (COLUMNS - 1) - counter; // reversed order, check with quant_i_act assignment in generate block
                        quant_store_reg <= 1'b1;

                        o_quant_addr <= start_c + counter + 1; // we can start reading the next quant data in the same cycle as storing the current quant result since the quant result is only valid in the next cycle
                        o_quant_read_en <= (o_quant_addr < limit_c) ? 1 : 0; // stop reading quant data once we have read all the necessary quant data for the current tile
                        
                        counter <= counter + 1;
                    end else begin
                        quant_idx <= 0;
                        quant_store_reg <= 0;

                        o_quant_read_en <= 0;
                        o_quant_addr <= 0;

                        counter <= 0;                        
                        state <= QUANT_DATA;
                    end
                end

                QUANT_DATA: begin
                    if (o_shift_en) begin
                        o_shift_en <= 0; // wait for one cycle for the shift to take effect
                    end
                    else begin
                        if (num_input_valid > 0) begin
                            if (quant_all_valid) begin
                                state         <= COLLECT_IN;
                                quant_en      <= 0;
                                data_left     <= quant_o_act;
                                data_left_cnt <= (limit_c - start_c + 1 < COLUMNS)? limit_c - start_c + 1 : COLUMNS;
                            end else begin
                                quant_en      <= 1'b1;
                                for(int i=0; i<COLUMNS; i=i+1) quant_i_act[i] <= i_ifmap[COLUMNS-i-1];
                            end
                        end 
                        else 
                            state <= DONE_STATE;
                    end
                end

                COLLECT_IN: begin
                    if (data_left_cnt > 0) begin
                        state <= SPAD_WRITE;
                        {data_left, data_buffer} <= data_left << (byte_offset * DATA_WIDTH);
                        o_addr <= word_addr;
                        o_write_mask <= ({SPAD_N{1'b1}} >> (SPAD_N - bytes_to_write)) << byte_offset;
                        current_c       <= current_c       + bytes_to_write;
                        num_input_valid <= num_input_valid - bytes_to_write;
                        data_left_cnt   <= data_left_cnt   - bytes_to_write;
                    end 
                    else begin
                        state <= NEXT_ADDR;
                    end
                end

                SPAD_WRITE: begin
                    if (!o_valid) begin
                        o_valid <= 1;
                    end
                    else begin
                        o_valid         <= 0;
                        // o_write_mask    <= 0;
                        // current_c       <= current_c       + bytes_to_write;
                        state           <= NEXT_ADDR;
                    end
                end

                NEXT_ADDR: begin
                    if (current_c > limit_c || data_left_cnt <= 0) begin
                        current_c <= start_c;

                        // TILING: x/y pixel iteration within tile removed — software steps one tile per invocation
                        // if (current_y >= limit_y) begin          // TILING
                        //     current_y <= 0;                      // TILING
                        //     if (current_x >= limit_x) begin      // TILING
                        //         current_x <= 0;                  // TILING
                        //     end else begin                       // TILING
                        //         current_x <= current_x + 1;     // TILING
                        //         xy_count <= xy_count + 1;       // TILING
                        //     end                                  // TILING
                        // end else begin                           // TILING
                        //     current_y <= current_y + 1;         // TILING
                        //     xy_count <= xy_count + 1;           // TILING
                        // end                                      // TILING

                        // if (xy_count == limit_xy) begin          // TILING: pixel count check
                        state <= DONE_STATE;  // one tile per invocation — always done after one pass
                        // end else begin                           // TILING
                        //     state <= QUANT_DATA;                 // TILING
                        //     o_shift_en <= 1;                     // TILING
                        // end                                      // TILING
                    end else begin
                        state <= COLLECT_IN;
                        o_shift_en <= 0;
                    end
                end

                DONE_STATE: begin
                    if (~o_done) begin
                        state  <= IDLE_STATE;
                        o_shift_en <= 0;
                        o_done <= 1;
                    end
                end

                default: state <= IDLE_STATE;
            endcase
        end
    end

endmodule
