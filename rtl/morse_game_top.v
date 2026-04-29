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
        .DEBOUNCE_TICKS(1_000_000)  // 10 ms
    ) u_debounce_morse (
        .clk    (clk),
        .rst    (btn_reset_db),
        .btn_in (btnC),
        .btn_out(btn_morse_db)
    );

    // ── Debounce: Reset button ──
    // Note: Reset debounce uses raw async reset from btnU
    debounce #(
        .DEBOUNCE_TICKS(1_000_000)  // 10 ms
    ) u_debounce_reset (
        .clk    (clk),
        .rst    (1'b0),           // No reset for the reset debouncer
        .btn_in (btnU),
        .btn_out(btn_reset_db)
    );

    // ── Press Duration Classifier ──
    press_classifier #(
        .DOT_MIN (20_000_000),   // 200 ms
        .DOT_MAX (80_000_000),   // 800 ms
        .DASH_MIN(80_000_000),   // 800 ms
        .DASH_MAX(150_000_000)   // 1.5 s
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
        .IDLE_TIMEOUT(200_000_000),  // 2 sec
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
        .PLAY_DOT_TICKS (30_000_000),  // 300 ms
        .PLAY_DASH_TICKS(90_000_000),  // 900 ms
        .PLAY_GAP_TICKS (30_000_000)   // 300 ms
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
        .DISPLAY_TICKS(200_000_000)  // 2 sec
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
        .REFRESH_TICKS(100_000)  // ~1 ms
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

    always @(posedge clk) begin
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
