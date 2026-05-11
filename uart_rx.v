// uart_rx.v
// Receptor UART - 8N1

module uart_rx #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115_200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,          
    output reg  [7:0] data_out,    
    output reg        valid        
);

localparam TICKS      = CLK_FREQ / BAUD_RATE;       
localparam HALF_TICKS = TICKS / 2;                  

localparam IDLE  = 2'd0;
localparam START = 2'd1;
localparam DATA  = 2'd2;
localparam STOP  = 2'd3;

reg [1:0] state;
reg [9:0] tick_cnt;
reg [2:0] bit_idx;
reg [7:0] shift_reg;


reg rx_s1, rx_sync;
always @(posedge clk) begin
    rx_s1   <= rx;
    rx_sync <= rx_s1;
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state     <= IDLE;
        valid     <= 1'b0;
        tick_cnt  <= 0;
        bit_idx   <= 0;
        shift_reg <= 0;
        data_out  <= 0;
    end else begin
        valid <= 1'b0;   

        case (state)

            IDLE: begin
                if (!rx_sync) begin   // flanco de bajada = bit de inicio
                    tick_cnt <= 0;
                    state    <= START;
                end
            end

            START: begin
                // Esperar hasta el centro del bit de inicio
                if (tick_cnt == HALF_TICKS - 1) begin
                    if (!rx_sync) begin   // confirmar que sigue en bajo
                        tick_cnt <= 0;
                        bit_idx  <= 0;
                        state    <= DATA;
                    end else begin
                        state <= IDLE;    // falsa alarma (ruido)
                    end
                end else begin
                    tick_cnt <= tick_cnt + 1;
                end
            end

            DATA: begin
                if (tick_cnt == TICKS - 1) begin
                    tick_cnt  <= 0;
                    shift_reg <= {rx_sync, shift_reg[7:1]};  // LSB primero
                    if (bit_idx == 7) begin
                        state <= STOP;
                    end else begin
                        bit_idx <= bit_idx + 1;
                    end
                end else begin
                    tick_cnt <= tick_cnt + 1;
                end
            end

            STOP: begin
                if (tick_cnt == TICKS - 1) begin
                    if (rx_sync) begin       // bit de parada valido
                        data_out <= shift_reg;
                        valid    <= 1'b1;
                    end
                    // si no hay bit de parada, se descarta el frame
                    tick_cnt <= 0;
                    state    <= IDLE;
                end else begin
                    tick_cnt <= tick_cnt + 1;
                end
            end

        endcase
    end
end

endmodule