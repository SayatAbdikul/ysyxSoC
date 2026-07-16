module psram_top_apb #(
`ifdef YSYXSOC_PSRAM_QPI
  parameter QPI_MODE = 1'b1
`else
  parameter QPI_MODE = 1'b0
`endif
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

  output qspi_sck,
  output qspi_ce_n,
  inout  [3:0] qspi_dio
);

  wire [3:0] din, dout, douten;
  wire ack;

`ifndef SYNTHESIS
  function automatic legal_write_strobe;
    input [3:0] strobe;
    begin
      case (strobe)
        4'b0001, 4'b0010, 4'b0100, 4'b1000,
        4'b0011, 4'b1100, 4'b1111: legal_write_strobe = 1'b1;
        default: legal_write_strobe = 1'b0;
      endcase
    end
  endfunction

  reg        apb_active;
  reg [31:0] accepted_paddr;
  reg        accepted_pwrite;
  reg [31:0] accepted_pwdata;
  reg [3:0]  accepted_pstrb;

  // This supplied bridge launches its internal controller from APB setup.
  // These checks make that exception explicit while enforcing the externally
  // visible APB contract: exactly one setup, stable access payload, and an
  // access-phase-only completion.
  always @(posedge clock or posedge reset) begin
    if (reset) begin
      apb_active <= 1'b0;
      accepted_paddr <= 32'b0;
      accepted_pwrite <= 1'b0;
      accepted_pwdata <= 32'b0;
      accepted_pstrb <= 4'b0;
    end else if (!apb_active) begin
      if (in_psel) begin
        assert (!in_penable)
          else $error("psram_top_apb: transaction did not start in setup phase");
        assert (!in_pwrite || legal_write_strobe(in_pstrb))
          else $error("psram_top_apb: unsupported PSTRB %b", in_pstrb);
        apb_active <= 1'b1;
        accepted_paddr <= in_paddr;
        accepted_pwrite <= in_pwrite;
        accepted_pwdata <= in_pwdata;
        accepted_pstrb <= in_pstrb;
      end
      assert (!(ack && in_psel))
        else $error("psram_top_apb: completion without an active APB transfer");
    end else begin
      assert (in_psel && in_penable)
        else $error("psram_top_apb: APB access phase was not held active");
      assert (in_paddr == accepted_paddr &&
              in_pwrite == accepted_pwrite &&
              in_pwdata == accepted_pwdata &&
              in_pstrb == accepted_pstrb)
        else $error("psram_top_apb: APB payload changed during access");
      if (ack) begin
        assert (in_psel && in_penable)
          else $error("psram_top_apb: completion occurred outside access phase");
        apb_active <= 1'b0;
      end
    end
  end
`endif

  EF_PSRAM_CTRL_wb #(.QPI_MODE(QPI_MODE)) u0 (
    .clk_i(clock),
    .rst_i(reset),
    .adr_i(in_paddr),
    .dat_i(in_pwdata),
    .dat_o(in_prdata),
    .sel_i(in_pstrb),
    .cyc_i(in_psel),
    .stb_i(in_psel),
    .ack_o(ack),
    .we_i(in_pwrite),
  
    .sck(qspi_sck),
    .ce_n(qspi_ce_n),
    .din(din),
    .dout(dout),
    .douten(douten)
  );
  
  assign in_pready = ack && in_psel;
  assign in_pslverr = 1'b0;
  assign qspi_dio[0] = douten[0] ? dout[0] : 1'bz;
  assign qspi_dio[1] = douten[1] ? dout[1] : 1'bz;
  assign qspi_dio[2] = douten[2] ? dout[2] : 1'bz;
  assign qspi_dio[3] = douten[3] ? dout[3] : 1'bz;
  assign din = qspi_dio;

endmodule
