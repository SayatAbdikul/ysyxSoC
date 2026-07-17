module gpio_top_apb(
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

  output [15:0] gpio_out,
  input  [15:0] gpio_in,
  output [7:0]  gpio_seg_0,
  output [7:0]  gpio_seg_1,
  output [7:0]  gpio_seg_2,
  output [7:0]  gpio_seg_3,
  output [7:0]  gpio_seg_4,
  output [7:0]  gpio_seg_5,
  output [7:0]  gpio_seg_6,
  output [7:0]  gpio_seg_7
);

  reg [15:0] gpio_out_q;
  reg [31:0] gpio_seg_q;
  reg [15:0] gpio_in_meta_q;
  reg [15:0] gpio_in_sync_q;

  wire apb_access = in_psel && in_penable;
  wire apb_write = apb_access && in_pwrite;
  wire [1:0] reg_index = in_paddr[3:2];

  assign in_pready = apb_access;
  assign in_pslverr = 1'b0;
  assign gpio_out = gpio_out_q;

  reg [31:0] read_data;
  always @(*) begin
    case (reg_index)
      2'd0: read_data = {16'b0, gpio_out_q};
      2'd1: read_data = {16'b0, gpio_in_sync_q};
      2'd2: read_data = gpio_seg_q;
      default: read_data = 32'b0;
    endcase
  end
  assign in_prdata = in_psel ? read_data : 32'b0;

  always @(posedge clock) begin
    if (reset) begin
      gpio_out_q <= 16'b0;
      gpio_seg_q <= 32'b0;
      gpio_in_meta_q <= 16'b0;
      gpio_in_sync_q <= 16'b0;
    end else begin
      // The switches are asynchronous board inputs. Two stages prevent their
      // transitions from feeding the APB read data directly.
      gpio_in_meta_q <= gpio_in;
      gpio_in_sync_q <= gpio_in_meta_q;

      if (apb_write && reg_index == 2'd0) begin
        if (in_pstrb[0]) gpio_out_q[7:0] <= in_pwdata[7:0];
        if (in_pstrb[1]) gpio_out_q[15:8] <= in_pwdata[15:8];
      end
      if (apb_write && reg_index == 2'd2) begin
        if (in_pstrb[0]) gpio_seg_q[7:0] <= in_pwdata[7:0];
        if (in_pstrb[1]) gpio_seg_q[15:8] <= in_pwdata[15:8];
        if (in_pstrb[2]) gpio_seg_q[23:16] <= in_pwdata[23:16];
        if (in_pstrb[3]) gpio_seg_q[31:24] <= in_pwdata[31:24];
      end
    end
  end

  // NVBoard's segment pins are active high and ordered A,B,C,D,E,F,G,DP.
  // gpio_seg_q nibble zero drives the rightmost display (SEG0).
  function [7:0] decode_hex;
    input [3:0] value;
    begin
      case (value)
        4'h0: decode_hex = 8'hfc;
        4'h1: decode_hex = 8'h60;
        4'h2: decode_hex = 8'hda;
        4'h3: decode_hex = 8'hf2;
        4'h4: decode_hex = 8'h66;
        4'h5: decode_hex = 8'hb6;
        4'h6: decode_hex = 8'hbe;
        4'h7: decode_hex = 8'he0;
        4'h8: decode_hex = 8'hfe;
        4'h9: decode_hex = 8'hf6;
        4'ha: decode_hex = 8'hee;
        4'hb: decode_hex = 8'h3e;
        4'hc: decode_hex = 8'h9c;
        4'hd: decode_hex = 8'h7a;
        4'he: decode_hex = 8'h9e;
        default: decode_hex = 8'h8e;
      endcase
    end
  endfunction

  assign gpio_seg_0 = decode_hex(gpio_seg_q[3:0]);
  assign gpio_seg_1 = decode_hex(gpio_seg_q[7:4]);
  assign gpio_seg_2 = decode_hex(gpio_seg_q[11:8]);
  assign gpio_seg_3 = decode_hex(gpio_seg_q[15:12]);
  assign gpio_seg_4 = decode_hex(gpio_seg_q[19:16]);
  assign gpio_seg_5 = decode_hex(gpio_seg_q[23:20]);
  assign gpio_seg_6 = decode_hex(gpio_seg_q[27:24]);
  assign gpio_seg_7 = decode_hex(gpio_seg_q[31:28]);

endmodule
