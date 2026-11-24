/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_example (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // All output pins must be assigned. If not used, assign to 0.
  assign uo_out  = ui_in + uio_in;  // Example: ou_out is the sum of ui_in and uio_in
  assign uio_out = 0;
  assign uio_oe  = 0;

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, clk, rst_n, 1'b0};

endmodule


module fir_8tap (
    input  wire clk,
    input  wire rst,
    input  wire signed [15:0] x,
    output reg  signed [15:0] y
);

    // =====================================================
    // 1. LINEA DE RETARDOS: 7 REGISTROS
    // =====================================================

    reg signed [15:0] d [0:6];

    integer i;

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 7; i = i + 1)
                d[i] <= 16'sd0;
        end
        else begin
            d[0] <= x;

            for (i = 1; i < 7; i = i + 1)
                d[i] <= d[i-1];
        end
    end

    // =====================================================
    // 2. SUMAS SIMETRICAS
    // =====================================================

    wire signed [16:0] pair0;
    wire signed [16:0] pair1;
    wire signed [16:0] pair2;
    wire signed [16:0] pair3;

    // h0 = h7 = 0.0043
    assign pair0 = {x[15],x} + {d[6][15],d[6]};

    // h1 = h6 = 0
    assign pair1 = {d[0][15],d[0]} + {d[5][15],d[5]};

    // h2 = h5 = -0.0798
    assign pair2 = {d[1][15],d[1]} + {d[4][15],d[4]};

    // h3 = h4 = 0.5755
    assign pair3 = {d[2][15],d[2]} + {d[3][15],d[3]};

    // =====================================================
    // 3. MULTIPLICADORES Q1.15
    // =====================================================

    wire signed [32:0] p0;
    wire signed [32:0] p2;
    wire signed [32:0] p3;

    assign p0 = pair0 * 16'sd141;
    assign p2 = pair2 * -16'sd2616;
    assign p3 = pair3 * 16'sd18859;

    // =====================================================
    // 4. ACUMULADOR
    // =====================================================

    wire signed [34:0] acc;

    assign acc = {{2{p0[32]}},p0}
               + {{2{p2[32]}},p2}
               + {{2{p3[32]}},p3};

    // =====================================================
    // 5. ESCALADO Q1.15
    // =====================================================

    wire signed [19:0] scaled;

    assign scaled = acc >>> 15;

    // =====================================================
    // 6. SATURACION Y REGISTRO DE SALIDA
    // =====================================================

    always @(posedge clk) begin
        if (rst) begin
            y <= 16'sd0;
        end
        else begin
            if (scaled > 20'sd32767)
                y <= 16'sd32767;

            else if (scaled < -20'sd32768)
                y <= -16'sd32768;

            else
                y <= scaled[15:0];
        end
    end

endmodule

