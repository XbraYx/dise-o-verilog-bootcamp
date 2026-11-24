/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_fir (
    input wire clk,
    input wire rst,
    input wire data_in,
    output reg signed [7:0] data_out
);

    // ==========================================
    // 1. RECEPCION SERIAL DE 8 BITS (MSB FIRST)
    // ==========================================

    reg [7:0] shift_reg;
    reg [2:0] bit_count;

    wire sample_valid;
    wire signed [7:0] x;

    assign sample_valid = (bit_count == 3'd7);
    assign x = {shift_reg[6:0], data_in};

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

    // ==========================================
    // 2. LINEA DE RETARDOS DEL FIR
    // ==========================================

    reg signed [7:0] d0, d1, d2, d3;
    reg signed [7:0] d4, d5, d6;

    // ==========================================
    // 3. SUMA DE MUESTRAS SIMETRICAS
    // ==========================================

    wire signed [8:0] pair0;
    wire signed [8:0] pair2;
    wire signed [8:0] pair3;

    assign pair0 = {x[7], x} + {d6[7], d6};
    assign pair2 = {d1[7], d1} + {d4[7], d4};
    assign pair3 = {d2[7], d2} + {d3[7], d3};

    // ==========================================
    // 4. MULTIPLICADORES DE COEFICIENTES
    // Coeficientes en formato Q1.15
    // ==========================================

    wire signed [24:0] p0;
    wire signed [24:0] p2;
    wire signed [24:0] p3;

    assign p0 = pair0 * 16'sd141;
    assign p2 = pair2 * -16'sd2615;
    assign p3 = pair3 * 16'sd18858;

    // ==========================================
    // 5. ACUMULADOR
    // ==========================================

    wire signed [26:0] acc;

    assign acc =
        {{2{p0[24]}}, p0} +
        {{2{p2[24]}}, p2} +
        {{2{p3[24]}}, p3};

    // Regresar de Q1.15 a entero
    wire signed [26:0] scaled;
    assign scaled = acc >>> 15;

    // ==========================================
    // 6. PROCESAMIENTO Y ACTUALIZACION
    // ==========================================

    always @(posedge clk) begin

        if (rst) begin

            d0 <= 0;
            d1 <= 0;
            d2 <= 0;
            d3 <= 0;
            d4 <= 0;
            d5 <= 0;
            d6 <= 0;

            data_out <= 0;

        end

        else if (sample_valid) begin

            // Saturacion a 8 bits con signo
            if (scaled > 127)
                data_out <= 8'sd127;

            else if (scaled < -128)
                data_out <= -8'sd128;

            else
                data_out <= scaled[7:0];

            // Desplazamiento de muestras
            d6 <= d5;
            d5 <= d4;
            d4 <= d3;
            d3 <= d2;
            d2 <= d1;
            d1 <= d0;
            d0 <= x;

        end
    end

endmodule




