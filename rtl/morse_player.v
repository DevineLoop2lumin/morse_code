//============================================================================
// Module:  morse_player
// Purpose: Plays back a Morse code pattern by blinking an LED.
//          Dot = short ON pulse, Dash = long ON pulse, with gaps between.
//          Controller triggers playback; player signals when done.
//
// Playback sequence for a pattern of length N:
//   symbol[N-1] ON → GAP → symbol[N-2] ON → GAP → ... → symbol[0] ON → DONE
//   (MSB first, matching the ROM encoding)
//============================================================================
module morse_player #(
    parameter PLAY_DOT_TICKS  = 30_000_000,   // 300 ms dot ON time
    parameter PLAY_DASH_TICKS = 90_000_000,   // 900 ms dash ON time
    parameter PLAY_GAP_TICKS  = 30_000_000    // 300 ms inter-symbol gap
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       start,          // 1-cycle pulse to begin playback
    input  wire [5:0] pattern,        // Morse pattern from ROM
    input  wire [2:0] length,         // Number of symbols
    output reg        led_out,        // LED output (1=ON)
    output reg        busy,           // 1 while playing
    output reg        done_pulse      // 1-cycle pulse when playback finished
);

    // Timer width must hold the largest tick count
    localparam TIMER_WIDTH = $clog2(PLAY_DASH_TICKS + 1);

    // FSM states
    localparam [2:0] S_IDLE    = 3'd0,
                     S_LOAD    = 3'd1,
                     S_PLAY_ON = 3'd2,
                     S_PLAY_GAP= 3'd3,
                     S_DONE    = 3'd4;

    reg [2:0]              state;
    reg [TIMER_WIDTH-1:0]  timer;
    reg [5:0]              pat_shift;    // Shifting copy of pattern
    reg [2:0]              sym_remaining;// Symbols left to play
    reg                    current_bit;  // Current symbol being played

    always @(posedge clk) begin
        if (rst) begin
            state         <= S_IDLE;
            timer         <= {TIMER_WIDTH{1'b0}};
            pat_shift     <= 6'b0;
            sym_remaining <= 3'd0;
            current_bit   <= 1'b0;
            led_out       <= 1'b0;
            busy          <= 1'b0;
            done_pulse    <= 1'b0;
        end else begin
            done_pulse <= 1'b0;  // Default: clear pulse

            case (state)
                // ────────────────────────────────────────
                S_IDLE: begin
                    led_out <= 1'b0;
                    busy    <= 1'b0;
                    if (start) begin
                        state <= S_LOAD;
                        busy  <= 1'b1;
                    end
                end

                // ────────────────────────────────────────
                // Load the pattern and prepare to play MSB first
                S_LOAD: begin
                    if (length == 3'd0) begin
                        // Nothing to play
                        state      <= S_DONE;
                    end else begin
                        // Shift pattern so MSB of significant bits is at bit[length-1]
                        pat_shift     <= pattern;
                        sym_remaining <= length;
                        // Extract the MSB (first symbol to play)
                        // Pattern is right-aligned, so first symbol is at bit[length-1]
                        current_bit   <= pattern[length - 1];
                        state         <= S_PLAY_ON;
                        timer         <= {TIMER_WIDTH{1'b0}};
                    end
                end

                // ────────────────────────────────────────
                // LED ON for dot or dash duration
                S_PLAY_ON: begin
                    led_out <= 1'b1;
                    if (current_bit == 1'b0) begin
                        // DOT
                        if (timer == PLAY_DOT_TICKS - 1) begin
                            led_out       <= 1'b0;
                            timer         <= {TIMER_WIDTH{1'b0}};
                            sym_remaining <= sym_remaining - 1'b1;
                            if (sym_remaining == 3'd1) begin
                                // Last symbol done
                                state <= S_DONE;
                            end else begin
                                state <= S_PLAY_GAP;
                            end
                        end else begin
                            timer <= timer + 1'b1;
                        end
                    end else begin
                        // DASH
                        if (timer == PLAY_DASH_TICKS - 1) begin
                            led_out       <= 1'b0;
                            timer         <= {TIMER_WIDTH{1'b0}};
                            sym_remaining <= sym_remaining - 1'b1;
                            if (sym_remaining == 3'd1) begin
                                state <= S_DONE;
                            end else begin
                                state <= S_PLAY_GAP;
                            end
                        end else begin
                            timer <= timer + 1'b1;
                        end
                    end
                end

                // ────────────────────────────────────────
                // Gap between symbols
                S_PLAY_GAP: begin
                    led_out <= 1'b0;
                    if (timer == PLAY_GAP_TICKS - 1) begin
                        timer <= {TIMER_WIDTH{1'b0}};
                        // Load next symbol: move to next lower bit
                        current_bit <= pat_shift[sym_remaining - 1];
                        state       <= S_PLAY_ON;
                    end else begin
                        timer <= timer + 1'b1;
                    end
                end

                // ────────────────────────────────────────
                S_DONE: begin
                    led_out    <= 1'b0;
                    done_pulse <= 1'b1;
                    state      <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
