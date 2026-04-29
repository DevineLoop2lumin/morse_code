//============================================================================
// Module:  press_classifier
// Purpose: FSM-based classifier that measures the duration of a debounced
//          button press and classifies it as DOT, DASH, or INVALID.
//
// Outputs single-cycle pulses:
//   symbol_valid  — valid dot or dash detected
//   symbol_bit    — 0 = dot, 1 = dash (valid only when symbol_valid=1)
//   invalid_pulse — press duration outside valid ranges
//============================================================================
module press_classifier #(
    parameter DOT_MIN  = 20_000_000,   // 200 ms  — minimum for a dot
    parameter DOT_MAX  = 80_000_000,   // 800 ms  — maximum for a dot
    parameter DASH_MIN = 80_000_000,   // 800 ms  — minimum for a dash
    parameter DASH_MAX = 150_000_000   // 1.5 s   — maximum for a dash
)(
    input  wire clk,
    input  wire rst,
    input  wire btn_debounced,
    output reg  symbol_valid,
    output reg  symbol_bit,
    output reg  invalid_pulse
);

    // Counter width must hold DASH_MAX + 1 to detect "too long" presses
    localparam CNT_WIDTH = $clog2(DASH_MAX + 2);

    // FSM states
    localparam [1:0] S_IDLE    = 2'd0,
                     S_PRESSED = 2'd1,
                     S_CLASSIFY = 2'd2;

    reg [1:0]            state;
    reg [CNT_WIDTH-1:0]  press_count;
    reg                  btn_prev;       // Previous button state for edge detect

    // ── FSM ──
    always @(posedge clk) begin
        if (rst) begin
            state         <= S_IDLE;
            press_count   <= {CNT_WIDTH{1'b0}};
            btn_prev      <= 1'b0;
            symbol_valid  <= 1'b0;
            symbol_bit    <= 1'b0;
            invalid_pulse <= 1'b0;
        end else begin
            // Default: clear single-cycle pulses
            symbol_valid  <= 1'b0;
            invalid_pulse <= 1'b0;
            btn_prev      <= btn_debounced;

            case (state)
                // ────────────────────────────────────────
                S_IDLE: begin
                    press_count <= {CNT_WIDTH{1'b0}};
                    // Detect rising edge (button press)
                    if (btn_debounced && !btn_prev) begin
                        state       <= S_PRESSED;
                        press_count <= {CNT_WIDTH{1'b0}};
                    end
                end

                // ────────────────────────────────────────
                S_PRESSED: begin
                    // Count while button is held
                    if (btn_debounced) begin
                        // Saturate counter at DASH_MAX + 1 to track "Too Long"
                        if (press_count <= DASH_MAX)
                            press_count <= press_count + 1'b1;
                    end

                    // Detect falling edge (button release)
                    if (!btn_debounced && btn_prev) begin
                        state <= S_CLASSIFY;
                    end

                    // If button held beyond DASH_MAX, it's already invalid
                    // but we wait for release to generate the pulse
                end

                // ────────────────────────────────────────
                S_CLASSIFY: begin
                    state <= S_IDLE;
                    if (press_count >= DOT_MIN && press_count < DOT_MAX) begin
                        // Valid DOT
                        symbol_valid <= 1'b1;
                        symbol_bit   <= 1'b0;
                    end else if (press_count >= DASH_MIN && press_count <= DASH_MAX) begin
                        // Valid DASH
                        symbol_valid <= 1'b1;
                        symbol_bit   <= 1'b1;
                    end else begin
                        // Too short or too long — invalid
                        invalid_pulse <= 1'b1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
