module sdram_array #(
  parameter SDRAM_DATA_W = 16,
  parameter SDRAM_CHIP_PAIRS = 1
)(
  input        clk,
  input        cke,
  input [SDRAM_CHIP_PAIRS-1:0] cs,
  input        ras,
  input        cas,
  input        we,
  input [12:0] a,
  input [ 1:0] ba,
  input [(SDRAM_DATA_W/8)-1:0] dqm,
  inout [SDRAM_DATA_W-1:0] dq
);
  localparam CHIPS_PER_PAIR = SDRAM_DATA_W / 16;
  localparam REQUIRED_BL = (SDRAM_DATA_W == 32) ? 1 : 2;

  genvar pair_index;
  genvar chip_index;
  generate
    for (pair_index = 0; pair_index < SDRAM_CHIP_PAIRS;
         pair_index = pair_index + 1) begin : pairs
      for (chip_index = 0; chip_index < CHIPS_PER_PAIR;
           chip_index = chip_index + 1) begin : chips
        sdram #(.REQUIRED_BURST_LENGTH(REQUIRED_BL)) chip (
          .clk(clk), .cke(cke), .cs(cs[pair_index]), .ras(ras),
          .cas(cas), .we(we), .a(a), .ba(ba),
          .dqm(dqm[chip_index * 2 +: 2]),
          .dq(dq[chip_index * 16 +: 16])
        );
      end
    end
  endgenerate
endmodule
