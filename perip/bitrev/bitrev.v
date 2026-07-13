module bitrev (
  input  sck,
  input  ss,
  input  mosi,
  output miso
);

  reg [7:0] data;
  reg [4:0] bit_count;

  // ss is active low. Its rising edge ends and resets the transaction.
  always @(posedge sck or posedge ss) begin
    if (ss) begin
      data <= 8'b0;
      bit_count <= 5'b0;
    end else begin
      if (bit_count < 5'd8) begin
        // Receive MOSI MSB first.
        data <= {data[6:0], mosi};
      end

      if (bit_count < 5'd16) begin
        bit_count <= bit_count + 5'd1;
      end
    end
  end

  // During the second byte, send data[0], data[1], ..., data[7].
  // Sending the original byte LSB first appears to the MSB-first master
  // as the bit-reversed byte.
  assign miso =
      ss                          ? 1'b1 :
      (bit_count >= 5'd8 &&
       bit_count <  5'd16)        ? data[bit_count[2:0]] :
                                    1'b1;

endmodule
