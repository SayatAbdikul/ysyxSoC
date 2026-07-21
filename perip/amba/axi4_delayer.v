`ifndef AXI_DELAY_RATIO_NUM
`define AXI_DELAY_RATIO_NUM 1
`endif

`ifndef AXI_DELAY_RATIO_SHIFT
`define AXI_DELAY_RATIO_SHIFT 0
`endif

module axi4_delayer #(
  parameter [31:0] RATIO_NUM = `AXI_DELAY_RATIO_NUM,
  parameter integer RATIO_SHIFT = `AXI_DELAY_RATIO_SHIFT
) (
  input         clock,
  input         reset,

  output        in_aw_ready,
  input         in_aw_valid,
  input  [3:0]  in_aw_bits_id,
  input  [31:0] in_aw_bits_addr,
  input  [7:0]  in_aw_bits_len,
  input  [2:0]  in_aw_bits_size,
  input  [1:0]  in_aw_bits_burst,
  input         in_aw_bits_lock,
  input  [3:0]  in_aw_bits_cache,
  input  [2:0]  in_aw_bits_prot,
  input  [3:0]  in_aw_bits_qos,
  output        in_w_ready,
  input         in_w_valid,
  input  [31:0] in_w_bits_data,
  input  [3:0]  in_w_bits_strb,
  input         in_w_bits_last,
  input         in_b_ready,
  output        in_b_valid,
  output [3:0]  in_b_bits_id,
  output [1:0]  in_b_bits_resp,
  output        in_ar_ready,
  input         in_ar_valid,
  input  [3:0]  in_ar_bits_id,
  input  [31:0] in_ar_bits_addr,
  input  [7:0]  in_ar_bits_len,
  input  [2:0]  in_ar_bits_size,
  input  [1:0]  in_ar_bits_burst,
  input         in_ar_bits_lock,
  input  [3:0]  in_ar_bits_cache,
  input  [2:0]  in_ar_bits_prot,
  input  [3:0]  in_ar_bits_qos,
  input         in_r_ready,
  output        in_r_valid,
  output [3:0]  in_r_bits_id,
  output [31:0] in_r_bits_data,
  output [1:0]  in_r_bits_resp,
  output        in_r_bits_last,

  input         out_aw_ready,
  output        out_aw_valid,
  output [3:0]  out_aw_bits_id,
  output [31:0] out_aw_bits_addr,
  output [7:0]  out_aw_bits_len,
  output [2:0]  out_aw_bits_size,
  output [1:0]  out_aw_bits_burst,
  output        out_aw_bits_lock,
  output [3:0]  out_aw_bits_cache,
  output [2:0]  out_aw_bits_prot,
  output [3:0]  out_aw_bits_qos,
  input         out_w_ready,
  output        out_w_valid,
  output [31:0] out_w_bits_data,
  output [3:0]  out_w_bits_strb,
  output        out_w_bits_last,
  output        out_b_ready,
  input         out_b_valid,
  input  [3:0]  out_b_bits_id,
  input  [1:0]  out_b_bits_resp,
  input         out_ar_ready,
  output        out_ar_valid,
  output [3:0]  out_ar_bits_id,
  output [31:0] out_ar_bits_addr,
  output [7:0]  out_ar_bits_len,
  output [2:0]  out_ar_bits_size,
  output [1:0]  out_ar_bits_burst,
  output        out_ar_bits_lock,
  output [3:0]  out_ar_bits_cache,
  output [2:0]  out_ar_bits_prot,
  output [3:0]  out_ar_bits_qos,
  output        out_r_ready,
  input         out_r_valid,
  input  [3:0]  out_r_bits_id,
  input  [31:0] out_r_bits_data,
  input  [1:0]  out_r_bits_resp,
  input         out_r_bits_last
);

  localparam integer READ_FIFO_DEPTH = 8;
  localparam [3:0] READ_FIFO_DEPTH_COUNT = 4'd8;
  localparam [127:0] ROUNDING_BIAS = RATIO_SHIFT == 0
      ? 128'd0 : (128'd1 << (RATIO_SHIFT - 1));

  reg [63:0] cycle_count;

  reg        read_active;
  reg        read_ar_done;
  reg [63:0] read_t0;
  reg [8:0]  read_expected_beats;
  reg [8:0]  read_received_beats;

  reg [3:0]  read_id_fifo [0:READ_FIFO_DEPTH-1];
  reg [31:0] read_data_fifo [0:READ_FIFO_DEPTH-1];
  reg [1:0]  read_resp_fifo [0:READ_FIFO_DEPTH-1];
  reg        read_last_fifo [0:READ_FIFO_DEPTH-1];
  reg [63:0] read_due_fifo [0:READ_FIFO_DEPTH-1];
  reg [2:0]  read_head;
  reg [2:0]  read_tail;
  reg [3:0]  read_count;

  reg        write_active;
  reg        write_aw_done;
  reg        write_w_done;
  reg [63:0] write_t0;
  reg        write_b_pending;
  reg [3:0]  write_b_id;
  reg [1:0]  write_b_resp;
  reg [63:0] write_b_due;

  function [63:0] calibrated_cycle;
    input [63:0] start_cycle;
    input [63:0] event_cycle;
    reg [63:0] elapsed;
    reg [127:0] product;
    reg [127:0] scaled;
    reg [63:0] target_elapsed;
    begin
      elapsed = event_cycle - start_cycle;
      product = elapsed * RATIO_NUM;
      scaled = (product + ROUNDING_BIAS) >> RATIO_SHIFT;
      if (|scaled[127:64]) begin
        target_elapsed = 64'hffff_ffff_ffff_ffff;
      end else if (scaled[63:0] < elapsed) begin
        target_elapsed = elapsed;
      end else begin
        target_elapsed = scaled[63:0];
      end
      if (64'hffff_ffff_ffff_ffff - start_cycle < target_elapsed) begin
        calibrated_cycle = 64'hffff_ffff_ffff_ffff;
      end else begin
        calibrated_cycle = start_cycle + target_elapsed;
      end
    end
  endfunction

  wire read_start = in_ar_valid && !read_active;
  wire read_ar_fire = out_ar_valid && out_ar_ready;
  wire [63:0] live_read_due = calibrated_cycle(read_t0, cycle_count);
  wire queued_read_valid = read_count != 4'd0 &&
      cycle_count >= read_due_fifo[read_head];
  wire live_read_valid = read_count == 4'd0 && out_r_valid && read_active &&
      cycle_count >= live_read_due;

  assign in_ar_ready = !read_ar_done && out_ar_ready;
  assign out_ar_valid = !read_ar_done && in_ar_valid;
  assign out_ar_bits_id = in_ar_bits_id;
  assign out_ar_bits_addr = in_ar_bits_addr;
  assign out_ar_bits_len = in_ar_bits_len;
  assign out_ar_bits_size = in_ar_bits_size;
  assign out_ar_bits_burst = in_ar_bits_burst;
  assign out_ar_bits_lock = in_ar_bits_lock;
  assign out_ar_bits_cache = in_ar_bits_cache;
  assign out_ar_bits_prot = in_ar_bits_prot;
  assign out_ar_bits_qos = in_ar_bits_qos;

  assign out_r_ready = read_active && read_count < READ_FIFO_DEPTH_COUNT;
  assign in_r_valid = queued_read_valid || live_read_valid;
  assign in_r_bits_id = queued_read_valid
      ? read_id_fifo[read_head] : out_r_bits_id;
  assign in_r_bits_data = queued_read_valid
      ? read_data_fifo[read_head] : out_r_bits_data;
  assign in_r_bits_resp = queued_read_valid
      ? read_resp_fifo[read_head] : out_r_bits_resp;
  assign in_r_bits_last = queued_read_valid
      ? read_last_fifo[read_head] : out_r_bits_last;

  wire downstream_read_fire = out_r_valid && out_r_ready;
  wire upstream_read_fire = in_r_valid && in_r_ready;
  wire direct_read_fire = live_read_valid && in_r_ready;
  wire queued_read_pop = queued_read_valid && in_r_ready;
  wire queued_read_push = downstream_read_fire && !direct_read_fire;

  wire write_start = (in_aw_valid || in_w_valid) && !write_active;
  wire write_aw_fire = out_aw_valid && out_aw_ready;
  wire write_w_fire = out_w_valid && out_w_ready;
  wire [63:0] live_write_due = calibrated_cycle(write_t0, cycle_count);
  wire queued_write_valid = write_b_pending && cycle_count >= write_b_due;
  wire live_write_valid = !write_b_pending && out_b_valid && write_active &&
      cycle_count >= live_write_due;

  assign in_aw_ready = !write_aw_done && out_aw_ready;
  assign out_aw_valid = !write_aw_done && in_aw_valid;
  assign out_aw_bits_id = in_aw_bits_id;
  assign out_aw_bits_addr = in_aw_bits_addr;
  assign out_aw_bits_len = in_aw_bits_len;
  assign out_aw_bits_size = in_aw_bits_size;
  assign out_aw_bits_burst = in_aw_bits_burst;
  assign out_aw_bits_lock = in_aw_bits_lock;
  assign out_aw_bits_cache = in_aw_bits_cache;
  assign out_aw_bits_prot = in_aw_bits_prot;
  assign out_aw_bits_qos = in_aw_bits_qos;
  assign in_w_ready = !write_w_done && out_w_ready;
  assign out_w_valid = !write_w_done && in_w_valid;
  assign out_w_bits_data = in_w_bits_data;
  assign out_w_bits_strb = in_w_bits_strb;
  assign out_w_bits_last = in_w_bits_last;
  assign out_b_ready = write_active && !write_b_pending;
  assign in_b_valid = queued_write_valid || live_write_valid;
  assign in_b_bits_id = queued_write_valid ? write_b_id : out_b_bits_id;
  assign in_b_bits_resp = queued_write_valid ? write_b_resp : out_b_bits_resp;

  wire downstream_write_fire = out_b_valid && out_b_ready;
  wire direct_write_fire = live_write_valid && in_b_ready;
  wire upstream_write_fire = in_b_valid && in_b_ready;

  integer fifo_index;
  always @(posedge clock) begin
    if (reset) begin
      cycle_count <= 64'd0;
      read_active <= 1'b0;
      read_ar_done <= 1'b0;
      read_t0 <= 64'd0;
      read_expected_beats <= 9'd0;
      read_received_beats <= 9'd0;
      read_head <= 3'd0;
      read_tail <= 3'd0;
      read_count <= 4'd0;
      write_active <= 1'b0;
      write_aw_done <= 1'b0;
      write_w_done <= 1'b0;
      write_t0 <= 64'd0;
      write_b_pending <= 1'b0;
      write_b_id <= 4'd0;
      write_b_resp <= 2'd0;
      write_b_due <= 64'd0;
      for (fifo_index = 0; fifo_index < READ_FIFO_DEPTH;
           fifo_index = fifo_index + 1) begin
        read_id_fifo[fifo_index] <= 4'd0;
        read_data_fifo[fifo_index] <= 32'd0;
        read_resp_fifo[fifo_index] <= 2'd0;
        read_last_fifo[fifo_index] <= 1'b0;
        read_due_fifo[fifo_index] <= 64'd0;
      end
    end else begin
      cycle_count <= cycle_count + 64'd1;

      if (read_start) begin
        read_active <= 1'b1;
        read_t0 <= cycle_count;
        read_received_beats <= 9'd0;
      end
      if (read_ar_fire) begin
        read_ar_done <= 1'b1;
        read_expected_beats <= {1'b0, in_ar_bits_len} + 9'd1;
      end

      if (queued_read_push) begin
        read_id_fifo[read_tail] <= out_r_bits_id;
        read_data_fifo[read_tail] <= out_r_bits_data;
        read_resp_fifo[read_tail] <= out_r_bits_resp;
        read_last_fifo[read_tail] <= out_r_bits_last;
        read_due_fifo[read_tail] <= live_read_due;
        read_tail <= read_tail + 3'd1;
      end
      if (queued_read_pop) begin
        read_head <= read_head + 3'd1;
      end
      case ({queued_read_push, queued_read_pop})
        2'b10: read_count <= read_count + 4'd1;
        2'b01: read_count <= read_count - 4'd1;
        default: read_count <= read_count;
      endcase
      if (downstream_read_fire) begin
        read_received_beats <= read_received_beats + 9'd1;
      end
      if (upstream_read_fire && in_r_bits_last) begin
        read_active <= 1'b0;
        read_ar_done <= 1'b0;
        read_expected_beats <= 9'd0;
        read_received_beats <= 9'd0;
      end

      if (write_start) begin
        write_active <= 1'b1;
        write_t0 <= cycle_count;
      end
      if (write_aw_fire) begin
        write_aw_done <= 1'b1;
      end
      if (write_w_fire) begin
        write_w_done <= 1'b1;
      end
      if (downstream_write_fire && !direct_write_fire) begin
        write_b_pending <= 1'b1;
        write_b_id <= out_b_bits_id;
        write_b_resp <= out_b_bits_resp;
        write_b_due <= live_write_due;
      end
      if (upstream_write_fire) begin
        write_active <= 1'b0;
        write_aw_done <= 1'b0;
        write_w_done <= 1'b0;
        write_b_pending <= 1'b0;
      end
    end
  end

`ifndef SYNTHESIS
`ifndef YOSYS
  reg previous_ar_stall;
  reg [60:0] previous_ar_payload;
  reg previous_aw_stall;
  reg [60:0] previous_aw_payload;
  reg previous_w_stall;
  reg [36:0] previous_w_payload;
  reg previous_r_stall;
  reg [38:0] previous_r_payload;
  reg previous_b_stall;
  reg [5:0] previous_b_payload;

  initial begin
    assert(RATIO_NUM != 0);
    assert(RATIO_SHIFT >= 0 && RATIO_SHIFT < 64);
    assert({32'd0, RATIO_NUM} >= (64'd1 << RATIO_SHIFT));
  end

  always @(posedge clock) begin
    if (reset) begin
      previous_ar_stall <= 1'b0;
      previous_ar_payload <= 61'd0;
      previous_aw_stall <= 1'b0;
      previous_aw_payload <= 61'd0;
      previous_w_stall <= 1'b0;
      previous_w_payload <= 37'd0;
      previous_r_stall <= 1'b0;
      previous_r_payload <= 39'd0;
      previous_b_stall <= 1'b0;
      previous_b_payload <= 6'd0;
    end else begin
      assert(read_count <= READ_FIFO_DEPTH_COUNT);
      assert(!out_r_valid || read_active);
      assert(!in_r_valid || read_active);
      assert(!out_b_valid || write_active);
      assert(!in_b_valid || write_active);

      if (read_ar_fire) begin
        assert(in_ar_bits_len < 8'd8);
      end
      if (downstream_read_fire) begin
        assert(read_ar_done);
        assert(out_r_bits_last ==
            (read_received_beats + 9'd1 == read_expected_beats));
      end
      if (write_aw_fire) begin
        assert(in_aw_bits_len == 8'd0);
      end
      if (write_w_fire) begin
        assert(in_w_bits_last);
      end

      if (previous_ar_stall) begin
        assert(out_ar_valid);
        assert({out_ar_bits_id, out_ar_bits_addr, out_ar_bits_len,
                out_ar_bits_size, out_ar_bits_burst, out_ar_bits_lock,
                out_ar_bits_cache, out_ar_bits_prot, out_ar_bits_qos} ==
            previous_ar_payload);
      end
      if (previous_aw_stall) begin
        assert(out_aw_valid);
        assert({out_aw_bits_id, out_aw_bits_addr, out_aw_bits_len,
                out_aw_bits_size, out_aw_bits_burst, out_aw_bits_lock,
                out_aw_bits_cache, out_aw_bits_prot, out_aw_bits_qos} ==
            previous_aw_payload);
      end
      if (previous_w_stall) begin
        assert(out_w_valid);
        assert({out_w_bits_data, out_w_bits_strb, out_w_bits_last} ==
            previous_w_payload);
      end
      if (previous_r_stall) begin
        assert(in_r_valid);
        assert({in_r_bits_id, in_r_bits_data, in_r_bits_resp,
                in_r_bits_last} == previous_r_payload);
      end
      if (previous_b_stall) begin
        assert(in_b_valid);
        assert({in_b_bits_id, in_b_bits_resp} == previous_b_payload);
      end

      previous_ar_stall <= out_ar_valid && !out_ar_ready;
      previous_ar_payload <= {out_ar_bits_id, out_ar_bits_addr,
          out_ar_bits_len, out_ar_bits_size, out_ar_bits_burst,
          out_ar_bits_lock, out_ar_bits_cache, out_ar_bits_prot,
          out_ar_bits_qos};
      previous_aw_stall <= out_aw_valid && !out_aw_ready;
      previous_aw_payload <= {out_aw_bits_id, out_aw_bits_addr,
          out_aw_bits_len, out_aw_bits_size, out_aw_bits_burst,
          out_aw_bits_lock, out_aw_bits_cache, out_aw_bits_prot,
          out_aw_bits_qos};
      previous_w_stall <= out_w_valid && !out_w_ready;
      previous_w_payload <= {out_w_bits_data, out_w_bits_strb,
          out_w_bits_last};
      previous_r_stall <= in_r_valid && !in_r_ready;
      previous_r_payload <= {in_r_bits_id, in_r_bits_data,
          in_r_bits_resp, in_r_bits_last};
      previous_b_stall <= in_b_valid && !in_b_ready;
      previous_b_payload <= {in_b_bits_id, in_b_bits_resp};
    end
  end
`endif
`endif

endmodule
