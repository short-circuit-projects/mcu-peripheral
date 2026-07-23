// tb_baud_gen.v
// Self-checking testbench for baud_gen.v (Module 1, Task 1).
//
// Checks the three simulation-based done conditions from Tasks-1:
//   1. Every pulse on Txclk_en/Rxclk_en is exactly one clock cycle wide.
//   2. Spacing between consecutive pulses is constant and equals the
//      correct Cmax+1 for this assignment's fixed 50 MHz / 115,200 baud /
//      16x oversampling parameters.
//   3. Pulse count over a 1 ms window matches the correct effective rate
//      to within +/-1 pulse.
//
// Run with a timing-capable simulation flow, e.g. Verilator:
//   $ verilator --binary --timing -Wno-fatal tb_baud_gen.v baud_gen.v
//   $ ./obj_dir/Vtb_baud_gen
// Exits with status 0 on pass, 1 on any failure.

`timescale 1ns/1ps

module tb_baud_gen;

    // Correct answers for this assignment's fixed parameters (50 MHz clock,
    // 115,200 baud, 16x oversampling) — not a hint to students, this is the
    // grading oracle.
    localparam integer TX_PERIOD     = 434;  // Cmax_tx + 1 = 433 + 1
    localparam integer RX_PERIOD     = 27;   // Cmax_rx + 1 = 26  + 1
    localparam integer WINDOW_CYCLES = 50_000; // 1 ms @ 50 MHz
    // expected_pulses = window_cycles / period; allow +/-1 pulse per Tasks-1.
    localparam integer TX_EXPECTED   = WINDOW_CYCLES / TX_PERIOD; // 115
    localparam integer RX_EXPECTED   = WINDOW_CYCLES / RX_PERIOD; // 1851

    // Cap how many of each failure type get printed, so a systematic bug
    // (wrong on every single period) doesn't bury the report in repeats.
    localparam integer MAX_PRINTS = 3;

    reg clk_50m = 1'b0;
    wire Txclk_en, Rxclk_en;

    integer errors;
    integer cycle;

    integer tx_last_edge, rx_last_edge;
    integer tx_high_run,  rx_high_run;
    integer tx_window_count, rx_window_count;
    reg     tx_seen_edge, rx_seen_edge;
    integer tx_width_fail_count, rx_width_fail_count;
    integer tx_spacing_fail_count, rx_spacing_fail_count;

    baud_gen dut (
        .clk_50m (clk_50m),
        .Txclk_en(Txclk_en),
        .Rxclk_en(Rxclk_en)
    );

    // 50 MHz clock: 20 ns period.
    always #10 clk_50m = ~clk_50m;

    initial begin
        errors                = 0;
        cycle                 = -1;
        tx_last_edge          = 0;
        rx_last_edge          = 0;
        tx_high_run           = 0;
        rx_high_run           = 0;
        tx_window_count       = 0;
        rx_window_count       = 0;
        tx_seen_edge          = 1'b0;
        rx_seen_edge          = 1'b0;
        tx_width_fail_count   = 0;
        rx_width_fail_count   = 0;
        tx_spacing_fail_count = 0;
        rx_spacing_fail_count = 0;
    end

    always @(posedge clk_50m) begin
        cycle = cycle + 1;

        // --- Txclk_en: width + spacing ---
        if (Txclk_en) begin
            tx_high_run = tx_high_run + 1;
            if (tx_high_run == 2) begin
                errors = errors + 1;
                tx_width_fail_count = tx_width_fail_count + 1;
                if (tx_width_fail_count <= MAX_PRINTS)
                    $display("[tb_baud_gen] FAIL: Txclk_en held high for more than one cycle at t=%0t (built a clock, not an enable)", $time);
            end
            if (tx_seen_edge && (cycle - tx_last_edge) !== TX_PERIOD) begin
                errors = errors + 1;
                tx_spacing_fail_count = tx_spacing_fail_count + 1;
                if (tx_spacing_fail_count <= MAX_PRINTS)
                    $display("[tb_baud_gen] FAIL: Txclk_en spacing=%0d cycles at t=%0t, expected %0d", cycle - tx_last_edge, $time, TX_PERIOD);
            end
            tx_last_edge = cycle;
            tx_seen_edge = 1'b1;
            if (cycle < WINDOW_CYCLES) tx_window_count = tx_window_count + 1;
        end else begin
            tx_high_run = 0;
        end

        // --- Rxclk_en: width + spacing ---
        if (Rxclk_en) begin
            rx_high_run = rx_high_run + 1;
            if (rx_high_run == 2) begin
                errors = errors + 1;
                rx_width_fail_count = rx_width_fail_count + 1;
                if (rx_width_fail_count <= MAX_PRINTS)
                    $display("[tb_baud_gen] FAIL: Rxclk_en held high for more than one cycle at t=%0t (built a clock, not an enable)", $time);
            end
            if (rx_seen_edge && (cycle - rx_last_edge) !== RX_PERIOD) begin
                errors = errors + 1;
                rx_spacing_fail_count = rx_spacing_fail_count + 1;
                if (rx_spacing_fail_count <= MAX_PRINTS)
                    $display("[tb_baud_gen] FAIL: Rxclk_en spacing=%0d cycles at t=%0t, expected %0d", cycle - rx_last_edge, $time, RX_PERIOD);
            end
            rx_last_edge = cycle;
            rx_seen_edge = 1'b1;
            if (cycle < WINDOW_CYCLES) rx_window_count = rx_window_count + 1;
        end else begin
            rx_high_run = 0;
        end
    end

    initial begin
        // Run just past the 1 ms window (50,000 cycles @ 50 MHz = 1,000,000 ns),
        // plus margin so the last in-window pulse's spacing still gets checked.
        #(20 * (WINDOW_CYCLES + TX_PERIOD));

        if (tx_width_fail_count > MAX_PRINTS)
            $display("[tb_baud_gen] ... Txclk_en width failure repeated %0d times total", tx_width_fail_count);
        if (tx_spacing_fail_count > MAX_PRINTS)
            $display("[tb_baud_gen] ... Txclk_en spacing failure repeated %0d times total", tx_spacing_fail_count);
        if (rx_width_fail_count > MAX_PRINTS)
            $display("[tb_baud_gen] ... Rxclk_en width failure repeated %0d times total", rx_width_fail_count);
        if (rx_spacing_fail_count > MAX_PRINTS)
            $display("[tb_baud_gen] ... Rxclk_en spacing failure repeated %0d times total", rx_spacing_fail_count);

        if ((tx_window_count < TX_EXPECTED - 1) || (tx_window_count > TX_EXPECTED + 1)) begin
            errors = errors + 1;
            $display("[tb_baud_gen] FAIL: Txclk_en pulse count over 1 ms = %0d, expected %0d +/-1", tx_window_count, TX_EXPECTED);
        end else begin
            $display("[tb_baud_gen] PASS: Txclk_en pulse count over 1 ms = %0d (expected %0d +/-1)", tx_window_count, TX_EXPECTED);
        end

        if ((rx_window_count < RX_EXPECTED - 1) || (rx_window_count > RX_EXPECTED + 1)) begin
            errors = errors + 1;
            $display("[tb_baud_gen] FAIL: Rxclk_en pulse count over 1 ms = %0d, expected %0d +/-1", rx_window_count, RX_EXPECTED);
        end else begin
            $display("[tb_baud_gen] PASS: Rxclk_en pulse count over 1 ms = %0d (expected %0d +/-1)", rx_window_count, RX_EXPECTED);
        end

        if (!tx_seen_edge) begin
            errors = errors + 1;
            $display("[tb_baud_gen] FAIL: Txclk_en never pulsed");
        end
        if (!rx_seen_edge) begin
            errors = errors + 1;
            $display("[tb_baud_gen] FAIL: Rxclk_en never pulsed");
        end

        if (errors == 0) begin
            $display("[tb_baud_gen] ALL CHECKS PASSED");
            $finish;
        end else begin
            $display("[tb_baud_gen] %0d CHECK(S) FAILED", errors);
            $fatal(1);
        end
    end

endmodule
