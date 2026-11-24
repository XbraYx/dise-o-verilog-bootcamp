/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module  tt_um_fir (
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



module fir_8tap_serial (
    input  wire clk,
    input  wire rst,

    // Entrada serial
    input  wire data_in,

    // Salida paralela
    output wire signed [7:0] data_out
);

    // =====================================================
    // 1. RECEPTOR SERIAL DE 8 BITS (MSB FIRST)
    // =====================================================

    reg [7:0] shift_reg;
    reg [2:0] bit_count;

    wire sample_valid;
    wire signed [7:0] sample_in;

    // El octavo bit completa una muestra
    assign sample_valid = (bit_count == 3'd7);

    // Incluye el bit que llega en el ciclo actual
    assign sample_in = {shift_reg[6:0], data_in};

    always @(posedge clk) begin
        if (rst) begin
            shift_reg <= 8'd0;
            bit_count <= 3'd0;
        end
        else begin
            shift_reg <= {shift_reg[6:0], data_in};

            if (bit_count == 3'd7)
                bit_count <= 3'd0;
            else
                bit_count <= bit_count + 1'b1;
        end
    end

    // =====================================================
    // 2. INSTANCIA DEL FILTRO FIR
    // =====================================================

    fir_8tap_core FIR (
        .clk(clk),
        .rst(rst),
        .sample_valid(sample_valid),
        .x(sample_in),
        .y(data_out)
    );

endmodule


// =========================================================
// MODULO FIR DE 8 TAPS
// =========================================================

module fir_8tap_core (
    input wire clk,
    input wire rst,

    input wire sample_valid,
    input wire signed [7:0] x,

    output reg signed [7:0] y
);

    // =====================================================
    // 1. REGISTROS DE RETARDO
    // =====================================================

    reg signed [7:0] d0, d1, d2, d3;
    reg signed [7:0] d4, d5, d6;

    // =====================================================
    // 2. SUMAS SIMETRICAS
    // =====================================================

    wire signed [8:0] pair0;
    wire signed [8:0] pair1;
    wire signed [8:0] pair2;
    wire signed [8:0] pair3;

    // Coeficientes simetricos
    assign pair0 = {x[7],x}  + {d6[7],d6};
    assign pair1 = {d0[7],d0} + {d5[7],d5};
    assign pair2 = {d1[7],d1} + {d4[7],d4};
    assign pair3 = {d2[7],d2} + {d3[7],d3};

    // =====================================================
    // 3. MULTIPLICADORES Q1.15
    // =====================================================

    // Coeficientes cuantizados:
    // 0.0043  = 141 / 32768
    // 0       = 0
    // -0.0798 = -2615 / 32768
    // 0.5755  = 18858 / 32768

    // Funcion para multiplicar 9 x 16 bits
    // con resultado signed de 25 bits.

    function signed [24:0] mult9x16;
        input signed [8:0] a;
        input signed [15:0] b;

        reg signed [24:0] aa;
        reg signed [24:0] bb;

        begin
            aa = {{16{a[8]}},a};
            bb = {{9{b[15]}},b};

            mult9x16 = aa * bb;
        end
    endfunction

    wire signed [24:0] p0;
    wire signed [24:0] p2;
    wire signed [24:0] p3;

    assign p0 = mult9x16(pair0, 16'sd141);
    assign p2 = mult9x16(pair2, -16'sd2615);
    assign p3 = mult9x16(pair3, 16'sd18858);

    // =====================================================
    // 4. ACUMULADOR
    // =====================================================

    wire signed [26:0] acc;

    assign acc =
          {{2{p0[24]}},p0}
        + {{2{p2[24]}},p2}
        + {{2{p3[24]}},p3};

    // =====================================================
    // 5. ESCALADO Q1.15
    // =====================================================

    wire signed [26:0] scaled;

    assign scaled = acc >>> 15;

    // =====================================================
    // 6. SATURACION Y SALIDA
    // =====================================================

    always @(posedge clk) begin

        if (rst) begin
            y <= 8'sd0;
        end

        else if (sample_valid) begin

            if (scaled > 27'sd127)
                y <= 8'sd127;

            else if (scaled < -27'sd128)
                y <= -8'sd128;

            else
                y <= scaled[7:0];

        end
    end

    // =====================================================
    // 7. ACTUALIZACION DE LA LINEA DE RETARDOS
    // =====================================================

    always @(posedge clk) begin

        if (rst) begin
            d0 <= 0;
            d1 <= 0;
            d2 <= 0;
            d3 <= 0;
            d4 <= 0;
            d5 <= 0;
            d6 <= 0;
        end

        else if (sample_valid) begin

            d0 <= x;
            d1 <= d0;
            d2 <= d1;
            d3 <= d2;
            d4 <= d3;
            d5 <= d4;
            d6 <= d5;

        end
    end

endmodule


