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
        // Initialize Inputs
        btnC = 0;
        btnU = 0;
        sw = 0;

        // Open wave dump for EDA playground
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_morse_game_top);

        // Reset the system
        #100;
        btnU = 1;
        #100;
        btnU = 0;
        #100;

        // NOTE: Full simulation of morse_game_top will take a VERY long time 
        // because the timers in your code are set for a 100MHz clock 
        // (e.g. 1 second = 100,000,000 cycles). 
        // To see things happen quickly in simulation, you need to either 
        // 1. Change the parameters in morse_game_top.v to much smaller values.
        // 2. Just simulate specific submodules like `press_classifier` directly.

        // Example: simulate a button press (this won't trigger the real logic
        // unless you reduce DEBOUNCE_TICKS and DOT_MIN in morse_game_top.v)
        btnC = 1;
        #50000; // Hold for some time
        btnC = 0;
        
        #100000;
        $finish;
    end
      
endmodule
