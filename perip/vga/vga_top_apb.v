module vga_top_apb(
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

  output [7:0]  vga_r,
  output [7:0]  vga_g,
  output [7:0]  vga_b,
  output        vga_hsync,
  output        vga_vsync,
  output        vga_valid
);

  localparam H_VISIBLE = 640;
  localparam H_FRONT   = 16;
  localparam H_SYNC    = 96;
  localparam H_TOTAL   = 800;
  localparam V_VISIBLE = 480;
  localparam V_FRONT   = 10;
  localparam V_SYNC    = 2;
  localparam V_TOTAL   = 525;
  localparam FB_WORDS  = 524288;  // 2 MiB / four bytes per word

  // The framebuffer is word-organized internally but byte-addressable over
  // APB. Each visible pixel is 0x00RRGGBB and the visible stride is 640 words
  // (2560 bytes). The unused aperture remains ordinary readable/writable RAM.
  reg [31:0] framebuffer [0:FB_WORDS-1];

  reg [1:0] pixel_divider;
  reg [9:0] horizontal;
  reg [9:0] vertical;
  reg [18:0] scan_address;

  wire apb_access = in_psel && in_penable;
  wire [18:0] apb_word_address = in_paddr[20:2];
  wire visible = (horizontal < H_VISIBLE) && (vertical < V_VISIBLE);
  wire [31:0] scan_pixel = framebuffer[scan_address];

  assign in_pready = apb_access;
  assign in_pslverr = 1'b0;
  assign in_prdata = in_psel ? framebuffer[apb_word_address] : 32'b0;

  assign vga_valid = visible;
  assign vga_hsync = !((horizontal >= H_VISIBLE + H_FRONT) &&
                       (horizontal < H_VISIBLE + H_FRONT + H_SYNC));
  assign vga_vsync = !((vertical >= V_VISIBLE + V_FRONT) &&
                       (vertical < V_VISIBLE + V_FRONT + V_SYNC));
  assign vga_r = visible ? scan_pixel[23:16] : 8'b0;
  assign vga_g = visible ? scan_pixel[15:8] : 8'b0;
  assign vga_b = visible ? scan_pixel[7:0] : 8'b0;

  always @(posedge clock) begin
    if (reset) begin
      pixel_divider <= 2'b0;
      horizontal <= 10'b0;
      vertical <= 10'b0;
      scan_address <= 19'b0;
    end else begin
      if (apb_access && in_pwrite) begin
        if (in_pstrb[0]) framebuffer[apb_word_address][7:0] <= in_pwdata[7:0];
        if (in_pstrb[1]) framebuffer[apb_word_address][15:8] <= in_pwdata[15:8];
        if (in_pstrb[2]) framebuffer[apb_word_address][23:16] <= in_pwdata[23:16];
        if (in_pstrb[3]) framebuffer[apb_word_address][31:24] <= in_pwdata[31:24];
      end

      // 100 MHz / 4 = 25 MHz pixel cadence, close to the standard 25.175 MHz
      // 640x480 mode. APB writes never pause these scan counters.
      if (pixel_divider == 3) begin
        pixel_divider <= 2'b0;

        if (visible) scan_address <= scan_address + 1'b1;

        if (horizontal == H_TOTAL - 1) begin
          horizontal <= 10'b0;
          if (vertical == V_TOTAL - 1) begin
            vertical <= 10'b0;
            scan_address <= 19'b0;
          end else begin
            vertical <= vertical + 1'b1;
          end
        end else begin
          horizontal <= horizontal + 1'b1;
        end
      end else begin
        pixel_divider <= pixel_divider + 1'b1;
      end
    end
  end

endmodule
