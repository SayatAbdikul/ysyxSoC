module axi4_delayer(
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

  assign in_aw_ready = out_aw_ready;
  assign out_aw_valid = in_aw_valid;
  assign out_aw_bits_id = in_aw_bits_id;
  assign out_aw_bits_addr = in_aw_bits_addr;
  assign out_aw_bits_len = in_aw_bits_len;
  assign out_aw_bits_size = in_aw_bits_size;
  assign out_aw_bits_burst = in_aw_bits_burst;
  assign out_aw_bits_lock = in_aw_bits_lock;
  assign out_aw_bits_cache = in_aw_bits_cache;
  assign out_aw_bits_prot = in_aw_bits_prot;
  assign out_aw_bits_qos = in_aw_bits_qos;
  assign in_w_ready = out_w_ready;
  assign out_w_valid = in_w_valid;
  assign out_w_bits_data = in_w_bits_data;
  assign out_w_bits_strb = in_w_bits_strb;
  assign out_w_bits_last = in_w_bits_last;
  assign out_b_ready = in_b_ready;
  assign in_b_valid = out_b_valid;
  assign in_b_bits_id = out_b_bits_id;
  assign in_b_bits_resp = out_b_bits_resp;

  assign in_ar_ready = out_ar_ready;
  assign out_ar_valid = in_ar_valid;
  assign out_ar_bits_id = in_ar_bits_id;
  assign out_ar_bits_addr = in_ar_bits_addr;
  assign out_ar_bits_len = in_ar_bits_len;
  assign out_ar_bits_size = in_ar_bits_size;
  assign out_ar_bits_burst = in_ar_bits_burst;
  assign out_ar_bits_lock = in_ar_bits_lock;
  assign out_ar_bits_cache = in_ar_bits_cache;
  assign out_ar_bits_prot = in_ar_bits_prot;
  assign out_ar_bits_qos = in_ar_bits_qos;
  assign out_r_ready = in_r_ready;
  assign in_r_valid = out_r_valid;
  assign in_r_bits_id = out_r_bits_id;
  assign in_r_bits_data = out_r_bits_data;
  assign in_r_bits_resp = out_r_bits_resp;
  assign in_r_bits_last = out_r_bits_last;

  wire unused_clock_reset = &{1'b0, clock, reset};

endmodule
