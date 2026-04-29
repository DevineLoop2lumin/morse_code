//============================================================================
// Module:  morse_capture
// Purpose: Accumulate dot/dash symbols into a shift register pattern.
//          Detects end-of-input when the user is idle for IDLE_TIMEOUT cycles.
//          Detects invalid input (bad press or overflow beyond MAX_SYMBOLS).
//
// Pattern encoding: MSB-first. First symbol goes into the MSB position
// relative to the captured length. Implemented as left-shift, new bit at LSB.
//============================================================================
module morse_capture #(
    parameter IDLE_TIMEOUT = 200_000_000,  // 2 sec at 100 MHz
    parameter MAX_SYMBOLS  = 6
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       symbol_valid,     // 1-cycle pulse: valid symbol
    input  wire       symbol_bit,       // 0=dot, 1=dash
    input  wire       invalid_pulse,    // 1-cycle pulse: invalid press
    output reg [5:0]  captured_pattern,
    output reg [2:0]  captured_length,  // number of symbols captured (0–6)
    output reg        input_done,       // 1-cycle pulse: input complete
    output reg        input_invalid     // 1-cycle pulse: invalid detected
);

    // Idle counter width
    localparam IDLE_WIDTH = $clog2(IDLE_TIMEOUT + 1);

    reg [IDLE_WIDTH-1:0] idle_count;
    reg                  has_input;      // At least one symbol received

    always @(posedge clk) begin
        if (rst) begin
            captured_pattern <= 6'b000000;
            captured_length  <= 3'd0;
            idle_count       <= {IDLE_WIDTH{1'b0}};
            has_input        <= 1'b0;
            input_done       <= 1'b0;
            input_invalid    <= 1'b0;
        end else begin
            // Default: clear single-cycle pulses
            input_done    <= 1'b0;
            input_invalid <= 1'b0;

            // ── Handle invalid press ──
            if (invalid_pulse) begin
                input_invalid <= 1'b1;
                // Reset state for retry
                captured_pattern <= 6'b000000;
                captured_length  <= 3'd0;
                idle_count       <= {IDLE_WIDTH{1'b0}};
                has_input        <= 1'b0;

            // ── Handle valid symbol ──
            end else if (symbol_valid) begin
                if (captured_length < MAX_SYMBOLS) begin
                    // Shift left, insert new bit at LSB
                    captured_pattern <= {captured_pattern[MAX_SYMBOLS-2:0], symbol_bit};
                    captured_length  <= captured_length + 1'b1;
                    idle_count       <= {IDLE_WIDTH{1'b0}};
                    has_input        <= 1'b1;
                end else begin
                    // Overflow: too many symbols
                    input_invalid    <= 1'b1;
                    captured_pattern <= 6'b000000;
                    captured_length  <= 3'd0;
                    idle_count       <= {IDLE_WIDTH{1'b0}};
                    has_input        <= 1'b0;
                end

            // ── Idle timeout detection ──
            end else if (has_input) begin
                if (idle_count == IDLE_TIMEOUT - 1) begin
                    input_done <= 1'b1;
                    // Don't clear pattern/length here — controller needs them
                    idle_count <= {IDLE_WIDTH{1'b0}};
                    has_input  <= 1'b0;
                end else begin
                    idle_count <= idle_count + 1'b1;
                end
            end
        end
    end

endmodule
