// define this macro to enable fast behavior simulation
// for flash by skipping SPI transfers
//`define FAST_FLASH

module spi_top_apb #(
  parameter flash_addr_start = 32'h30000000,
  parameter flash_addr_end   = 32'h3fffffff,
  parameter spi_ss_num       = 8
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
  output        in_pready,
  output [31:0] in_prdata,
  output        in_pslverr,

  output                  spi_sck,
  output [spi_ss_num-1:0] spi_ss,
  output                  spi_mosi,
  input                   spi_miso,
  output                  spi_irq_out
);

`ifdef FAST_FLASH

wire [31:0] data;
parameter invalid_cmd = 8'h0;
flash_cmd flash_cmd_i(
  .clock(clock),
  .valid(in_psel && !in_penable),
  .cmd(in_pwrite ? invalid_cmd : 8'h03),
  .addr({8'b0, in_paddr[23:2], 2'b0}),
  .data(data)
);
assign spi_sck    = 1'b0;
assign spi_ss     = 8'b0;
assign spi_mosi   = 1'b1;
assign spi_irq_out= 1'b0;
assign in_pslverr = 1'b0;
assign in_pready  = in_penable && in_psel && !in_pwrite;
assign in_prdata  = data >> (in_paddr[1:0] * 8);

`else

localparam [4:0]
  IDLE         = 5'd0,
  XIP_DIVIDER  = 5'd1,
  DIVIDER_GAP  = 5'd2,
  XIP_SS       = 5'd3,
  SS_GAP       = 5'd4,
  XIP_TX1      = 5'd5,
  TX1_GAP      = 5'd6,
  XIP_TX0      = 5'd7,
  TX0_GAP      = 5'd8,
  XIP_CTRL     = 5'd9,
  CTRL_GAP     = 5'd10,
  XIP_GO       = 5'd11,
  GO_GAP       = 5'd12,
  XIP_POLL     = 5'd13,
  POLL_GAP     = 5'd14,
  XIP_RX       = 5'd15,
  RX_GAP       = 5'd16,
  XIP_RESPONSE = 5'd17,
  XIP_ERROR    = 5'd18;

localparam [31:0]
  SPI_CTRL_CONFIG = 32'h00002440,
  SPI_CTRL_START  = 32'h00002540;

reg [4:0] state;
reg [31:0] xip_offset;
reg [1:0] xip_byte_offset;
reg [31:0] xip_rdata;
reg poll_complete;

reg  [4:0]  wb_addr;
reg  [31:0] wb_wdata;
reg  [3:0]  wb_sel;
reg         wb_we;
reg         wb_stb;
reg         wb_cyc;

wire [31:0] wb_rdata;
wire        wb_ack;
wire        wb_err;

reg         in_pready_r;
reg  [31:0] in_prdata_r;
reg         in_pslverr_r;

wire is_xip_addr =
    in_paddr >= flash_addr_start &&
    in_paddr <= flash_addr_end;

assign in_pready  = in_pready_r;
assign in_prdata  = in_prdata_r;
assign in_pslverr = in_pslverr_r;

always @(posedge clock or posedge reset) begin
  if (reset) begin
    state         <= IDLE;
    xip_offset    <= 32'b0;
    xip_byte_offset <= 2'b0;
    xip_rdata     <= 32'b0;
    poll_complete <= 1'b0;
  end else begin
    case (state)
      IDLE: begin
        if (in_psel && !in_penable && is_xip_addr) begin
          xip_offset <=
              (in_paddr - flash_addr_start) & 32'h00ff_fffc;
          xip_byte_offset <= in_paddr[1:0];
          state <= in_pwrite ? XIP_ERROR : XIP_DIVIDER;
        end
      end

      XIP_DIVIDER: if (wb_ack) state <= DIVIDER_GAP;
      DIVIDER_GAP: state <= XIP_SS;
      XIP_SS:      if (wb_ack) state <= SS_GAP;
      SS_GAP:      state <= XIP_TX1;
      XIP_TX1:     if (wb_ack) state <= TX1_GAP;
      TX1_GAP:     state <= XIP_TX0;
      XIP_TX0:     if (wb_ack) state <= TX0_GAP;
      TX0_GAP:     state <= XIP_CTRL;
      XIP_CTRL:    if (wb_ack) state <= CTRL_GAP;
      CTRL_GAP:    state <= XIP_GO;
      XIP_GO:      if (wb_ack) state <= GO_GAP;
      GO_GAP:      state <= XIP_POLL;

      XIP_POLL: begin
        if (wb_ack) begin
          poll_complete <= (wb_rdata[8] == 1'b0);
          state <= POLL_GAP;
        end
      end

      POLL_GAP: begin
        state <= poll_complete ? XIP_RX : XIP_POLL;
      end

      XIP_RX: begin
        if (wb_ack) begin
          xip_rdata <= {
            wb_rdata[7:0], wb_rdata[15:8],
            wb_rdata[23:16], wb_rdata[31:24]
          };
          state <= RX_GAP;
        end
      end

      RX_GAP: state <= XIP_RESPONSE;

      XIP_RESPONSE: begin
        if (in_psel && in_penable)
          state <= IDLE;
      end

      XIP_ERROR: begin
        if (in_psel && in_penable)
          state <= IDLE;
      end

      default: state <= IDLE;
    endcase
  end
end

always @(*) begin
  wb_addr  = 5'b0;
  wb_wdata = 32'b0;
  wb_sel   = 4'hf;
  wb_we    = 1'b0;
  wb_stb   = 1'b0;
  wb_cyc   = 1'b0;

  in_pready_r  = 1'b0;
  in_prdata_r  = 32'b0;
  in_pslverr_r = 1'b0;

  case (state)
    IDLE: begin
      if (!is_xip_addr) begin
        wb_addr  = in_paddr[4:0];
        wb_wdata = in_pwdata;
        wb_sel   = in_pstrb;
        wb_we    = in_pwrite;
        wb_stb   = in_psel;
        wb_cyc   = in_penable;

        in_pready_r  = wb_ack;
        in_prdata_r  = wb_rdata;
        in_pslverr_r = wb_err;
      end
    end

    XIP_DIVIDER: begin
      wb_addr  = 5'h14;
      wb_wdata = 32'h00000001;
      wb_we    = 1'b1;
      wb_stb   = 1'b1;
      wb_cyc   = 1'b1;
    end

    XIP_SS: begin
      wb_addr  = 5'h18;
      wb_wdata = 32'h00000001;
      wb_we    = 1'b1;
      wb_stb   = 1'b1;
      wb_cyc   = 1'b1;
    end

    XIP_TX1: begin
      wb_addr  = 5'h04;
      wb_wdata = 32'h03000000 | xip_offset;
      wb_we    = 1'b1;
      wb_stb   = 1'b1;
      wb_cyc   = 1'b1;
    end

    XIP_TX0: begin
      wb_addr  = 5'h00;
      wb_wdata = 32'b0;
      wb_we    = 1'b1;
      wb_stb   = 1'b1;
      wb_cyc   = 1'b1;
    end

    XIP_CTRL: begin
      wb_addr  = 5'h10;
      wb_wdata = SPI_CTRL_CONFIG;
      wb_we    = 1'b1;
      wb_stb   = 1'b1;
      wb_cyc   = 1'b1;
    end

    XIP_GO: begin
      wb_addr  = 5'h10;
      wb_wdata = SPI_CTRL_START;
      wb_we    = 1'b1;
      wb_stb   = 1'b1;
      wb_cyc   = 1'b1;
    end

    XIP_POLL: begin
      wb_addr = 5'h10;
      wb_stb  = 1'b1;
      wb_cyc  = 1'b1;
    end

    XIP_RX: begin
      wb_addr = 5'h00;
      wb_stb  = 1'b1;
      wb_cyc  = 1'b1;
    end

    XIP_RESPONSE: begin
      in_pready_r = in_psel && in_penable;
      in_prdata_r = xip_rdata >> (xip_byte_offset * 8);
    end

    XIP_ERROR: begin
      in_pready_r  = in_psel && in_penable;
      in_pslverr_r = in_psel && in_penable;
    end

    default: begin
    end
  endcase
end

spi_top u0_spi_top (
  .wb_clk_i(clock),
  .wb_rst_i(reset),
  .wb_adr_i(wb_addr),
  .wb_dat_i(wb_wdata),
  .wb_dat_o(wb_rdata),
  .wb_sel_i(wb_sel),
  .wb_we_i(wb_we),
  .wb_stb_i(wb_stb),
  .wb_cyc_i(wb_cyc),
  .wb_ack_o(wb_ack),
  .wb_err_o(wb_err),
  .wb_int_o(spi_irq_out),

  .ss_pad_o(spi_ss),
  .sclk_pad_o(spi_sck),
  .mosi_pad_o(spi_mosi),
  .miso_pad_i(spi_miso)
);

`endif // FAST_FLASH

endmodule
