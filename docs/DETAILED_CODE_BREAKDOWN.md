# 📚 COMPREHENSIVE MORSE CODE GAME — DETAILED CODE BREAKDOWN
## A Complete Line-by-Line Explanation for Teachers & Non-Technical Readers

---

## TABLE OF CONTENTS
1. [System Architecture (The Big Picture)](#system-architecture)
2. [Module 1: debounce.v (Noise Filter)](#module-1-debouncev)
3. [Module 2: press_classifier.v (Dot vs Dash Referee)](#module-2-press_classifierv)
4. [Module 3: morse_capture.v (Pattern Recorder)](#module-3-morse_capturev)
5. [Module 4: morse_rom.v (The Morse Dictionary)](#module-4-morse_romv)
6. [Module 5: morse_player.v (LED Blinker)](#module-5-morse_playerv)
7. [Module 6: game_controller.v (The Game Brain)](#module-6-game_controllerv)
8. [Module 7: seg7_driver.v (Display Driver)](#module-7-seg7_driverv)
9. [Module 8: morse_game_top.v (The Glue)](#module-8-morse_game_topv)
10. [Where to Tweak Code for Changes](#tweaking-guide)

---

# SYSTEM ARCHITECTURE
## The Big Picture: How Everything Works Together

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

# MODULE 1: debounce.v
## The Noise Filter — Cleaning Up Button Press Signals

### **What Does debounce.v Do?**

When you press a physical button, it doesn't transition smoothly from 0V to 5V. Instead, it bounces:
- Your finger contacts the button.
- Electrical "noise" causes rapid 0→1→0→1→0 changes for 5–20 milliseconds.
- Eventually, it settles to a steady 1.

**Without debounce:** The FPGA might see 10 button presses when you only pressed once!

**With debounce:** We ignore all those bounces and only report the press once the signal is stable for 10 milliseconds.

---

### **Code Breakdown**

```verilog
module debounce #(
    parameter DEBOUNCE_TICKS = 1_000_000  // 10 ms at 100 MHz
)
```

**What it means:**
- `module debounce` — We're defining a building block called "debounce".
- `parameter DEBOUNCE_TICKS = 1_000_000` — This is a **setting** we can adjust. Right now it's set to 1 million ticks (= 10 ms). If we want faster debouncing, we could change it to 500_000 (= 5 ms).

**Tweaking Point #1:** Want a faster or slower debounce?
```verilog
parameter DEBOUNCE_TICKS = 1_000_000  // Change this number
// 1_000_000 = 10 ms (slow, but very safe)
// 500_000 = 5 ms (medium)
// 200_000 = 2 ms (fast, but risky if button is very noisy)
```

---

```verilog
(
    input  wire clk,
    input  wire rst,
    input  wire btn_in,
    output reg  btn_out
);
```

**What these "ports" mean:**
- `input wire clk` — The 100 MHz clock signal. Debounce listens for clock edges.
- `input wire rst` — Reset signal. When rst=1, clear everything.
- `input wire btn_in` — The **raw, bouncy** button signal from the FPGA pin.
- `output reg btn_out` — The **clean, debounced** button signal we send downstream.

The pattern: `raw button → debounce → clean button`

---

```verilog
localparam CNT_WIDTH = $clog2(DEBOUNCE_TICKS + 1);
```

**What it does:**
- `$clog2(...)` — Ceiling log base 2. Calculates how many bits we need to count up to `DEBOUNCE_TICKS`.
- Example: `$clog2(1_000_001)` ≈ 20 bits (because 2^20 = 1,048,576 > 1,000,000).
- **Why?** We need a counter big enough to hold the number 1,000,000. If we only used 16 bits, it could only count to 65,535—not enough!

**In plain English:** "How big a counter do we need?" → This line calculates it automatically.

---

```verilog
reg [CNT_WIDTH-1:0] count = 0;
reg                 btn_sync_0 = 0, btn_sync_1 = 0;  // 2-FF synchronizer
```

**What these registers store:**
- `count` — A counter that counts from 0 up to DEBOUNCE_TICKS. Size: CNT_WIDTH bits (e.g., 20 bits).
- `btn_sync_0, btn_sync_1` — Two **flip-flops** (1-bit memory cells) that synchronize the button signal with the clock.

**Why two flip-flops?** This is a **Metastability Guard**. Asynchronous inputs (buttons) can be unstable right when the clock edge happens. The two flip-flops ensure the signal is aligned with the clock before debouncing begins.

---

```verilog
// ── Two-stage synchronizer (metastability guard) ──
always @(posedge clk) begin
    if (rst) begin
        btn_sync_0 <= 1'b0;
        btn_sync_1 <= 1'b0;
    end else begin
        btn_sync_0 <= btn_in;
        btn_sync_1 <= btn_sync_0;
    end
end
```

**What this block does, line by line:**

1. `always @(posedge clk) begin` — **"On every rising clock edge, do the following:"**
   - Example: The clock beats 100 million times per second, so this block runs 100 million times per second.

2. `if (rst) begin` — **"If the reset signal is 1, reset everything."**
   - When the user presses the reset button or the FPGA boots, this clears all stored values.

3. `btn_sync_0 <= 1'b0; btn_sync_1 <= 1'b0;` — **"Set both flip-flops to 0."**
   - `1'b0` means "1-bit binary zero".

4. `else begin` — **"Otherwise (normal operation):"**

5. `btn_sync_0 <= btn_in;` — **"On this clock beat, copy the raw button input into the first flip-flop."**
   - Think of it like: "Remember what the button was this tick."

6. `btn_sync_1 <= btn_sync_0;` — **"On this clock beat, copy the first flip-flop into the second flip-flop."**
   - Think of it like: "Remember what the button WAS last tick."

**What the synchronizer accomplishes:**
```
Tick N-1: btn_in = 1 (maybe), btn_sync_0 = ?, btn_sync_1 = ?
After Tick N-1: btn_sync_0 = 1, btn_sync_1 = ?
After Tick N:   btn_sync_0 = btn_in, btn_sync_1 = 1
```

By using two flip-flops, we ensure the signal is synchronized to the clock before we start the debounce counter.

---

```verilog
// ── Debounce counter logic ──
always @(posedge clk) begin
    if (rst) begin
        count   <= {CNT_WIDTH{1'b0}};
        btn_out <= 1'b0;
    end else begin
        if (btn_sync_1 != btn_out) begin
            // Input differs from output — count up
```

**Let's break this down:**

- `if (btn_sync_1 != btn_out)` — **"Has the button state CHANGED compared to our last output?"**
  - `btn_sync_1` is the current (synced) button state.
  - `btn_out` is the debounced output we're maintaining.
  - If they're different, we detected a change → start counting.

Example scenario:
- `btn_out = 0` (we've been saying "button NOT pressed")
- `btn_sync_1 = 1` (but now the button IS pressed)
- Difference detected! Start the counter.

---

```verilog
            if (count == DEBOUNCE_TICKS - 1) begin
                btn_out <= btn_sync_1;   // Stable long enough, update
                count   <= {CNT_WIDTH{1'b0}};
            end else begin
                count <= count + 1'b1;
            end
```

**What this does:**

1. `if (count == DEBOUNCE_TICKS - 1)` — **"Has the signal been stable for DEBOUNCE_TICKS counts?"**
   - We use `DEBOUNCE_TICKS - 1` because counters are zero-indexed. When count goes from 0 to 999,999, that's 1,000,000 ticks total.

2. `btn_out <= btn_sync_1;` — **"Yes! The signal has been stable. Update our output to match."**
   - So if btn_sync_1 has been 1 for 10ms straight, we now say `btn_out = 1` (button is pressed).

3. `count <= {CNT_WIDTH{1'b0}};` — **"Reset the counter for the next transition."**
   - `{CNT_WIDTH{1'b0}}` is a shorthand for "create a vector of CNT_WIDTH bits, all set to 0".

4. `else begin count <= count + 1'b1;` — **"If not stable yet, increment the counter and wait."**
   - We keep counting. Next clock tick, count becomes 1, then 2, then 3...

---

```verilog
        end else begin
            // Input matches output — reset counter
            count <= {CNT_WIDTH{1'b0}};
        end
    end
end
```

**What this means:**

- `else begin` — **"If the input HAS NOT changed:"**
  - `btn_sync_1 == btn_out` (current = previous output, no change)

- `count <= {CNT_WIDTH{1'b0}};` — **"Reset the counter to 0."**
  - Why? Because if there's no change, we don't need to count. The signal is stable.

---

### **How debounce.v Works — Full Timeline**

```
TIME    btn_in   btn_sync_0   btn_sync_1   count    btn_out   DESCRIPTION
────────────────────────────────────────────────────────────────────────────
0 ms      0         0            0         0         0        Idle
          
5 ms      1         0            0         0         0        Button pressed (but noisy)
         (bounce)

10 ms     0         0            0         0         0        Still bouncing
         (bounce)

15 ms     1         1            0         0         0        Raw signal is 1, sync_0 updated
         (stable)

20 ms     1         1            1         0         0        sync_1 updated, change detected!
         (stable)
          
After    1         1            1         1         0        count=1, still waiting
20ms

After    1         1            1         2         0        count=2, still waiting
20ms+1tick

...

After    1         1            1      999,999   0        count is almost at max
20ms+10ms

After    1         1            1    1,000,000   1        COUNT REACHED! Output = 1
20ms+10ms

After    1         1            1         0         1        Counter reset, button held
20ms+10ms+
1 tick

30 ms     0         1            1         0         1        Button released, but not yet
         (release)

35 ms     0         0            1         1         1        Raw is 0, sync_0 is 0, 
         (bounce)                                            change detected! count++

...

After    0         0            0      999,999   1        count is almost at max
30ms+10ms

After    0         0            0    1,000,000   0        COUNT REACHED! Output = 0
30ms+10ms

After    0         0            0         0         0        Counter reset, button stable
30ms+10ms+
1 tick
```

---

### **Tweaking Point #1: Change Debounce Time**

In `morse_game_top.v`, find these lines:
```verilog
debounce #(
    .DEBOUNCE_TICKS(1_000_000)  // 10 ms ← CHANGE THIS
) u_debounce_morse (
```

**Experiments to try:**
- Change to `500_000` → 5 ms debounce (faster response, but might miss bounces)
- Change to `2_000_000` → 20 ms debounce (slower response, but very safe)

**Expected result:** Button input will respond faster or slower.

---

# MODULE 2: press_classifier.v
## The Referee — Measuring Button Duration to Classify Dot vs Dash

### **What Does press_classifier.v Do?**

Once we have a clean button signal from debounce, we need to measure HOW LONG the user holds the button:

- **Short press (200–800 ms)** = **DOT** (morse code: .)
- **Long press (800 ms–1.5 s)** = **DASH** (morse code: -)
- **Too short or too long** = **INVALID** (error beep or try again)

This module is like a referee with a stopwatch:
1. User presses button → start the timer.
2. User releases button → stop the timer.
3. Check if duration is in valid range → output dot/dash/invalid.

---

### **Code Breakdown**

```verilog
module press_classifier #(
    parameter DOT_MIN  = 20_000_000,   // 200 ms
    parameter DOT_MAX  = 80_000_000,   // 800 ms
    parameter DASH_MIN = 80_000_000,   // 800 ms
    parameter DASH_MAX = 150_000_000   // 1.5 s
)
```

**What these parameters do:**

- `DOT_MIN = 20_000_000` — **A dot must be held for at least 200 milliseconds.**
  - 20_000_000 ticks × 10 ns/tick = 200,000,000 ns = 200 ms
  
- `DOT_MAX = 80_000_000` — **A dot must be released within 800 milliseconds.**
  - If you hold it longer than 800 ms, it's not a dot anymore!
  
- `DASH_MIN = 80_000_000` — **A dash must be held for at least 800 milliseconds.**
  - Dashes are longer than dots, so they start where dots end.
  
- `DASH_MAX = 150_000_000` — **A dash must be released within 1.5 seconds.**
  - If you hold it longer than 1.5 seconds, it's invalid.

**Tweaking Point #2: Change Dot/Dash Speed**

In `morse_game_top.v`, find:
```verilog
press_classifier #(
    .DOT_MIN (20_000_000),   // ← Start of DOT range (200 ms)
    .DOT_MAX (80_000_000),   // ← End of DOT range (800 ms)
    .DASH_MIN(80_000_000),   // ← Start of DASH range (800 ms)
    .DASH_MAX(150_000_000)   // ← End of DASH range (1.5 s)
) u_classifier (
```

**Experiment:** Make the game faster:
```verilog
    .DOT_MIN (10_000_000),   // 100 ms instead of 200 ms
    .DOT_MAX (40_000_000),   // 400 ms instead of 800 ms
    .DASH_MIN(40_000_000),   // 400 ms instead of 800 ms
    .DASH_MAX(75_000_000)    // 750 ms instead of 1.5 s
```

This makes dots and dashes faster to input!

---

### **Inputs and Outputs**

```verilog
(
    input  wire clk,
    input  wire rst,
    input  wire btn_debounced,      // Clean button signal from debounce
    output reg  symbol_valid,       // Pulse: 1 when dot/dash is valid
    output reg  symbol_bit,         // 0=dot, 1=dash
    output reg  invalid_pulse       // Pulse: 1 when press is invalid
);
```

**What each signal means:**
- `btn_debounced` — The already-cleaned button signal from debounce module. No bounce!
- `symbol_valid` — **"I found a valid symbol!"** This is a 1-clock-tick pulse. It lasts for just one clock cycle.
- `symbol_bit` — If symbol_valid=1, this tells us: 0=dot, 1=dash.
- `invalid_pulse` — **"That press was too short or too long!"** Another 1-tick pulse.

**Why are these pulses?** So the downstream modules (morse_capture) know exactly when a new symbol arrived. If we held the signal high for the whole 200ms, morse_capture wouldn't know when the symbol started.

---

### **FSM States**

```verilog
localparam [1:0] S_IDLE    = 2'd0,
                 S_PRESSED = 2'd1,
                 S_CLASSIFY = 2'd2;
```

This FSM has 3 states:

1. **S_IDLE (0)** — Waiting for button press. Nothing happening.
2. **S_PRESSED (1)** — Button is held down. Counting the duration.
3. **S_CLASSIFY (2)** — Button was released. Measure the duration and decide: dot, dash, or invalid?

---

### **State Machine Logic**

```verilog
// ────────────────────────────────────────
S_IDLE: begin
    press_count <= {CNT_WIDTH{1'b0}};  // Reset counter to 0
    // Detect rising edge (button press)
    if (btn_debounced && !btn_prev) begin
        state       <= S_PRESSED;      // Move to PRESSED state
        press_count <= {CNT_WIDTH{1'b0}};
    end
end
```

**What this does:**

- `press_count <= {CNT_WIDTH{1'b0}};` — **"Reset the timer to 0."**
  - This is always done in IDLE because we're not actively timing anything.

- `if (btn_debounced && !btn_prev)` — **"Has the button JUST been pressed?"**
  - `btn_debounced` = current button state (1=pressed)
  - `!btn_prev` = previous button state was NOT pressed (0)
  - Together: "Button went from 0→1" → Rising edge = press!

- `state <= S_PRESSED;` — **"Move to the PRESSED state to start timing."**

---

```verilog
// ────────────────────────────────────────
S_PRESSED: begin
    // Count while button is held
    if (btn_debounced) begin
        if (press_count <= DASH_MAX)
            press_count <= press_count + 1'b1;  // Increment counter
    end

    // Detect falling edge (button release)
    if (!btn_debounced && btn_prev) begin
        state <= S_CLASSIFY;  // Move to CLASSIFY state
    end
end
```

**What this does:**

- `if (btn_debounced)` — **"Is the button still pressed?"**
  - If YES: increment the press_count timer.
  - If NO: do nothing (timer stays the same).

- `if (press_count <= DASH_MAX)` — **"Is the counter still in valid range?"**
  - This prevents the counter from counting forever if the user forgets to release the button.
  - Once it reaches DASH_MAX + 1, it stops incrementing.

- `if (!btn_debounced && btn_prev)` — **"Has the button JUST been released?"**
  - `!btn_debounced` = button is NOT pressed now (0)
  - `btn_prev` = button WAS pressed before (1)
  - Together: "Button went from 1→0" → Falling edge = release!

- `state <= S_CLASSIFY;` — **"Move to CLASSIFY state to evaluate what we measured."**

---

```verilog
// ────────────────────────────────────────
S_CLASSIFY: begin
    state <= S_IDLE;  // Immediately go back to IDLE
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
```

**What this does:**

- `state <= S_IDLE;` — **"We're done classifying, go back to waiting for the next press."**

- First IF: **"Is the press duration in the DOT range?"**
  ```
  press_count >= DOT_MIN  AND  press_count < DOT_MAX
  ≥ 200 ms                AND  < 800 ms
  ```
  If YES:
  - `symbol_valid <= 1'b1;` → Tell downstream: "I found a symbol!"
  - `symbol_bit <= 1'b0;` → Tell downstream: "It's a DOT (0)."

- Second ELSE IF: **"Is the press duration in the DASH range?"**
  ```
  press_count >= DASH_MIN  AND  press_count <= DASH_MAX
  ≥ 800 ms                 AND  ≤ 1500 ms
  ```
  If YES:
  - `symbol_valid <= 1'b1;` → "I found a symbol!"
  - `symbol_bit <= 1'b1;` → "It's a DASH (1)."

- Third ELSE: **"Duration is outside both ranges → INVALID!"**
  - `invalid_pulse <= 1'b1;` → Tell downstream: "This press was bad."

---

### **Example Timeline: Pressing a DOT**

```
TIME     btn_debounced   btn_prev   state       press_count   symbol_valid   symbol_bit   invalid_pulse
─────────────────────────────────────────────────────────────────────────────────────────────────────
0 ms         0             0        S_IDLE          0              0             x              0

User presses button...

100 ms       1             0        S_PRESSED       1              0             x              0
             ↑ Rising edge!
             Move to S_PRESSED

200 ms       1             1        S_PRESSED      20              0             x              0
             (same)        (update)  (count up)

400 ms       1             1        S_PRESSED      40              0             x              0
             (same)        (update)

500 ms       1             1        S_PRESSED      50              0             x              0

User releases button...

550 ms       0             1        S_CLASSIFY     50              1             0              0
             ↑ Falling edge!          (EVALUATE)     ↑ In DOT       ↑ YES! DOT   ↑ NOT INVALID
             Move to S_CLASSIFY        then S_IDLE   range?         (symbol_bit=0)

600 ms       0             0        S_IDLE          0              0             x              0
             (after 1 cycle)          (back to       (reset)        (pulse ended)
                                       waiting)
```

After this sequence, downstream modules (morse_capture) will see:
- `symbol_valid` pulse = 1 for one clock tick
- `symbol_bit` = 0 (indicating DOT)

---

### **Tweaking Point #2B: Make Game Easier for Beginners**

Expand the dot/dash windows in `morse_game_top.v`:
```verilog
press_classifier #(
    .DOT_MIN (15_000_000),   // More lenient: 150 ms
    .DOT_MAX (120_000_000),  // More lenient: 1200 ms
    .DASH_MIN(120_000_000),  // More lenient: 1200 ms
    .DASH_MAX(200_000_000)   // More lenient: 2 seconds
) u_classifier (
```

Now dots and dashes have a larger acceptable range, so timing doesn't need to be as precise.

---

# MODULE 3: morse_capture.v
## The Clipboard — Accumulating Dots and Dashes into a Pattern

### **What Does morse_capture.v Do?**

Once we have valid dots and dashes from press_classifier, we need to accumulate them into a sequence. For example:

- User presses: dot, dash, dot → morse_capture stores "010" → this is the letter 'A' (.-.)
- User presses: dash, dash, dash → morse_capture stores "111" → this is the letter 'O' (---)

morse_capture acts like a clipboard that:
1. Records each dot/dash symbol.
2. Stores them in the right order.
3. Detects when the user is done typing (2-second pause).
4. Sends the complete pattern downstream to game_controller.

---

### **Code Breakdown**

```verilog
module morse_capture #(
    parameter IDLE_TIMEOUT = 200_000_000,  // 2 sec at 100 MHz
    parameter MAX_SYMBOLS  = 6
)
```

**What these parameters mean:**

- `IDLE_TIMEOUT = 200_000_000` — **"If the user doesn't press for 2 seconds, assume they're done typing."**
  - 200,000,000 ticks × 10 ns/tick = 2,000,000,000 ns = 2 seconds.
  - This timeout prevents the game from waiting forever.

- `MAX_SYMBOLS = 6` — **"A morse code character can have at most 6 symbols (like '0' in morse is '-----', 5 dashes + 1 space = 6 bits)."**
  - Actually, in morse code:
    - Letters (A-Z) use 2–4 symbols
    - Digits (0-9) use 5 symbols each
  - We use 6 bits in a register to store up to 6 symbols.

---

### **Inputs and Outputs**

```verilog
(
    input  wire       clk,
    input  wire       rst,
    input  wire       symbol_valid,     // Pulse: valid symbol arrived
    input  wire       symbol_bit,       // 0=dot, 1=dash
    input  wire       invalid_pulse,    // Pulse: invalid input
    output reg [5:0]  captured_pattern, // The collected morse pattern
    output reg [2:0]  captured_length,  // How many symbols (0–6)
    output reg        input_done,       // Pulse: input complete (timeout)
    output reg        input_invalid     // Pulse: invalid detected
);
```

**Key signals:**
- `symbol_valid` — From press_classifier: "A new dot or dash is ready!"
- `symbol_bit` — The value: 0=dot, 1=dash.
- `captured_pattern` — A 6-bit register holding the pattern. Example: `6'b010101` = dot-dash-dot-dash-dot-dash.
- `captured_length` — How many of those 6 bits are actually valid? If user typed ".-", length=2 (not 6).
- `input_done` — "The user hasn't typed for 2 seconds, so I assume they're finished."
- `input_invalid` — "The user pressed the button for way too short or too long, or typed more than 6 symbols."

---

### **Registers Inside**

```verilog
reg [IDLE_WIDTH-1:0] idle_count;
reg                  has_input;
```

**What they track:**
- `idle_count` — A timer counting how long since the last symbol.
- `has_input` — A flag: "Have we received at least one symbol yet?"
  - Why track this? So we don't trigger `input_done` if the user hasn't typed anything.

---

### **Main Logic: Handling Symbols**

```verilog
if (invalid_pulse) begin
    input_invalid <= 1'b1;
    // Reset state for retry
    captured_pattern <= 6'b000000;
    captured_length  <= 3'd0;
    idle_count       <= {IDLE_WIDTH{1'b0}};
    has_input        <= 1'b0;
```

**What this does:**

- `if (invalid_pulse)` — **"Did press_classifier say this press was invalid?"**
  - Example: User pressed for 1 millisecond (too short) or 10 seconds (way too long).

- `input_invalid <= 1'b1;` — **"Tell downstream: this input was bad!"**
  - game_controller will see this and display "ERR " on the screen.

- Reset everything:
  - `captured_pattern <= 6'b000000;` → Clear the pattern.
  - `captured_length <= 3'd0;` → Length = 0.
  - `idle_count <= {IDLE_WIDTH{1'b0}};` → Clear the idle timer.
  - `has_input <= 1'b0;` → "We haven't received any valid input."

---

```verilog
end else if (symbol_valid) begin
    if (captured_length < MAX_SYMBOLS) begin
        // Shift left, insert new bit at LSB
        captured_pattern <= {captured_pattern[MAX_SYMBOLS-2:0], symbol_bit};
        captured_length  <= captured_length + 1'b1;
        idle_count       <= {IDLE_WIDTH{1'b0}};
        has_input        <= 1'b1;
```

**What this does:**

- `else if (symbol_valid)` — **"Did we just receive a valid dot or dash?"**

- `if (captured_length < MAX_SYMBOLS)` — **"Do we have room for more symbols?"**
  - If we already have 6 symbols, we can't add more (that's the max for any morse character).

**The Shift Line Explained:**
```verilog
captured_pattern <= {captured_pattern[MAX_SYMBOLS-2:0], symbol_bit};
```

This is called **left-shift with insertion**. Let's break it down with an example:

```
Initial state:
captured_pattern = 6'b010000 (we've captured ".", which is 0)
captured_length = 1

User presses and we detect a dash (symbol_bit = 1):

New captured_pattern = {captured_pattern[4:0], 1}
                     = {6'b01000[4:0], 1}
                     = {5'b1000, 1}
                     = 6'b10001

Wait, that doesn't look right...

Let me trace through more carefully:
captured_pattern[4:0] = 5-bit slice of 6'b010000 = 5'b10000
Concatenate with symbol_bit = 1
Result = 6'b100001

Hmm, still not matching intuition. Let me think about this differently.

Actually, Verilog bit indexing works like this:
6'b010000 has bits [5:4:3:2:1:0]
bit[5] = 0
bit[4] = 1
bit[3] = 0
bit[2] = 0
bit[1] = 0
bit[0] = 0

captured_pattern[4:0] extracts bits [4:0]:
= bits 4,3,2,1,0 = {1,0,0,0,0} = 5'b10000

Concatenate with symbol_bit=1:
{5'b10000, 1'b1} = 6'b100001

Actually wait. Let me re-read the code and think about what "shift left, insert at LSB" means in this context.

The comment says "shift left, insert new bit at LSB". But the code does:
{captured_pattern[4:0], symbol_bit}

This removes the MSB and inserts at the LSB. That's actually a RIGHT shift conceptually (newer symbols go to lower bit indices). But in terms of the morse pattern sequence:

Actually, I think the key insight is that "captured_pattern[MAX_SYMBOLS-2:0]" with MAX_SYMBOLS=6 gives us [4:0], which is the lower 5 bits. When we concatenate {[4:0], new_bit}, we're:
- Taking the old lower 5 bits
- Putting the new bit at position 0 (LSB)

So older symbols move up in index (to the left), and new symbols enter at position 0 (right).

Let me just trace through an example step by step:

Step 1: User types DOT
- captured_pattern = 6'b000001 (dot in position 0)
- captured_length = 1

Step 2: User types DASH
- captured_pattern <= {captured_pattern[4:0], 1}
- = {6'b000001[4:0], 1}
- = {5'b00000, 1}
- = 6'b000001 with new bit

Wait, this is confusing. Let me look at how morse_player uses this pattern to understand the convention.

Looking at morse_player.v, I see:
current_bit <= pattern[length - 1];

This extracts the bit at position [length-1]. If length=2, it gets pattern[1].

So for a 2-symbol morse code, if the pattern is stored as:
pattern[5:0] = 6'b??????XY where X is first symbol, Y is second symbol
and length = 2
Then current_bit = pattern[1] (Y, the first symbol we should play)

This suggests that symbols are stored MSB-first (in descending bit positions).

But the capture code shifts left and inserts at LSB, which would put newer symbols at lower bit indices. That seems backwards...

Let me re-read the morse_capture comment:
"Pattern encoding: MSB-first. First symbol goes into the MSB position relative to the captured length."

And also from morse_capture:
"Implemented as left-shift, new bit at LSB."

I think the key is "relative to the captured length". So:

Captured_pattern is right-aligned. The "length" field tells us how many bits are valid.

Example:
captured_pattern = 6'b000001, captured_length = 1
→ Only 1 bit is valid, and it's at position 0 (LSB)
→ This is the symbol "." (dot = 0)

When we add a dash (bit = 1):
captured_pattern <= {captured_pattern[4:0], 1}
= {5'b00000, 1}
= 6'b000001... wait that doesn't change it.

OK I think I'm confusing myself. Let me look at the actual binary:
6'b000001 with [4:0] gives us 5'b00000
Concatenating with 1 gives: 6'b000001 (same thing!)

That can't be right. Let me be more careful about the indexing:

6'b000001 is a 6-bit value. In Verilog, this is:
[5]=0, [4]=0, [3]=0, [2]=0, [1]=0, [0]=1

When we take [4:0], we get bits 4 down to 0 (5 bits total):
[4]=0, [3]=0, [2]=0, [1]=0, [0]=1 = 5'b00001

Concatenate with the new bit (1):
{5'b00001, 1'b1} = 6'b000011

So:
Before: 6'b000001 (just a dot in position 0)
After: 6'b000011 (dot at position 1, dash at position 0!)

Ah! So newer symbols go to position [0], and older symbols move up.

Let me trace the full example:

Step 1: User types DOT (symbol_bit = 0)
- Initial: captured_pattern = 6'b000000, captured_length = 0
- After: captured_pattern = {6'b00000[4:0], 0} = {5'b00000, 0} = 6'b000000
- Actually wait, if length=0 before, it's the first symbol, not a shift.

Let me look at the actual code flow:

```verilog
end else if (symbol_valid) begin
    if (captured_length < MAX_SYMBOLS) begin
        captured_pattern <= {captured_pattern[MAX_SYMBOLS-2:0], symbol_bit};
        captured_length  <= captured_length + 1'b1;
```

So EVERY time a symbol arrives, we shift and insert.

First symbol (DOT):
- Before: captured_pattern = 6'b000000, captured_length = 0
- Operation: {6'b000000[4:0], 0} = {5'b00000, 0} = 6'b000000
- After: captured_pattern = 6'b000000, captured_length = 1
- Hmm, it's still 0. That makes sense because we're shifting in a 0 (dot).

Second symbol (DASH):
- Before: captured_pattern = 6'b000000, captured_length = 1
- Operation: {6'b000000[4:0], 1} = {5'b00000, 1} = 6'b000001
- After: captured_pattern = 6'b000001, captured_length = 2
- So dot (0) moved to position [1], dash (1) is at position [0]

When morse_player plays this:
- length = 2
- First symbol to play: pattern[length-1] = pattern[1] = 0 (dot)
- Second symbol: pattern[length-2] = pattern[0] = 1 (dash)

Perfect! So the pattern is right-aligned, with bit[0] being the most-recently-added symbol, and bit[length-1] being the first symbol added.

When playing, we iterate from MSB (bit[length-1]) down to LSB (bit[0]), which gives us the right order.
```

Got it! The key insight is:
- `captured_pattern` stores symbols in reverse chronological order (newest at LSB, oldest at MSB).
- When stored in morse_rom, the ROM stores them the same way (right-aligned).
- morse_player extracts them from MSB down to LSB, which plays them in the correct chronological order.

Let me rewrite my explanation:

---

**The Shift Operation Explained:**

When a new symbol arrives, we shift the existing pattern and insert the new symbol at the LSB (rightmost position):

```
Initial (user types DOT):
captured_pattern = 6'b000000
captured_length = 0

After DOT (symbol_bit = 0):
{captured_pattern[4:0], 0} = {5'b00000, 0} = 6'b000000
captured_length = 1

After DASH (symbol_bit = 1):
{captured_pattern[4:0], 1} = {5'b00000, 1} = 6'b000001
captured_length = 2
(the 0 shifted up to bit[1], new 1 inserted at bit[0])

After DOT (symbol_bit = 0):
{captured_pattern[4:0], 0} = {5'b00000[4:0], 0} = {5'b00001, 0} = 6'b000010
captured_length = 3
(previous bits shifted up)

Final captured_pattern = 6'b000010, captured_length = 3
This represents: . - . (dot-dash-dot) = "A" in morse code
```

The pattern is stored **right-aligned**, with the most recently entered symbol at the LSB.

---

**Back to the code:**

```verilog
        captured_length  <= captured_length + 1'b1;
        idle_count       <= {IDLE_WIDTH{1'b0}};
        has_input        <= 1'b1;
```

- `captured_length <= captured_length + 1'b1;` — **"Increment the count of symbols."**
  - If we had 2 symbols before, now we have 3.

- `idle_count <= {IDLE_WIDTH{1'b0}};` — **"Reset the idle timer."**
  - The user just typed something, so reset the 2-second timeout counter to 0.
  - This prevents the game from ending early while the user is still typing.

- `has_input <= 1'b1;` — **"Mark that we've received at least one valid symbol."**

---

```verilog
    end else begin
        // Overflow: too many symbols
        input_invalid    <= 1'b1;
        captured_pattern <= 6'b000000;
        captured_length  <= 3'd0;
        idle_count       <= {IDLE_WIDTH{1'b0}};
        has_input        <= 1'b0;
    end
```

- `end else begin` — **"We already have 6 symbols, and the user is trying to add more!"**
  - This is an error condition. Morse characters have at most 5 symbols (like "0" = "-----").

- `input_invalid <= 1'b1;` — **"Reject this input!"**
  - game_controller will see this and display "ERR ".

- Clear everything for retry.

---

```verilog
end else if (has_input) begin
    if (idle_count == IDLE_TIMEOUT - 1) begin
        input_done <= 1'b1;
```

- `else if (has_input)` — **"We've received at least one symbol, and no new symbol just arrived."**
  - This is the normal "waiting" condition.

- `if (idle_count == IDLE_TIMEOUT - 1)` — **"Has 2 seconds passed since the last symbol?"**
  - If YES, the user is done typing.

- `input_done <= 1'b1;` — **"Tell downstream: the input sequence is complete!"**
  - game_controller will take this pattern and compare it with the ROM entry.

---

```verilog
        idle_count <= {IDLE_WIDTH{1'b0}};
        has_input  <= 1'b0;
    end else begin
        idle_count <= idle_count + 1'b1;
    end
end
```

- `idle_count <= {IDLE_WIDTH{1'b0}};` — **"Reset the timer after completion."**
  - Get ready for the next sequence.

- `has_input <= 1'b0;` — **"Clear the 'we have input' flag."**

- `else` block: If idle_count hasn't reached the timeout yet, increment it.

---

### **Example Timeline: User Types ".-" (Letter A)**

```
TIME      symbol_valid  symbol_bit  captured_pattern  captured_length  idle_count  input_done
─────────────────────────────────────────────────────────────────────────────────────────────
0 ms           0           x         6'b000000         0               0           0

User presses for 300ms (DOT)...
310 ms         1           0         6'b000000         1               0           0
               ↑ DOT        ↑         (shifted in 0)    ↑ Now 1 symbol  ↑ Reset     ↑ Not done

User releases, waits 50ms, presses again for 900ms (DASH)...
360 ms         0           x         6'b000000         1               50          0
               (no symbol)            (no change)       (waiting)       (counting)  (not done)

900 ms         1           1         6'b000001         2               0           0
               ↑ DASH       ↑         (0 shifted left,  ↑ Now 2 symbols ↑ Reset     ↑ Not done
                                      1 inserted)

User releases, waits 2 seconds...
2 sec          0           x         6'b000001         2              200000000    1
               (no symbol)            (no change)       (still 2)       (timeout!)   ↑ DONE!
                                                                        (1 tick
                                                                         left to
                                                                         threshold)

2 sec+         0           x         6'b000001         2              0            0
               (next cycle)           (no change)       (still 2)       (reset)      (pulse ended)
```

At the end, morse_capture outputs:
- `captured_pattern = 6'b000001` (the morse code for ".-")
- `captured_length = 2`
- `input_done` pulse (1 cycle)

---

### **Tweaking Point #3: Change Input Timeout**

In `morse_game_top.v`, find:
```verilog
morse_capture #(
    .IDLE_TIMEOUT(200_000_000),  // 2 sec ← CHANGE THIS
    .MAX_SYMBOLS (6)
) u_capture (
```

**Experiments:**
- Change to `100_000_000` → 1 second (user must finish typing quickly)
- Change to `400_000_000` → 4 seconds (more forgiving timeout)

**Expected result:** The game waits longer or shorter before accepting the input.

---

# MODULE 4: morse_rom.v
## The Dictionary — The Official Morse Code Reference

### **What Does morse_rom.v Do?**

morse_rom is a **combinational lookup table** that stores all 36 morse code entries:
- Letters A–Z (26 entries)
- Digits 0–9 (10 entries)

It's like a dictionary. When the game_controller says "Give me the morse pattern for level 5", the ROM instantly returns:
- The morse pattern (.-.)
- The pattern length (2 symbols)
- The ASCII character ('A')

---

### **Code Breakdown**

```verilog
module morse_rom (
    input  wire [5:0]  addr,       // Which entry? (0–35)
    output reg  [5:0]  pattern,    // Morse pattern
    output reg  [2:0]  length,     // Symbols in pattern
    output reg  [7:0]  ascii_char  // ASCII code
);
```

**Inputs/Outputs:**
- `addr` — A number 0–35. Example: addr=0 means "give me the morse code for 'A'".
- `pattern` — Output: the morse pattern in binary. Example: 0b000001 for ".-"
- `length` — Output: how many valid bits in the pattern. Example: 2 for ".-"
- `ascii_char` — Output: the ASCII code to display. Example: 0x41 for 'A'

---

### **How Morse is Encoded**

Morse code uses:
- **Dot (.)** = short symbol = binary **0**
- **Dash (-)** = long symbol = binary **1**

Example: 'A' = ".-" = [0, 1] in binary = 0b000001 (right-aligned in 6 bits, length=2)

The ROM stores patterns **right-aligned** with a separate `length` field telling us how many bits are meaningful.

---

### **The Combinational Logic**

```verilog
always @(*) begin
    case (addr)
        // ──── Letters A–Z ────
        6'd0:  begin pattern = 6'b000001; length = 3'd2; ascii_char = 8'h41; end // A .-
        6'd1:  begin pattern = 6'b001000; length = 3'd4; ascii_char = 8'h42; end // B -...
        6'd2:  begin pattern = 6'b001010; length = 3'd4; ascii_char = 8'h43; end // C -.-.
```

**What this means:**

- `always @(*)` — **"Combinational logic. Whenever the input changes, immediately update the output."**
  - There's no clock delay. Combinational = instantaneous.

- `case (addr)` — **"What level are we looking up?"**
  - If addr=0, return data for 'A'.
  - If addr=1, return data for 'B', etc.

**Let's decode 'A':**
```
6'd0:  begin
    pattern = 6'b000001;       // Morse: .- (dot-dash)
    length = 3'd2;            // 2 symbols
    ascii_char = 8'h41;       // ASCII 0x41 = 'A' (decimal 65)
end
```

- `pattern = 6'b000001` in decimal is 1. In binary: [5:0] = 000001.
  - When shifted right and read from MSB, this represents: [5:4:3:2:1:0] = [0:0:0:0:0:1]
  - But we only look at the lower 2 bits (because length=2): [1:0] = [0:1]
  - In order [1] then [0], that's: 0 then 1 = dot then dash = ".-" = 'A'. ✓

**Let's decode 'B' (dash-dot-dot-dot = -...)**
```
6'd1:  begin
    pattern = 6'b001000;       // Binary: 001000 = decimal 8
    length = 3'd4;            // 4 symbols
    ascii_char = 8'h42;       // ASCII 0x42 = 'B'
end
```

- `pattern = 6'b001000`:
  - Binary: [5:4:3:2:1:0] = [0:0:1:0:0:0]
  - We use the lower 4 bits (because length=4): [3:0] = [1:0:0:0]
  - In order [3] [2] [1] [0], that's: 1, 0, 0, 0 = dash, dot, dot, dot = "-..." = 'B'. ✓

---

**Morse Code Encoding Convention (Important!):**

In this project, morse patterns are stored in a specific way:
1. **Dot = 0, Dash = 1**
2. **Right-aligned in 6 bits** (bits [5:0])
3. **MSB-first playback** using the `length` field

Example for "ABC":
```
'A' = .-    → binary 01, length 2 → stored as 6'b000001
'B' = -...  → binary 1000, length 4 → stored as 6'b001000
'C' = -.-.  → binary 1010, length 4 → stored as 6'b001010
```

When morse_player reads these:
- It extracts bits from position [length-1] down to [0]
- This gives the right chronological order

---

### **All 36 Morse Codes in the ROM**

```verilog
// ──── Letters A–Z ────
6'd0:  pattern = 6'b000001; // A = .-
6'd1:  pattern = 6'b001000; // B = -...
6'd2:  pattern = 6'b001010; // C = -.-.
6'd3:  pattern = 6'b000100; // D = -..
6'd4:  pattern = 6'b000000; // E = .
6'd5:  pattern = 6'b000010; // F = ..-.
6'd6:  pattern = 6'b000110; // G = --.
6'd7:  pattern = 6'b000000; // H = ....
6'd8:  pattern = 6'b000000; // I = ..
6'd9:  pattern = 6'b000111; // J = .---
// ... (more letters, then 0-9)
```

---

### **Tweaking Point #4: Change Game Difficulty**

You can modify the order of morse codes to change the game difficulty. For example, reorder the ROM entries so easier letters come first:

Current order (levels 0–25):
```
Level 0 = A, Level 1 = B, Level 2 = C, ...
```

Modified order (easier first):
```
6'd0:  pattern = 6'b000000; // E = . (one dot, simplest!)
6'd1:  pattern = 6'b000001; // T = - (one dash, very easy)
6'd2:  pattern = 6'b000001; // A = .- (two symbols, easy)
6'd3:  pattern = 6'b000010; // N = -. (two symbols, easy)
// ... then harder ones later
```

This way, beginners start with the simplest morse codes and gradually progress.

---

### **ASCII Codes Used**

```verilog
ascii_char = 8'h41;  // 0x41 = 65 decimal = 'A'
ascii_char = 8'h30;  // 0x30 = 48 decimal = '0'
```

These ASCII codes are used by seg7_driver to display the character on the 7-segment display.

---

# MODULE 5: morse_player.v
## The LED Blinker — Playing Morse Code for Hints

### **What Does morse_player.v Do?**

In Encoding mode with hints enabled (sw[1] = 1), before the player types their answer, an LED blinks the correct morse code pattern. This is the "hint" system.

morse_player takes:
- The morse pattern from ROM (e.g., 6'b000001 for 'A')
- The length (e.g., 2 for 'A')
- And blinks an LED to show the pattern

The blink timing is:
- **Dot on:** 300 ms (short)
- **Dash on:** 900 ms (long)
- **Gap between symbols:** 300 ms

---

### **Code Breakdown**

```verilog
module morse_player #(
    parameter PLAY_DOT_TICKS  = 30_000_000,   // 300 ms dot ON
    parameter PLAY_DASH_TICKS = 90_000_000,   // 900 ms dash ON
    parameter PLAY_GAP_TICKS  = 30_000_000    // 300 ms inter-symbol gap
)
```

**These parameters control the playback timing:**
- `PLAY_DOT_TICKS = 30_000_000` (300 ms): How long to light the LED for a dot.
- `PLAY_DASH_TICKS = 90_000_000` (900 ms): How long to light the LED for a dash.
- `PLAY_GAP_TICKS = 30_000_000` (300 ms): How long the LED stays off between symbols (for visual separation).

---

### **Inputs and Outputs**

```verilog
(
    input  wire       clk,
    input  wire       rst,
    input  wire       start,          // Pulse to begin playback
    input  wire [5:0] pattern,        // Morse pattern from ROM
    input  wire [2:0] length,         // Number of symbols
    output reg        led_out,        // LED output (1=ON)
    output reg        busy,           // 1 while playing
    output reg        done_pulse      // Pulse when finished
);
```

**Key signals:**
- `start` — game_controller sends a 1-cycle pulse: "Play the morse code!"
- `pattern, length` — The morse code from ROM to play.
- `led_out` — Controls the LED. 1 = LED on, 0 = LED off.
- `busy` — game_controller checks this: if busy=0, it's safe to trigger playback.
- `done_pulse` — When playback finishes, morse_player sends a 1-cycle pulse, and game_controller moves to the next state.

---

### **FSM States**

```verilog
localparam [2:0] S_IDLE    = 3'd0,  // Waiting for start
                 S_LOAD    = 3'd1,  // Load pattern and prepare
                 S_PLAY_ON = 3'd2,  // LED on (dot or dash duration)
                 S_PLAY_GAP= 3'd3,  // LED off (gap between symbols)
                 S_DONE    = 3'd4;  // Playback finished
```

**State machine flow:**
```
S_IDLE → S_LOAD → S_PLAY_ON → S_PLAY_GAP → S_PLAY_ON → S_DONE → S_IDLE
         (setup)  (dot/dash) (gap)        (next sym)  (finish)  (wait)
```

---

### **S_IDLE: Waiting for Start Command**

```verilog
S_IDLE: begin
    led_out <= 1'b0;
    busy    <= 1'b0;
    if (start) begin
        state <= S_LOAD;
        busy  <= 1'b1;
    end
end
```

**What this does:**
- Keep the LED off.
- Set busy=0 (not playing).
- If game_controller sends `start` pulse, move to S_LOAD and set busy=1.

---

### **S_LOAD: Prepare the Pattern**

```verilog
S_LOAD: begin
    if (length == 3'd0) begin
        // Nothing to play
        state <= S_DONE;
    end else begin
        pat_shift     <= pattern;
        sym_remaining <= length;
        // Extract the MSB (first symbol to play)
        current_bit   <= pattern[length - 1];
        state         <= S_PLAY_ON;
        timer         <= {TIMER_WIDTH{1'b0}};
    end
end
```

**What this does:**

- If `length == 0`, there's nothing to play, so go directly to S_DONE (skip playback).

- Otherwise:
  - `pat_shift <= pattern;` — **"Copy the pattern into a working register."**
    - We'll shift through this register bit by bit.
  
  - `sym_remaining <= length;` — **"We have `length` symbols to play."**
    - Example: length=2 means we need to play 2 symbols.
  
  - `current_bit <= pattern[length - 1];` — **"Load the first symbol (MSB)."**
    - Morse is stored right-aligned. To play MSB-first, we start at index [length-1].
    - Example: pattern=6'b000001, length=2 → pattern[2-1]=pattern[1]=0 (dot).
  
  - `timer <= {TIMER_WIDTH{1'b0}};` — **"Reset the timer."**
    - We're about to start playing, so clear any old timer value.

---

### **S_PLAY_ON: LED Blinks (Dot or Dash)**

```verilog
S_PLAY_ON: begin
    led_out <= 1'b1;
    if (current_bit == 1'b0) begin  // DOT
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
```

**What this does:**

- `led_out <= 1'b1;` — **"Turn the LED on."**

- `if (current_bit == 1'b0)` — **"Is this symbol a DOT (0)?"**

- `if (timer == PLAY_DOT_TICKS - 1)` — **"Has the LED been on for 300 ms?"**
  - When timer reaches 30_000_000 - 1 ticks, turn it off.
  - Why `- 1`? Counters are 0-indexed. 0 to 29,999,999 is 30,000,000 ticks.

- `led_out <= 1'b0;` — **"Turn the LED off."**

- `sym_remaining <= sym_remaining - 1'b1;` — **"One symbol played, decrement counter."**

- `if (sym_remaining == 3'd1)` — **"Was that the last symbol?"**
  - If YES, go to S_DONE (playback finished).
  - If NO, go to S_PLAY_GAP (add a gap before the next symbol).

---

**The DASH branch is similar:**

```verilog
    end else begin  // DASH
        if (timer == PLAY_DASH_TICKS - 1) begin
            led_out       <= 1'b0;
            timer         <= {TIMER_WIDTH{1'b0}};
            sym_remaining <= sym_remaining - 1'b1;
            if (sym_remaining == 3'd1) begin
                state <= S_DONE;
            end else begin
                state <= S_PLAY_GAP;
            end
```

The only difference is `PLAY_DASH_TICKS` (900 ms) instead of `PLAY_DOT_TICKS` (300 ms).

---

### **S_PLAY_GAP: Silent Gap Between Symbols**

```verilog
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
```

**What this does:**

- `led_out <= 1'b0;` — **"Keep LED off during the gap."**

- `if (timer == PLAY_GAP_TICKS - 1)` — **"Has the gap lasted 300 ms?"**

- `current_bit <= pat_shift[sym_remaining - 1];` — **"Load the next symbol from the pattern."**
  - We use `pat_shift[sym_remaining - 1]` to extract the next bit.
  - `sym_remaining` decrements as we play, so we're moving to lower indices.

- `state <= S_PLAY_ON;` — **"Play the next symbol."**

---

### **S_DONE: Playback Complete**

```verilog
S_DONE: begin
    led_out    <= 1'b0;
    done_pulse <= 1'b1;
    state      <= S_IDLE;
end
```

**What this does:**
- Turn off the LED.
- Send a `done_pulse` (1-cycle pulse) to tell game_controller playback finished.
- Go back to S_IDLE to wait for the next start command.

---

### **Example Timeline: Playing 'A' (.-)**

```
TIME      start  state    current_bit  timer   led_out  sym_remaining  done_pulse
────────────────────────────────────────────────────────────────────────────────
0 ms       0     S_IDLE   x           0        0       x              0

User enables hint and we reach PLAYBACK state...

1 ms       1     S_LOAD   x           0        0       x              0
                  ↑ start pulse

2 ms       0     S_PLAY_ON 0 (dot)    0        1       2              0
                  ↑ switch to   ↑ first   ↑ start ↑ LED on  ↑ 2 symbols
                    S_PLAY_ON   symbol    timer         to play

100 ms     0     S_PLAY_ON 0          30_000   1       2              0
                           (dot)

300 ms     0     S_PLAY_GAP (gap)      -1       0       1              0
                  ↑ dot done!  ↑ prep       ↑       ↑ 1 symbol
                  move to gap  for gap      timer    left
                               reached!

310 ms     0     S_PLAY_ON 1 (dash)   0        1       1              0
                  ↑ gap done!  ↑ next       ↑ LED
                  play next    symbol      on for
                              is dash      dash

900 ms     0     S_PLAY_ON 1          90_000   1       1              0
                           (dash)

1200 ms    0     S_DONE    (final)    -1       0       0              1
                  ↑ dash done!         ↑       ↑ pulse!
                  last symbol,         timer
                  so go to DONE        reached!

1300 ms    0     S_IDLE    x           0        0       x              0
                  ↑ back to      ↑ LED  ↑ pulse
                    waiting      off   ended
```

Result: The LED blinks: dot (300ms off) dash (900ms). The player sees ".- " on the LED and knows to enter the morse code for 'A'.

---

### **Tweaking Point #5: Change Playback Speed**

In `morse_game_top.v`, find:
```verilog
morse_player #(
    .PLAY_DOT_TICKS (30_000_000),  // 300 ms ← CHANGE THIS
    .PLAY_DASH_TICKS(90_000_000),  // 900 ms ← CHANGE THIS
    .PLAY_GAP_TICKS (30_000_000)   // 300 ms ← CHANGE THIS
) u_player (
```

**Experiments:**
- Make faster (half the time):
  ```verilog
  .PLAY_DOT_TICKS (15_000_000),  // 150 ms
  .PLAY_DASH_TICKS(45_000_000),  // 450 ms
  .PLAY_GAP_TICKS (15_000_000)   // 150 ms
  ```
  
- Make slower (double the time):
  ```verilog
  .PLAY_DOT_TICKS (60_000_000),  // 600 ms
  .PLAY_DASH_TICKS(180_000_000), // 1800 ms
  .PLAY_GAP_TICKS (60_000_000)   // 600 ms
  ```

**Expected result:** The LED blinks faster or slower when hints are enabled.

---

# MODULE 6: game_controller.v
## The Game Brain — Managing Game Logic and State

### **What Does game_controller.v Do?**

This is the central logic module. It:
1. Tracks the current level (0–35 for A–Z, 0–9).
2. Manages the game state (idle, playing, evaluating, showing results).
3. Decides whether to show level display or target character.
4. Compares player's input with the ROM entry.
5. Controls when morse_player should blink hints.
6. Displays "PASS", "ERR ", or "donE" based on results.
7. Handles mode switching (Encoding vs Decoding).

---

### **Code Breakdown**

```verilog
module game_controller #(
    parameter NUM_LEVELS    = 36,
    parameter DISPLAY_TICKS = 200_000_000  // 2 sec result display
)
```

**Parameters:**
- `NUM_LEVELS = 36` — A–Z (26) + 0–9 (10) = 36 total levels.
- `DISPLAY_TICKS = 200_000_000` — Show "PASS"/"ERR " for 2 seconds before returning to the level.

---

### **FSM States**

```verilog
localparam [2:0] S_IDLE       = 3'd0,
                 S_PLAYBACK   = 3'd1,
                 S_WAIT_INPUT = 3'd2,
                 S_EVALUATE   = 3'd3,
                 S_SHOW_PASS  = 3'd4,
                 S_SHOW_ERROR = 3'd5,
                 S_SHOW_DONE  = 3'd6,
                 S_RESET_CAP  = 3'd7;
```

**Game flow:**
```
        ┌─ (encoding + hint enabled) ─→ S_PLAYBACK ─┐
        │                                             │
S_IDLE ─┤                                   S_WAIT_INPUT
        │                                     ↓
        └─────────────────────────→ (no hints)    (input complete)
                                                   ↓
        ┌──────────────── S_EVALUATE ────────────┬────────────────┐
        │                 ↑                      ↓                 ↓
    MATCH?         (pattern matches)         PASS            ERROR
        │              ↑                       ↓                 ↓
        └─── Correct ───┴─ S_SHOW_PASS     2 sec            S_SHOW_ERROR
                              ↓              ↓                2 sec
                          Level++           IDLE               ↓
                              │            ↑                  IDLE
                          All done?         └──────────────────┘
                           (Yes)
                              ↓
                         S_SHOW_DONE (2 sec)
                              ↓
                           Level = 0
                              ↓
                            IDLE
```

---

### **S_IDLE: Display Level or Character**

```verilog
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
```

**What this does:**

- `capture_rst <= 1'b1;` — **"Clear the morse_capture module."**
  - Get ready for new input.

- **Encoding mode (sw[0] = 0):**
  - Display "L01" (level 1), "L02" (level 2), etc.
  - `disp_char3 = 'L'` (leftmost digit)
  - `disp_char2, disp_char1` = tens and ones digits (calculated from current_level)
  - `disp_char0 = blank` (rightmost digit)

- **Decoding mode (sw[0] = 1):**
  - Display the target character: `rom_ascii` from the ROM.
  - Left-pad with blanks so the character appears on the right: `"   A"`.

- `state <= S_RESET_CAP;` — Move to the next state.

---

### **S_RESET_CAP: Hold Reset for Morse Capture**

```verilog
S_RESET_CAP: begin
    capture_rst <= 1'b1;  // Keep reset active

    if (sw_mode_sync1 == 1'b0 && sw_hint_sync1) begin
        state <= S_PLAYBACK;
    end else begin
        state <= S_WAIT_INPUT;
    end
end
```

**What this does:**

- Keep the reset signal high for one more cycle to ensure morse_capture is properly reset.

- Check conditions for playback:
  - `sw_mode_sync1 == 1'b0` — Encoding mode (not decoding).
  - `sw_hint_sync1` — Hint switch is enabled.
  - If BOTH true, play the morse code hint first.
  - Otherwise, skip to S_WAIT_INPUT.

---

### **S_PLAYBACK: Play Morse Hint**

```verilog
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
```

**What this does:**

- Check if morse_player is ready (`!player_busy && !player_start`).
  - If yes, send a `player_start` pulse.
  - This triggers the LED to blink the morse code.

- Maintain the level display ("L01") while the LED is blinking.

- When `player_done` pulse arrives, the playback is finished.
  - Move to S_WAIT_INPUT so the player can now enter their answer.

---

### **S_WAIT_INPUT: Accept User Input**

```verilog
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
```

**What this does:**

- Display the current level/character (same as S_IDLE).

- Check if the user finished typing:
  - `if (input_done)` — User held the button for 2+ seconds with no press.
    - Move to S_EVALUATE to check the answer.
  
  - `else if (input_invalid)` — User made an invalid press.
    - Move to S_SHOW_ERROR to display "ERR " for 2 seconds.

---

### **S_EVALUATE: Compare with ROM**

```verilog
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
```

**What this does:**

**The Critical Comparison:**
```verilog
if (captured_length == rom_length &&
    captured_pattern[5:0] == rom_pattern[5:0])
```

For a correct answer:
1. **Length must match:** `captured_length == rom_length`
   - If user types ".-" (A = 2 symbols) and ROM says A = 2 symbols ✓
   - If user types ".-." (3 symbols) but ROM says A = 2 symbols ✗

2. **Pattern must match:** `captured_pattern == rom_pattern`
   - Bit-by-bit comparison of the morse code.

**If both match:**
- Check if this is the last level (`current_level == NUM_LEVELS - 1`):
  - If YES (level 35), go to S_SHOW_DONE (game finished!).
  - If NO, go to S_SHOW_PASS (show "PASS", then next level).

**If mismatch:**
- Go to S_SHOW_ERROR (show "ERR ", then retry same level).

---

### **S_SHOW_PASS: Display "PASS" for 2 Seconds**

```verilog
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
```

**What this does:**

- Set all 4 display digits to "PASS".
  - 8'h50 = 0x50 = 80 decimal = 'P' (ASCII)
  - 8'h41 = 0x41 = 65 decimal = 'A'
  - 8'h53 = 0x53 = 83 decimal = 'S'

- Increment the display_timer until it reaches 2 seconds.
  - `if (display_timer == DISPLAY_TICKS - 1)` — 2 seconds have passed.

- When timer expires:
  - `current_level <= current_level + 1'b1;` — **"Advance to the next level."**
  - `state <= S_IDLE;` — Return to the display.

---

### **S_SHOW_ERROR: Display "ERR " for 2 Seconds**

```verilog
S_SHOW_ERROR: begin
    // Display "ERR "
    disp_char3 <= 8'h45;  // 'E'
    disp_char2 <= 8'h52;  // 'R'
    disp_char1 <= 8'h52;  // 'R'
    disp_char0 <= 8'h20;  // blank

    if (display_timer == DISPLAY_TICKS - 1) begin
        state <= S_IDLE;
        // Same level, capture will be reset in IDLE
    end else begin
        display_timer <= display_timer + 1'b1;
    end
end
```

**What this does:**

- Display "ERR " (Error message).

- Count up to 2 seconds.

- When timer expires:
  - `state <= S_IDLE;` — Return to the same level.
  - `current_level` does NOT increment, so the player tries the same character again.

---

### **S_SHOW_DONE: Display "donE" (Game Finished)**

```verilog
S_SHOW_DONE: begin
    // Display "donE"
    disp_char3 <= 8'h44;  // 'd'
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
```

**What this does:**

- Display "donE" (game complete).

- Count up to 2 seconds.

- When timer expires:
  - `current_level <= 6'd0;` — **"Reset to level 0 for a new game."**
  - `state <= S_IDLE;` — Start over.

---

### **Tweaking Point #6: Change Result Display Time**

In `morse_game_top.v`, find:
```verilog
game_controller #(
    .NUM_LEVELS   (36),
    .DISPLAY_TICKS(200_000_000)  // 2 sec ← CHANGE THIS
) u_controller (
```

**Experiments:**
- Show results for 1 second:
  ```verilog
  .DISPLAY_TICKS(100_000_000)
  ```
  
- Show results for 5 seconds:
  ```verilog
  .DISPLAY_TICKS(500_000_000)
  ```

**Expected result:** "PASS", "ERR ", and "donE" messages display for longer or shorter times.

---

### **Tweaking Point #7: Change Game Difficulty**

In `game_controller.v`, modify the NUM_LEVELS parameter to have fewer levels:

Original:
```verilog
parameter NUM_LEVELS = 36  // A-Z + 0-9
```

Shorter game:
```verilog
parameter NUM_LEVELS = 10  // Only A-J (easier for beginners)
```

Then modify `morse_rom.v` to only include the first 10 characters, or it will attempt to display levels that don't exist.

---

# MODULE 7: seg7_driver.v
## The Display Driver — Multiplexed 7-Segment Display

### **What Does seg7_driver.v Do?**

A 7-segment display shows characters using 7 LED segments:
```
   AAA
  F   B
   GGG
  E   C
   DDD
```

The Basys 3 board has a **4-digit 7-segment display**. However, there are only 7 wires for the segments (not 28). So we use **multiplexing**: rapidly switch between digits so fast that our eyes see all 4 digits lit simultaneously.

seg7_driver does exactly this:
- Takes 4 ASCII characters as input
- Converts each to a 7-segment pattern (which LEDs to light)
- Multiplexes through all 4 digits at ~1 kHz refresh rate

---

### **Code Breakdown**

```verilog
module seg7_driver #(
    parameter REFRESH_TICKS = 100_000  // ~1 ms per digit at 100 MHz
)
```

**Parameter:**
- `REFRESH_TICKS = 100_000` — Show each digit for 100,000 ticks = 1 millisecond.
- With 4 digits × 1 ms = 4 ms per full refresh cycle.
- Refresh rate = 1000 ms / 4 ms ≈ 250 Hz (very fast, human eye sees it as solid).

---

### **Inputs/Outputs**

```verilog
(
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] char0,   // Rightmost digit
    input  wire [7:0] char1,
    input  wire [7:0] char2,
    input  wire [7:0] char3,   // Leftmost digit
    output reg  [6:0] seg,     // Segment cathodes (active low)
    output reg        dp,      // Decimal point (active low)
    output reg  [3:0] an       // Anode enables (active low)
);
```

**Key signals:**
- `char0–char3` — ASCII codes for 4 characters to display. Example: char0=0x41 for 'A'.
- `seg[6:0]` — Which of the 7 segments to light. Active LOW (0=on, 1=off).
- `an[3:0]` — Which digit to activate. Active LOW (0=on, 1=off).
  - an[0] activates digit 0 (rightmost)
  - an[1] activates digit 1
  - an[2] activates digit 2
  - an[3] activates digit 3 (leftmost)
- `dp` — Decimal point. Always off in this project.

---

### **Refresh Counter & Digit Selection**

```verilog
always @(posedge clk) begin
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
```

**What this does:**

- Count from 0 to REFRESH_TICKS-1 (100,000 counts = 1 millisecond).
- When the counter reaches max, reset it and increment `digit_sel`.
- `digit_sel` cycles: 0 → 1 → 2 → 3 → 0 → 1 → ...
- So every 1 ms, we switch to the next digit.

---

### **Multiplexer: Select Current Character**

```verilog
always @(*) begin
    case (digit_sel)
        2'd0: current_char = char0;
        2'd1: current_char = char1;
        2'd2: current_char = char2;
        2'd3: current_char = char3;
        default: current_char = 8'h20; // space
    endcase
end
```

**What this does:**

Based on `digit_sel`, pick which of the 4 characters to display right now.
- If digit_sel=0, display char0 (rightmost digit).
- If digit_sel=1, display char1, etc.

---

### **ASCII to 7-Segment Decoder**

```verilog
always @(*) begin
    case (current_char)
        // ──── Digits 0–9 ────
        8'h30: seg_pattern = 7'b1111110; // 0
        8'h31: seg_pattern = 7'b0110000; // 1
        8'h32: seg_pattern = 7'b1101101; // 2
        // ... more entries ...

        // ──── Letters ────
        8'h41: seg_pattern = 7'b1110111; // A
        8'h42: seg_pattern = 7'b0011111; // b
        // ... more entries ...

        // ──── Special ────
        8'h20: seg_pattern = 7'b0000000; // Space (blank)
        default: seg_pattern = 7'b0000000; // Blank for unknown
    endcase
end
```

**What this does:**

This is a **lookup table** converting ASCII codes to 7-segment patterns.

Example: 'A' = 0x41
```
seg_pattern = 7'b1110111
            = {A, B, C, D, E, F, G}
            = {1, 1, 1, 0, 1, 1, 1}
```

Which segments light up:
```
   AAA   (A=1, light up)
  F   B  (F=1, B=1, light up)
   GGG   (G=1, light up)
  E   C  (E=1, C=1, light up)
   ---   (D=0, don't light)
```

This draws the letter 'A' on the 7-segment display.

**Note:** These patterns are **active HIGH** internally (1 = segment on). The output will be inverted to active LOW.

---

### **Register Outputs (Active LOW)**

```verilog
always @(posedge clk) begin
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
            2'd0: an <= 4'b1110;  // Enable digit 0 (an[0]=0)
            2'd1: an <= 4'b1101;  // Enable digit 1 (an[1]=0)
            2'd2: an <= 4'b1011;  // Enable digit 2 (an[2]=0)
            2'd3: an <= 4'b0111;  // Enable digit 3 (an[3]=0)
            default: an <= 4'b1111;
        endcase
    end
end
```

**What this does:**

- `seg <= ~seg_pattern;` — **"Invert the 7-segment pattern."**
  - Internal pattern is active HIGH (1=on).
  - Hardware is active LOW (0=on).
  - So we invert: `~7'b1110111` = `7'b0001000`.

- **Enable one digit at a time:**
  - When digit_sel=0, set an=4'b1110 (an[0]=0, others=1).
  - This activates digit 0's common anode.
  - The inverted segment pattern is applied to all digits, but only digit 0's anode is pulled LOW, so only digit 0 lights up.

---

### **How Multiplexing Works (Timeline)**

```
TIME    digit_sel  current_char  seg_pattern    seg (inverted)  an       RESULT
─────────────────────────────────────────────────────────────────────────────────
0 ms        0       char0='A'     0b1110111      0b0001000      0b1110   Digit 0 shows 'A'
           (1ms)

1 ms        1       char1='B'     0b0011111      0b1100000      0b1101   Digit 1 shows 'B'
           (1ms)

2 ms        2       char2='C'     0b1001110      0b0110001      0b1011   Digit 2 shows 'C'
           (1ms)

3 ms        3       char3='D'     0b0111101      0b1000010      0b0111   Digit 3 shows 'D'
           (1ms)

4 ms        0       char0='A'     0b1110111      0b0001000      0b1110   Digit 0 shows 'A' (repeat)
           (1ms)

...
```

Refresh rate = 4 cycles × 1 ms = 4 ms per frame = 250 Hz.

Human eye sees all 4 digits lit simultaneously. The 7-segment display appears to show "DABC" (reading right to left: char0-char1-char2-char3).

---

### **Tweaking Point #8: Change Display Refresh Rate**

In `morse_game_top.v`, find:
```verilog
seg7_driver #(
    .REFRESH_TICKS(100_000)  // ~1 ms per digit ← CHANGE THIS
) u_display (
```

**Experiments:**
- Make display **flicker** (slower refresh):
  ```verilog
  .REFRESH_TICKS(500_000)  // 5 ms per digit (noticeable flicker)
  ```
  
- Make display **smoother** (faster refresh):
  ```verilog
  .REFRESH_TICKS(50_000)   // 0.5 ms per digit (very smooth)
  ```

**Expected result:** Display either flickers noticeably or appears extra smooth.

---

# MODULE 8: morse_game_top.v
## The Glue — Connecting Everything Together

### **What Does morse_game_top.v Do?**

This is the **top-level module**. It's like the main wiring diagram of the FPGA. It:
1. Instantiates all 7 sub-modules.
2. Connects their inputs and outputs together.
3. Defines all timing parameters.
4. Handles debug LEDs.

---

### **Code Breakdown**

```verilog
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
```

**External pins:**
- `clk` — 100 MHz oscillator from the board.
- `btnC` — Center button for morse input.
- `btnU` — Up button for reset.
- `sw[0]` — Mode switch. 0=Encoding, 1=Decoding.
- `sw[1]` — Hint switch. 1=Enable LED playback.
- `seg[6:0]` — 7-segment cathode pins (to light up segments).
- `an[3:0]` — 7-segment anode pins (to select which digit).
- `led[15:0]` — 16 debug LEDs.

---

### **Internal Wires**

```verilog
// Debounced buttons
wire btn_morse_db;
wire btn_reset_db;

// Press classifier outputs
wire symbol_valid;
wire symbol_bit;
wire invalid_pulse;

// ... (many more internal signals) ...
```

These wires connect the modules to each other. For example:
- `btn_morse_db` comes out of debounce and goes into press_classifier.
- `symbol_valid` comes out of press_classifier and goes into morse_capture.

---

### **Module Instantiations**

#### **Debounce for Morse Button**

```verilog
debounce #(
    .DEBOUNCE_TICKS(1_000_000)  // 10 ms
) u_debounce_morse (
    .clk    (clk),
    .rst    (btn_reset_db),
    .btn_in (btnC),
    .btn_out(btn_morse_db)
);
```

**What this does:**
- Takes the raw `btnC` input (noisy).
- Outputs `btn_morse_db` (clean).
- Uses 10 ms debounce.

Note: `rst` is fed from `btn_reset_db`, creating a dependency. But debounce of the reset button also uses the reset button... how does this work?

---

#### **Debounce for Reset Button**

```verilog
debounce #(
    .DEBOUNCE_TICKS(1_000_000)
) u_debounce_reset (
    .clk    (clk),
    .rst    (1'b0),           // No reset for the reset debouncer!
    .btn_in (btnU),
    .btn_out(btn_reset_db)
);
```

**Interesting Design Note:**
- The reset debouncer has `rst = 1'b0` (always not reset).
- Why? Because we need `btn_reset_db` to reset everything else, including itself!
- If the reset debouncer was reset by `btn_reset_db`, it would cause a circular dependency.

---

#### **Press Classifier**

```verilog
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
```

**Signal flow:**
- Input: `btn_morse_db` (clean button from debounce)
- Output: `symbol_valid` (pulse), `symbol_bit` (0=dot, 1=dash), `invalid_pulse`

---

#### **Morse Capture**

```verilog
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
```

**Key line:**
```verilog
wire capture_reset_combined;
assign capture_reset_combined = btn_reset_db | capture_rst;
```

- The capture module is reset by EITHER button reset OR game controller's capture reset.
- This allows the game to reset the capture mid-game (e.g., after an error).

---

#### **Morse ROM**

```verilog
morse_rom u_rom (
    .addr      (rom_addr),
    .pattern   (rom_pattern),
    .length    (rom_length),
    .ascii_char(rom_ascii)
);
```

**No parameters** — ROM is fixed.
- `rom_addr` — Input from game_controller (which level to look up).
- Outputs: `rom_pattern`, `rom_length`, `rom_ascii`.

---

#### **Morse Player**

```verilog
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
```

**Signal flow:**
- game_controller sets `player_start` to trigger playback.
- morse_player reads `pattern` and `length` from the ROM (connected in parallel).
- morse_player outputs `led_out` (to control the LED) and pulses `player_done` when finished.

---

#### **Game Controller**

```verilog
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
```

**This is the heart of the system.** game_controller:
- Receives captured input from morse_capture.
- Looks up the ROM entry using rom_addr.
- Compares the input with the ROM.
- Controls morse_player for hints.
- Outputs display characters.

---

#### **7-Segment Display Driver**

```verilog
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
```

**Takes the 4 display characters from game_controller and drives the 7-segment display.**

---

### **Debug LED Assignments**

```verilog
assign led[0]     = btn_morse_db;           // Button state
assign led[1]     = led_sym_valid_latch;    // Symbol detected
assign led[2]     = led_sym_bit_latch;      // Dot (0) or Dash (1)
assign led[3]     = led_input_done_latch;   // Input sequence complete
assign led[4]     = led_input_invalid_latch;// Invalid press
assign led[5]     = sw[0];                  // Mode switch
assign led[6]     = sw[1];                  // Hint switch
assign led[7]     = player_led;             // Morse player LED output
assign led[11:8]  = current_level[3:0];     // Current level (lower 4 bits)
assign led[12:15] = fsm_state;              // FSM state
```

**What each LED indicates:**
- `led[0]` — Button is pressed (visual feedback).
- `led[1]` — A valid symbol was detected (latched).
- `led[2]` — Last symbol was a dash (1) or dot (0).
- `led[3]` — Input sequence completed (2-second timeout).
- `led[4]` — Invalid press detected.
- `led[5]` — Mode switch state (0=Encoding, 1=Decoding).
- `led[6]` — Hint switch state.
- `led[7]` — Morse player is outputting (for testing the blink pattern).
- `led[11:8]` — Current level (0–15 shown on LEDs, though max level is 35).
- `led[12:15]` — Current FSM state (0–7, shown on LEDs).

These LEDs are **for debugging and learning.** They show what's happening inside the FPGA in real-time.

---

### **Summary: Complete Data Flow**

```
USER PRESSES BUTTON
       ↓
[debounce] (removes electrical noise, 10 ms filter)
       ↓
btn_morse_db (clean button signal)
       ↓
[press_classifier] (measures duration)
       ↓
symbol_valid, symbol_bit (0=dot, 1=dash)
or
invalid_pulse (bad press)
       ↓
[morse_capture] (accumulates dots/dashes)
       ↓
captured_pattern, captured_length (e.g., 6'b000001, length=2 for 'A')
or
input_done (2-second timeout → input complete)
or
input_invalid (overflow or invalid press)
       ↓
[game_controller] (game logic)
├─ Looks up ROM entry
├─ Compares user input with ROM
├─ Manages game state (IDLE, PLAYBACK, WAIT_INPUT, EVALUATE, etc.)
└─ Outputs display characters
       ↓
[seg7_driver] (displays "L01", "PASS", "ERR ", etc.)
       ↓
PLAYER SEES RESULT ON 4-DIGIT 7-SEGMENT DISPLAY
```

---

---

# TWEAKING GUIDE
## Where You Can Change Code to See Results

### **Summary of All Tweaking Points**

| # | What | File | Parameter | Original | Faster | Slower/Longer |
|---|------|------|-----------|----------|--------|-----------------|
| 1 | Debounce time | morse_game_top.v | DEBOUNCE_TICKS | 1_000_000 | 500_000 | 2_000_000 |
| 2 | Dot/Dash timing | morse_game_top.v | DOT_MIN, DOT_MAX, DASH_MIN, DASH_MAX | 20M-80M / 80M-150M | Halve | Double |
| 3 | Input timeout | morse_game_top.v | IDLE_TIMEOUT | 200_000_000 | 100_000_000 | 400_000_000 |
| 4 | Game difficulty | morse_rom.v | Entry order | A-Z, 0-9 | Reorder | (Hard first) |
| 5 | Playback speed | morse_game_top.v | PLAY_*_TICKS | 30M/90M/30M | Halve | Double |
| 6 | Result display time | morse_game_top.v | DISPLAY_TICKS | 200_000_000 | 100_000_000 | 500_000_000 |
| 7 | Game length | game_controller.v | NUM_LEVELS | 36 | 10 | 52 |
| 8 | Display refresh | morse_game_top.v | REFRESH_TICKS | 100_000 | 50_000 | 500_000 |

---

### **Hands-On Experiment 1: Speed Up the Game**

Make everything 2x faster for a challenging game:

**In morse_game_top.v:**

```verilog
// Debounce: 5 ms instead of 10 ms
debounce #(
    .DEBOUNCE_TICKS(500_000)  // WAS: 1_000_000
) u_debounce_morse (

// Dot/Dash timing: half the original
press_classifier #(
    .DOT_MIN (10_000_000),      // WAS: 20_000_000
    .DOT_MAX (40_000_000),      // WAS: 80_000_000
    .DASH_MIN(40_000_000),      // WAS: 80_000_000
    .DASH_MAX(75_000_000)       // WAS: 150_000_000
) u_classifier (

// Input timeout: 1 second instead of 2
morse_capture #(
    .IDLE_TIMEOUT(100_000_000) // WAS: 200_000_000
) u_capture (

// Playback: 2x faster
morse_player #(
    .PLAY_DOT_TICKS (15_000_000), // WAS: 30_000_000
    .PLAY_DASH_TICKS(45_000_000), // WAS: 90_000_000
    .PLAY_GAP_TICKS (15_000_000)  // WAS: 30_000_000
) u_player (

// Results display: 1 second instead of 2
game_controller #(
    .NUM_LEVELS   (36),
    .DISPLAY_TICKS(100_000_000) // WAS: 200_000_000
) u_controller (
```

**Result:** Everything happens twice as fast. For advanced players!

---

### **Hands-On Experiment 2: Make the Game Educational**

Show only 10 levels (A–J) and increase all timers for learning:

**In morse_game_top.v:**

```verilog
// Longer debounce for old people or kids with shaky hands
debounce #(
    .DEBOUNCE_TICKS(2_000_000)  // WAS: 1_000_000 (20 ms)
) u_debounce_morse (

// More lenient dot/dash windows
press_classifier #(
    .DOT_MIN (15_000_000),      // WAS: 20_000_000 (150 ms)
    .DOT_MAX (120_000_000),     // WAS: 80_000_000 (1200 ms)
    .DASH_MIN(120_000_000),     // WAS: 80_000_000 (1200 ms)
    .DASH_MAX(250_000_000)      // WAS: 150_000_000 (2500 ms)
) u_classifier (

// Longer input timeout: 4 seconds to think
morse_capture #(
    .IDLE_TIMEOUT(400_000_000) // WAS: 200_000_000
) u_capture (

// Longer result display: 5 seconds to celebrate/learn from error
game_controller #(
    .NUM_LEVELS   (10),          // WAS: 36 (only A-J for beginners)
    .DISPLAY_TICKS(500_000_000) // WAS: 200_000_000 (5 seconds)
) u_controller (
```

**Result:** Beginner-friendly game perfect for teaching morse code.

---

### **Hands-On Experiment 3: Change Game Difficulty Order**

Reorder the ROM so the easiest morse codes come first:

**In morse_rom.v, rearrange the entries:**

Original (starts with A=.-):
```verilog
6'd0:  begin pattern = 6'b000001; length = 3'd2; ascii_char = 8'h41; end // A .-
6'd1:  begin pattern = 6'b001000; length = 3'd4; ascii_char = 8'h42; end // B -...
```

Modified (start with E and T, the easiest):
```verilog
6'd0:  begin pattern = 6'b000000; length = 3'd1; ascii_char = 8'h45; end // E . (one dot!)
6'd1:  begin pattern = 6'b000001; length = 3'd1; ascii_char = 8'h54; end // T - (one dash!)
6'd2:  begin pattern = 6'b000001; length = 3'd2; ascii_char = 8'h41; end // A .- (two symbols)
6'd3:  begin pattern = 6'b000010; length = 3'd2; ascii_char = 8'h4E; end // N -. (two symbols)
// ... then harder ones
```

**Result:** Players start with the simplest morse codes (single dot, single dash) and gradually progress to more complex patterns.

---

### **Hands-On Experiment 4: Display Blinking Effect**

Slow down the 7-segment multiplexing to see the blinking:

**In morse_game_top.v:**

```verilog
seg7_driver #(
    .REFRESH_TICKS(2_000_000)  // WAS: 100_000 (20x slower!)
) u_display (
```

**Result:** The 4-digit display noticeably flickers as each digit activates one at a time. This demonstrates **how the multiplexing works**. Your girlfriend will see "what's under the hood" of the display!

---

---

## **CONCLUSION**

Every module has a clear purpose and adjustable parameters:

1. **debounce.v** — Noise filter. Tweak: debounce time.
2. **press_classifier.v** — Dot/dash detector. Tweak: duration thresholds.
3. **morse_capture.v** — Pattern accumulator. Tweak: input timeout, max symbols.
4. **morse_rom.v** — Morse dictionary. Tweak: entry order for difficulty.
5. **morse_player.v** — LED hint system. Tweak: playback timing.
6. **game_controller.v** — Game logic FSM. Tweak: display time, number of levels.
7. **seg7_driver.v** — Display driver. Tweak: refresh rate.
8. **morse_game_top.v** — Top-level glue. All parameters appear here.

Now your girlfriend and teacher can understand not just what the code does, but **why it does it** and **how to modify it** to change the game's behavior!

