# 📖 MORSE CODE GAME - PRACTICAL IMPLEMENTATION GUIDE
## Visual Walkthroughs, Code Examples, and Real Scenarios

This document complements the detailed breakdown with **real code snippets** and **step-by-step scenarios** that show exactly what happens in specific situations.

---

## TABLE OF CONTENTS
1. [Real Scenario 1: Player Presses a Button](#scenario-1-player-presses-button)
2. [Real Scenario 2: Player Enters a Complete Morse Code](#scenario-2-complete-morse-code)
3. [Real Scenario 3: Playback Hint System](#scenario-3-playback-hint)
4. [Real Scenario 4: Mode Switching](#scenario-4-mode-switching)
5. [Verilog Basics for Non-Programmers](#verilog-basics)
6. [Understanding Registers and State](#registers-and-state)
7. [Debugging with Debug LEDs](#debugging)

---

# SCENARIO 1: PLAYER PRESSES A BUTTON
## From Raw Input to Classified Symbol (Step-by-Step with Real Numbers)

### **The Physical Action**
```
TIME: 0 ms     — Player's finger touches the button (noisy electrical signal)
     ↓         — Electrical noise: button bounces between 0 and 1 randomly
     ↓         — for ~15 milliseconds
     ↓
     15 ms     — Button signal stabilizes at 1 (pressed)
     ↓
     500 ms    — Player holds button for 500 milliseconds (HALF A SECOND)
     ↓
     515 ms    — Player releases the button (signal returns to 0)
     ↓         — Electrical noise again: bounces for ~10 milliseconds
     ↓
     525 ms    — Signal finally settles to 0 (unpressed)
```

### **What the FPGA Sees (WITHOUT debounce)**
```
     0 ms                        15 ms                        500 ms                     525 ms
     |                            |                             |                         |
     01010101...1111111111111111111111...00101010001010...0000000
     ↑          ↑                  ↑                         ↑     ↑
  Noise      Settling            Stable press         Release noise
```

The FPGA sees rapid 0→1→0→1 transitions during the bouncing periods!

### **What Happens in debounce.v**

**Inside debounce.v:**
```verilog
always @(posedge clk) begin
    btn_sync_0 <= btn_in;      // Capture raw button (noisy)
    btn_sync_1 <= btn_sync_0;  // Delay by 1 clock cycle
end
```

These 2 flip-flops **synchronize** the asynchronous button signal with our 100 MHz clock.

```verilog
if (btn_sync_1 != btn_out) begin
    // Button state has changed. Start counting.
    if (count == DEBOUNCE_TICKS - 1) begin
        btn_out <= btn_sync_1;  // Change output after stable for 10 ms
        count   <= 0;           // Reset counter
    end else begin
        count <= count + 1;     // Keep counting
    end
end else begin
    // Button state hasn't changed. Reset counter.
    count <= 0;
end
```

**Timeline (with actual clock cycles):**

```
CLOCK TICK  | btn_in | btn_sync_0 | btn_sync_1 | count      | btn_out | ACTION
────────────┼────────┼────────────┼────────────┼────────────┼─────────┼──────────────────────
0           | 0      | 0          | 0          | 0          | 0       | All zero
1           | 0      | 0          | 0          | 0          | 0       | Still zero
2           | 0      | 0          | 0          | 0          | 0       | Still zero

(User presses button, but it bounces...)

100         | 1      | 1          | 0          | 0          | 0       | Raw btn=1, but sync_1=0
            |        |            |            |            |         | Difference detected!
101         | 0      | 0          | 1          | 1          | 0       | count=1 (still waiting)
102         | 1      | 1          | 0          | 0          | 0       | Different from sync_1=0
103         | 1      | 1          | 1          | 1          | 0       | count=1 again
104         | 1      | 1          | 1          | 2          | 0       | count=2 (keep counting)
105         | 1      | 1          | 1          | 3          | 0       | count=3
...

(Keep counting while btn_sync_1=1 and btn_out=0)

1000099     | 1      | 1          | 1          | 999999     | 0       | count=999999
1000100     | 1      | 1          | 1          | 1000000    | 1       | REACHED MAX! btn_out ← 1
            |        |            |            | (resets)   |         | Output now shows PRESSED
1000101     | 1      | 1          | 1          | 0          | 1       | count reset, btn stays 1

(Button held down while debounce counts down next transition)

10000000    | 1      | 1          | 1          | 0          | 1       | Still pressed, count=0
10000050    | 0      | 0          | 1          | 1          | 1       | Raw btn=0, but sync_1=1
            |        |            |            |            |         | Difference detected!
10000051    | 0      | 0          | 0          | 2          | 1       | count=2 (waiting for release)
10000052    | 0      | 0          | 0          | 3          | 1       | count=3
...

(Keep counting while btn_sync_1=0 and btn_out=1)

10001049    | 0      | 0          | 0          | 1000000    | 0       | REACHED MAX! btn_out ← 0
            |        |            |            | (resets)   |         | Output now shows RELEASED
10001050    | 0      | 0          | 0          | 0          | 0       | count reset, btn stays 0
```

**Output Timeline:**
```
TIME (ms)  | btn_in (raw)        | btn_out (debounced) | DESCRIPTION
───────────┼─────────────────────┼────────────────────┼──────────────────────
0          | 0                   | 0                  | Idle
10         | (bouncing 0,1,0,1)  | 0                  | Button being pressed
15         | 1                   | 0                  | Signal stabilizes
25         | 1 (stable)          | 1                  | 10ms stable → OUTPUT CHANGES!
500        | 1 (held)            | 1                  | Button held
515        | (bouncing 1,0,1,0)  | 1                  | Button being released
520        | 0                   | 1                  | Signal stabilizes
530        | 0 (stable)          | 0                  | 10ms stable → OUTPUT CHANGES!
```

**Key Insight:** The debounced output takes a "jump" 10 ms after each transition, once the input is stable.

---

### **What Happens in press_classifier.v**

Once debounce outputs a clean signal, press_classifier measures how long it stays at 1:

```verilog
// Detect rising edge: transition from 0→1
if (btn_debounced && !btn_prev) begin
    state       <= S_PRESSED;      // Move to PRESSED state
    press_count <= 0;              // Start the timer
end
```

**While the button is pressed:**
```verilog
if (btn_debounced) begin
    press_count <= press_count + 1;  // Increment counter every clock cycle
end
```

With a 100 MHz clock:
- Press for 300 ms = 300 × 1,000,000 ticks = 30,000,000 counts
- Press for 500 ms = 500 × 1,000,000 ticks = 50,000,000 counts
- Press for 900 ms = 900 × 1,000,000 ticks = 90,000,000 counts

**Classification:**
```verilog
if (press_count >= DOT_MIN && press_count < DOT_MAX) begin
    // 20M to 80M ticks = 200 ms to 800 ms = DOT
    symbol_valid <= 1'b1;
    symbol_bit   <= 1'b0;    // 0 = DOT
end else if (press_count >= DASH_MIN && press_count <= DASH_MAX) begin
    // 80M to 150M ticks = 800 ms to 1500 ms = DASH
    symbol_valid <= 1'b1;
    symbol_bit   <= 1'b1;    // 1 = DASH
end else begin
    // Outside both ranges = INVALID
    invalid_pulse <= 1'b1;
end
```

### **Scenario 1 Timeline: Complete**

```
TIME (ms)  | Raw Input    | Debounce Output | Press Classifier State | press_count | symbol_valid | symbol_bit
───────────┼──────────────┼─────────────────┼───────────────────────┼─────────────┼──────────────┼──────────
0          | 0            | 0               | S_IDLE                | 0           | 0            | x
10         | (bounce)     | 0               | S_IDLE                | 0           | 0            | x
15         | 1 (stable)   | 0               | S_IDLE                | 0           | 0            | x
25         | 1            | 1               | S_PRESSED (counter=1) | 1           | 0            | x
100        | 1            | 1               | S_PRESSED             | 500k        | 0            | x
300        | 1            | 1               | S_PRESSED             | 30M         | 0            | x
                                           (300 ms = 30M ticks)
500        | 1            | 1               | S_PRESSED             | 50M         | 0            | x
                                           (500 ms = 50M ticks)
515        | (bounce)     | 1               | S_PRESSED             | 50M+        | 0            | x
520        | 0 (stable)   | 1               | S_PRESSED             | 50M+x       | 0            | x
530        | 0            | 0               | S_CLASSIFY (release)  | 50M         | 1            | 1
                                           (50M is in DASH range)
531        | 0            | 0               | S_IDLE                | 0           | 0            | x
532        | 0            | 0               | S_IDLE                | 0           | 0            | x
```

**Result:** Output signal `symbol_valid = 1` with `symbol_bit = 1` (DASH detected!)

---

# SCENARIO 2: COMPLETE MORSE CODE INPUT
## User Types 'A' = Dot-Dash (.-) — Full Flow

### **The User's Actions**
```
TIME    ACTION
─────   ──────────────────────────────────
0 ms    Game displays "L01" (waiting)
50 ms   User presses button (dot: 300 ms press)
350 ms  User releases
400 ms  User waits (gap between symbols)
450 ms  User presses button (dash: 900 ms press)
1350 ms User releases
1400 ms User waits (idle)
3400 ms 2 seconds pass without input → DONE!
```

### **Debounce Module (First Button Press)**
```verilog
// 50 ms: button pressed, debounce counts 10 ms
// 60 ms: output btn_morse_db = 1 (debounced)

// 350 ms: button released, debounce counts 10 ms
// 360 ms: output btn_morse_db = 0 (debounced)
```

### **Press Classifier Module (First Symbol = DOT)**

**Clock tick 50 ms → 360 ms: button transitions from 0→1**
```verilog
// Detect rising edge
if (btn_debounced && !btn_prev) begin  // YES: 1 && !0 = TRUE
    state       <= S_PRESSED;
    press_count <= 0;
end
```

**Clock ticks 60 ms → 360 ms: counting while button is pressed**
```verilog
while (btn_debounced == 1) begin
    press_count <= press_count + 1;
end
// At 360 ms: press_count = 300 milliseconds = 30,000,000 ticks
```

**At 360 ms, button transitions 1→0 (release)**
```verilog
if (!btn_debounced && btn_prev) begin  // YES: 0 && 1 = TRUE
    state <= S_CLASSIFY;
end
```

**Classify: press_count = 30,000,000**
```verilog
if (press_count >= DOT_MIN && press_count < DOT_MAX) begin
    // Is 30,000,000 >= 20,000,000? YES
    // Is 30,000,000 < 80,000,000? YES
    // → This is a DOT!
    symbol_valid <= 1'b1;
    symbol_bit   <= 1'b0;    // 0 = DOT
    state        <= S_IDLE;
end
```

**Output at 360 ms:** `symbol_valid = 1, symbol_bit = 0` (DOT)

---

### **Morse Capture Module (First Symbol)**

**Before input:**
```verilog
captured_pattern = 6'b000000
captured_length  = 3'd0
idle_count       = 0
has_input        = 1'b0
```

**At 360 ms, symbol_valid pulse arrives:**
```verilog
else if (symbol_valid) begin
    if (captured_length < MAX_SYMBOLS) begin
        // Shift and insert: {captured_pattern[4:0], symbol_bit}
        captured_pattern <= {6'b000000[4:0], 1'b0};
                          = {5'b00000, 1'b0};
                          = 6'b000000;  // Shifted in a 0 (dot)
        captured_length  <= 3'd1;       // Now we have 1 symbol
        idle_count       <= 0;          // Reset timer
        has_input        <= 1'b1;       // Mark that we have input
    end
end
```

**After first symbol:**
```verilog
captured_pattern = 6'b000000  (the 0 is at position [0])
captured_length  = 1
idle_count       = 0
has_input        = 1
```

---

### **Morse Capture Module (Second Symbol = DASH)**

**At 1350 ms, second symbol_valid pulse arrives (symbol_bit = 1 for dash):**
```verilog
captured_pattern <= {6'b000000[4:0], 1'b1};
                  = {5'b00000, 1'b1};
                  = 6'b000001;  // Previous 0 shifted to position [1], new 1 at position [0]
captured_length  <= 3'd2;       // Now we have 2 symbols
idle_count       <= 0;          // Reset timer
```

**After second symbol:**
```verilog
captured_pattern = 6'b000001  (dot at [1], dash at [0])
captured_length  = 2
idle_count       = 0
has_input        = 1
```

---

### **Morse Capture Module (Idle Timeout)**

**From 1350 ms to 3350 ms, no new symbols arrive:**
```verilog
else if (has_input) begin
    if (idle_count == IDLE_TIMEOUT - 1) begin
        // 2 seconds = 200,000,000 ticks
        // Has idle_count reached that?
        // YES!
        input_done <= 1'b1;     // Pulse: input is COMPLETE!
        has_input  <= 1'b0;     // Clear flag
        idle_count <= 0;        // Reset timer
    end else begin
        idle_count <= idle_count + 1;  // Keep counting
    end
end
```

**At 3350 ms:**
```
input_done = 1 (1-clock-cycle pulse!)
captured_pattern = 6'b000001  (the morse code for 'A' = .-)
captured_length = 2
```

---

### **Game Controller Module (Evaluate)**

**At 3350 ms, game_controller sees input_done pulse:**
```verilog
if (input_done) begin
    state <= S_EVALUATE;
end
```

**In S_EVALUATE state:**
```verilog
// game_controller has already looked up the ROM for current_level
// rom_addr = current_level = 0 (Level 1 = 'A')
// rom_pattern = 6'b000001  (morse for 'A' = .-)
// rom_length = 3'd2        (2 symbols)

// Compare user input with ROM:
if (captured_length == rom_length &&
    captured_pattern[5:0] == rom_pattern[5:0]) begin
    // captured_length = 2 == rom_length = 2? YES
    // captured_pattern = 6'b000001 == rom_pattern = 6'b000001? YES
    // → CORRECT ANSWER!
    state <= S_SHOW_PASS;
    display_timer <= 0;
end
```

---

### **7-Segment Display (Show "PASS")**

**In S_SHOW_PASS state:**
```verilog
disp_char3 <= 8'h50;  // 'P'
disp_char2 <= 8'h41;  // 'A'
disp_char1 <= 8'h53;  // 'S'
disp_char0 <= 8'h53;  // 'S'

if (display_timer == DISPLAY_TICKS - 1) begin  // 2 seconds later
    current_level <= 1;  // Advance to next level
    state <= S_IDLE;
end else begin
    display_timer <= display_timer + 1;
end
```

---

### **Scenario 2 Complete Timeline**

```
TIME (ms)  | Action                        | Display           | Internal State
───────────┼───────────────────────────────┼───────────────────┼─────────────────────────────
0          | Game starts                   | "L01"             | S_IDLE, level=0, has_input=0
50         | User presses (dot)            | "L01"             | Debounce counting
60         | Debounce outputs              | "L01"             | Classifier S_PRESSED
350        | User releases                 | "L01"             | Classifier counting
360        | Debounce outputs release      | "L01"             | Classifier S_CLASSIFY
361        | ✓ DOT detected                | "L01"             | Morse Capture: length=1
400        | (User thinking)               | "L01"             | Morse Capture: idle counting
450        | User presses (dash)           | "L01"             | Debounce counting
460        | Debounce outputs              | "L01"             | Classifier S_PRESSED
1350       | User releases                 | "L01"             | Classifier counting
1360       | Debounce outputs release      | "L01"             | Classifier S_CLASSIFY
1361       | ✓ DASH detected               | "L01"             | Morse Capture: length=2
1400       | (User done typing)            | "L01"             | Morse Capture: idle counting
2350       | (1 second of idle)            | "L01"             | Idle count = 100M
3350       | ✓ 2-second timeout!           | "L01"             | input_done pulse!
3351       | Game evaluates               | "L01"             | S_EVALUATE (comparing)
3352       | ✓ MATCH! Correct!            | "PASS"            | S_SHOW_PASS
5352       | 2 seconds elapsed            | "PASS"→ "L02"     | Back to S_IDLE, level++
```

---

# SCENARIO 3: PLAYBACK HINT SYSTEM
## LED Blinks 'A' (.-) Before User Inputs

### **Initial Setup**
```
sw[0] = 0  (Encoding mode)
sw[1] = 1  (Hint enabled)
current_level = 0 (showing 'A')
```

### **Game Controller: S_IDLE State**

```verilog
if (sw_mode_sync1 == 0 && sw_hint_sync1) begin
    state <= S_PLAYBACK;  // Move to playback
end
```

**Transition:** S_IDLE → S_RESET_CAP (one cycle) → S_PLAYBACK

---

### **Game Controller: S_PLAYBACK State**

```verilog
if (!player_busy && !player_start) begin
    player_start <= 1'b1;  // Send START pulse
end
```

**At this moment:**
- `player_start` = 1 (for 1 clock cycle)
- morse_player receives this pulse

---

### **Morse Player: Receives Start Command**

```verilog
S_IDLE: begin
    if (start) begin          // YES! start pulse received
        state <= S_LOAD;
        busy  <= 1'b1;
    end
end
```

---

### **Morse Player: S_LOAD State**

```verilog
S_LOAD: begin
    if (length == 3'd0) begin
        state <= S_DONE;  // Nothing to play
    end else begin
        pat_shift     <= pattern;       // pattern = 6'b000001 from ROM
        sym_remaining <= length;        // length = 2 from ROM
        current_bit   <= pattern[length - 1];
                       = 6'b000001[2-1]
                       = 6'b000001[1]
                       = 0              // First symbol is 0 (DOT)
        state         <= S_PLAY_ON;
        timer         <= 0;
    end
end
```

---

### **Morse Player: S_PLAY_ON (First Symbol = DOT)**

```verilog
S_PLAY_ON: begin
    led_out <= 1'b1;  // Turn LED ON

    if (current_bit == 1'b0) begin  // YES: it's a DOT
        if (timer == PLAY_DOT_TICKS - 1) begin
            // 30,000,000 - 1 ticks = 300 ms
            led_out       <= 1'b0;       // Turn LED OFF
            timer         <= 0;          // Reset timer
            sym_remaining <= sym_remaining - 1;  // 2 - 1 = 1 remaining
            if (sym_remaining == 3'd1) begin
                // NOT the last symbol? We have 1 remaining after decrement.
                state <= S_PLAY_GAP;
            end else begin
                state <= S_DONE;
            end
        end else begin
            timer <= timer + 1;          // Keep counting
        end
    end
end
```

**Timeline for DOT:**
```
TIME (ms)  | timer    | led_out | ACTION
───────────┼──────────┼─────────┼─────────────────────────────
0          | 0        | 1       | LED turns ON
150        | 15M      | 1       | LED still ON
300        | 30M-1    | 0       | 300 ms reached! LED turns OFF
301        | 0        | 0       | Move to S_PLAY_GAP
```

---

### **Morse Player: S_PLAY_GAP (300 ms Silent Gap)**

```verilog
S_PLAY_GAP: begin
    led_out <= 1'b0;  // Keep LED OFF

    if (timer == PLAY_GAP_TICKS - 1) begin
        // 30,000,000 - 1 ticks = 300 ms gap
        timer <= 0;
        current_bit <= pat_shift[sym_remaining - 1];
                    = pat_shift[1 - 1]
                    = pat_shift[0]
                    = 6'b000001[0]
                    = 1        // Next symbol is 1 (DASH)
        state <= S_PLAY_ON;
    end else begin
        timer <= timer + 1;
    end
end
```

**Timeline for GAP:**
```
TIME (ms)  | timer    | led_out | ACTION
───────────┼──────────┼─────────┼─────────────────────────────
300        | 0        | 0       | GAP starts, LED OFF
450        | 15M      | 0       | Still in gap
600        | 30M-1    | 0       | 300 ms gap reached!
601        | 0        | 0       | Transition to S_PLAY_ON
```

---

### **Morse Player: S_PLAY_ON (Second Symbol = DASH)**

```verilog
S_PLAY_ON: begin
    led_out <= 1'b1;  // Turn LED ON (for DASH)

    if (current_bit == 1'b1) begin  // YES: it's a DASH
        if (timer == PLAY_DASH_TICKS - 1) begin
            // 90,000,000 - 1 ticks = 900 ms
            led_out       <= 1'b0;
            timer         <= 0;
            sym_remaining <= sym_remaining - 1;  // 1 - 1 = 0 remaining
            if (sym_remaining == 3'd1) begin
                state <= S_PLAY_GAP;  // More symbols?
            end else begin
                state <= S_DONE;      // NO: all done!
            end
        end else begin
            timer <= timer + 1;
        end
    end
end
```

**Timeline for DASH:**
```
TIME (ms)  | timer    | led_out | sym_remaining | ACTION
───────────┼──────────┼─────────┼───────────────┼──────────────────
601        | 0        | 1       | 0             | LED ON, dash starts
750        | 15M      | 1       | 0             | LED still ON
1500       | 90M-1    | 0       | 0             | 900 ms reached!
1501       | 0        | 0       | 0             | sym_remaining=0-1=-1 (wraps)
1502       | 0        | 0       | 0             | Actually: 0-1 underflows in 3-bit
                                               | Verilog, result is 3'b111=7
           |          |         | (7 if calc'd)| Move to S_DONE
```

---

### **Morse Player: S_DONE**

```verilog
S_DONE: begin
    led_out    <= 1'b0;
    done_pulse <= 1'b1;     // Pulse: playback finished!
    state      <= S_IDLE;
end
```

---

### **Game Controller: Back to S_WAIT_INPUT**

```verilog
S_PLAYBACK: begin
    if (player_done) begin  // YES! done_pulse received
        capture_rst <= 1'b1;
        state       <= S_WAIT_INPUT;  // Now accept user input
    end
end
```

---

### **Scenario 3 Complete Timeline**

```
TIME (ms)  | LED Output | Audio/Visual                    | FSM State
───────────┼────────────┼─────────────────────────────────┼─────────────────
0          | OFF        | Game displays "L01"             | S_PLAYBACK
0          | ON         | LED starts blinking hint        | S_LOAD→S_PLAY_ON
300        | OFF        | Dot blink ends (300 ms total)   | S_PLAY_GAP
600        | ON         | Gap ends, dash starts           | S_PLAY_ON
1500       | OFF        | Dash ends (900 ms total)        | S_DONE
1501       | OFF        | done_pulse sent to game_ctrl    | S_IDLE→S_WAIT_INPUT
1502       | OFF        | Game now waits for user input   | S_WAIT_INPUT

▌▌▌  ▌▌▌▌▌▌▌▌▌▌▌▌▌▌
0  300 600         1500 ms

Dot: 300 ms ON    Gap: 300 ms OFF    Dash: 900 ms ON
```

**Result:** Player sees the LED blink "dot, long gap, dash" = .-  = 'A', and now knows what to type!

---

# SCENARIO 4: MODE SWITCHING
## User Flips Switch from Encoding (0) to Decoding (1)

### **Before Switch Change**
```
sw[0] = 0  (Encoding mode)
Game is at Level 5 ('E')
Display shows: "L05"
```

### **User Flips Switch**
```
sw[0] changes: 0 → 1
```

### **Game Controller Detects Change**

```verilog
// Two-FF Synchronizer captures sw[0]
always @(posedge clk) begin
    sw_mode_sync0 <= sw_mode;      // Capture raw switch
    sw_mode_sync1 <= sw_mode_sync0;  // Delay by 1 cycle (synchronize)
end
```

**After 2 clock cycles:**
- `sw_mode_sync1` = 1 (new mode)
- `prev_mode` = 0 (previous mode)

### **Main FSM Detects Edge**

```verilog
// ── Mode switch detection: reset game on mode change ──
if (sw_mode_sync1 != prev_mode) begin
    // YES: Mode has changed!
    current_level <= 6'd0;    // Reset to level 0
    capture_rst   <= 1'b1;    // Reset capture module
    state         <= S_IDLE;  // Return to idle
end else begin
    // No, mode is the same. Continue normal operation.
    // ... (FSM continues)
end
```

### **S_IDLE State Adapts to New Mode**

```verilog
S_IDLE: begin
    if (sw_mode_sync1 == 1'b0) begin
        // ── Encoding Mode (0) ──
        disp_char3 <= 8'h4C;   // 'L'
        disp_char2 <= tens_ascii;
        disp_char1 <= ones_ascii;
        disp_char0 <= 8'h20;   // Shows "L01"
    end else begin
        // ── Decoding Mode (1) ──
        disp_char3 <= 8'h20;   // blank
        disp_char2 <= 8'h20;   // blank
        disp_char1 <= 8'h20;   // blank
        disp_char0 <= rom_ascii;  // Shows target character "A" (right-aligned)
    end
end
```

---

### **Scenario 4 Timeline**

```
TIME (ticks) | sw[0]  | sw_mode_sync0 | sw_mode_sync1 | prev_mode | Detected | Display
──────────────┼────────┼───────────────┼───────────────┼───────────┼──────────┼──────────
0             | 0      | 0             | 0             | 0         | NO       | "L05"
(User flips)  
100           | 1      | 0             | 0             | 0         | NO       | "L05" (raw switch=1, but sync not updated yet)
101           | 1      | 1             | 0             | 0         | NO       | "L05" (first FF captured=1, but second FF still=0)
102           | 1      | 1             | 1             | 0         | YES!     | (about to change)
103           | 1      | 1             | 1             | 1         | NO       | "A   " (now in Decoding mode, level reset to 0)
```

**Result:**
- Mode changes from Encoding to Decoding.
- Level resets to 0 (character 'A').
- Display changes from "L05" to "   A" (decoding mode shows just the character).
- Game is ready for decoding challenges.

---

# VERILOG BASICS FOR NON-PROGRAMMERS
## Understanding the Language Used in the FPGA Code

Verilog is a language for describing **hardware logic**. Here are the key concepts:

### **1. `always @(posedge clk)` — The Heartbeat**

```verilog
always @(posedge clk) begin
    // This block runs EVERY TIME the clock rises
end
```

**Analogy:** Imagine a teacher ringing a bell every second. When the bell rings, all students check their assignments and update their work.

**In our FPGA:** The clock rings 100 million times per second. Every ring, the circuit updates.

### **2. `reg` — Register (Memory)**

```verilog
reg [7:0] counter;  // An 8-bit memory cell
reg       led;      // A 1-bit memory cell
```

**Analogy:** A chalkboard where we write and remember numbers.

**In code:**
```verilog
counter <= counter + 1;  // Increment the counter each clock cycle
```

**Note:** We use `<=` (non-blocking assignment) in `always @(posedge clk)` blocks. This means:
- Read the current value of counter.
- After the clock edge, update it to counter + 1.
- All `<=` assignments happen simultaneously (hardware-like behavior).

### **3. `wire` — Connection (No Memory)**

```verilog
wire [5:0] result;  // A 6-bit connection (read-only, combinational)
```

**Analogy:** A physical wire connecting two components. Electricity flows through it instantly.

**In code:**
```verilog
assign result = input_a + input_b;  // Combinational: result updates instantly
```

No clock delay. The result is always the current sum.

### **4. `if / else` — Decision**

```verilog
if (button == 1'b1) begin
    led <= 1'b1;  // Light up LED
end else begin
    led <= 1'b0;  // Turn off LED
end
```

**In hardware:** A multiplexer (a switch) selects between two paths based on a condition.

### **5. `case` — Multi-way Decision**

```verilog
case (state)
    2'd0: action_0();  // If state is 0, do action 0
    2'd1: action_1();  // If state is 1, do action 1
    2'd2: action_2();  // If state is 2, do action 2
    default: idle();   // Otherwise, do idle
endcase
```

**Analogy:** A railroad switch that sends a train to one of several tracks based on the switch position.

### **6. Bit Indexing and Slicing**

```verilog
reg [7:0] my_byte;  // An 8-bit value

my_byte[0]    // Rightmost bit (LSB) — the "ones" place
my_byte[7]    // Leftmost bit (MSB) — the "128s" place
my_byte[3:0]  // Lower 4 bits (bits 3, 2, 1, 0)
my_byte[7:4]  // Upper 4 bits (bits 7, 6, 5, 4)
```

**Analogy:** A byte is like a row of 8 light switches.
- `[0]` is the rightmost switch.
- `[7]` is the leftmost switch.
- `[3:0]` is a group of the rightmost 4 switches.

### **7. Concatenation: `{}`**

```verilog
result = {a, b, c};  // Combine a, b, c into a larger value
```

**Example:**
```verilog
a = 2'b10
b = 2'b11
c = 2'b01
result = {a, b, c} = 6'b101101  // Concatenated in order: a, then b, then c
```

**Analogy:** Gluing three pieces of paper together.

### **8. Shift Operations**

```verilog
value = {value[4:0], new_bit};  // Left shift, insert at LSB
```

**What it does:**
```
Before: value = 6'b101010
        value[5:0] = {1,0,1,0,1,0}

{value[4:0], 1'b1} = {5'b10101, 1'b1} = 6'b101011
                      value[4] moves to [5]
                      value[3] moves to [4]
                      ... (each bit shifts left)
                      new_bit moves to [0]
```

This is how morse_capture accumulates morse symbols.

### **9. Pulse vs. Level**

**Pulse (1 clock cycle high):**
```verilog
signal <= 1'b1;   // Clock 100: signal is 1
// signal stays 1 for this clock edge
// Clock 101: signal must be reset (or it becomes a level, not a pulse)
signal <= 1'b0;   // Cleared at next clock
```

**Level (stays high):**
```verilog
if (condition) begin
    signal <= 1'b1;  // Signal becomes 1
    // It stays 1 until we explicitly set it to 0
    // (without a clock edge clearing it)
end
```

**In our project:**
- `symbol_valid` is a **pulse** (1 cycle only).
- `btn_out` is a **level** (stays 1 while button is pressed).

### **10. Parameters (Configurable Constants)**

```verilog
module my_module #(
    parameter DELAY = 100,  // Default value is 100
    parameter WIDTH = 8     // Default value is 8
) (
    input  wire [WIDTH-1:0] data_in,
    output wire [WIDTH-1:0] data_out
);
```

**Usage:**
```verilog
my_module #(.DELAY(200), .WIDTH(16)) instance_1 (...)  // Use DELAY=200, WIDTH=16
my_module #(.DELAY(100), .WIDTH(8))  instance_2 (...)  // Use defaults
```

**In our project:** Enables tweaking without changing code (e.g., DOT_MIN, DOT_MAX).

---

# UNDERSTANDING REGISTERS AND STATE
## How the Game Remembers Information

### **Register: A 1-Bit Memory Cell**

```verilog
reg my_flag;  // One bit: can be 0 or 1
```

In hardware:
```
      ┌────────┐
      │        │
  ───→│  Flip- │──→ Output (current value)
  (D) │ Flop   │
      │ (reg)  │
      │        │
   ┌──┴────────┘
   │
 (clk)
```

On every clock edge:
- The flip-flop "captures" the input (D) and outputs it on the next cycle.
- It "remembers" the value indefinitely.

### **Example: A Simple Counter**

```verilog
reg [7:0] counter;

always @(posedge clk) begin
    if (rst)
        counter <= 8'd0;  // Reset to 0
    else
        counter <= counter + 1;  // Increment by 1
end
```

**Hardware behavior:**
```
CLOCK CYCLE | rst | Input to Flip-Flop | Output (counter) | What Happens
────────────┼─────┼────────────────────┼──────────────────┼──────────────
0           | 1   | (ignored)          | 00000000         | Reset active
           
1           | 0   | 00000001 (0+1)     | 00000000         | Input prepared
                                                           (not output yet)
           
2           | 0   | 00000010 (1+1)     | 00000001         | Now 1 is output
           
3           | 0   | 00000011 (2+1)     | 00000010         | Now 2 is output
           
4           | 0   | 00000100 (3+1)     | 00000011         | Now 3 is output
```

**Key insight:** The output lags the input by 1 clock cycle. This is called **pipelining** and is fundamental to digital design.

### **State Machine: A Bigger Register**

Instead of just a counter, we use a register to hold a "state":

```verilog
reg [2:0] state;  // Can hold values 0-7

localparam [2:0] S_IDLE  = 3'd0,
                 S_WAIT  = 3'd1,
                 S_DONE  = 3'd2;

always @(posedge clk) begin
    if (rst)
        state <= S_IDLE;
    else
        case (state)
            S_IDLE: begin
                if (start_signal)
                    state <= S_WAIT;  // Transition
            end
            S_WAIT: begin
                if (done_signal)
                    state <= S_DONE;  // Transition
            end
            S_DONE: begin
                state <= S_IDLE;      // Transition
            end
        endcase
end
```

**Hardware view:**
```
       ┌──────────────┐
       │              │
   ───→│   3-bit      │───→ 3-bit Output
 (next │   Register   │     (current state)
 state)│   (state)    │
       │              │
       └──────────────┘
            ↑
          (clk)
```

**FSM transitions happen once per clock cycle:**
```
CYCLE | start_signal | done_signal | Current State | Next State | Display
──────┼──────────────┼─────────────┼───────────────┼────────────┼──────────
0     | 0            | 0           | S_IDLE        | S_IDLE     | Idle
1     | 1            | 0           | S_IDLE        | S_WAIT     | Waiting
2     | 0            | 0           | S_WAIT        | S_WAIT     | Waiting
3     | 0            | 1           | S_WAIT        | S_DONE     | Processing
4     | 0            | 0           | S_DONE        | S_IDLE     | Back to Idle
```

### **Why Pipelining Matters**

When you write:
```verilog
if (button == 1) begin
    state <= S_PRESSED;  // "next state"
end
```

The actual state doesn't change until the NEXT clock edge. The `<=` is **non-blocking**—it says "set this value for the next cycle."

**Benefit:** All parts of the circuit can update simultaneously without race conditions.

---

# DEBUGGING WITH DEBUG LEDS
## Understanding What the FPGA is Doing in Real-Time

### **Debug LED Assignments**

```verilog
assign led[0]     = btn_morse_db;           // Real-time button state
assign led[1]     = led_sym_valid_latch;    // Symbol detection (latched)
assign led[2]     = led_sym_bit_latch;      // Dot=0 or Dash=1 (latched)
assign led[3]     = led_input_done_latch;   // Input complete (latched)
assign led[4]     = led_input_invalid_latch;// Invalid input (latched)
assign led[5]     = sw[0];                  // Mode switch: 0=Encode, 1=Decode
assign led[6]     = sw[1];                  // Hint switch
assign led[7]     = player_led;             // Morse player blink (real-time)
assign led[11:8]  = current_level[3:0];     // Level counter (4 LSBs shown)
assign led[12]    = fsm_state[0];           // FSM state bit 0
assign led[13]    = fsm_state[1];           // FSM state bit 1
assign led[14]    = fsm_state[2];           // FSM state bit 2
assign led[15]    = 1'b0;                   // Always off (unused)
```

### **What Each LED Tells You**

| LED | Signal | What It Shows | When It's On |
|-----|--------|---------------|--------------|
| 0 | btn_morse_db | Button pressed (debounced) | User holding button |
| 1 | symbol_valid | A dot or dash was detected | After each symbol (latched) |
| 2 | symbol_bit | Was it dot (0) or dash (1)? | 0=dot, 1=dash |
| 3 | input_done | Morse sequence complete | When user finishes typing |
| 4 | input_invalid | Invalid press detected | Bad timing (too short/long) |
| 5 | sw[0] | Mode switch | 0=Encoding, 1=Decoding |
| 6 | sw[1] | Hint enabled | 0=No hint, 1=Show hint |
| 7 | player_led | LED playback active | During hint playback |
| 8-11 | Level | Current level (0-15) | Shows which level (binary) |
| 12-14 | FSM State | Current FSM state (0-7) | Shows which state (binary) |

### **Using LEDs to Debug: Example**

**Scenario:** "Player pressed button, but no symbol was detected."

**Check LEDs:**
1. Led[0] = 1? Yes → Button press was registered.
2. Led[1] = 1? No → Symbol was NOT detected.
   - This means press_classifier didn't classify it.

**Possible causes:**
- User pressed too short (< 200 ms) → press_count < DOT_MIN → invalid
- User pressed too long (> 1500 ms) → press_count > DASH_MAX → invalid
- Check Led[4]: Is it 1? → Yes, input_invalid is active → confirmed!

**Solution:** Tell player to adjust timing.

---

### **Understanding FSM State via LEDs**

FSM has 8 states (0-7), displayed on LEDs 12-14 (3 bits):

```
FSM STATE (Binary) | LED14 | LED13 | LED12 | Decimal | Meaning
────────────────────┼───────┼───────┼───────┼─────────┼──────────────
0                  | 0     | 0     | 0     | 0       | S_IDLE
0                  | 0     | 0     | 1     | 1       | S_PLAYBACK
0                  | 0     | 1     | 0     | 2       | S_WAIT_INPUT
0                  | 0     | 1     | 1     | 3       | S_EVALUATE
1                  | 1     | 0     | 0     | 4       | S_SHOW_PASS
1                  | 1     | 0     | 1     | 5       | S_SHOW_ERROR
1                  | 1     | 1     | 0     | 6       | S_SHOW_DONE
1                  | 1     | 1     | 1     | 7       | S_RESET_CAP
```

**Example: Game is in "WAIT_INPUT" state**
- FSM displays 3 (binary 011)
- Led[12] = 1, Led[13] = 1, Led[14] = 0

### **Live Debugging Checklist**

**Issue: "Game is stuck"**
1. Check Led[14:12] (FSM state). Which state is it in?
   - If S_WAIT_INPUT: waiting for user input. Is user pressing the button?
   - Check Led[0]: Is the button being detected?
2. Check Led[0]. Is button being registered?
3. Check Led[1] & Led[2]. Is the symbol being detected?
4. Check Led[3]. Did input_done fire (2-second timeout)?

---

### **Complete Debugging Session Example**

**User says:** "I pressed the button for 500 ms, but the game said ERROR."

**Debug steps:**

1. **Reload the FPGA with the code.**

2. **User presses button (holds for 500 ms).**

3. **Watch LEDs:**
   - Time 0: Led[0] = 0 (button idle)
   - Time 50 ms: Led[0] = 1 (button pressed, after 10 ms debounce)
   - Time 500 ms: Led[1] = 1 (symbol detected!)
   - Time 510 ms: Led[0] = 0 (button released, after debounce)
   - Time 511 ms: Led[1] = 0 (latch cleared)

4. **Check Led[2] (what symbol was detected?):**
   - Led[2] = 1 → DASH was detected
   - 500 ms falls in the DASH range (80M–150M ticks)? 
   - 500 ms = 50M ticks... wait, that's NOT in the DASH range!
   - DASH_MIN = 80M (800 ms)
   - So 500 ms (50M ticks) < 80M → press was classified as INVALID!

5. **Check Led[4]:**
   - Led[4] = 1 → Confirms INVALID press!

6. **Conclusion:** User pressed too short to be a dash (needs ≥ 800 ms) but long enough for a dot. The timing falls in the "gap" between dot and dash ranges.

**Solution:** Adjust timing thresholds or tell user to press longer.

---

## **SUMMARY**

This practical guide provides:
1. **Real-world scenarios** showing exactly what happens in each module.
2. **Detailed timelines** with actual numbers and FSM states.
3. **Verilog basics** explained without assuming programming knowledge.
4. **State machine fundamentals** and pipelining concepts.
5. **Debugging techniques** using the physical LEDs on the board.

With this information, you can:
- Explain the game to anyone (even non-technical people).
- Modify parameters and predict the outcome.
- Debug issues using the debug LEDs.
- Understand why each line of code is necessary.

