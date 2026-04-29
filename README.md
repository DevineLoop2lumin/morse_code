<<<<<<< HEAD
# 🎯 MORSE CODE FPGA GAME — COMPLETE DOCUMENTATION
## End-to-End Guide: Architecture → Quick Reference → Detailed Breakdown → Practical Implementation

**Perfect for explaining to your teacher and girlfriend!**  
*Last Updated: April 2026*

---

## 📑 TABLE OF CONTENTS

- [PART 1: SYSTEM ARCHITECTURE](#part-1-system-architecture)
- [PART 2: QUICK REFERENCE GUIDE](#part-2-quick-reference-guide)
- [PART 3: DETAILED CODE BREAKDOWN](#part-3-detailed-code-breakdown)
- [PART 4: PRACTICAL IMPLEMENTATION GUIDE](#part-4-practical-implementation-guide)

---

---

# PART 1: SYSTEM ARCHITECTURE

## Overview

This project implements a Morse Code Training Game on the **Basys 3 FPGA** board (Artix-7 XC7A35T, 100 MHz clock). The game has two modes:

1. **Encoding Mode** — Display shows a level number (L01–L36). An LED blinks the Morse pattern as a hint (if enabled via sw[1]). The user reproduces the pattern using button presses.

2. **Decoding Mode** — Display shows a target character (A–Z, 0–9). The user must input the correct Morse code for that character.

---

## System Architecture

```
INPUTS                          PIPELINE PROCESSING                    OUTPUTS
───────────────────             ────────────────────                   ───────

100 MHz Clock ─────────────────→ All Modules
btnC (Morse Input) ──→ Debounce → Press Classifier → Morse Capture ──→ Game Controller
btnU (Reset) ─────────────────────────────────────→ (controls) ────→ 7-Segment Display
sw[0] (Mode) ──────────────────────────────────────────→ (controls) → Display Output
sw[1] (Hint Enable) ───────────────────────────────────────────────→ Debug LEDs (16 total)

Morse ROM (Lookup Table) ──→ Game Controller ──→ Morse Player ──→ LED Playback
```

---

## Module Hierarchy

```
morse_game_top (Top-level module)
├── debounce.v              (×2: morse button, reset button)
├── press_classifier.v      (classifies dot / dash / invalid)
├── morse_capture.v         (shift register + idle timeout)
├── morse_rom.v             (36-entry combinational ROM)
├── morse_player.v          (LED playback FSM)
├── game_controller.v       (central game logic FSM)
└── seg7_driver.v           (4-digit multiplexed display)
```

---

## Signal Flow

```
btnC → [debounce] → btn_morse_db → [press_classifier] → symbol_valid/bit/invalid
                                                              ↓
                                                    [morse_capture]
                                                    captured_pattern/length
                                                    input_done/invalid
                                                              ↓
                                                    [game_controller] ←→ [morse_rom]
                                                         ↓           ←→ [morse_player]
                                                    disp_char[3:0]        led_out
                                                         ↓
                                                    [seg7_driver]
                                                    seg[6:0], an[3:0]
```

### Data Flow Summary

1. **Button press** → Debounce → clean signal
2. **Debounced signal** → Press Classifier → dot/dash/invalid classification
3. **Classified symbols** → Morse Capture → shift register accumulates pattern, idle timer detects end-of-input
4. **Captured pattern + length** → Game Controller compares with ROM entry → determines pass/fail
5. **Morse Player** → In encoding mode, blinks LED to show the Morse pattern from ROM before user input is accepted
6. **Game state** → 7-Segment Driver → multiplexed display output

---

## Timing Parameters

All timing is derived from the 100 MHz system clock (10 ns period).

| Parameter | Value | Cycles | Constant Name |
|-----------|-------|--------|---------------|
| Debounce | 10 ms | 1,000,000 | `DEBOUNCE_TICKS` |
| Dot press min | 200 ms | 20,000,000 | `DOT_MIN` |
| Dot press max | 800 ms | 80,000,000 | `DOT_MAX` |
| Dash press min | 800 ms | 80,000,000 | `DASH_MIN` |
| Dash press max | 1.5 s | 150,000,000 | `DASH_MAX` |
| Idle timeout | 2 s | 200,000,000 | `IDLE_TIMEOUT` |
| Dot playback | 300 ms | 30,000,000 | `PLAY_DOT_TICKS` |
| Dash playback | 900 ms | 90,000,000 | `PLAY_DASH_TICKS` |
| Symbol gap | 300 ms | 30,000,000 | `PLAY_GAP_TICKS` |
| Display refresh | 1 ms | 100,000 | `REFRESH_TICKS` |
| Result display | 2 s | 200,000,000 | `DISPLAY_TICKS` |

---

## Morse Code Encoding

- **dot = 0, dash = 1**
- Stored MSB-first (first transmitted symbol is in the highest significant bit)
- Right-aligned in a 6-bit field
- Length field (3 bits) indicates how many symbols are significant

Example: A = `.-` → binary `01`, length 2 → stored as `6'b000001`

---

## Pin Assignments

| Signal | Pin | Description |
|--------|-----|-------------|
| clk | W5 | 100 MHz clock |
| btnC | U18 | Morse input (center button) |
| btnU | T18 | Reset (up button) |
| sw[0] | V17 | Mode: 0=Encoding, 1=Decoding |
| sw[1] | V16 | Hint: 1=Enable LED playback |
| seg[6:0] | W7,W6,U8,V8,U5,V5,U7 | 7-seg cathodes |
| dp | V7 | Decimal point |
| an[3:0] | U2,U4,V4,W4 | 7-seg anodes |
| led[15:0] | various | Debug LEDs |

---

## Display Format

| Situation | Display |
|-----------|---------|
| Encoding idle | `L01` to `L36` (digit 3 = 'L', digits 2-1 = level, digit 0 = blank) |
| Decoding idle | Target character (e.g., `"   A"`, `"   5"`) |
| Correct answer | `PASS` |
| Wrong answer | `ERR ` |
| All levels done | `donE` |

---

## Game Controller FSM

```
     ┌──────────┐
     │   IDLE   │ Display level/character
     └────┬─────┘
          │
     ┌────▼─────┐
     │RESET_CAP │ Hold capture reset
     └────┬─────┘
          │
    ┌─────┴──────┐ (encoding + hint)
    ▼            ▼
┌────────┐  ┌──────────┐
│PLAYBACK│  │WAIT_INPUT│ ◄── User enters Morse
└───┬────┘  └────┬─────┘
    │            │ input_done / input_invalid
    └────┬───────┘
         ▼
    ┌──────────┐
    │ EVALUATE │ Compare with ROM
    └────┬─────┘
    ┌────┴────┐
    ▼         ▼
┌───────┐ ┌───────┐ ┌───────┐
│ PASS  │ │ ERROR │ │ DONE  │
│2 sec  │ │2 sec  │ │2 sec  │
└───┬───┘ └───┬───┘ └───┬───┘
    │         │         │
    └────┬────┘    level→0
         ▼
       IDLE
```

---

## Debug LEDs

| LED | Signal |
|-----|--------|
| 0 | Debounced button state |
| 1 | Symbol valid (latched) |
| 2 | Symbol bit (0=dot, 1=dash) |
| 3 | Input done (latched) |
| 4 | Input invalid (latched) |
| 5 | Mode switch |
| 6 | Hint switch |
| 7 | Morse player LED |
| 11:8 | Current level [3:0] |
| 15:12 | FSM state |

---

## File Structure

```
morse_game_verilog/
├── rtl/
│   ├── debounce.v
│   ├── press_classifier.v
│   ├── morse_capture.v
│   ├── morse_rom.v
│   ├── morse_player.v
│   ├── game_controller.v
│   ├── seg7_driver.v
│   └── morse_game_top.v
├── constraints/
│   └── basys3.xdc
├── docs/
│   ├── architecture.md
│   ├── QUICK_REFERENCE_GUIDE.md
│   ├── DETAILED_CODE_BREAKDOWN.md
│   ├── PRACTICAL_IMPLEMENTATION_GUIDE.md
│   └── README.md (this file)
└── tb/
    └── (testbenches)
```

---

## Vivado Project Setup

1. Create new RTL project targeting **xc7a35tcpg236-1**
2. Add all `.v` files from `rtl/` as design sources
3. Add `basys3.xdc` from `constraints/` as constraints
4. Set `morse_game_top` as the top module
5. Run Synthesis → Implementation → Generate Bitstream
6. Program via USB-JTAG

---

---

# PART 2: QUICK REFERENCE GUIDE

## Quick Module Summary

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

## Common Questions & Answers

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

## Tweaking Cheat Sheet

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

## Verilog Cheat Sheet

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

## Presentation Tips for Your Teacher

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

---

# PART 3: DETAILED CODE BREAKDOWN

## System Architecture: The Big Picture

### **Analogy: A Classroom Teacher & Students**

Imagine a teacher running a morse code class:
- **The Doorkeeper (debounce)**: Before letting a student's question into class, the doorkeeper waits to make sure they're not just passing by and accidentally bumping the door. They wait for 10 milliseconds to confirm the student is really there.
- **The Referee (press_classifier)**: Once a student's hand is on the door, the referee measures HOW LONG they're pushing it. A quick tap = "dot", a long push = "dash", or if they push weirdly = "invalid".
- **The Clipboard (morse_capture)**: The clipboard writes down each dot and dash, forming a complete morse code pattern like ".-.-" (the letter "A").
- **The Dictionary (morse_rom)**: The dictionary tells you: "Yes, '.-' means 'A'".
- **The LED Blinker (morse_player)**: Before the student tries, the hint system blinks the correct morse code on an LED so they can see the pattern.
- **The Brain (game_controller)**: The game's central logic that keeps track of levels, checks if answers are right or wrong, and decides what to display.
- **The Screen (seg7_driver)**: Shows the game state on the 4-digit display ("L01", "PASS", "ERR ", "donE").
- **The Glue (morse_game_top)**: Connects everything together like the nervous system.

---

### **Signal Flow Diagram (How Data Moves)**

```
PLAYER PRESSES BUTTON
         ↓
    [debounce.v]
    (filters noise)
         ↓
   [press_classifier.v]
   (measures duration)
   DOT or DASH detected
         ↓
   [morse_capture.v]
   (builds pattern: .-.-) 
   PATTERN COMPLETE
         ↓
   [game_controller.v]
   ROM_ADDR = current level
         ↓
   [morse_rom.v]
   RETURNS: pattern, length, ASCII char
         ↓
   [game_controller.v]
   COMPARES: User input vs ROM
         ↓
   RESULT: PASS / ERROR / DONE
         ↓
   [seg7_driver.v]
   DISPLAY: "PASS" or "ERR "
   [morse_player.v]
   LED: blinks if hint enabled
```

---

### **100 MHz Clock: The Heartbeat**

Every calculation happens on the beat of a 100 MHz clock:
- **1 tick = 10 nanoseconds**
- **100,000 ticks = 1 millisecond (ms)**
- **100,000,000 ticks = 1 second (s)**

When you see `20_000_000` in code, it means: 20,000,000 clock ticks = 0.2 seconds.

---

## All 8 Modules Explained (Summary)

For **detailed line-by-line explanations** of all 8 modules with complete code breakdowns, see the file:
📄 `DETAILED_CODE_BREAKDOWN.md`

### **Module 1: debounce.v — The Noise Filter**
Cleans button input by waiting 10ms for signal to stabilize before reporting a change.

### **Module 2: press_classifier.v — Dot vs Dash Detector**
Measures button press duration and classifies as DOT (200–800ms), DASH (800–1500ms), or INVALID.

### **Module 3: morse_capture.v — Pattern Recorder**
Shifts dots and dashes into a 6-bit pattern, detects 2-second idle timeout for end-of-input.

### **Module 4: morse_rom.v — The Morse Dictionary**
Combinational ROM with 36 morse code entries (A–Z, 0–9) stored as pattern + length + ASCII.

### **Module 5: morse_player.v — LED Hint Blinker**
FSM that plays morse code on LED: blinks dot (300ms), dash (900ms), gaps (300ms).

### **Module 6: game_controller.v — The Game Brain**
8-state FSM managing game logic: idle → playback (optional) → wait input → evaluate → pass/error/done → idle.

### **Module 7: seg7_driver.v — 7-Segment Display Driver**
Multiplexes 4-digit display at ~250Hz, converts ASCII to 7-segment patterns.

### **Module 8: morse_game_top.v — The Glue**
Instantiates all 7 modules, connects all signals, defines parameters, assigns debug LEDs.

---

---

# PART 4: PRACTICAL IMPLEMENTATION GUIDE

## Real Scenario 1: Player Presses a Button
### From Raw Input to Classified Symbol (Step-by-Step with Real Numbers)

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

### **Debounce Module Processing**

```verilog
always @(posedge clk) begin
    btn_sync_0 <= btn_in;      // Capture raw button (noisy)
    btn_sync_1 <= btn_sync_0;  // Delay by 1 clock cycle
end
```

These 2 flip-flops **synchronize** the asynchronous button signal with our 100 MHz clock.

**Timeline with actual clock cycles:**

```
CLOCK TICK  | btn_in | btn_sync_0 | btn_sync_1 | count      | btn_out | ACTION
────────────┼────────┼────────────┼────────────┼────────────┼─────────┼──────────────────────
0           | 0      | 0          | 0          | 0          | 0       | All zero
25 ms       | 1      | 1          | 0          | 0          | 0       | Raw btn=1, sync_1=0
26 ms       | 0      | 0          | 1          | 1          | 0       | count=1
27 ms       | 1      | 1          | 0          | 0          | 0       | Different again
...         |        |            |            |            |         |
35 ms       | 1      | 1          | 1          | count      | 0       | Stable
...         |        |            |            |            |         |
45 ms       | 1      | 1          | 1          | 1M-1       | 1       | REACHED MAX! btn_out ← 1
525 ms      | 0      | 0          | 0          | 1M-1       | 0       | Released & confirmed
```

**Output Timeline:**
```
TIME (ms)  | btn_in (raw)        | btn_out (debounced) | DESCRIPTION
───────────┼─────────────────────┼────────────────────┼──────────────────────
0          | 0                   | 0                  | Idle
10         | (bouncing 0,1,0,1)  | 0                  | Button being pressed
15         | 1 (stable)          | 0                  | Signal stabilizes
25         | 1 (stable)          | 1                  | 10ms stable → OUTPUT CHANGES!
500        | 1 (held)            | 1                  | Button held
515        | (bouncing 1,0,1,0)  | 1                  | Button being released
520        | 0 (stable)          | 1                  | Signal stabilizes
530        | 0 (stable)          | 0                  | 10ms stable → OUTPUT CHANGES!
```

---

## Real Scenario 2: Complete Morse Code Input
### User Types 'A' = Dot-Dash (.-) — Full Flow

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

### **Step-by-Step Timeline**

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

## Real Scenario 3: Playback Hint System
### LED Blinks 'A' (.-) Before User Inputs

### **Initial Setup**
```
sw[0] = 0  (Encoding mode)
sw[1] = 1  (Hint enabled)
current_level = 0 (showing 'A')
```

### **LED Playback Timeline**

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

## Real Scenario 4: Mode Switching
### User Flips Switch from Encoding (0) to Decoding (1)

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

### **Mode Switching Timeline**

```
TIME (ticks) | sw[0]  | sw_mode_sync0 | sw_mode_sync1 | prev_mode | Detected | Display
──────────────┼────────┼───────────────┼───────────────┼───────────┼──────────┼──────────
0             | 0      | 0             | 0             | 0         | NO       | "L05"
(User flips)  
100           | 1      | 0             | 0             | 0         | NO       | "L05"
101           | 1      | 1             | 0             | 0         | NO       | "L05"
102           | 1      | 1             | 1             | 0         | YES!     | (changing)
103           | 1      | 1             | 1             | 1         | NO       | "A   " (Decoding, level 0)
```

**Result:** Mode changes from Encoding to Decoding, level resets to 0, display shows target character.

---

## Verilog Basics for Non-Programmers

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

### **3. `wire` — Connection (No Memory)**

```verilog
wire [5:0] result;  // A 6-bit connection (read-only, combinational)
```

**Analogy:** A physical wire connecting two components. Electricity flows through it instantly.

### **4. Bit Indexing and Slicing**

```verilog
reg [7:0] my_byte;  // An 8-bit value

my_byte[0]    // Rightmost bit (LSB) — the "ones" place
my_byte[7]    // Leftmost bit (MSB) — the "128s" place
my_byte[3:0]  // Lower 4 bits (bits 3, 2, 1, 0)
my_byte[7:4]  // Upper 4 bits (bits 7, 6, 5, 4)
```

**Analogy:** A byte is like a row of 8 light switches. `[0]` is the rightmost. `[7]` is the leftmost.

### **5. Concatenation: `{}`**

```verilog
result = {a, b, c};  // Combine a, b, c into a larger value
```

**Example:**
```verilog
a = 2'b10
b = 2'b11
c = 2'b01
result = {a, b, c} = 6'b101101  // a, then b, then c
```

### **6. Shift Operations (Critical for morse_capture)**

```verilog
value = {value[4:0], new_bit};  // Left shift, insert at LSB
```

This is exactly how morse_capture accumulates morse symbols: each new symbol shifts the pattern left and enters at the right.

---

## Understanding Registers and State

### **Register: A 1-Bit Memory Cell**

```verilog
reg my_flag;  // One bit: can be 0 or 1
```

On every clock edge:
- The flip-flop "captures" the input and outputs it on the next cycle.
- It "remembers" the value indefinitely.

### **State Machine: A Bigger Register**

Instead of just a counter, we use a register to hold a "state":

```verilog
reg [2:0] state;  // Can hold values 0-7

always @(posedge clk) begin
    if (rst)
        state <= S_IDLE;
    else
        case (state)
            S_IDLE: begin
                if (start_signal)
                    state <= S_WAIT;
            end
            S_WAIT: begin
                if (done_signal)
                    state <= S_DONE;
            end
            S_DONE: begin
                state <= S_IDLE;
            end
        endcase
end
```

**FSM transitions happen once per clock cycle.**

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

## Debugging with Debug LEDs

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

| LED | Signal | What It Shows |
|-----|--------|---------------|
| 0 | btn_morse_db | Button pressed (debounced) |
| 1 | symbol_valid | A dot or dash was detected |
| 2 | symbol_bit | Was it dot (0) or dash (1)? |
| 3 | input_done | Morse sequence complete |
| 4 | input_invalid | Invalid press detected |
| 5 | sw[0] | Mode switch |
| 6 | sw[1] | Hint enabled |
| 7 | player_led | LED playback active |
| 8-11 | Level | Current level (0-15) |
| 12-14 | FSM State | Current FSM state (0-7) |

### **Using LEDs to Debug: Example**

**Scenario:** "Player pressed button, but no symbol was detected."

**Check LEDs:**
1. Led[0] = 1? Yes → Button press was registered.
2. Led[1] = 1? No → Symbol was NOT detected.
   - press_classifier didn't classify it.

**Possible causes:**
- User pressed too short (< 200 ms) → press_count < DOT_MIN → invalid
- User pressed too long (> 1500 ms) → press_count > DASH_MAX → invalid
- Check Led[4]: Is it 1? → Yes → confirmed!

**Solution:** Tell player to adjust timing.

---

### **Complete Debugging Session Example**

**User says:** "I pressed the button for 500 ms, but the game said ERROR."

**Debug steps:**

1. **Watch LEDs while user presses for 500 ms:**
   - Led[0] = 0 initially (button idle)
   - Led[0] = 1 when pressed (after 10 ms debounce)
   - Led[1] = 1 when released (symbol detected!)
   - Led[0] = 0 when released (after debounce)

2. **Check Led[2] (what symbol was detected?):**
   - 500 ms = 50M ticks
   - DOT range: 20M–80M ✓ (falls within DOT range)
   - But if Led[2] = 1 → It was classified as DASH!
   - DASH_MIN = 80M (800 ms) → 500ms is too short for a dash!

3. **Check Led[4]:**
   - Led[4] = 1 → Input was INVALID!

4. **Conclusion:** The timing fell between dot and dash ranges or the button press was misclassified.

---

---

## SUMMARY & NEXT STEPS

### **What You Now Understand**

1. ✅ **Architecture:** How 8 modules work together to create a morse game
2. ✅ **Quick Reference:** 1-page summaries of each module and common questions
3. ✅ **Detailed Breakdown:** Line-by-line code explanation for all modules
4. ✅ **Practical Implementation:** Real scenarios showing what happens when you press buttons
5. ✅ **Debugging:** How to use debug LEDs to troubleshoot issues

### **How to Explain to Your Teacher**

Use this roadmap:

1. **Start with Part 1 (Architecture):** "Here's the big picture—button → debounce → classifier → capture → compare → display"
2. **Show Part 2 (Quick Reference):** "Each module does one specific job. Here's what each module is responsible for."
3. **Dive into Part 3 (Detailed Breakdown):** "Now let me show you the actual code and explain every line."
4. **Use Part 4 (Practical):** "Here's what happens when someone actually uses the game. Watch this timeline..."
5. **Demonstrate with LEDs:** "The debug LEDs let us see exactly what's happening inside the FPGA in real-time."

### **How to Tweak the Code**

1. Find the parameter you want to change in the "Tweaking Cheat Sheet" (Part 2)
2. Open `morse_game_top.v`
3. Locate the parameter definition
4. Change the value (e.g., `DOT_MIN` from `20_000_000` to `10_000_000` for faster dots)
5. Re-synthesize and re-upload to FPGA
6. Test the change and observe the effect

### **Helpful Files**

- 📄 **architecture.md** — System overview (read first)
- 📄 **QUICK_REFERENCE_GUIDE.md** — 1-page module summaries & Q&A (reference)
- 📄 **DETAILED_CODE_BREAKDOWN.md** — Full code line-by-line (deep dive)
- 📄 **PRACTICAL_IMPLEMENTATION_GUIDE.md** — Real scenarios (examples)
- 📄 **README.md** (this file) — Everything combined in one place

---

**You're ready to explain this project to anyone! 🚀**

Good luck with your presentation!

=======
# morse_code
>>>>>>> adc6f30a361e5f0acd128e194ab9b59573242289
