// uart_tx.v
// Transmisor UART - 8N1

module uart_tx #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115_200
)(
    input  wire       clk,
    input  wire       rst,        
    input  wire [7:0] data_in,   
    input  wire       send,       
    output reg        tx,         
    output reg        busy        
);

localparam TICKS = CLK_FREQ / BAUD_RATE;  

// Estados
localparam IDLE  = 2'd0;
localparam START = 2'd1;
localparam DATA  = 2'd2;
localparam STOP  = 2'd3;

reg [1:0]  state;
reg [9:0]  tick_cnt;   // contador de ciclos por bit
reg [2:0]  bit_idx;    
reg [7:0]  shift_reg;  // copia del dato

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state     <= IDLE;
        tx        <= 1'b1;
        busy      <= 1'b0;
        tick_cnt  <= 0;
        bit_idx   <= 0;
        shift_reg <= 0;
    end else begin
        case (state)

            IDLE: begin
                tx   <= 1'b1;
                busy <= 1'b0;
                if (send) begin
                    shift_reg <= data_in;
                    busy      <= 1'b1;
                    tick_cnt  <= 0;
                    state     <= START;
                end
            end

            START: begin
                tx <= 1'b0;             // bit de inicio
                if (tick_cnt == TICKS - 1) begin
                    tick_cnt <= 0;
                    bit_idx  <= 0;
                    state    <= DATA;
                end else begin
                    tick_cnt <= tick_cnt + 1;
                end
            end

            DATA: begin
                tx <= shift_reg[0];     // LSB primero
                if (tick_cnt == TICKS - 1) begin
                    tick_cnt  <= 0;
                    shift_reg <= shift_reg >> 1;
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
                tx <= 1'b1;             // bit de parada
                if (tick_cnt == TICKS - 1) begin
                    tick_cnt <= 0;
                    busy     <= 1'b0;
                    state    <= IDLE;
                end else begin
                    tick_cnt <= tick_cnt + 1;
                end
            end

        endcase
    end
end

endmodule