module fpga_rx_top (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       uart_rx,
    output reg        led_ok,
    output reg        led_err,
    output wire [6:0] hex0,
    output wire [6:0] hex1
);

wire rst = ~rst_n;

wire [7:0] rx_data;
wire       rx_valid;

uart_rx #(
    .CLK_FREQ (50_000_000),
    .BAUD_RATE(115_200)
) u_rx (
    .clk     (clk),
    .rst     (rst),
    .rx      (uart_rx),
    .data_out(rx_data),
    .valid   (rx_valid)
);

reg [7:0] buf_rx [0:32];
reg [5:0] rx_count;
reg       frame_ready;
reg [20:0] timeout_cnt;

// Buffer de recepción y auto-recuperación
always @(posedge clk or posedge rst) begin
    if (rst) begin
        rx_count    <= 6'd0;
        frame_ready <= 1'b0;
        timeout_cnt <= 20'd0;
    end else begin
        frame_ready <= 1'b0;
        
        if (rx_valid) begin
            buf_rx[rx_count] <= rx_data;
            timeout_cnt <= 21'd0;
            
            if (rx_count == 6'd32) begin
                rx_count    <= 6'd0;
                frame_ready <= 1'b1;
            end else begin
                rx_count <= rx_count + 6'd1;
            end
        end else if (rx_count > 0) begin
            // 40ms timeout (2 millones de ciclos a 50MHz)
            if (timeout_cnt == 21'd2_000_000) begin
                rx_count    <= 6'd0;
                timeout_cnt <= 21'd0;
            end else begin
                timeout_cnt <= timeout_cnt + 21'd1;
            end
        end
    end
end

reg          sha_start;
wire [255:0] sha_hash;
wire         sha_done;
reg  [7:0]   dato_latch;
reg  [255:0] hash_latch;

sha256_core u_sha (
    .clk     (clk),
    .rst     (rst),
    .start   (sha_start),
    .data_in ({24'h000000, dato_latch}),
    .hash_out(sha_hash),
    .done    (sha_done)
);

localparam ST_IDLE    = 3'd0;
localparam ST_LATCH   = 3'd1;
localparam ST_HASH    = 3'd2;
localparam ST_COMPARE = 3'd3;

reg [2:0] state;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state      <= ST_IDLE;
        sha_start  <= 1'b0;
        led_ok     <= 1'b0;
        led_err    <= 1'b0;
        dato_latch <= 8'h0;
        hash_latch <= 256'h0;
    end else begin
        sha_start <= 1'b0;

        // DIAGNOSTICO HARDWARE: 
        // Si entra al menos UN byte por el UART, prendemos led_err para siempre.
        if (rx_valid) begin
            led_err <= 1'b1;
        end

        case (state)
            ST_IDLE: begin
                if (frame_ready) begin
                    dato_latch <= buf_rx[0];
                    hash_latch <= {
                        buf_rx[1],  buf_rx[2],  buf_rx[3],  buf_rx[4],
                        buf_rx[5],  buf_rx[6],  buf_rx[7],  buf_rx[8],
                        buf_rx[9],  buf_rx[10], buf_rx[11], buf_rx[12],
                        buf_rx[13], buf_rx[14], buf_rx[15], buf_rx[16],
                        buf_rx[17], buf_rx[18], buf_rx[19], buf_rx[20],
                        buf_rx[21], buf_rx[22], buf_rx[23], buf_rx[24],
                        buf_rx[25], buf_rx[26], buf_rx[27], buf_rx[28],
                        buf_rx[29], buf_rx[30], buf_rx[31], buf_rx[32]
                    };
                    led_ok    <= 1'b0;
                    // led_err   <= 1'b0; // REMOVED FOR DIAGNOSTIC
                    state     <= ST_LATCH;
                end
            end

            ST_LATCH: begin
                sha_start <= 1'b1;
                state     <= ST_HASH;
            end

            ST_HASH: begin
                if (sha_done) begin
                    state <= ST_COMPARE;
                end
            end

            ST_COMPARE: begin
                if (sha_hash == hash_latch) begin
                    led_ok  <= 1'b1;
                end else begin
                    led_ok  <= 1'b0;
                end
                state <= ST_IDLE;
            end
        endcase
    end
end

reg [6:0] seg_low, seg_high;
always @(*) begin
    case (rx_count[3:0]) // DIAGNOSTICO: Mostrar rx_count en vez de dato_latch
        4'h0: seg_low = 7'b1000000;
        4'h1: seg_low = 7'b1111001;
        4'h2: seg_low = 7'b0100100;
        4'h3: seg_low = 7'b0110000;
        4'h4: seg_low = 7'b0011001;
        4'h5: seg_low = 7'b0010010;
        4'h6: seg_low = 7'b0000010;
        4'h7: seg_low = 7'b1111000;
        4'h8: seg_low = 7'b0000000;
        4'h9: seg_low = 7'b0010000;
        4'hA: seg_low = 7'b0001000;
        4'hB: seg_low = 7'b0000011;
        4'hC: seg_low = 7'b1000110;
        4'hD: seg_low = 7'b0100001;
        4'hE: seg_low = 7'b0000110;
        4'hF: seg_low = 7'b0001110;
        default: seg_low = 7'b1111111;
    endcase
    case ({2'b00, rx_count[5:4]}) // DIAGNOSTICO: Mostrar rx_count en vez de dato_latch
        4'h0: seg_high = 7'b1000000;
        4'h1: seg_high = 7'b1111001;
        4'h2: seg_high = 7'b0100100;
        4'h3: seg_high = 7'b0110000;
        4'h4: seg_high = 7'b0011001;
        4'h5: seg_high = 7'b0010010;
        4'h6: seg_high = 7'b0000010;
        4'h7: seg_high = 7'b1111000;
        4'h8: seg_high = 7'b0000000;
        4'h9: seg_high = 7'b0010000;
        4'hA: seg_high = 7'b0001000;
        4'hB: seg_high = 7'b0000011;
        4'hC: seg_high = 7'b1000110;
        4'hD: seg_high = 7'b0100001;
        4'hE: seg_high = 7'b0000110;
        4'hF: seg_high = 7'b0001110;
        default: seg_high = 7'b1111111;
    endcase
end

assign hex0 = seg_low;
assign hex1 = seg_high;

endmodule
