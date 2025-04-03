module top_quant #(
    parameter ROWS = 4,
    parameter DATA_WIDTH = 8
) (
    input  logic i_clk,
    input  logic i_nrst, 
    input  logic i_en, 
    input  logic i_store_reg,
    input  logic [ROWS-1:0][  DATA_WIDTH-1:0] i_sh,
    input  logic [ROWS-1:0][2*DATA_WIDTH-1:0] i_m0,
    input  logic [ROWS-1:0][2*DATA_WIDTH-1:0] i_act,
    output logic [ROWS-1:0][  DATA_WIDTH-1:0] o_act
);
    genvar n;
    generate
        for (n=0; n<ROWS; n=n+1) begin
            quant #(    
                .DATA_WIDTH(DATA_WIDTH)
            ) quant_inst (
                .i_clk(i_clk),
                .i_nrst(i_nrst),
                .i_en(i_en),
                .i_store_reg(i_store_reg),
                .i_sh(i_sh[n]),
                .i_m0(i_m0[n]),
                .i_act(i_act[n]),
                .o_act(o_act[n])
            );
        end
    endgenerate
endmodule