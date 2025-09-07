// Generator : SpinalHDL v1.12.2    git head : f25edbcee624ef41548345cfb91c42060e33313f
// Component : FpRoundMax

`timescale 1ns/1ps

module FpRoundMax (
  input  wire          inVec_valid,
  output wire          inVec_ready,
  input  wire [271:0]  inVec_payload,
  output wire          outMax_valid,
  input  wire          outMax_ready,
  output wire [15:0]   outMax_payload,
  input  wire          clk,
  input  wire          resetn
);

  reg        [15:0]   cmp_io_a;
  wire                cmp_io_greater;
  wire       [4:0]    _zz_idx_valueNext;
  wire       [0:0]    _zz_idx_valueNext_1;
  reg        [15:0]   _zz__zz_maxReg;
  wire       [15:0]   words_0;
  wire       [15:0]   words_1;
  wire       [15:0]   words_2;
  wire       [15:0]   words_3;
  wire       [15:0]   words_4;
  wire       [15:0]   words_5;
  wire       [15:0]   words_6;
  wire       [15:0]   words_7;
  wire       [15:0]   words_8;
  wire       [15:0]   words_9;
  wire       [15:0]   words_10;
  wire       [15:0]   words_11;
  wire       [15:0]   words_12;
  wire       [15:0]   words_13;
  wire       [15:0]   words_14;
  wire       [15:0]   words_15;
  wire       [15:0]   words_16;
  reg                 busy;
  reg                 idx_willIncrement;
  wire                idx_willClear;
  reg        [4:0]    idx_valueNext;
  reg        [4:0]    idx_value;
  wire                idx_willOverflowIfInc;
  wire                idx_willOverflow;
  reg        [15:0]   maxReg;
  reg                 validReg;
  wire                inVec_fire;
  wire       [15:0]   _zz_maxReg;
  wire                outMax_fire;

  assign _zz_idx_valueNext_1 = idx_willIncrement;
  assign _zz_idx_valueNext = {4'd0, _zz_idx_valueNext_1};
  FpCmp cmp (
    .io_a       (cmp_io_a[15:0]), //i
    .io_b       (maxReg[15:0]  ), //i
    .io_greater (cmp_io_greater)  //o
  );
  always @(*) begin
    case(idx_value)
      5'b00000 : _zz__zz_maxReg = words_0;
      5'b00001 : _zz__zz_maxReg = words_1;
      5'b00010 : _zz__zz_maxReg = words_2;
      5'b00011 : _zz__zz_maxReg = words_3;
      5'b00100 : _zz__zz_maxReg = words_4;
      5'b00101 : _zz__zz_maxReg = words_5;
      5'b00110 : _zz__zz_maxReg = words_6;
      5'b00111 : _zz__zz_maxReg = words_7;
      5'b01000 : _zz__zz_maxReg = words_8;
      5'b01001 : _zz__zz_maxReg = words_9;
      5'b01010 : _zz__zz_maxReg = words_10;
      5'b01011 : _zz__zz_maxReg = words_11;
      5'b01100 : _zz__zz_maxReg = words_12;
      5'b01101 : _zz__zz_maxReg = words_13;
      5'b01110 : _zz__zz_maxReg = words_14;
      5'b01111 : _zz__zz_maxReg = words_15;
      default : _zz__zz_maxReg = words_16;
    endcase
  end

  assign words_0 = inVec_payload[15 : 0];
  assign words_1 = inVec_payload[31 : 16];
  assign words_2 = inVec_payload[47 : 32];
  assign words_3 = inVec_payload[63 : 48];
  assign words_4 = inVec_payload[79 : 64];
  assign words_5 = inVec_payload[95 : 80];
  assign words_6 = inVec_payload[111 : 96];
  assign words_7 = inVec_payload[127 : 112];
  assign words_8 = inVec_payload[143 : 128];
  assign words_9 = inVec_payload[159 : 144];
  assign words_10 = inVec_payload[175 : 160];
  assign words_11 = inVec_payload[191 : 176];
  assign words_12 = inVec_payload[207 : 192];
  assign words_13 = inVec_payload[223 : 208];
  assign words_14 = inVec_payload[239 : 224];
  assign words_15 = inVec_payload[255 : 240];
  assign words_16 = inVec_payload[271 : 256];
  always @(*) begin
    idx_willIncrement = 1'b0;
    if(busy) begin
      idx_willIncrement = 1'b1;
    end
  end

  assign idx_willClear = 1'b0;
  assign idx_willOverflowIfInc = (idx_value == 5'h10);
  assign idx_willOverflow = (idx_willOverflowIfInc && idx_willIncrement);
  always @(*) begin
    if(idx_willOverflow) begin
      idx_valueNext = 5'h0;
    end else begin
      idx_valueNext = (idx_value + _zz_idx_valueNext);
    end
    if(idx_willClear) begin
      idx_valueNext = 5'h0;
    end
  end

  assign inVec_ready = (! busy);
  assign outMax_valid = validReg;
  assign outMax_payload = maxReg;
  always @(*) begin
    cmp_io_a = words_0;
    if(busy) begin
      cmp_io_a = _zz_maxReg;
    end
  end

  assign inVec_fire = (inVec_valid && inVec_ready);
  assign _zz_maxReg = _zz__zz_maxReg;
  assign outMax_fire = (outMax_valid && outMax_ready);
  always @(posedge clk) begin
    if(!resetn) begin
      busy <= 1'b0;
      idx_value <= 5'h0;
      maxReg <= 16'h0;
      validReg <= 1'b0;
    end else begin
      idx_value <= idx_valueNext;
      if(inVec_fire) begin
        maxReg <= words_0;
        idx_value <= 5'h01;
        busy <= 1'b1;
      end
      if(busy) begin
        if(cmp_io_greater) begin
          maxReg <= _zz_maxReg;
        end
        if(idx_willOverflow) begin
          busy <= 1'b0;
          validReg <= 1'b1;
        end
      end
      if(outMax_fire) begin
        validReg <= 1'b0;
      end
    end
  end


endmodule

module FpCmp (
  input  wire [15:0]   io_a,
  input  wire [15:0]   io_b,
  output wire          io_greater
);

  wire                diffSign;
  wire                gtPos;
  wire                gtNeg;

  assign diffSign = (io_a[15] ^ io_b[15]);
  assign gtPos = ((io_b[14 : 7] < io_a[14 : 7]) || ((io_a[14 : 7] == io_b[14 : 7]) && (io_b[6 : 0] < io_a[6 : 0])));
  assign gtNeg = ((io_a[14 : 7] < io_b[14 : 7]) || ((io_a[14 : 7] == io_b[14 : 7]) && (io_a[6 : 0] < io_b[6 : 0])));
  assign io_greater = (((diffSign && (! io_a[15])) || (((! diffSign) && (! io_a[15])) && gtPos)) || (((! diffSign) && io_a[15]) && gtNeg));

endmodule
