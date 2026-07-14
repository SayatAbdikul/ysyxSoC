`timescale 1ns/1ps

module psram(
  input sck,
  input ce_n,
  inout [3:0] dio
);
  localparam PSRAM_BYTES = 1 << 22;

  localparam PH_IDLE  = 3'd0;
  localparam PH_CMD   = 3'd1;
  localparam PH_ADDR  = 3'd2;
  localparam PH_DUMMY = 3'd3;
  localparam PH_READ  = 3'd4;
  localparam PH_WRITE = 3'd5;

  reg [7:0] memory [0:PSRAM_BYTES-1];
  wire [3:0] dio_in = dio;

  reg  [3:0] dio_out;
  reg        dio_oe;
  assign dio = dio_oe ? dio_out : 4'bz;

  reg [2:0] phase;

  reg [7:0]  opcode_shift;
  reg [3:0]  command_count;

  reg [19:0] address_shift;
  reg [2:0]  address_count;
  reg [21:0] transaction_address;

  reg [2:0] dummy_count;

  reg [3:0] read_nibble_index;
  reg [2:0] write_nibble_index;
  reg [3:0] write_high_nibble;
  reg [2:0] write_byte_index;
  wire [21:0] read_byte_offset =
    {{19{1'b0}}, read_nibble_index[3:1]};
  wire [21:0] write_byte_offset = {{19{1'b0}}, write_byte_index};

  // Only the protocol state is initialized.  The memory array is deliberately
  // left uninitialized so software cannot depend on a power-on RAM value.
  initial begin
    phase               = PH_IDLE;
    opcode_shift        = 8'b0;
    command_count       = 4'b0;
    address_shift       = 20'b0;
    address_count       = 3'b0;
    transaction_address = 22'b0;
    dummy_count         = 3'b0;
    read_nibble_index   = 4'b0;
    write_nibble_index  = 3'b0;
    write_high_nibble   = 4'b0;
    write_byte_index    = 3'b0;
    dio_out             = 4'b0;
    dio_oe              = 1'b0;
  end

  // The controller changes its outputs on falling SCK edges.  Commands,
  // addresses, and write data are therefore sampled on rising SCK edges.
  // Read data is also selected here, leaving it stable for the controller's
  // following falling-edge sample.
  always @(posedge sck or posedge ce_n) begin
    if (ce_n) begin
      // Raising CE terminates (or aborts) every transaction immediately.
      phase              <= PH_IDLE;
      command_count      <= 4'b0;
      address_count      <= 3'b0;
      dummy_count        <= 3'b0;
      read_nibble_index  <= 4'b0;
      write_nibble_index <= 3'b0;
      write_byte_index   <= 3'b0;
      dio_oe             <= 1'b0;
      dio_out            <= 4'b0;
    end else begin
      case (phase)
        PH_IDLE: begin
          // Commands are single-bit SPI, MSB first, on DIO[0].
          opcode_shift  <= {7'b0, dio_in[0]};
          command_count <= 4'd1;
          phase         <= PH_CMD;
          dio_oe        <= 1'b0;
        end

        PH_CMD: begin
          opcode_shift <= {opcode_shift[6:0], dio_in[0]};
          if (command_count == 4'd7) begin
            command_count <= 4'b0;
            address_shift <= 20'b0;
            address_count <= 3'b0;
            if ({opcode_shift[6:0], dio_in[0]} == 8'heb)
              phase <= PH_ADDR;
            else if ({opcode_shift[6:0], dio_in[0]} == 8'h38)
              phase <= PH_ADDR;
            else begin
              $error("psram: unsupported command 0x%02x",
                     {opcode_shift[6:0], dio_in[0]});
              phase <= PH_IDLE;
            end
          end else begin
            command_count <= command_count + 1'b1;
          end
        end

        PH_ADDR: begin
          // The 24-bit address is transferred as six quad-data nibbles.
          address_shift <= {address_shift[15:0], dio_in};
          if (address_count == 3'd5) begin
            // This model contains 4 MiB, so only address bits [21:0] exist.
            if (address_shift[19:18] != 2'b00)
              $error("psram: address 0x%06x exceeds the 4 MiB device",
                     {address_shift[19:0], dio_in});
            transaction_address <= {address_shift[17:0], dio_in};
            address_count <= 3'b0;

            if (opcode_shift == 8'heb) begin
              // EBh has six dummy clocks after the address.
              dummy_count       <= 3'b0;
              read_nibble_index <= 4'b0;
              phase             <= PH_DUMMY;
            end else begin
              // 38h write data follows the address without dummy clocks.
              write_nibble_index <= 3'b0;
              write_byte_index   <= 3'b0;
              phase              <= PH_WRITE;
            end
          end else begin
            address_count <= address_count + 1'b1;
          end
        end

        PH_DUMMY: begin
          if (dummy_count == 3'd5) begin
            // Enable the PSRAM side only after all six dummy clocks.  The first
            // data nibble is selected on the next rising edge.
            read_nibble_index <= 4'b0;
            dio_oe            <= 1'b1;
            phase             <= PH_READ;
          end else begin
            dummy_count <= dummy_count + 1'b1;
          end
        end

        PH_READ: begin
          dio_oe <= 1'b1;
          if (read_nibble_index[0])
            dio_out <= memory[transaction_address + read_byte_offset][3:0];
          else
            dio_out <= memory[transaction_address + read_byte_offset][7:4];

          // EBh reads used by this SoC return four ascending bytes, high
          // nibble first.  Hold the final nibble until CE is released.
          if (read_nibble_index != 4'd7)
            read_nibble_index <= read_nibble_index + 1'b1;
        end

        PH_WRITE: begin
          // Commit only complete bytes.  The supplied controller may produce
          // a final unpaired high nibble while ending a transfer; CE aborts it
          // before it can alter memory.
          if (!write_nibble_index[0]) begin
            write_high_nibble <= dio_in;
          end else begin
            memory[transaction_address + write_byte_offset]
              <= {write_high_nibble, dio_in};
            write_byte_index <= write_byte_index + 1'b1;
          end
          write_nibble_index <= write_nibble_index + 1'b1;
        end

        default: begin
          phase  <= PH_IDLE;
          dio_oe <= 1'b0;
        end
      endcase
    end
  end
endmodule
