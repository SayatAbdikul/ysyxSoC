`ifndef APB_DELAY_RATIO_NUM
`define APB_DELAY_RATIO_NUM 1
`endif

`ifndef APB_DELAY_RATIO_SHIFT
`define APB_DELAY_RATIO_SHIFT 0
`endif

module apb_delayer #(
  parameter [31:0] RATIO_NUM = `APB_DELAY_RATIO_NUM,
  parameter integer RATIO_SHIFT = `APB_DELAY_RATIO_SHIFT
) (
  input         clock,
  input         reset,
  input  [31:0] in_paddr,
  input         in_psel,
  input         in_penable,
  input  [2:0]  in_pprot,
  input         in_pwrite,
  input  [31:0] in_pwdata,
  input  [3:0]  in_pstrb,
  output reg        in_pready,
  output reg [31:0] in_prdata,
  output reg        in_pslverr,

  output reg [31:0] out_paddr,
  output reg        out_psel,
  output reg        out_penable,
  output reg [2:0]  out_pprot,
  output reg        out_pwrite,
  output reg [31:0] out_pwdata,
  output reg [3:0]  out_pstrb,
  input         out_pready,
  input  [31:0] out_prdata,
  input         out_pslverr
);

  localparam [1:0] S_IDLE   = 2'd0;
  localparam [1:0] S_ACCESS = 2'd1;
  localparam [1:0] S_DELAY  = 2'd2;

  reg [1:0] state;
  reg [31:0] request_paddr;
  reg [2:0]  request_pprot;
  reg        request_pwrite;
  reg [31:0] request_pwdata;
  reg [3:0]  request_pstrb;
  reg [31:0] response_prdata;
  reg        response_pslverr;
  reg [63:0] elapsed_cycles;
  reg [63:0] delay_remaining;

  wire setup = in_psel && !in_penable;
  wire upstream_access = in_psel && in_penable;
  wire downstream_complete = state == S_ACCESS && out_pready;
  wire [63:0] downstream_latency = elapsed_cycles + 64'd1;
  wire [127:0] latency_wide = {64'b0, downstream_latency};
  wire [127:0] ratio_wide = {96'b0, RATIO_NUM};
  wire [127:0] scaled_product = latency_wide * ratio_wide;
  localparam [127:0] ROUNDING_BIAS =
      RATIO_SHIFT == 0 ? 128'd0 : (128'd1 << (RATIO_SHIFT - 1));
  wire [127:0] scaled_wide =
      (scaled_product + ROUNDING_BIAS) >> RATIO_SHIFT;
  wire [63:0] scaled_latency = |scaled_wide[127:64]
      ? 64'hffff_ffff_ffff_ffff : scaled_wide[63:0];
  wire [63:0] target_latency = scaled_latency > downstream_latency
      ? scaled_latency : downstream_latency;
  wire [63:0] extra_delay = target_latency - downstream_latency;
  wire immediate_response = downstream_complete && extra_delay == 64'd0;
  wire delayed_response = state == S_DELAY && delay_remaining == 64'd1;

  always @(*) begin
    in_pready = 1'b0;
    in_prdata = 32'b0;
    in_pslverr = 1'b0;

    out_paddr = request_paddr;
    out_psel = 1'b0;
    out_penable = 1'b0;
    out_pprot = request_pprot;
    out_pwrite = request_pwrite;
    out_pwdata = request_pwdata;
    out_pstrb = request_pstrb;

    case (state)
      S_IDLE: begin
        if (setup) begin
          out_paddr = in_paddr;
          out_psel = 1'b1;
          out_penable = 1'b0;
          out_pprot = in_pprot;
          out_pwrite = in_pwrite;
          out_pwdata = in_pwdata;
          out_pstrb = in_pstrb;
        end
      end

      S_ACCESS: begin
        out_psel = 1'b1;
        out_penable = 1'b1;
        if (immediate_response && upstream_access) begin
          in_pready = 1'b1;
          in_prdata = out_prdata;
          in_pslverr = out_pslverr;
        end
      end

      S_DELAY: begin
        if (delayed_response && upstream_access) begin
          in_pready = 1'b1;
          in_prdata = response_prdata;
          in_pslverr = response_pslverr;
        end
      end

      default: begin
      end
    endcase
  end

  always @(posedge clock) begin
    if (reset) begin
      state <= S_IDLE;
      request_paddr <= 32'b0;
      request_pprot <= 3'b0;
      request_pwrite <= 1'b0;
      request_pwdata <= 32'b0;
      request_pstrb <= 4'b0;
      response_prdata <= 32'b0;
      response_pslverr <= 1'b0;
      elapsed_cycles <= 64'b0;
      delay_remaining <= 64'b0;
    end else begin
      case (state)
        S_IDLE: begin
          if (setup) begin
            request_paddr <= in_paddr;
            request_pprot <= in_pprot;
            request_pwrite <= in_pwrite;
            request_pwdata <= in_pwdata;
            request_pstrb <= in_pstrb;
            elapsed_cycles <= 64'b0;
            state <= S_ACCESS;
          end
        end

        S_ACCESS: begin
          if (out_pready) begin
            response_prdata <= out_prdata;
            response_pslverr <= out_pslverr;
            if (extra_delay == 64'd0) begin
              state <= S_IDLE;
            end else begin
              delay_remaining <= extra_delay;
              state <= S_DELAY;
            end
          end else begin
            elapsed_cycles <= elapsed_cycles + 64'd1;
          end
        end

        S_DELAY: begin
          if (delay_remaining > 64'd1) begin
            delay_remaining <= delay_remaining - 64'd1;
          end else if (delayed_response && upstream_access) begin
            delay_remaining <= 64'b0;
            state <= S_IDLE;
          end
        end

        default: begin
          state <= S_IDLE;
        end
      endcase
    end
  end

`ifndef SYNTHESIS
`ifndef YOSYS
  initial begin
    assert(RATIO_NUM != 0);
    assert(RATIO_SHIFT >= 0 && RATIO_SHIFT < 64);
  end

  always @(posedge clock) begin
    if (!reset) begin
      assert(!in_pready || upstream_access);

      if (state != S_IDLE) begin
        assert(upstream_access);
        assert(in_paddr == request_paddr);
        assert(in_pprot == request_pprot);
        assert(in_pwrite == request_pwrite);
        assert(in_pwdata == request_pwdata);
        assert(in_pstrb == request_pstrb);
      end

      if (state == S_ACCESS && out_psel && out_penable && !out_pready) begin
        assert(out_paddr == request_paddr);
        assert(out_pprot == request_pprot);
        assert(out_pwrite == request_pwrite);
        assert(out_pwdata == request_pwdata);
        assert(out_pstrb == request_pstrb);
      end

      if (state == S_DELAY) begin
        assert(!out_psel);
        assert(delay_remaining != 64'd0);
      end

      if (state == S_ACCESS && !out_pready) begin
        assert(elapsed_cycles != 64'hffff_ffff_ffff_ffff);
      end
    end
  end
`endif
`endif

endmodule
