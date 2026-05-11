// sha256_core.v
// SHA-256 para mensaje de 32 bits
// Ventana deslizante de 16 palabras + estado LOAD de 1 ciclo
// Total: 67 ciclos desde start hasta done

module sha256_core (
    input  wire         clk,
    input  wire         rst,
    input  wire         start,
    input  wire [31:0]  data_in,
    output reg  [255:0] hash_out,
    output reg          done
);

// ----------------------------------------------------------------
// Constantes K
// ----------------------------------------------------------------
wire [31:0] K [0:63];
assign K[0]  = 32'h428a2f98; assign K[1]  = 32'h71374491;
assign K[2]  = 32'hb5c0fbcf; assign K[3]  = 32'he9b5dba5;
assign K[4]  = 32'h3956c25b; assign K[5]  = 32'h59f111f1;
assign K[6]  = 32'h923f82a4; assign K[7]  = 32'hab1c5ed5;
assign K[8]  = 32'hd807aa98; assign K[9]  = 32'h12835b01;
assign K[10] = 32'h243185be; assign K[11] = 32'h550c7dc3;
assign K[12] = 32'h72be5d74; assign K[13] = 32'h80deb1fe;
assign K[14] = 32'h9bdc06a7; assign K[15] = 32'hc19bf174;
assign K[16] = 32'he49b69c1; assign K[17] = 32'hefbe4786;
assign K[18] = 32'h0fc19dc6; assign K[19] = 32'h240ca1cc;
assign K[20] = 32'h2de92c6f; assign K[21] = 32'h4a7484aa;
assign K[22] = 32'h5cb0a9dc; assign K[23] = 32'h76f988da;
assign K[24] = 32'h983e5152; assign K[25] = 32'ha831c66d;
assign K[26] = 32'hb00327c8; assign K[27] = 32'hbf597fc7;
assign K[28] = 32'hc6e00bf3; assign K[29] = 32'hd5a79147;
assign K[30] = 32'h06ca6351; assign K[31] = 32'h14292967;
assign K[32] = 32'h27b70a85; assign K[33] = 32'h2e1b2138;
assign K[34] = 32'h4d2c6dfc; assign K[35] = 32'h53380d13;
assign K[36] = 32'h650a7354; assign K[37] = 32'h766a0abb;
assign K[38] = 32'h81c2c92e; assign K[39] = 32'h92722c85;
assign K[40] = 32'ha2bfe8a1; assign K[41] = 32'ha81a664b;
assign K[42] = 32'hc24b8b70; assign K[43] = 32'hc76c51a3;
assign K[44] = 32'hd192e819; assign K[45] = 32'hd6990624;
assign K[46] = 32'hf40e3585; assign K[47] = 32'h106aa070;
assign K[48] = 32'h19a4c116; assign K[49] = 32'h1e376c08;
assign K[50] = 32'h2748774c; assign K[51] = 32'h34b0bcb5;
assign K[52] = 32'h391c0cb3; assign K[53] = 32'h4ed8aa4a;
assign K[54] = 32'h5b9cca4f; assign K[55] = 32'h682e6ff3;
assign K[56] = 32'h748f82ee; assign K[57] = 32'h78a5636f;
assign K[58] = 32'h84c87814; assign K[59] = 32'h8cc70208;
assign K[60] = 32'h90befffa; assign K[61] = 32'ha4506ceb;
assign K[62] = 32'hbef9a3f7; assign K[63] = 32'hc67178f2;

// ----------------------------------------------------------------
// Valores iniciales H
// ----------------------------------------------------------------
localparam H0_I = 32'h6a09e667;
localparam H1_I = 32'hbb67ae85;
localparam H2_I = 32'h3c6ef372;
localparam H3_I = 32'ha54ff53a;
localparam H4_I = 32'h510e527f;
localparam H5_I = 32'h9b05688c;
localparam H6_I = 32'h1f83d9ab;
localparam H7_I = 32'h5be0cd19;

// ----------------------------------------------------------------
// Estados
// ----------------------------------------------------------------
localparam ST_IDLE = 2'd0;
localparam ST_LOAD = 2'd1;
localparam ST_RUN  = 2'd2;
localparam ST_DONE = 2'd3;

// ----------------------------------------------------------------
// Registros internos
// ----------------------------------------------------------------
reg [1:0]  state;
reg [31:0] W [0:15];        // ventana deslizante de 16 palabras
reg [31:0] a, b, c, d, e, f, g, h_r;
reg [31:0] H0, H1, H2, H3, H4, H5, H6, H7;
reg [6:0]  round;
reg [31:0] T1, T2;

// ----------------------------------------------------------------
// Indices circulares para ventana deslizante
// ----------------------------------------------------------------
wire [3:0] idx    = round[3:0];
wire [3:0] idx_2  = (round - 6'd2)  & 4'hF;
wire [3:0] idx_7  = (round - 6'd7)  & 4'hF;
wire [3:0] idx_15 = (round - 6'd15) & 4'hF;

// ----------------------------------------------------------------
// W_cur: valor combinacional de la palabra actual
// Para rondas 0-15 usa W directamente
// Para rondas 16-63 calcula la expansion del schedule
// ----------------------------------------------------------------
wire [31:0] w15    = W[idx_15];
wire [31:0] w2     = W[idx_2];
wire [31:0] w7     = W[idx_7];
wire [31:0] w_base = W[idx];

wire [31:0] s0_w15 = ((w15 >> 7)  | (w15 << 25)) ^
                     ((w15 >> 18) | (w15 << 14)) ^
                      (w15 >> 3);

wire [31:0] s1_w2  = ((w2  >> 17) | (w2  << 15)) ^
                     ((w2  >> 19) | (w2  << 13)) ^
                      (w2  >> 10);

wire [31:0] W_cur  = (round < 7'd16) ? w_base :
                     (s1_w2 + w7 + s0_w15 + w_base);

// ----------------------------------------------------------------
// Funciones SHA-256
// ----------------------------------------------------------------
function [31:0] rotr32;
    input [31:0] x;
    input [4:0]  n;
    rotr32 = (x >> n) | (x << (32 - n));
endfunction

function [31:0] SIG0;
    input [31:0] x;
    SIG0 = rotr32(x, 5'd2) ^ rotr32(x, 5'd13) ^ rotr32(x, 5'd22);
endfunction

function [31:0] SIG1;
    input [31:0] x;
    SIG1 = rotr32(x, 5'd6) ^ rotr32(x, 5'd11) ^ rotr32(x, 5'd25);
endfunction

function [31:0] Ch;
    input [31:0] x, y, z;
    Ch = (x & y) ^ (~x & z);
endfunction

function [31:0] Maj;
    input [31:0] x, y, z;
    Maj = (x & y) ^ (x & z) ^ (y & z);
endfunction

// ----------------------------------------------------------------
// Maquina de estados principal
// ----------------------------------------------------------------
always @(posedge clk or posedge rst) begin
    if (rst) begin
        state    <= ST_IDLE;
        done     <= 1'b0;
        round    <= 7'd0;
        hash_out <= 256'h0;
        a  <= 32'h0; b  <= 32'h0;
        c  <= 32'h0; d  <= 32'h0;
        e  <= 32'h0; f  <= 32'h0;
        g  <= 32'h0; h_r<= 32'h0;
        H0 <= 32'h0; H1 <= 32'h0;
        H2 <= 32'h0; H3 <= 32'h0;
        H4 <= 32'h0; H5 <= 32'h0;
        H6 <= 32'h0; H7 <= 32'h0;
        W[0]  <= 32'h0; W[1]  <= 32'h0;
        W[2]  <= 32'h0; W[3]  <= 32'h0;
        W[4]  <= 32'h0; W[5]  <= 32'h0;
        W[6]  <= 32'h0; W[7]  <= 32'h0;
        W[8]  <= 32'h0; W[9]  <= 32'h0;
        W[10] <= 32'h0; W[11] <= 32'h0;
        W[12] <= 32'h0; W[13] <= 32'h0;
        W[14] <= 32'h0; W[15] <= 32'h0;
    end

    else begin
        done <= 1'b0;

        case (state)

            // ----------------------------------------------------
            ST_IDLE: begin
                if (start) begin
                    // Padding SHA-256 para mensaje de 32 bits:
                    // [dato_32b | 1000...0 | longitud_64b]
                    W[0]  <= data_in;
                    W[1]  <= 32'h80000000;
                    W[2]  <= 32'h00000000;
                    W[3]  <= 32'h00000000;
                    W[4]  <= 32'h00000000;
                    W[5]  <= 32'h00000000;
                    W[6]  <= 32'h00000000;
                    W[7]  <= 32'h00000000;
                    W[8]  <= 32'h00000000;
                    W[9]  <= 32'h00000000;
                    W[10] <= 32'h00000000;
                    W[11] <= 32'h00000000;
                    W[12] <= 32'h00000000;
                    W[13] <= 32'h00000000;
                    W[14] <= 32'h00000000;
                    W[15] <= 32'h00000020; // 32 bits en big-endian

                    // Inicializar registros de trabajo
                    a   <= H0_I; b   <= H1_I;
                    c   <= H2_I; d   <= H3_I;
                    e   <= H4_I; f   <= H5_I;
                    g   <= H6_I; h_r <= H7_I;

                    // Guardar H iniciales para suma final
                    H0 <= H0_I; H1 <= H1_I;
                    H2 <= H2_I; H3 <= H3_I;
                    H4 <= H4_I; H5 <= H5_I;
                    H6 <= H6_I; H7 <= H7_I;

                    round <= 7'd0;
                    state <= ST_LOAD;
                end
            end

            // ----------------------------------------------------
            // 1 ciclo de espera para que W quede estable
            // antes de que W_cur lo lea combinacionalmente
            // ----------------------------------------------------
            ST_LOAD: begin
                state <= ST_RUN;
            end

            // ----------------------------------------------------
            ST_RUN: begin
                if (round < 7'd64) begin
                    // Calcular T1 y T2 con asignacion bloqueante
                    // para que e,d se actualicen en orden correcto
                    T1 = h_r + SIG1(e) + Ch(e,f,g) + K[round] + W_cur;
                    T2 = SIG0(a) + Maj(a,b,c);

                    // Actualizar ventana deslizante
                    if (round >= 7'd16)
                        W[idx] <= W_cur;

                    // Rotar registros de trabajo
                    h_r <= g;
                    g   <= f;
                    f   <= e;
                    e   <= d + T1;
                    d   <= c;
                    c   <= b;
                    b   <= a;
                    a   <= T1 + T2;

                    round <= round + 7'd1;
                end else begin
                    state <= ST_DONE;
                end
            end

            // ----------------------------------------------------
            ST_DONE: begin
                hash_out <= { H0 + a, H1 + b,
                              H2 + c, H3 + d,
                              H4 + e, H5 + f,
                              H6 + g, H7 + h_r };
                done  <= 1'b1;
                state <= ST_IDLE;
                round <= 7'd0;
            end

        endcase
    end
end

endmodule