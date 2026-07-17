module ps2_top_apb(
  input         clock,
  input         reset,
  input  [31:0] in_paddr,
  input         in_psel,
  input         in_penable,
  input  [2:0]  in_pprot,
  input         in_pwrite,
  input  [31:0] in_pwdata,
  input  [3:0]  in_pstrb,
  output        in_pready,
  output [31:0] in_prdata,
  output        in_pslverr,

  input         ps2_clk,
  input         ps2_data
);

  localparam FIFO_DEPTH = 16;

  reg [2:0] ps2_clk_sync;
  reg [2:0] ps2_data_sync;
  reg [3:0] clk_history;
  reg       filtered_clk;
  reg       filtered_clk_d;

  reg       receiving;
  reg [3:0] bit_index;
  reg [7:0] shift_data;
  reg       parity_xor;
  reg       parity_ok;

  reg [7:0] fifo [0:FIFO_DEPTH-1];
  reg [3:0] write_pointer;
  reg [3:0] read_pointer;
  reg [4:0] fifo_count;
  reg       fifo_overflow;

  wire apb_access = in_psel && in_penable;
  wire fifo_pop = apb_access && !in_pwrite && !in_paddr[2] &&
                  (fifo_count != 0);
  wire filtered_falling = filtered_clk_d && !filtered_clk;

  assign in_pready = apb_access;
  assign in_pslverr = 1'b0;
  assign in_prdata = !in_psel ? 32'b0 :
                     !in_paddr[2] ?
                       ((fifo_count == 0) ? 32'b0 : {24'b0, fifo[read_pointer]}) :
                       {23'b0, fifo_overflow, 3'b0, fifo_count};

  always @(posedge clock) begin
    if (reset) begin
      ps2_clk_sync <= 3'b111;
      ps2_data_sync <= 3'b111;
      clk_history <= 4'hf;
      filtered_clk <= 1'b1;
      filtered_clk_d <= 1'b1;
      receiving <= 1'b0;
      bit_index <= 4'b0;
      shift_data <= 8'b0;
      parity_xor <= 1'b0;
      parity_ok <= 1'b0;
      write_pointer <= 4'b0;
      read_pointer <= 4'b0;
      fifo_count <= 5'b0;
      fifo_overflow <= 1'b0;
    end else begin
      // Both PS/2 pins are asynchronous. The clock additionally passes a
      // four-sample glitch filter before falling edges are recognized. This
      // remains shorter than NVBoard's eleven-cycle PS/2 half-period.
      ps2_clk_sync <= {ps2_clk_sync[1:0], ps2_clk};
      ps2_data_sync <= {ps2_data_sync[1:0], ps2_data};
      clk_history <= {clk_history[2:0], ps2_clk_sync[2]};
      if (&clk_history) filtered_clk <= 1'b1;
      else if (~|clk_history) filtered_clk <= 1'b0;
      filtered_clk_d <= filtered_clk;

      if (fifo_pop) begin
        read_pointer <= read_pointer + 1'b1;
        fifo_count <= fifo_count - 1'b1;
      end

      // Offset +4 is a diagnostic status register. Any write clears its
      // sticky overflow flag; offset +0 remains a read/pop-only data port.
      if (apb_access && in_pwrite && in_paddr[2]) fifo_overflow <= 1'b0;

      if (filtered_falling) begin
        if (!receiving) begin
          // A frame begins only with a low start bit.
          if (!ps2_data_sync[2]) begin
            receiving <= 1'b1;
            bit_index <= 4'b0;
            parity_xor <= 1'b0;
            parity_ok <= 1'b0;
          end
        end else if (bit_index < 8) begin
          shift_data[bit_index[2:0]] <= ps2_data_sync[2];
          parity_xor <= parity_xor ^ ps2_data_sync[2];
          bit_index <= bit_index + 1'b1;
        end else if (bit_index == 8) begin
          // PS/2 uses odd parity across the data and parity bits.
          parity_ok <= parity_xor ^ ps2_data_sync[2];
          bit_index <= 4'd9;
        end else begin
          receiving <= 1'b0;
          if (ps2_data_sync[2] && parity_ok) begin
            // A simultaneous APB pop frees a slot and permits this push.
            if ((fifo_count < FIFO_DEPTH) || fifo_pop) begin
              fifo[write_pointer] <= shift_data;
              write_pointer <= write_pointer + 1'b1;
              // A push and pop in the same cycle leave the occupancy unchanged.
              if (fifo_pop) fifo_count <= fifo_count;
              else fifo_count <= fifo_count + 1'b1;
            end else begin
              fifo_overflow <= 1'b1;
            end
          end
        end
      end
    end
  end

endmodule
