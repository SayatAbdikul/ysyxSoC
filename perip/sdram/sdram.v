module sdram #(
  parameter REQUIRED_BURST_LENGTH = 2
)(
  input        clk,
  input        cke,
  input        cs,
  input        ras,
  input        cas,
  input        we,
  input [12:0] a,
  input [ 1:0] ba,
  input [ 1:0] dqm,
  inout [15:0] dq
);

  localparam BANKS = 4;
  localparam ROWS = 8192;
  localparam COLS = 512;
  localparam WORDS = BANKS * ROWS * COLS;

  localparam CMD_NOP       = 4'b0111;
  localparam CMD_ACTIVE    = 4'b0011;
  localparam CMD_READ      = 4'b0101;
  localparam CMD_WRITE     = 4'b0100;
  localparam CMD_TERMINATE = 4'b0110;
  localparam CMD_PRECHARGE = 4'b0010;
  localparam CMD_REFRESH   = 4'b0001;
  localparam CMD_LOAD_MODE = 4'b0000;

  // Four banks x 8192 rows x 512 columns x 16 bits = 32 MiB. The array is
  // deliberately not initialized: SDRAM contents are undefined at power-on.
  reg [15:0] memory [0:WORDS-1];

  reg [3:0] row_open;
  reg [12:0] active_row [0:BANKS-1];

  reg [3:0] burst_length;
  reg [2:0] cas_latency;
  reg       interleaved_burst;

  reg       read_pending;
  reg       read_active;
  reg [2:0] read_latency_left;
  reg [3:0] read_beats_left;
  reg [1:0] read_bank;
  reg [12:0] read_row;
  reg [8:0] read_column;
  reg [1:0] read_dqm;
  reg       read_auto_precharge;

  reg       write_active;
  reg [3:0] write_beats_left;
  reg [1:0] write_bank;
  reg [12:0] write_row;
  reg [8:0] write_column;
  reg       write_auto_precharge;

  reg [15:0] dq_out;
  reg [1:0]  dq_oe;
  assign dq[7:0]  = dq_oe[0] ? dq_out[7:0]  : 8'bz;
  assign dq[15:8] = dq_oe[1] ? dq_out[15:8] : 8'bz;

  wire [3:0] command = {cs, ras, cas, we};

  integer command_inhibit_count;
  integer command_nop_count;
  integer command_active_count;
  integer command_read_count;
  integer command_write_count;
  integer command_terminate_count;
  integer command_precharge_count;
  integer command_refresh_count;
  integer command_load_mode_count;

  integer i;
  integer index;

  function integer memory_index;
    input [1:0] bank;
    input [12:0] row;
    input [8:0] column;
    integer bank_index;
    integer row_index;
    integer column_index;
    begin
      bank_index = {30'b0, bank};
      row_index = {19'b0, row};
      column_index = {23'b0, column};
      memory_index = ((bank_index * ROWS) + row_index) * COLS + column_index;
    end
  endfunction

  task write_beat;
    input [1:0] bank;
    input [12:0] row;
    input [8:0] column;
    input [15:0] value;
    input [1:0] mask;
    begin
      index = memory_index(bank, row, column);
      if (!mask[0]) memory[index][7:0] = value[7:0];
      if (!mask[1]) memory[index][15:8] = value[15:8];
    end
  endtask

  // Initialize protocol metadata and bus ownership only. Do not initialize
  // the storage array.
  initial begin
    row_open = 4'b0;
    for (i = 0; i < BANKS; i = i + 1)
      active_row[i] = 13'b0;
    burst_length = REQUIRED_BURST_LENGTH;
    cas_latency = 3'd2;
    interleaved_burst = 1'b0;
    read_pending = 1'b0;
    read_active = 1'b0;
    read_latency_left = 3'b0;
    read_beats_left = 4'b0;
    read_bank = 2'b0;
    read_row = 13'b0;
    read_column = 9'b0;
    read_dqm = 2'b0;
    read_auto_precharge = 1'b0;
    write_active = 1'b0;
    write_beats_left = 4'b0;
    write_bank = 2'b0;
    write_row = 13'b0;
    write_column = 9'b0;
    write_auto_precharge = 1'b0;
    dq_out = 16'b0;
    dq_oe = 2'b0;
    command_inhibit_count = 0;
    command_nop_count = 0;
    command_active_count = 0;
    command_read_count = 0;
    command_write_count = 0;
    command_terminate_count = 0;
    command_precharge_count = 0;
    command_refresh_count = 0;
    command_load_mode_count = 0;
  end

  // The supplied controller drives sdram_clk_o = ~clock and changes command
  // and write-data registers on the falling edge of this external clock. The
  // SDRAM model therefore decodes commands and captures writes here.
  always @(posedge clk) begin
    dq_oe <= 2'b0;

    if (!cke) begin
      // CKE gates command decoding and burst progress; it does not alter the
      // stored mode, open rows, or an in-flight transaction.
      dq_oe <= 2'b0;
    end else begin
      // Continue a previously accepted WRITE burst. The command cycle itself
      // captured beat zero; following NOP cycles carry the remaining beats.
      if (write_active && command != CMD_TERMINATE) begin
        write_beat(write_bank, write_row, write_column, dq, dqm);
        write_column <= write_column + 1'b1;
        if (write_beats_left == 4'd1) begin
          write_active <= 1'b0;
          if (write_auto_precharge)
            row_open[write_bank] <= 1'b0;
        end else begin
          write_beats_left <= write_beats_left - 1'b1;
        end
      end

      // CL=2 in this controller/model pairing means one intervening SDRAM
      // rising edge. Driving after that edge makes each beat stable for the
      // controller's following falling-edge input pipeline.
      if (read_pending && command != CMD_TERMINATE) begin
        if (read_latency_left > 3'd1) begin
          read_latency_left <= read_latency_left - 1'b1;
        end else begin
          dq_out <= memory[memory_index(read_bank, read_row, read_column)];
          dq_oe <= ~read_dqm;
          read_pending <= 1'b0;
          read_column <= read_column + 1'b1;
          if (read_beats_left == 4'd1) begin
            if (read_auto_precharge)
              row_open[read_bank] <= 1'b0;
          end else begin
            read_active <= 1'b1;
            read_beats_left <= read_beats_left - 1'b1;
          end
        end
      end else if (read_active && command != CMD_TERMINATE) begin
        dq_out <= memory[memory_index(read_bank, read_row, read_column)];
        dq_oe <= ~read_dqm;
        read_column <= read_column + 1'b1;
        if (read_beats_left == 4'd1) begin
          read_active <= 1'b0;
          if (read_auto_precharge)
            row_open[read_bank] <= 1'b0;
        end else begin
          read_beats_left <= read_beats_left - 1'b1;
        end
      end

      casez (command)
        4'b1???: begin
          command_inhibit_count <= command_inhibit_count + 1;
        end
        CMD_NOP: begin
          command_nop_count <= command_nop_count + 1;
        end
        CMD_ACTIVE: begin
          command_active_count <= command_active_count + 1;
`ifndef SYNTHESIS
          assert (!row_open[ba])
            else $error("sdram: ACTIVE issued to already-open bank %0d", ba);
`endif
          row_open[ba] <= 1'b1;
          active_row[ba] <= a;
        end
        CMD_READ: begin
          command_read_count <= command_read_count + 1;
`ifndef SYNTHESIS
          assert (row_open[ba])
            else $error("sdram: READ issued to closed bank %0d", ba);
`endif
          read_pending <= 1'b1;
          read_active <= 1'b0;
          read_latency_left <= cas_latency - 1'b1;
          read_beats_left <= burst_length;
          read_bank <= ba;
          read_row <= active_row[ba];
          read_column <= a[8:0];
          read_dqm <= dqm;
          read_auto_precharge <= a[10];
        end
        CMD_WRITE: begin
          command_write_count <= command_write_count + 1;
`ifndef SYNTHESIS
          assert (row_open[ba])
            else $error("sdram: WRITE issued to closed bank %0d", ba);
`endif
          write_beat(ba, active_row[ba], a[8:0], dq, dqm);
          write_bank <= ba;
          write_row <= active_row[ba];
          write_column <= a[8:0] + 1'b1;
          write_auto_precharge <= a[10];
          if (burst_length > 4'd1) begin
            write_active <= 1'b1;
            write_beats_left <= burst_length - 1'b1;
          end else if (a[10]) begin
            row_open[ba] <= 1'b0;
          end
        end
        CMD_TERMINATE: begin
          command_terminate_count <= command_terminate_count + 1;
          read_pending <= 1'b0;
          read_active <= 1'b0;
          write_active <= 1'b0;
          dq_oe <= 2'b0;
        end
        CMD_PRECHARGE: begin
          command_precharge_count <= command_precharge_count + 1;
          if (a[10])
            row_open <= 4'b0;
          else
            row_open[ba] <= 1'b0;
          if (a[10] || read_bank == ba) begin
            read_pending <= 1'b0;
            read_active <= 1'b0;
            dq_oe <= 2'b0;
          end
          if (a[10] || write_bank == ba)
            write_active <= 1'b0;
        end
        CMD_REFRESH: begin
          command_refresh_count <= command_refresh_count + 1;
        end
        CMD_LOAD_MODE: begin
          command_load_mode_count <= command_load_mode_count + 1;
          interleaved_burst <= a[3];
          cas_latency <= a[6:4];
          case (a[2:0])
            3'b000: burst_length <= 4'd1;
            3'b001: burst_length <= 4'd2;
            3'b010: burst_length <= 4'd4;
            3'b011: burst_length <= 4'd8;
            default: burst_length <= 4'd0;
          endcase
`ifndef SYNTHESIS
          assert (((REQUIRED_BURST_LENGTH == 1 && a[2:0] == 3'b000) ||
                   (REQUIRED_BURST_LENGTH == 2 && a[2:0] == 3'b001)) &&
                  a[3] == 1'b0 && a[6:4] == 3'b010)
            else $error("sdram: unsupported mode BL=%03b type=%0b CL=%03b",
                        a[2:0], a[3], a[6:4]);
`endif
        end
        default: begin
        end
      endcase
    end
  end

endmodule
