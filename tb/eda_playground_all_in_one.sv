// --- BEGIN debounce.v ---
//============================================================================
// Module:  debounce
// Purpose: Eliminate mechanical bounce from push button inputs.
//          Uses a counter-based approach: output only changes when the input
//          has been stable for DEBOUNCE_TICKS consecutive clock cycles.
//============================================================================
module debounce #(
    parameter DEBOUNCE_TICKS = 1_000_000  // 10 ms at 100 MHz
)(
    input  wire clk,
    input  wire rst,
    input  wire btn_in,
    output reg  btn_out
);

    // Counter width must hold DEBOUNCE_TICKS
    localparam CNT_WIDTH = $clog2(DEBOUNCE_TICKS + 1);

    reg [CNT_WIDTH-1:0] count = 0;
    reg                 btn_sync_0 = 0, btn_sync_1 = 0;  // 2-FF synchronizer

    initial begin
        count = 0;
        btn_sync_0 = 0;
        btn_sync_1 = 0;
        btn_out = 0;
    end

    // ── Two-stage synchronizer (metastability guard) ──
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            btn_sync_0 <= 1'b0;
            btn_sync_1 <= 1'b0;
        end else begin
            btn_sync_0 <= btn_in;
            btn_sync_1 <= btn_sync_0;
        end
    end

    // ── Debounce counter logic ──
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            count   <= {CNT_WIDTH{1'b0}};
            btn_out <= 1'b0;
        end else begin
            if (btn_sync_1 != btn_out) begin
                // Input differs from output — count up
                if (count == DEBOUNCE_TICKS - 1) begin
                    btn_out <= btn_sync_1;   // Stable long enough, update
                    count   <= {CNT_WIDTH{1'b0}};
                end else begin
                    count <= count + 1'b1;
                end
            end else begin
                // Input matches output — reset counter
                count <= {CNT_WIDTH{1'b0}};
            end
        end
    end

endmodule

// --- END debounce.v ---

// --- BEGIN game_controller.v ---
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

    // ── Main FSM ──
    always @(posedge clk or posedge rst) begin
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
            prev_mode     <= sw_mode;

            // ── Mode switch detection: reset game on mode change ──
            if (sw_mode != prev_mode) begin
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

                        if (sw_mode == 1'b0) begin
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

                        if (sw_mode == 1'b0 && sw_hint) begin
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
                        if (sw_mode == 1'b0) begin
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

// --- END game_controller.v ---

// --- BEGIN morse_capture.v ---
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

    always @(posedge clk or posedge rst) begin
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
                    captured_pattern <= {captured_pattern[4:0], symbol_bit};
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

// --- END morse_capture.v ---

// --- BEGIN morse_player.v ---
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

    always @(posedge clk or posedge rst) begin
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

// --- END morse_player.v ---

// --- BEGIN morse_rom.v ---
//============================================================================
// Module:  morse_rom
// Purpose: Combinational ROM storing Morse code patterns for A–Z (0–25)
//          and 0–9 (26–35). Total: 36 entries.
//
// Encoding: dot=0, dash=1, MSB-first within the significant bits.
//   Example: A = .- = 01 (2 symbols), pattern stored as 6'b000001
//            B = -... = 1000 (4 symbols), pattern stored as 6'b001000
//
// The pattern bits are right-aligned (LSB-aligned) to match the shift
// register output from morse_capture (which shifts left, new bit at LSB).
//============================================================================
module morse_rom (
    input  wire [5:0]  addr,       // 0–35
    output reg  [5:0]  pattern,    // Morse pattern (dot=0, dash=1)
    output reg  [2:0]  length,     // Number of symbols (1–6)
    output reg  [7:0]  ascii_char  // ASCII code of character
);

    always @(*) begin
        case (addr)
            //         Pattern    Len  ASCII
            // ──── Letters A–Z ────
            6'd0:  begin pattern = 6'b000001; length = 3'd2; ascii_char = 8'h41; end // A .-
            6'd1:  begin pattern = 6'b001000; length = 3'd4; ascii_char = 8'h42; end // B -...
            6'd2:  begin pattern = 6'b001010; length = 3'd4; ascii_char = 8'h43; end // C -.-.
            6'd3:  begin pattern = 6'b000100; length = 3'd3; ascii_char = 8'h44; end // D -..
            6'd4:  begin pattern = 6'b000000; length = 3'd1; ascii_char = 8'h45; end // E .
            6'd5:  begin pattern = 6'b000010; length = 3'd4; ascii_char = 8'h46; end // F ..-.
            6'd6:  begin pattern = 6'b000110; length = 3'd3; ascii_char = 8'h47; end // G --.
            6'd7:  begin pattern = 6'b000000; length = 3'd4; ascii_char = 8'h48; end // H ....
            6'd8:  begin pattern = 6'b000000; length = 3'd2; ascii_char = 8'h49; end // I ..
            6'd9:  begin pattern = 6'b000111; length = 3'd4; ascii_char = 8'h4A; end // J .---
            6'd10: begin pattern = 6'b000101; length = 3'd3; ascii_char = 8'h4B; end // K -.-
            6'd11: begin pattern = 6'b000100; length = 3'd4; ascii_char = 8'h4C; end // L .-..
            6'd12: begin pattern = 6'b000011; length = 3'd2; ascii_char = 8'h4D; end // M --
            6'd13: begin pattern = 6'b000010; length = 3'd2; ascii_char = 8'h4E; end // N -.
            6'd14: begin pattern = 6'b000111; length = 3'd3; ascii_char = 8'h4F; end // O ---
            6'd15: begin pattern = 6'b000110; length = 3'd4; ascii_char = 8'h50; end // P .--.
            6'd16: begin pattern = 6'b001101; length = 3'd4; ascii_char = 8'h51; end // Q --.-
            6'd17: begin pattern = 6'b000010; length = 3'd3; ascii_char = 8'h52; end // R .-.
            6'd18: begin pattern = 6'b000000; length = 3'd3; ascii_char = 8'h53; end // S ...
            6'd19: begin pattern = 6'b000001; length = 3'd1; ascii_char = 8'h54; end // T -
            6'd20: begin pattern = 6'b000001; length = 3'd3; ascii_char = 8'h55; end // U ..-
            6'd21: begin pattern = 6'b000001; length = 3'd4; ascii_char = 8'h56; end // V ...-
            6'd22: begin pattern = 6'b000011; length = 3'd3; ascii_char = 8'h57; end // W .--
            6'd23: begin pattern = 6'b001001; length = 3'd4; ascii_char = 8'h58; end // X -..-
            6'd24: begin pattern = 6'b001011; length = 3'd4; ascii_char = 8'h59; end // Y -.--
            6'd25: begin pattern = 6'b001100; length = 3'd4; ascii_char = 8'h5A; end // Z --..

            // ──── Digits 0–9 ────
            6'd26: begin pattern = 6'b011111; length = 3'd5; ascii_char = 8'h30; end // 0 -----
            6'd27: begin pattern = 6'b001111; length = 3'd5; ascii_char = 8'h31; end // 1 .----
            6'd28: begin pattern = 6'b000111; length = 3'd5; ascii_char = 8'h32; end // 2 ..---
            6'd29: begin pattern = 6'b000011; length = 3'd5; ascii_char = 8'h33; end // 3 ...--
            6'd30: begin pattern = 6'b000001; length = 3'd5; ascii_char = 8'h34; end // 4 ....-
            6'd31: begin pattern = 6'b000000; length = 3'd5; ascii_char = 8'h35; end // 5 .....
            6'd32: begin pattern = 6'b010000; length = 3'd5; ascii_char = 8'h36; end // 6 -....
            6'd33: begin pattern = 6'b011000; length = 3'd5; ascii_char = 8'h37; end // 7 --...
            6'd34: begin pattern = 6'b011100; length = 3'd5; ascii_char = 8'h38; end // 8 ---..
            6'd35: begin pattern = 6'b011110; length = 3'd5; ascii_char = 8'h39; end // 9 ----.

            default: begin pattern = 6'b000000; length = 3'd0; ascii_char = 8'h20; end // space
        endcase
    end

endmodule

// --- END morse_rom.v ---

// --- BEGIN press_classifier.v ---
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
    always @(posedge clk or posedge rst) begin
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

// --- END press_classifier.v ---

// --- BEGIN seg7_driver.v ---
//============================================================================
// Module:  seg7_driver
// Purpose: Multiplexed 4-digit 7-segment display driver for Basys 3.
//          Accepts 4 ASCII characters and drives the common-anode display.
//          Refresh rate ~1 kHz (each digit active for ~1 ms).
//
// Basys 3 7-segment: active LOW cathodes (seg), active LOW anodes (an).
// Segment mapping: seg[6:0] = {CA, CB, CC, CD, CE, CF, CG}
//   Segment layout:
//       AAA
//      F   B
//       GGG
//      E   C
//       DDD
//============================================================================
module seg7_driver #(
    parameter REFRESH_TICKS = 100_000  // ~1 ms per digit at 100 MHz
)(
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] char0,   // Rightmost digit (ASCII)
    input  wire [7:0] char1,
    input  wire [7:0] char2,
    input  wire [7:0] char3,   // Leftmost digit (ASCII)
    output reg  [6:0] seg,     // Segment cathodes (active low)
    output reg        dp,      // Decimal point (active low, always off)
    output reg  [3:0] an       // Anode enables (active low)
);

    // Refresh counter
    localparam CNT_WIDTH = $clog2(REFRESH_TICKS);
    reg [CNT_WIDTH-1:0] refresh_count;
    reg [1:0]           digit_sel;     // Which digit is currently active
    reg [7:0]           current_char;  // ASCII char for active digit
    reg [6:0]           seg_pattern;   // Decoded segment pattern (active high)

    // ── Refresh counter & digit selection ──
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            refresh_count <= {CNT_WIDTH{1'b0}};
            digit_sel     <= 2'd0;
        end else begin
            if (refresh_count == REFRESH_TICKS - 1) begin
                refresh_count <= {CNT_WIDTH{1'b0}};
                digit_sel     <= digit_sel + 1'b1;
            end else begin
                refresh_count <= refresh_count + 1'b1;
            end
        end
    end

    // ── Multiplex: select which character to display ──
    always @(*) begin
        case (digit_sel)
            2'd0: current_char = char0;
            2'd1: current_char = char1;
            2'd2: current_char = char2;
            2'd3: current_char = char3;
            default: current_char = 8'h20; // space
        endcase
    end

    // ── ASCII to 7-segment decoder ──
    // Output is active HIGH internally, inverted to active LOW for output
    //   seg_pattern[6:0] = {A, B, C, D, E, F, G}
    always @(*) begin
        case (current_char)
            // ──── Digits 0–9 ────
            8'h30: seg_pattern = 7'b1111110; // 0
            8'h31: seg_pattern = 7'b0110000; // 1
            8'h32: seg_pattern = 7'b1101101; // 2
            8'h33: seg_pattern = 7'b1111001; // 3
            8'h34: seg_pattern = 7'b0110011; // 4
            8'h35: seg_pattern = 7'b1011011; // 5
            8'h36: seg_pattern = 7'b1011111; // 6
            8'h37: seg_pattern = 7'b1110000; // 7
            8'h38: seg_pattern = 7'b1111111; // 8
            8'h39: seg_pattern = 7'b1111011; // 9

            // ──── Letters (uppercase) ────
            8'h41: seg_pattern = 7'b1110111; // A
            8'h42: seg_pattern = 7'b0011111; // b
            8'h43: seg_pattern = 7'b1001110; // C
            8'h44: seg_pattern = 7'b0111101; // d
            8'h45: seg_pattern = 7'b1001111; // E
            8'h46: seg_pattern = 7'b1000111; // F
            8'h47: seg_pattern = 7'b1011110; // G
            8'h48: seg_pattern = 7'b0110111; // H
            8'h49: seg_pattern = 7'b0110000; // I (same as 1)
            8'h4A: seg_pattern = 7'b0111100; // J
            8'h4B: seg_pattern = 7'b0110111; // K (same as H)
            8'h4C: seg_pattern = 7'b0001110; // L
            8'h4D: seg_pattern = 7'b1110110; // M (upper part)
            8'h4E: seg_pattern = 7'b0010101; // n
            8'h4F: seg_pattern = 7'b1111110; // O (same as 0)
            8'h50: seg_pattern = 7'b1100111; // P
            8'h51: seg_pattern = 7'b1110011; // Q
            8'h52: seg_pattern = 7'b0000101; // r
            8'h53: seg_pattern = 7'b1011011; // S (same as 5)
            8'h54: seg_pattern = 7'b0001111; // t
            8'h55: seg_pattern = 7'b0111110; // U
            8'h56: seg_pattern = 7'b0111110; // V (same as U)
            8'h57: seg_pattern = 7'b0111110; // W (same as U)
            8'h58: seg_pattern = 7'b0110111; // X (same as H)
            8'h59: seg_pattern = 7'b0111011; // Y
            8'h5A: seg_pattern = 7'b1101101; // Z (same as 2)

            // ──── Lowercase letters (for display strings) ────
            8'h6F: seg_pattern = 7'b0011101; // o (lowercase)
            8'h6E: seg_pattern = 7'b0010101; // n (lowercase)
            8'h72: seg_pattern = 7'b0000101; // r (lowercase)

            // ──── Special characters ────
            8'h20: seg_pattern = 7'b0000000; // Space (blank)
            8'h2D: seg_pattern = 7'b0000001; // - (dash/minus)
            8'h2E: seg_pattern = 7'b0000000; // . (handled by dp)
            8'h5F: seg_pattern = 7'b0001000; // _ (underscore)

            default: seg_pattern = 7'b0000000; // Blank for unknown
        endcase
    end

    // ── Register outputs (active LOW for Basys 3) ──
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            seg <= 7'b1111111;  // All off (active low)
            an  <= 4'b1111;     // All off (active low)
            dp  <= 1'b1;        // DP off (active low)
        end else begin
            // Invert for active-low cathodes
            seg <= ~seg_pattern;
            dp  <= 1'b1;  // DP always off

            // Enable only the active digit (active low)
            case (digit_sel)
                2'd0: an <= 4'b1110;
                2'd1: an <= 4'b1101;
                2'd2: an <= 4'b1011;
                2'd3: an <= 4'b0111;
                default: an <= 4'b1111;
            endcase
        end
    end

endmodule

// --- END seg7_driver.v ---

// --- BEGIN morse_game_top.v ---
//============================================================================
// Module:  morse_game_top
// Purpose: Top-level module integrating all components for the Morse Code
//          Training Game on the Basys 3 FPGA board.
//
// Pin Mapping:
//   clk     — 100 MHz oscillator (W5)
//   btnC    — Morse input button (U18)
//   btnU    — Reset button (T18)
//   sw[0]   — Mode select: 0=Encoding, 1=Decoding (V17)
//   sw[1]   — Playback hint enable (V16)
//   seg[6:0]— 7-segment cathodes (active low)
//   dp      — Decimal point (active low)
//   an[3:0] — 7-segment anodes (active low)
//   led[15:0] — Debug LEDs
//============================================================================
module morse_game_top (
    input  wire        clk,      // 100 MHz
    input  wire        btnC,     // Morse input
    input  wire        btnU,     // Reset
    input  wire [1:0]  sw,       // sw[0]=mode, sw[1]=hint
    output wire [6:0]  seg,      // 7-seg cathodes
    output wire        dp,       // Decimal point
    output wire [3:0]  an,       // 7-seg anodes
    output wire [15:0] led       // Debug LEDs
);

    // ════════════════════════════════════════════════════════════════
    //  Internal Wires
    // ════════════════════════════════════════════════════════════════

    // Debounced buttons
    wire btn_morse_db;
    wire btn_reset_db;

    // Press classifier outputs
    wire symbol_valid;
    wire symbol_bit;
    wire invalid_pulse;

    // Morse capture outputs
    wire [5:0] captured_pattern;
    wire [2:0] captured_length;
    wire       input_done;
    wire       input_invalid;

    // ROM interface
    wire [5:0] rom_addr;
    wire [5:0] rom_pattern;
    wire [2:0] rom_length;
    wire [7:0] rom_ascii;

    // Morse player interface
    wire       player_start;
    wire       player_busy;
    wire       player_done;
    wire       player_led;

    // Game controller outputs
    wire [7:0] disp_char3, disp_char2, disp_char1, disp_char0;
    wire       capture_rst;
    wire [5:0] current_level;
    wire [2:0] fsm_state;

    // Combined reset for capture module
    wire capture_reset_combined;
    assign capture_reset_combined = btn_reset_db | capture_rst;

    // ════════════════════════════════════════════════════════════════
    //  Module Instantiations
    // ════════════════════════════════════════════════════════════════

    // ── Debounce: Morse input button ──
    debounce #(
        .DEBOUNCE_TICKS(10)  // 10 ms
    ) u_debounce_morse (
        .clk    (clk),
        .rst    (btn_reset_db),
        .btn_in (btnC),
        .btn_out(btn_morse_db)
    );

    // ── Debounce: Reset button ──
    // Note: Reset debounce uses raw async reset from btnU
    debounce #(
        .DEBOUNCE_TICKS(10)  // 10 ms
    ) u_debounce_reset (
        .clk    (clk),
        .rst    (1'b0),           // No reset for the reset debouncer
        .btn_in (btnU),
        .btn_out(btn_reset_db)
    );

    // ── Press Duration Classifier ──
    press_classifier #(
        .DOT_MIN(200),   // 200 ms
        .DOT_MAX(800),   // 800 ms
        .DASH_MIN(800),   // 800 ms
        .DASH_MAX(1500)   // 1.5 s
    ) u_classifier (
        .clk          (clk),
        .rst          (btn_reset_db),
        .btn_debounced(btn_morse_db),
        .symbol_valid (symbol_valid),
        .symbol_bit   (symbol_bit),
        .invalid_pulse(invalid_pulse)
    );

    // ── Morse Capture ──
    morse_capture #(
        .IDLE_TIMEOUT(2000),  // 2 sec
        .MAX_SYMBOLS (6)
    ) u_capture (
        .clk             (clk),
        .rst             (capture_reset_combined),
        .symbol_valid    (symbol_valid),
        .symbol_bit      (symbol_bit),
        .invalid_pulse   (invalid_pulse),
        .captured_pattern(captured_pattern),
        .captured_length (captured_length),
        .input_done      (input_done),
        .input_invalid   (input_invalid)
    );

    // ── Morse ROM ──
    morse_rom u_rom (
        .addr      (rom_addr),
        .pattern   (rom_pattern),
        .length    (rom_length),
        .ascii_char(rom_ascii)
    );

    // ── Morse Player (LED playback) ──
    morse_player #(
        .PLAY_DOT_TICKS(300),  // 300 ms
        .PLAY_DASH_TICKS(900),  // 900 ms
        .PLAY_GAP_TICKS(300)   // 300 ms
    ) u_player (
        .clk       (clk),
        .rst       (btn_reset_db),
        .start     (player_start),
        .pattern   (rom_pattern),
        .length    (rom_length),
        .led_out   (player_led),
        .busy      (player_busy),
        .done_pulse(player_done)
    );

    // ── Game Controller FSM ──
    game_controller #(
        .NUM_LEVELS   (36),
        .DISPLAY_TICKS(2000)  // 2 sec
    ) u_controller (
        .clk             (clk),
        .rst             (btn_reset_db),
        .sw_mode         (sw[0]),
        .sw_hint         (sw[1]),
        .captured_pattern(captured_pattern),
        .captured_length (captured_length),
        .input_done      (input_done),
        .input_invalid   (input_invalid),
        .rom_addr        (rom_addr),
        .rom_pattern     (rom_pattern),
        .rom_length      (rom_length),
        .rom_ascii       (rom_ascii),
        .player_start    (player_start),
        .player_busy     (player_busy),
        .player_done     (player_done),
        .disp_char3      (disp_char3),
        .disp_char2      (disp_char2),
        .disp_char1      (disp_char1),
        .disp_char0      (disp_char0),
        .capture_rst     (capture_rst),
        .current_level   (current_level),
        .fsm_state_out   (fsm_state)
    );

    // ── 7-Segment Display Driver ──
    seg7_driver #(
        .REFRESH_TICKS(10)  // ~1 ms
    ) u_display (
        .clk  (clk),
        .rst  (btn_reset_db),
        .char0(disp_char0),
        .char1(disp_char1),
        .char2(disp_char2),
        .char3(disp_char3),
        .seg  (seg),
        .dp   (dp),
        .an   (an)
    );

    // ════════════════════════════════════════════════════════════════
    //  Debug LED Assignments
    // ════════════════════════════════════════════════════════════════
    //
    //  led[0]     — Debounced Morse button state
    //  led[1]     — symbol_valid (latched for visibility)
    //  led[2]     — symbol_bit (0=dot, 1=dash)
    //  led[3]     — input_done
    //  led[4]     — input_invalid
    //  led[5]     — Mode switch state
    //  led[6]     — Hint switch state
    //  led[7]     — Morse player LED output
    //  led[11:8]  — Current level [3:0]
    //  led[15:12] — FSM state (padded to 4 bits)

    // Latch symbol_valid for visibility (stays on until next symbol)
    reg led_sym_valid_latch;
    reg led_sym_bit_latch;
    reg led_input_done_latch;
    reg led_input_invalid_latch;

    always @(posedge clk or posedge btn_reset_db) begin
        if (btn_reset_db) begin
            led_sym_valid_latch   <= 1'b0;
            led_sym_bit_latch     <= 1'b0;
            led_input_done_latch  <= 1'b0;
            led_input_invalid_latch <= 1'b0;
        end else begin
            if (symbol_valid) begin
                led_sym_valid_latch <= 1'b1;
                led_sym_bit_latch   <= symbol_bit;
            end
            if (input_done)
                led_input_done_latch <= 1'b1;
            if (input_invalid)
                led_input_invalid_latch <= 1'b1;

            // Clear latches when entering IDLE state
            if (fsm_state == 3'd0) begin
                led_sym_valid_latch     <= 1'b0;
                led_input_done_latch    <= 1'b0;
                led_input_invalid_latch <= 1'b0;
            end
        end
    end

    assign led[0]     = btn_morse_db;
    assign led[1]     = led_sym_valid_latch;
    assign led[2]     = led_sym_bit_latch;
    assign led[3]     = led_input_done_latch;
    assign led[4]     = led_input_invalid_latch;
    assign led[5]     = sw[0];
    assign led[6]     = sw[1];
    assign led[7]     = player_led;
    assign led[11:8]  = current_level[3:0];
    assign led[12]    = fsm_state[0];
    assign led[13]    = fsm_state[1];
    assign led[14]    = fsm_state[2];
    assign led[15]    = 1'b0;

endmodule

// --- END morse_game_top.v ---


// --- BEGIN tb_morse_game_top.v ---
`timescale 1ns / 1ps

module tb_morse_game_top();
    // Inputs
    reg clk;
    reg btnC;
    reg btnU;
    reg [1:0] sw;

    // Outputs
    wire [6:0] seg;
    wire dp;
    wire [3:0] an;
    wire [15:0] led;

    // Instantiate the Unit Under Test (UUT)
    morse_game_top uut (
        .clk(clk), 
        .btnC(btnC), 
        .btnU(btnU), 
        .sw(sw), 
        .seg(seg), 
        .dp(dp), 
        .an(an), 
        .led(led)
    );

    // Clock generation (100 MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        // Open wave dump for EDA playground
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_morse_game_top);

        // Initialize Inputs
        btnC = 0;
        btnU = 0;
        sw = 0;

        // Reset the system
        #100;
        btnU = 1;
        #100;
        btnU = 0;
        #100;

        // 1. Simulate a 'Dot'
        btnC = 1;
        #4000;       // Hold for 400 cycles (Valid Dot)
        btnC = 0;
        
        // 2. Wait for a small gap between presses
        #2000;       // Gap of 200 cycles
        
        // 3. Simulate a 'Dash'
        btnC = 1;
        #10000;      // Hold for 1000 cycles (Valid Dash, because DASH_MIN is 800)
        btnC = 0;
        
        // 4. Wait for the game to process the word (IDLE_TIMEOUT)
        #20000;      
        
        // 5. Wait for the "PASS" text to disappear and level to increment
        #30000; 

        $finish;
    end
endmodule
// --- END tb_morse_game_top.v ---
