module fpga_tx_top (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] sw,
    input  wire       btn_send_n,
    output wire       uart_tx,
    output reg        led_busy
);

wire rst = ~rst_n;

// Sincronizador y detector de flanco para el botón
reg btn_r1, btn_r2, btn_r3;
always @(posedge clk) begin
    btn_r1 <= btn_send_n;
    btn_r2 <= btn_r1;
    btn_r3 <= btn_r2;
end
wire btn_pulse = ~btn_r2 & btn_r3; // pulso al presionar el botón (flanco de bajada)

localparam ST_IDLE  = 3'd0;
localparam ST_HASH  = 3'd1;
localparam ST_LOAD  = 3'd2;
localparam ST_SEND  = 3'd3;
localparam ST_WAIT  = 3'd4;
localparam ST_DELAY = 3'd5;

reg [2:0]  state;
reg [5:0]  byte_idx;
reg [7:0]  frame [0:32];
reg [24:0] delay_cnt;

reg          sha_start;
wire [255:0] sha_hash;
wire         sha_done;

sha256_core u_sha (
    .clk     (clk),
    .rst     (rst),
    .start   (sha_start),
    .data_in ({24'h000000, sw}),
    .hash_out(sha_hash),
    .done    (sha_done)
);

reg        tx_send;
reg  [7:0] tx_data;
wire       tx_busy;

uart_tx #(
    .CLK_FREQ (50_000_000),
    .BAUD_RATE(115_200)
) u_tx (
    .clk    (clk),
    .rst    (rst),
    .data_in(tx_data),
    .send   (tx_send),
    .tx     (uart_tx),
    .busy   (tx_busy)
);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state     <= ST_IDLE;
        sha_start <= 1'b0;
        tx_send   <= 1'b0;
        byte_idx  <= 6'd0;
        led_busy  <= 1'b0;
        delay_cnt <= 25'd0;
    end else begin
        sha_start <= 1'b0;
        tx_send   <= 1'b0;

        case (state)
            ST_IDLE: begin
                led_busy <= 1'b0;
                if (btn_pulse) begin
                    sha_start <= 1'b1;
                    led_busy  <= 1'b1;
                    state     <= ST_HASH;
                end
            end

            ST_HASH: begin
                if (sha_done) begin
                    frame[0]  <= sw;
                    frame[1]  <= sha_hash[255:248];
                    frame[2]  <= sha_hash[247:240];
                    frame[3]  <= sha_hash[239:232];
                    frame[4]  <= sha_hash[231:224];
                    frame[5]  <= sha_hash[223:216];
                    frame[6]  <= sha_hash[215:208];
                    frame[7]  <= sha_hash[207:200];
                    frame[8]  <= sha_hash[199:192];
                    frame[9]  <= sha_hash[191:184];
                    frame[10] <= sha_hash[183:176];
                    frame[11] <= sha_hash[175:168];
                    frame[12] <= sha_hash[167:160];
                    frame[13] <= sha_hash[159:152];
                    frame[14] <= sha_hash[151:144];
                    frame[15] <= sha_hash[143:136];
                    frame[16] <= sha_hash[135:128];
                    frame[17] <= sha_hash[127:120];
                    frame[18] <= sha_hash[119:112];
                    frame[19] <= sha_hash[111:104];
                    frame[20] <= sha_hash[103:96];
                    frame[21] <= sha_hash[95:88];
                    frame[22] <= sha_hash[87:80];
                    frame[23] <= sha_hash[79:72];
                    frame[24] <= sha_hash[71:64];
                    frame[25] <= sha_hash[63:56];
                    frame[26] <= sha_hash[55:48];
                    frame[27] <= sha_hash[47:40];
                    frame[28] <= sha_hash[39:32];
                    frame[29] <= sha_hash[31:24];
                    frame[30] <= sha_hash[23:16];
                    frame[31] <= sha_hash[15:8];
                    frame[32] <= sha_hash[7:0];
                    byte_idx  <= 6'd0;
                    state     <= ST_LOAD;
                end
            end

            ST_LOAD: begin
                if (!tx_busy) begin
                    tx_data <= frame[byte_idx];
                    tx_send <= 1'b1;
                    state   <= ST_SEND;
                end
            end

            ST_SEND: begin
                if (tx_busy) begin
                    state <= ST_WAIT;
                end
            end

            ST_WAIT: begin
                if (!tx_busy) begin
                    if (byte_idx == 6'd32) begin
                        state     <= ST_DELAY;
                        delay_cnt <= 25'd0;
                    end else begin
                        byte_idx <= byte_idx + 6'd1;
                        state    <= ST_LOAD;
                    end
                end
            end

            ST_DELAY: begin
                // Mantener el LED encendido por 0.5 segundos (25 millones de ciclos)
                // para que sea humanamente visible.
                if (delay_cnt == 25'd25_000_000) begin
                    led_busy <= 1'b0;
                    state    <= ST_IDLE;
                end else begin
                    delay_cnt <= delay_cnt + 25'd1;
                end
            end
        endcase
    end
end
endmodule
