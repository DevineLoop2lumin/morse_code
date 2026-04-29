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
                2'd0: an <= 4'b1110;
                2'd1: an <= 4'b1101;
                2'd2: an <= 4'b1011;
                2'd3: an <= 4'b0111;
                default: an <= 4'b1111;
            endcase
        end
    end

endmodule
