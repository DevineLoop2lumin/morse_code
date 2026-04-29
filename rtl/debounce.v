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
    always @(posedge clk) begin
        if (rst) begin
            btn_sync_0 <= 1'b0;
            btn_sync_1 <= 1'b0;
        end else begin
            btn_sync_0 <= btn_in;
            btn_sync_1 <= btn_sync_0;
        end
    end

    // ── Debounce counter logic ──
    always @(posedge clk) begin
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
