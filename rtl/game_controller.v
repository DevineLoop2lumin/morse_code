//============================================================================
// Module:  game_controller
// Purpose: Central game logic FSM. Handles mode switching, level progression,
//          Morse playback triggering, pass/fail evaluation, and display control.
//
// FSM States:
//   IDLE       → Display level/character, prepare for input
//   PLAYBACK   → Trigger morse_player (encoding mode + hint enabled)
//   WAIT_INPUT → Accept user Morse input, wait for input_done
//   EVALUATE   → Compare captured pattern with ROM
//   SHOW_PASS  → Display "PASS" for 2 sec
//   SHOW_ERROR → Display "ERR " for 2 sec
//   SHOW_DONE  → Display "donE" for 2 sec after all levels complete
//============================================================================
module game_controller #(
    parameter NUM_LEVELS    = 36,
    parameter DISPLAY_TICKS = 200_000_000  // 2 sec result display
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       sw_mode,           // 0=encoding, 1=decoding
    input  wire       sw_hint,           // 1=playback hint enabled
    input  wire [5:0] captured_pattern,
    input  wire [2:0] captured_length,
    input  wire       input_done,        // Pulse: user finished input
    input  wire       input_invalid,     // Pulse: invalid input detected

    // ROM interface
    output reg  [5:0] rom_addr,
    input  wire [5:0] rom_pattern,
    input  wire [2:0] rom_length,
    input  wire [7:0] rom_ascii,

    // Morse player interface
    output reg        player_start,      // Pulse to start playback
    input  wire       player_busy,
    input  wire       player_done,

    // Display outputs (ASCII characters for 4 digits)
    output reg [7:0]  disp_char3,        // Leftmost  digit
    output reg [7:0]  disp_char2,
    output reg [7:0]  disp_char1,
    output reg [7:0]  disp_char0,        // Rightmost digit

    // Capture reset (active high pulse)
    output reg        capture_rst,

    // Debug
    output reg [5:0]  current_level,
    output reg [2:0]  fsm_state_out      // For LED debug
);

    // ── FSM State Encoding ──
    localparam [2:0] S_IDLE       = 3'd0,
                     S_PLAYBACK   = 3'd1,
                     S_WAIT_INPUT = 3'd2,
                     S_EVALUATE   = 3'd3,
                     S_SHOW_PASS  = 3'd4,
                     S_SHOW_ERROR = 3'd5,
                     S_SHOW_DONE  = 3'd6,
                     S_RESET_CAP  = 3'd7;

    reg [2:0] state;

    // Display timer
    localparam TIMER_WIDTH = $clog2(DISPLAY_TICKS + 1);
    reg [TIMER_WIDTH-1:0] display_timer;

    // Previous mode for edge detection
    reg prev_mode;

    // Level number decomposition for "L01"–"L36" display
    // level 0 → "L01", level 35 → "L36"
    wire [5:0] display_level;
    wire [3:0] tens_digit;
    wire [3:0] ones_digit;

    assign display_level = current_level + 1'b1;  // 1-indexed for display

    // Simple binary-to-BCD for 1–36
    assign tens_digit = (display_level >= 6'd30) ? 4'd3 :
                        (display_level >= 6'd20) ? 4'd2 :
                        (display_level >= 6'd10) ? 4'd1 : 4'd0;
    assign ones_digit = display_level - (tens_digit * 4'd10);

    // Convert BCD digit to ASCII
    wire [7:0] tens_ascii;
    wire [7:0] ones_ascii;
    assign tens_ascii = {4'h3, tens_digit};  // '0'=0x30, '1'=0x31, etc.
    assign ones_ascii = {4'h3, ones_digit};

    // ── Input Synchronization (Metastability Guard) ──
    reg sw_mode_sync0, sw_mode_sync1;
    reg sw_hint_sync0, sw_hint_sync1;

    always @(posedge clk) begin
        sw_mode_sync0 <= sw_mode;
        sw_mode_sync1 <= sw_mode_sync0;
        sw_hint_sync0 <= sw_hint;
        sw_hint_sync1 <= sw_hint_sync0;
    end

    // ── Main FSM ──
    always @(posedge clk) begin
        if (rst) begin
            state         <= S_IDLE;
            current_level <= 6'd0;
            display_timer <= {TIMER_WIDTH{1'b0}};
            prev_mode     <= 1'b0;
            player_start  <= 1'b0;
            capture_rst   <= 1'b0;
            rom_addr      <= 6'd0;
            disp_char3    <= 8'h20;
            disp_char2    <= 8'h20;
            disp_char1    <= 8'h20;
            disp_char0    <= 8'h20;
            fsm_state_out <= 3'd0;
        end else begin
            // Defaults
            player_start  <= 1'b0;
            capture_rst   <= 1'b0;
            fsm_state_out <= state;
            rom_addr      <= current_level;
            prev_mode     <= sw_mode_sync1;

            // ── Mode switch detection: reset game on mode change ──
            if (sw_mode_sync1 != prev_mode) begin
                current_level <= 6'd0;
                capture_rst   <= 1'b1;
                state         <= S_IDLE;
            end else begin

                case (state)
                    // ────────────────────────────────────────
                    // IDLE: Set up display, then move to RESET_CAP
                    S_IDLE: begin
                        capture_rst   <= 1'b1;  // Assert reset for capture
                        display_timer <= {TIMER_WIDTH{1'b0}};

                        if (sw_mode_sync1 == 1'b0) begin
                            // ── Encoding Mode: show "L01" ──
                            disp_char3 <= 8'h4C;   // 'L'
                            disp_char2 <= tens_ascii;
                            disp_char1 <= ones_ascii;
                            disp_char0 <= 8'h20;   // blank
                        end else begin
                            // ── Decoding Mode: show target character ──
                            disp_char3 <= 8'h20;   // blank
                            disp_char2 <= 8'h20;   // blank
                            disp_char1 <= 8'h20;   // blank
                            disp_char0 <= rom_ascii;
                        end

                        state <= S_RESET_CAP;
                    end

                    // ────────────────────────────────────────
                    // RESET_CAP: Hold capture reset one more cycle, then proceed
                    S_RESET_CAP: begin
                        capture_rst <= 1'b1;  // Keep reset active

                        if (sw_mode_sync1 == 1'b0 && sw_hint_sync1) begin
                            state <= S_PLAYBACK;
                        end else begin
                            state <= S_WAIT_INPUT;
                        end
                    end

                    // ────────────────────────────────────────
                    S_PLAYBACK: begin
                        // Trigger morse player (one-shot)
                        if (!player_busy && !player_start) begin
                            player_start <= 1'b1;
                        end

                        // Keep showing level while playing
                        disp_char3 <= 8'h4C;   // 'L'
                        disp_char2 <= tens_ascii;
                        disp_char1 <= ones_ascii;
                        disp_char0 <= 8'h20;

                        // Wait for playback to finish
                        if (player_done) begin
                            capture_rst <= 1'b1;
                            state       <= S_WAIT_INPUT;
                        end
                    end

                    // ────────────────────────────────────────
                    S_WAIT_INPUT: begin
                        // Maintain display
                        if (sw_mode_sync1 == 1'b0) begin
                            disp_char3 <= 8'h4C;
                            disp_char2 <= tens_ascii;
                            disp_char1 <= ones_ascii;
                            disp_char0 <= 8'h20;
                        end else begin
                            disp_char3 <= 8'h20;
                            disp_char2 <= 8'h20;
                            disp_char1 <= 8'h20;
                            disp_char0 <= rom_ascii;
                        end

                        // Check for input completion
                        if (input_done) begin
                            state <= S_EVALUATE;
                        end else if (input_invalid) begin
                            state <= S_SHOW_ERROR;
                            display_timer <= {TIMER_WIDTH{1'b0}};
                        end
                    end

                    // ────────────────────────────────────────
                    S_EVALUATE: begin
                        // Compare captured pattern with ROM
                        if (captured_length == rom_length &&
                            captured_pattern[5:0] == rom_pattern[5:0]) begin
                            // ── MATCH ──
                            if (current_level == NUM_LEVELS - 1) begin
                                // All levels complete
                                state         <= S_SHOW_DONE;
                                display_timer <= {TIMER_WIDTH{1'b0}};
                            end else begin
                                state         <= S_SHOW_PASS;
                                display_timer <= {TIMER_WIDTH{1'b0}};
                            end
                        end else begin
                            // ── MISMATCH ──
                            state         <= S_SHOW_ERROR;
                            display_timer <= {TIMER_WIDTH{1'b0}};
                        end
                    end

                    // ────────────────────────────────────────
                    S_SHOW_PASS: begin
                        // Display "PASS"
                        disp_char3 <= 8'h50;  // 'P'
                        disp_char2 <= 8'h41;  // 'A'
                        disp_char1 <= 8'h53;  // 'S'
                        disp_char0 <= 8'h53;  // 'S'

                        if (display_timer == DISPLAY_TICKS - 1) begin
                            current_level <= current_level + 1'b1;
                            state         <= S_IDLE;
                        end else begin
                            display_timer <= display_timer + 1'b1;
                        end
                    end

                    // ────────────────────────────────────────
                    S_SHOW_ERROR: begin
                        // Display "ERR "
                        disp_char3 <= 8'h45;  // 'E'
                        disp_char2 <= 8'h52;  // 'R' (will show as 'r')
                        disp_char1 <= 8'h52;  // 'R'
                        disp_char0 <= 8'h20;  // blank

                        if (display_timer == DISPLAY_TICKS - 1) begin
                            state <= S_IDLE;
                            // Same level, capture will be reset in IDLE
                        end else begin
                            display_timer <= display_timer + 1'b1;
                        end
                    end

                    // ────────────────────────────────────────
                    S_SHOW_DONE: begin
                        // Display "donE"
                        disp_char3 <= 8'h44;  // 'd' (shows as 'd')
                        disp_char2 <= 8'h6F;  // 'o' (lowercase)
                        disp_char1 <= 8'h6E;  // 'n' (lowercase)
                        disp_char0 <= 8'h45;  // 'E'

                        if (display_timer == DISPLAY_TICKS - 1) begin
                            current_level <= 6'd0;  // Reset to beginning
                            state         <= S_IDLE;
                        end else begin
                            display_timer <= display_timer + 1'b1;
                        end
                    end

                    default: state <= S_IDLE;
                endcase
            end
        end
    end

endmodule
