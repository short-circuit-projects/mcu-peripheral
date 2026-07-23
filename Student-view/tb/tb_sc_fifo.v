// tb_sc_fifo.v
// Self-checking testbench for sc_fifo.v (Module 1, Task 2).
//
// Runs the ten scenarios in Tasks-1's "Done conditions — test matrix"
// against a DATA_WIDTH=8, DEPTH=4 instance (the graded configuration),
// plus a lighter wraparound check at DEPTH=6 to confirm the module is
// genuinely parameterized (Tasks-1's "8/4, but DEPTH=6 must still work"
// requirement).
//
// Run with a timing-capable simulation flow, e.g. Verilator:
//   $ verilator --binary --timing -Wno-fatal tb_sc_fifo.v sc_fifo.v
//   $ ./obj_dir/Vtb_sc_fifo
// Exits with status 0 on pass, 1 on any failure.

`timescale 1ns/1ps

module tb_sc_fifo;

    // The check_* tasks below take 32-bit integer args; passing this DUT's
    // narrower count/count6 signals into them is a deliberate, harmless
    // zero-extension, not a real width bug — this suppresses the resulting
    // lint noise for exactly that pattern within this testbench file.
    /* verilator lint_off WIDTHEXPAND */

    integer errors = 0;

    // ---------------------------------------------------------------
    // DUT #1: DATA_WIDTH=8, DEPTH=4 — the graded configuration.
    // ---------------------------------------------------------------
    reg        clk = 1'b0;
    reg        rst_n;
    reg        wr_en, rd_en;
    reg  [7:0] din;
    wire [7:0] dout;
    wire       full, empty, overflow, underflow;
    wire [2:0] count;

    sc_fifo #(.DATA_WIDTH(8), .DEPTH(4)) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .wr_en    (wr_en),
        .rd_en    (rd_en),
        .din      (din),
        .dout     (dout),
        .full     (full),
        .empty    (empty),
        .overflow (overflow),
        .underflow(underflow),
        .count    (count)
    );

    always #10 clk = ~clk;

    // One clock's worth of stimulus: set inputs away from the edge, let the
    // edge happen, then settle so non-blocking updates are visible to the
    // checks that run right after this task returns.
    task do_cycle(input wr, input rd, input [7:0] data);
    begin
        @(negedge clk);
        wr_en = wr;
        rd_en = rd;
        din   = data;
        @(posedge clk);
        #1;
    end
    endtask

    task idle_cycle;
    begin
        do_cycle(1'b0, 1'b0, 8'h00);
    end
    endtask

    task apply_reset;
    begin
        @(negedge clk);
        rst_n = 1'b0;
        wr_en = 1'b0;
        rd_en = 1'b0;
        din   = 8'h00;
        @(negedge clk); // hold reset across a full cycle
        rst_n = 1'b1;
        #1;
    end
    endtask

    task check_bit(input [8*48-1:0] name, input got, input exp);
    begin
        if (got !== exp) begin
            errors = errors + 1;
            $display("[tb_sc_fifo] FAIL: %0s = %0d, expected %0d at t=%0t", name, got, exp, $time);
        end
    end
    endtask

    task check_byte(input [8*48-1:0] name, input [7:0] got, input [7:0] exp);
    begin
        if (got !== exp) begin
            errors = errors + 1;
            $display("[tb_sc_fifo] FAIL: %0s = 0x%0h, expected 0x%0h at t=%0t", name, got, exp, $time);
        end
    end
    endtask

    task check_int(input [8*48-1:0] name, input integer got, input integer exp);
    begin
        if (got !== exp) begin
            errors = errors + 1;
            $display("[tb_sc_fifo] FAIL: %0s = %0d, expected %0d at t=%0t", name, got, exp, $time);
        end
    end
    endtask

    integer scenario_errors_before;
    task begin_scenario(input [8*64-1:0] label);
    begin
        scenario_errors_before = errors;
        $display("[tb_sc_fifo] --- %0s ---", label);
    end
    endtask
    task end_scenario;
    begin
        if (errors == scenario_errors_before)
            $display("[tb_sc_fifo] PASS");
    end
    endtask

    initial begin
        wr_en = 1'b0;
        rd_en = 1'b0;
        din   = 8'h00;
        rst_n = 1'b1;

        // ---- Scenario 1: assert and release reset ----
        begin_scenario("Scenario 1: reset");
        apply_reset;
        check_bit("empty",     empty,     1'b1);
        check_bit("full",      full,      1'b0);
        check_int("count",     count,     0);
        check_byte("dout",     dout,      8'h00);
        check_bit("overflow",  overflow,  1'b0);
        check_bit("underflow", underflow, 1'b0);
        end_scenario;

        // ---- Scenario 2: single write to empty FIFO ----
        begin_scenario("Scenario 2: single write to empty FIFO");
        do_cycle(1'b1, 1'b0, 8'hA1);
        check_int("count", count, 1);
        check_bit("empty", empty, 1'b0);
        check_bit("full",  full,  1'b0);
        check_bit("overflow", overflow, 1'b0);
        idle_cycle;
        end_scenario;

        // ---- Scenario 3: single read of that entry ----
        begin_scenario("Scenario 3: single read of that entry");
        do_cycle(1'b0, 1'b1, 8'h00);
        check_byte("dout", dout, 8'hA1);
        check_int("count", count, 0);
        check_bit("empty", empty, 1'b1);
        check_bit("underflow", underflow, 1'b0);
        idle_cycle;
        end_scenario;

        // ---- Scenario 4: four writes, then four reads ----
        begin_scenario("Scenario 4: four writes, then four reads");
        do_cycle(1'b1, 1'b0, 8'h11);
        do_cycle(1'b1, 1'b0, 8'h22);
        do_cycle(1'b1, 1'b0, 8'h33);
        do_cycle(1'b1, 1'b0, 8'h44);
        check_bit("full after 4th write", full, 1'b1);
        check_int("count after 4th write", count, 4);
        do_cycle(1'b0, 1'b1, 8'h00);
        check_byte("dout (1st read)", dout, 8'h11);
        do_cycle(1'b0, 1'b1, 8'h00);
        check_byte("dout (2nd read)", dout, 8'h22);
        do_cycle(1'b0, 1'b1, 8'h00);
        check_byte("dout (3rd read)", dout, 8'h33);
        do_cycle(1'b0, 1'b1, 8'h00);
        check_byte("dout (4th read)", dout, 8'h44);
        check_bit("empty after 4th read", empty, 1'b1);
        idle_cycle;
        end_scenario;

        // ---- Extra: reset after real activity (not one of Tasks-1's ten,
        // but power-up reset alone can't tell a correct reset branch from one
        // that forgets dout/overflow/underflow, since both start at 0 anyway.
        // dout is a real non-zero value here (0x44 from scenario 4), so this
        // actually exercises the reset branch instead of restating a value
        // it already happened to hold. ----
        begin_scenario("Extra: reset after prior activity clears dout/flags too");
        apply_reset;
        check_bit("empty",     empty,     1'b1);
        check_bit("full",      full,      1'b0);
        check_int("count",     count,     0);
        check_byte("dout",     dout,      8'h00);
        check_bit("overflow",  overflow,  1'b0);
        check_bit("underflow", underflow, 1'b0);
        end_scenario;

        // ---- Scenario 5: more than DEPTH writes with interleaved reads ----
        // Forces wr_ptr and rd_ptr each around the wrap point at least once.
        begin_scenario("Scenario 5: wraparound with interleaved reads");
        do_cycle(1'b1, 1'b0, 8'hA0); // write A, count 1
        do_cycle(1'b1, 1'b0, 8'hB0); // write B, count 2
        do_cycle(1'b0, 1'b1, 8'h00); // read -> A, count 1
        check_byte("wrap read 1", dout, 8'hA0);
        do_cycle(1'b1, 1'b0, 8'hC0); // write C, count 2
        do_cycle(1'b0, 1'b1, 8'h00); // read -> B, count 1
        check_byte("wrap read 2", dout, 8'hB0);
        do_cycle(1'b1, 1'b0, 8'hD0); // write D, count 2
        do_cycle(1'b1, 1'b0, 8'hE0); // write E, count 3
        do_cycle(1'b1, 1'b0, 8'hF0); // write F, count 4 (full) -- wr_ptr has wrapped by now
        check_bit("full during wraparound sequence", full, 1'b1);
        do_cycle(1'b0, 1'b1, 8'h00); // read -> C
        check_byte("wrap read 3", dout, 8'hC0);
        do_cycle(1'b0, 1'b1, 8'h00); // read -> D
        check_byte("wrap read 4", dout, 8'hD0);
        do_cycle(1'b0, 1'b1, 8'h00); // read -> E
        check_byte("wrap read 5", dout, 8'hE0);
        do_cycle(1'b0, 1'b1, 8'h00); // read -> F
        check_byte("wrap read 6", dout, 8'hF0);
        check_bit("empty after draining wraparound sequence", empty, 1'b1);
        idle_cycle;
        end_scenario;

        // ---- Scenario 6: write-only attempt while full ----
        begin_scenario("Scenario 6: write-only attempt while full");
        do_cycle(1'b1, 1'b0, 8'h01);
        do_cycle(1'b1, 1'b0, 8'h02);
        do_cycle(1'b1, 1'b0, 8'h03);
        do_cycle(1'b1, 1'b0, 8'h04);
        check_bit("full before overflow attempt", full, 1'b1);
        do_cycle(1'b1, 1'b0, 8'hFF); // rejected: FIFO already full
        check_bit("overflow pulses", overflow, 1'b1);
        check_int("count unchanged by rejected write", count, 4);
        idle_cycle;
        check_bit("overflow deasserts next cycle", overflow, 1'b0);
        // Drain and confirm the four original values survived untouched.
        do_cycle(1'b0, 1'b1, 8'h00); check_byte("post-overflow drain 1", dout, 8'h01);
        do_cycle(1'b0, 1'b1, 8'h00); check_byte("post-overflow drain 2", dout, 8'h02);
        do_cycle(1'b0, 1'b1, 8'h00); check_byte("post-overflow drain 3", dout, 8'h03);
        do_cycle(1'b0, 1'b1, 8'h00); check_byte("post-overflow drain 4", dout, 8'h04);
        check_bit("empty after drain", empty, 1'b1);
        idle_cycle;
        end_scenario;

        // ---- Scenario 7: read-only attempt while empty ----
        begin_scenario("Scenario 7: read-only attempt while empty");
        check_bit("empty before underflow attempt", empty, 1'b1);
        do_cycle(1'b0, 1'b1, 8'h00); // rejected: FIFO already empty
        check_bit("underflow pulses", underflow, 1'b1);
        check_int("count stays 0", count, 0);
        idle_cycle;
        check_bit("underflow deasserts next cycle", underflow, 1'b0);
        end_scenario;

        // ---- Scenario 8: simultaneous read+write while partially filled ----
        begin_scenario("Scenario 8: simultaneous read+write while partially filled");
        do_cycle(1'b1, 1'b0, 8'h51); // write, count 1
        do_cycle(1'b1, 1'b0, 8'h52); // write, count 2 (partially filled: not empty, not full)
        do_cycle(1'b1, 1'b1, 8'h53); // simultaneous: read oldest (0x51), write 0x53
        check_byte("dout shows oldest entry", dout, 8'h51);
        check_int("count unchanged by accepted simultaneous op", count, 2);
        check_bit("no overflow", overflow, 1'b0);
        check_bit("no underflow", underflow, 1'b0);
        // Drain to confirm both the surviving old entry and the new write landed.
        do_cycle(1'b0, 1'b1, 8'h00); check_byte("drain after simultaneous (old entry)", dout, 8'h52);
        do_cycle(1'b0, 1'b1, 8'h00); check_byte("drain after simultaneous (new entry)", dout, 8'h53);
        check_bit("empty after drain", empty, 1'b1);
        idle_cycle;
        end_scenario;

        // ---- Scenario 9: simultaneous read+write while full ----
        begin_scenario("Scenario 9: simultaneous read+write while full");
        do_cycle(1'b1, 1'b0, 8'h61);
        do_cycle(1'b1, 1'b0, 8'h62);
        do_cycle(1'b1, 1'b0, 8'h63);
        do_cycle(1'b1, 1'b0, 8'h64);
        check_bit("full before simultaneous-while-full", full, 1'b1);
        do_cycle(1'b1, 1'b1, 8'hFF); // rejected: whole op dropped, not just the write half
        check_int("count unchanged", count, 4);
        check_bit("no overflow", overflow, 1'b0);
        check_bit("no underflow", underflow, 1'b0);
        do_cycle(1'b0, 1'b1, 8'h00); check_byte("drain 1 unaffected", dout, 8'h61);
        do_cycle(1'b0, 1'b1, 8'h00); check_byte("drain 2 unaffected", dout, 8'h62);
        do_cycle(1'b0, 1'b1, 8'h00); check_byte("drain 3 unaffected", dout, 8'h63);
        do_cycle(1'b0, 1'b1, 8'h00); check_byte("drain 4 unaffected", dout, 8'h64);
        check_bit("empty after drain", empty, 1'b1);
        idle_cycle;
        end_scenario;

        // ---- Scenario 10: simultaneous read+write while empty ----
        begin_scenario("Scenario 10: simultaneous read+write while empty");
        check_bit("empty before simultaneous-while-empty", empty, 1'b1);
        do_cycle(1'b1, 1'b1, 8'h70); // rejected: whole op dropped
        check_int("count stays 0", count, 0);
        check_bit("no overflow", overflow, 1'b0);
        check_bit("no underflow", underflow, 1'b0);
        idle_cycle;
        // Confirm the rejected write never landed: FIFO should still be empty
        // and a fresh write should land in slot 0 with the value we choose now.
        do_cycle(1'b1, 1'b0, 8'h71);
        check_int("count after fresh write", count, 1);
        do_cycle(1'b0, 1'b1, 8'h00);
        check_byte("fresh write is the only surviving entry", dout, 8'h71);
        idle_cycle;
        end_scenario;

        if (errors == 0)
            $display("[tb_sc_fifo] DEPTH=4 scenarios: ALL CHECKS PASSED");
        else
            $display("[tb_sc_fifo] DEPTH=4 scenarios: %0d CHECK(S) FAILED", errors);

        run_depth6_check;

        if (errors == 0) begin
            $display("[tb_sc_fifo] ALL CHECKS PASSED");
            $finish;
        end else begin
            $display("[tb_sc_fifo] %0d CHECK(S) FAILED TOTAL", errors);
            $fatal(1);
        end
    end

    // ---------------------------------------------------------------
    // DUT #2: DATA_WIDTH=8, DEPTH=6 — parameterization sanity check.
    // Tasks-1 requires the module to still work correctly at DEPTH=6,
    // which is not a power of two, so natural pointer overflow (the
    // DEPTH=4 shortcut) would silently break here if a student relied
    // on it instead of explicit wraparound.
    // ---------------------------------------------------------------
    reg        rst_n6;
    reg        wr_en6, rd_en6;
    reg  [7:0] din6;
    wire [7:0] dout6;
    wire       full6, empty6, overflow6, underflow6;
    wire [3:0] count6;

    sc_fifo #(.DATA_WIDTH(8), .DEPTH(6)) dut6 (
        .clk      (clk),
        .rst_n    (rst_n6),
        .wr_en    (wr_en6),
        .rd_en    (rd_en6),
        .din      (din6),
        .dout     (dout6),
        .full     (full6),
        .empty    (empty6),
        .overflow (overflow6),
        .underflow(underflow6),
        .count    (count6)
    );

    task do_cycle6(input wr, input rd, input [7:0] data);
    begin
        @(negedge clk);
        wr_en6 = wr;
        rd_en6 = rd;
        din6   = data;
        @(posedge clk);
        #1;
    end
    endtask

    task run_depth6_check;
        integer i;
        reg [7:0] expected_val;
    begin
        begin_scenario("DEPTH=6 parameterization check (wraparound past slot 5)");
        rst_n6 = 1'b1;
        wr_en6 = 1'b0;
        rd_en6 = 1'b0;
        din6   = 8'h00;
        @(negedge clk);
        rst_n6 = 1'b0;
        @(negedge clk);
        rst_n6 = 1'b1;
        #1;
        check_bit("dut6 empty after reset", empty6, 1'b1);

        // Fill all 6 slots (0..5), forcing wr_ptr to reach DEPTH-1=5.
        for (i = 0; i < 6; i = i + 1)
            do_cycle6(1'b1, 1'b0, i[7:0]);
        check_bit("dut6 full at 6 entries", full6, 1'b1);
        check_int("dut6 count == 6", count6, 6);

        // Drain 2 (wr_ptr will need to wrap to 0 on the next writes).
        do_cycle6(1'b0, 1'b1, 8'h00);
        check_byte("dut6 first drained value", dout6, 8'h00);
        do_cycle6(1'b0, 1'b1, 8'h00);
        check_byte("dut6 second drained value", dout6, 8'h01);

        // Write 2 more (values 6, 7) — wr_ptr must wrap from 5 back to 0,
        // not to nonexistent slots 6/7.
        do_cycle6(1'b1, 1'b0, 8'h06);
        do_cycle6(1'b1, 1'b0, 8'h07);
        check_bit("dut6 full again after wraparound writes", full6, 1'b1);

        // Drain everything and confirm FIFO order held across the wrap:
        // remaining order should be 2,3,4,5,6,7.
        expected_val = 8'h02;
        for (i = 0; i < 6; i = i + 1) begin
            do_cycle6(1'b0, 1'b1, 8'h00);
            check_byte("dut6 post-wrap drain order", dout6, expected_val);
            expected_val = expected_val + 8'h01;
        end
        check_bit("dut6 empty after full drain", empty6, 1'b1);
        do_cycle6(1'b0, 1'b0, 8'h00);
        end_scenario;
    end
    endtask

    /* verilator lint_on WIDTHEXPAND */

endmodule
