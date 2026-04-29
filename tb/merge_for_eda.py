import os

rtl_dir = 'd:/Projects/cpp_projects/morse_game_verilog/rtl'
tb_dir = 'd:/Projects/cpp_projects/morse_game_verilog/tb'

files_to_concat = [
    'debounce.v',
    'game_controller.v',
    'morse_capture.v',
    'morse_player.v',
    'morse_rom.v',
    'press_classifier.v',
    'seg7_driver.v',
    'morse_game_top.v'
]

combined_code = ''
for f in files_to_concat:
    with open(os.path.join(rtl_dir, f), 'r', encoding='utf-8') as file:
        content = file.read()
        
        # Scale down parameters in morse_game_top.v for simulation
        if f == 'morse_game_top.v':
            content = content.replace('.DEBOUNCE_TICKS(1_000_000)', '.DEBOUNCE_TICKS(10)')
            content = content.replace('.DOT_MIN (20_000_000)', '.DOT_MIN(200)')
            content = content.replace('.DOT_MAX (80_000_000)', '.DOT_MAX(800)')
            content = content.replace('.DASH_MIN(80_000_000)', '.DASH_MIN(800)')
            content = content.replace('.DASH_MAX(150_000_000)', '.DASH_MAX(1500)')
            content = content.replace('.IDLE_TIMEOUT(200_000_000)', '.IDLE_TIMEOUT(2000)')
            content = content.replace('.PLAY_DOT_TICKS (30_000_000)', '.PLAY_DOT_TICKS(300)')
            content = content.replace('.PLAY_DASH_TICKS(90_000_000)', '.PLAY_DASH_TICKS(900)')
            content = content.replace('.PLAY_GAP_TICKS (30_000_000)', '.PLAY_GAP_TICKS(300)')
            content = content.replace('.DISPLAY_TICKS(200_000_000)', '.DISPLAY_TICKS(2000)')
            content = content.replace('.REFRESH_TICKS(100_000)', '.REFRESH_TICKS(10)')
            
        combined_code += f'// --- BEGIN {f} ---\n'
        combined_code += content + '\n'
        combined_code += f'// --- END {f} ---\n\n'

testbench_code = """
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
"""

combined_code += testbench_code

output_path = os.path.join(tb_dir, 'eda_playground_all_in_one.sv')
with open(output_path, 'w', encoding='utf-8') as out_file:
    out_file.write(combined_code)

print(f'Successfully wrote all-in-one testing file to {output_path}')
