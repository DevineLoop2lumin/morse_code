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
