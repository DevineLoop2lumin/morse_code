# 📋 MORSE CODE GAME - QUICK REFERENCE GUIDE
## One-Page Explanations for Each Module & Common Questions

Perfect for quick lookups when explaining to your teacher!

---

## QUICK MODULE SUMMARY

### **debounce.v — The Noise Filter**
**What:** Removes electrical noise from button presses.  
**Input:** Raw button signal (bouncy)  
**Output:** Clean button signal  
**Time:** 10 milliseconds (adjustable)  
**Key Code:** Counter waits for stable input before reporting a change.  
**Tweak:** Change `DEBOUNCE_TICKS` to adjust wait time.

---

### **press_classifier.v — Dot vs Dash Detector**
**What:** Measures button press duration and classifies it.  
**Input:** Clean button signal  
**Output:** Pulse saying "SYMBOL_VALID" with 0=dot or 1=dash, OR "INVALID"  
**FSM States:** S_IDLE → S_PRESSED (count ticks) → S_CLASSIFY (decide) → S_IDLE  
**Classification Rules:**
- 200–800 ms = DOT (bit 0)
- 800–1500 ms = DASH (bit 1)
- Outside range = INVALID

**Tweak:** Change `DOT_MIN`, `DOT_MAX`, `DASH_MIN`, `DASH_MAX` to make game faster/slower.

---

### **morse_capture.v — Pattern Recorder**
**What:** Accumulates dots and dashes into a morse pattern.  
**Input:** Symbol pulses from press_classifier  
**Output:** 6-bit pattern + 3-bit length + "INPUT_DONE" pulse after 2 seconds  
**Encoding:** Right-aligned, MSB-first (0=dot, 1=dash)  
**Example:** User types dot-dash = pattern 000001, length 2  
**Shift Logic:** Each new symbol shifted left, inserted at LSB.

```
After dot:  pattern = 000000, length = 1
After dash: pattern = 000001, length = 2  (dot moved left, dash inserted right)
```

**Tweak:** Change `IDLE_TIMEOUT` to adjust when input is considered complete.

---

### **morse_rom.v — The Morse Dictionary**
**What:** Lookup table with 36 morse code entries (A–Z, 0–9).  
**Input:** Level number (0–35)  
**Output:** Pattern, Length, ASCII character  
**Encoding Example:**
```
'A' = .-     → pattern=000001, length=2, ascii=0x41
'B' = -...   → pattern=001000, length=4, ascii=0x42
'0' = ----- → pattern=011111, length=5, ascii=0x30
```

**How to Change:** Reorder entries in the `case` statement to change difficulty.

---

### **morse_player.v — LED Hint Blinker**
**What:** Plays morse code on an LED as a hint.  
**Input:** Pattern + length from ROM  
**Output:** LED on/off signal + "DONE" pulse  
**FSM States:** S_IDLE → S_LOAD → S_PLAY_ON → S_PLAY_GAP → S_DONE  
**Timing:**
- Dot ON: 300 ms
- Dash ON: 900 ms
- Gap between symbols: 300 ms

**Tweak:** Change `PLAY_DOT_TICKS`, `PLAY_DASH_TICKS`, `PLAY_GAP_TICKS`.

---

### **game_controller.v — The Game Brain**
**What:** Central game logic. Manages states, compares answers, controls progression.  
**FSM States:** 8 states total
```
S_IDLE (show level) → S_RESET_CAP → S_PLAYBACK (optional) → S_WAIT_INPUT
                                                              ↓
                                                          S_EVALUATE
                                                              ↓
                                    ┌──→ S_SHOW_PASS → IDLE → next level
                                    │
Compare user vs ROM ─→ Match? ─┤
                                    │
                                    └──→ S_SHOW_ERROR → IDLE → retry
                                    
                                    └──→ S_SHOW_DONE → IDLE → restart game
```

**Key Logic:**
```verilog
if (captured_length == rom_length && captured_pattern == rom_pattern) then PASS
else ERROR
```

**Tweak:** `DISPLAY_TICKS` (how long "PASS"/"ERR " show), `NUM_LEVELS` (game length).

---

### **seg7_driver.v — 7-Segment Display Driver**
**What:** Multiplexes 4-digit 7-segment display.  
**Input:** 4 ASCII characters  
**Output:** Segment signals + anode signals (active low)  
**How:** Shows one digit at a time, cycling at ~250 Hz (fast enough to look constant).  
**ASCII to Segments:** 26-line lookup table converting ASCII codes to 7-segment patterns.

**Tweak:** `REFRESH_TICKS` (display refresh rate — lower = smoother, higher = flickers).

---

### **morse_game_top.v — The Glue Module**
**What:** Top-level instantiates all 7 modules and connects them.  
**Does:** Tie module I/Os together, define parameters, assign debug LEDs.  
**Where All Parameters Live:** All timing parameters can be adjusted here.

---

---

## COMMON QUESTIONS & ANSWERS

### **Q: How does the 100 MHz clock relate to timing?**
**A:** 100 MHz = 100 million cycles per second.
- 1 cycle = 10 nanoseconds
- 1,000 cycles = 10 microseconds
- 100,000 cycles = 1 millisecond
- 100,000,000 cycles = 1 second

So `DOT_MIN = 20_000_000` ticks = 0.2 seconds = 200 milliseconds.

---

### **Q: What is a "pulse" vs. a "level"?**
**A:**
- **Pulse:** Signal is 1 for exactly 1 clock cycle, then goes back to 0.
  - Example: `symbol_valid` pulse (1 cycle high = symbol detected)
  - Used to trigger events once
  
- **Level:** Signal stays at 1 until something changes it.
  - Example: `btn_out` level (stays 1 while button pressed)
  - Used to represent continuous state

---

### **Q: Why do we use synchronizers (2 flip-flops)?**
**A:** External inputs (buttons, switches) can transition at any random time, not aligned with the clock. If we read them directly, the hardware might "see" the transition on two adjacent clock edges simultaneously (metastability), causing unpredictable behavior. The 2-FF synchronizer gives the signal 2 clock cycles to stabilize before we use it.

---

### **Q: What does `<=` mean vs. `=`?**
**A:**
- `<=` (non-blocking assignment) — Used in `always @(posedge clk)` blocks. "Schedule this update for the next clock edge."
  ```verilog
  always @(posedge clk) begin
      reg_a <= reg_b;  // On next clock, reg_a ← reg_b (current value)
      reg_b <= reg_a;  // On next clock, reg_b ← reg_a (current value)
  end
  // After the clock edge: reg_a and reg_b swap! Both use the OLD values.
  ```

- `=` (blocking assignment) — Used in combinational (`always @(*)`) or procedural blocks. "Update immediately."
  ```verilog
  always @(*) begin
      result = input_a + input_b;  // Update immediately (no clock wait)
  end
  ```

---

### **Q: How does morse_capture accumulate symbols?**
**A:** Using left-shift with insertion:
```verilog
captured_pattern <= {captured_pattern[4:0], symbol_bit};
```
Each time a new symbol arrives, the register shifts left (old bits move to higher indices) and the new bit enters at the LSB (bit 0).

```
Before: captured_pattern = 6'b000001 (pattern for .)
                           {captured_pattern[4:0], 0}
After:  captured_pattern = 6'b000010 (pattern for ..)
```

---

### **Q: Why is morse_rom a "combinational" module?**
**A:** The ROM uses `always @(*)`, not `always @(posedge clk)`. This means outputs update instantly when inputs change, with no clock delay. It's like a lookup table in memory — very fast.

---

### **Q: How does morse_player extract symbols in the right order?**
**A:** The ROM stores patterns right-aligned. morse_player extracts bits from position `[length-1]` down to `[0]`, which gives the chronological order.

```
Pattern: 6'b000001, Length: 2
Extract: pattern[2-1] = pattern[1] = 0 (first symbol = dot)
        then: pattern[2-2] = pattern[0] = 1 (second symbol = dash)
Result: dot, dash = .-  = 'A' ✓
```

---

### **Q: What happens if the user presses the button for 500 ms?**
**A:**
1. press_classifier measures: 500 ms = 50 million ticks
2. Check range:
   - Is 50M >= DOT_MIN (20M)? YES
   - Is 50M < DOT_MAX (80M)? YES
   - → Classified as DOT!
3. morse_capture receives `symbol_valid=1, symbol_bit=0`
4. Pattern accumulates.

---

### **Q: What happens if the user presses for 900 ms?**
**A:**
1. press_classifier measures: 900 ms = 90 million ticks
2. Check ranges:
   - Is 90M >= DOT_MIN (20M)? YES, but
   - Is 90M < DOT_MAX (80M)? NO → not a dot
   - Is 90M >= DASH_MIN (80M)? YES
   - Is 90M <= DASH_MAX (150M)? YES
   - → Classified as DASH!
3. morse_capture receives `symbol_valid=1, symbol_bit=1`
4. Pattern accumulates.

---

### **Q: What happens after the player enters morse code?**
**A:**
1. morse_capture times 2 seconds of idle → sends `input_done` pulse
2. game_controller sees pulse, moves to S_EVALUATE
3. Compares: `captured_pattern` vs. `rom_pattern`
4. If match: S_SHOW_PASS (display "PASS" for 2 seconds), then level++
5. If mismatch: S_SHOW_ERROR (display "ERR " for 2 seconds), same level
6. If all 36 levels done: S_SHOW_DONE (display "donE"), reset to level 0

---

### **Q: How does mode switching work?**
**A:**
1. User flips `sw[0]` from 0 to 1 (or 1 to 0)
2. game_controller detects change (using 2-FF synchronizer first)
3. Resets: `current_level = 0`, `capture_rst = 1`, `state = S_IDLE`
4. On next S_IDLE:
   - If `sw[0] = 0` (Encoding): Display "L01"
   - If `sw[0] = 1` (Decoding): Display "   A" (target character)

---

### **Q: What do the debug LEDs show?**
**A:**
| LED | Shows |
|-----|-------|
| [0] | Button pressed (real-time) |
| [1] | Symbol detected (latched) |
| [2] | Last symbol: 0=dot, 1=dash |
| [3] | Input sequence complete (latched) |
| [4] | Invalid press (latched) |
| [5] | Mode switch: 0=Encode, 1=Decode |
| [6] | Hint switch: 0=off, 1=on |
| [7] | Morse player LED (real-time blink) |
| [11:8] | Current level (4 LSBs shown) |
| [14:12] | FSM state (0–7) |

---

### **Q: How do I explain the project to my teacher?**
**A:** Use this structure:

1. **Start with the big picture:** "This is a morse code learning game on an FPGA."

2. **Explain the 2 modes:**
   - Encoding: Show level, user types morse
   - Decoding: Show character, user types its morse

3. **Walk through the signal flow:**
   - Button → debounce → classifier → capture → compare → display

4. **Explain key modules:**
   - debounce: Removes electrical noise
   - classifier: Measures duration (dot vs dash)
   - capture: Accumulates symbols
   - rom: Looks up morse codes
   - game_controller: Game logic
   - display: Shows results

5. **Show tweaking examples:**
   - "Change this parameter to make dots and dashes faster or slower"

6. **Mention debug LEDs:**
   - "The LEDs show exactly what's happening inside the FPGA"

---

---

## TWEAKING CHEAT SHEET

| Want to... | File | Parameter | Original | Try |
|---|---|---|---|---|
| Make game faster | morse_game_top.v | DOT_MIN, DOT_MAX, DASH_MIN, DASH_MAX | 20M–80M, 80M–150M | Halve |
| Make game slower | morse_game_top.v | (same) | (same) | Double |
| Longer input timeout | morse_game_top.v | IDLE_TIMEOUT | 200M | 400M |
| Shorter input timeout | morse_game_top.v | (same) | (same) | 100M |
| Longer result display | morse_game_top.v | DISPLAY_TICKS | 200M | 500M |
| Faster LED playback | morse_game_top.v | PLAY_DOT/DASH/GAP_TICKS | 30M/90M/30M | Halve |
| Smaller game | game_controller.v | NUM_LEVELS | 36 | 10 |
| Smoother display | morse_game_top.v | REFRESH_TICKS | 100k | 50k |
| Flickering display | morse_game_top.v | REFRESH_TICKS | 100k | 500k |
| Faster debounce | morse_game_top.v | DEBOUNCE_TICKS | 1M | 500k |

---

---

## VERILOG CHEAT SHEET

| Concept | Example | Meaning |
|---|---|---|
| Register (memory) | `reg [7:0] counter;` | 8-bit value that persists |
| Wire (connection) | `wire [5:0] result;` | 6-bit combinational output |
| Always block (clocked) | `always @(posedge clk)` | Runs on every clock edge |
| Always block (combinational) | `always @(*)` | Runs immediately when inputs change |
| Non-blocking assign | `reg <= value;` | Schedule update for next clock |
| Blocking assign | `wire = value;` | Update immediately |
| Bit indexing | `my_byte[0]` | Rightmost bit (LSB) |
| Bit slicing | `my_byte[3:0]` | Lower 4 bits |
| Concatenation | `{a, b, c}` | Combine into larger vector |
| Binary literal | `4'b1010` | 4-bit binary |
| Decimal literal | `4'd10` | 4-bit decimal (same as above) |
| If/else | `if (cond) begin ... end` | Conditional logic |
| Case | `case (var) ... endcase` | Multi-way conditional |
| Parameter | `parameter WIDTH = 8;` | Configurable constant |

---

---

## MORSE CODE REFERENCE (For Completeness)

| Symbol | Code | Bits | Pattern |
|--------|------|------|---------|
| A | .- | 2 | 01 |
| B | -... | 4 | 1000 |
| C | -.-. | 4 | 1010 |
| ... | ... | ... | ... |
| E | . | 1 | 0 |
| T | - | 1 | 1 |
| 0 | ----- | 5 | 11111 |
| 1 | .---- | 5 | 01111 |
| 9 | ----. | 5 | 11110 |

---

---

## PRESENTATION TIPS FOR YOUR TEACHER

### **Visual Aid 1: System Diagram**
Draw this on the board:
```
BUTTON → DEBOUNCE → CLASSIFIER → CAPTURE → COMPARE → DISPLAY
                    (dot/dash)   (pattern)  (ROM)     (7-seg)
```

### **Visual Aid 2: State Machine Diagram**
Show the FSM with boxes and arrows.

### **Visual Aid 3: Timeline**
Use a timeline to show what happens when user presses button for 500 ms.

### **Talking Points**
1. "This project uses metastability guards to safely interface with the physical world."
2. "The FSM coordinates all operations in a structured way."
3. "Parameters make the design reusable and tweakable."
4. "Debug LEDs let us see inside the FPGA in real-time."

### **Demo Ideas**
1. Show the game in action (all 36 levels).
2. Change a parameter and re-synthesize to show the effect.
3. Watch debug LEDs while pressing the button.
4. Explain how to make the game harder/easier.

---

**Good luck with your presentation! You've got this! 🚀**

