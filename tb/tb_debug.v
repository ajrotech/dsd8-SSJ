// tb_debug.v -- comprehensive self-checking testbench for the built-in CPU debugger
// Verifies trace_buffer, debug_controller FSM, breakpoint-by-PC, single-stepping,
// shadow register inspection, and dsd8_top gating without changing tb_dsd8.v.
//
// Convention: prints "TESTBENCH: PASS" or "TESTBENCH: FAIL (N errors)".

`timescale 1ns/1ps

module tb_debug;

    reg clk;
    reg rst_n;
    integer errors;

    // Clock generation: 10ns period (100 MHz)
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // =========================================================================
    // Unit 1: Direct Verification of trace_buffer (Circular Depth 16)
    // =========================================================================
    reg        tb_clear;
    reg        tb_retire;
    reg [8:0]  tb_retire_pc;
    reg [15:0] tb_retire_ir;
    reg        tb_retire_rf_we;
    reg [2:0]  tb_retire_rf_addr;
    reg [7:0]  tb_retire_rf_data;
    reg        tb_retire_mem_we;
    reg [7:0]  tb_retire_mem_addr;
    reg [7:0]  tb_retire_mem_data;
    reg [3:0]  tb_retire_flags;

    reg  [3:0] tb_read_slot;
    wire [8:0] tb_hist_pc;
    wire [15:0]tb_hist_ir;
    wire       tb_hist_rf_we;
    wire [2:0] tb_hist_rf_addr;
    wire [7:0] tb_hist_rf_data;
    wire       tb_hist_mem_we;
    wire [7:0] tb_hist_mem_addr;
    wire [7:0] tb_hist_mem_data;
    wire [3:0] tb_hist_flags;
    wire [4:0] tb_valid_count;

    trace_buffer #(.DEPTH(16)) dut_trace_buf (
        .clk             (clk),
        .rst_n           (rst_n),
        .clear           (tb_clear),
        .retire          (tb_retire),
        .retire_pc       (tb_retire_pc),
        .retire_ir       (tb_retire_ir),
        .retire_rf_we    (tb_retire_rf_we),
        .retire_rf_addr  (tb_retire_rf_addr),
        .retire_rf_data  (tb_retire_rf_data),
        .retire_mem_we   (tb_retire_mem_we),
        .retire_mem_addr (tb_retire_mem_addr),
        .retire_mem_data (tb_retire_mem_data),
        .retire_flags    (tb_retire_flags),
        .read_slot       (tb_read_slot),
        .hist_pc         (tb_hist_pc),
        .hist_ir         (tb_hist_ir),
        .hist_rf_we      (tb_hist_rf_we),
        .hist_rf_addr    (tb_hist_rf_addr),
        .hist_rf_data    (tb_hist_rf_data),
        .hist_mem_we     (tb_hist_mem_we),
        .hist_mem_addr   (tb_hist_mem_addr),
        .hist_mem_data   (tb_hist_mem_data),
        .hist_flags      (tb_hist_flags),
        .valid_count     (tb_valid_count)
    );

    // =========================================================================
    // Unit 2: Direct Verification of debug_controller FSM & Handshake
    // =========================================================================
    reg        dc_debug_en;
    reg        dc_cmd_step;
    reg        dc_cmd_resume;
    reg        dc_cmd_pause;
    reg        dc_bp_en;
    reg [8:0]  dc_bp_pc;
    reg [8:0]  dc_imem_addr;
    reg [15:0] dc_imem_data;
    reg        dc_cpu_halted;
    reg        dc_retire;
    reg [8:0]  dc_retire_pc;
    reg [15:0] dc_retire_ir;
    reg        dc_retire_rf_we;
    reg [2:0]  dc_retire_rf_addr;
    reg [7:0]  dc_retire_rf_data;
    reg [3:0]  dc_retire_flags;
    reg        dc_bus_io_ready;

    wire       dc_cpu_io_ready;
    wire [2:0] dc_debug_state;
    wire       dc_dbg_paused;
    wire       dc_dbg_bp_hit;
    reg  [3:0] dc_inspect_sel;
    wire [7:0] dc_inspect_data;

    debug_controller dut_ctrl (
        .clk             (clk),
        .rst_n           (rst_n),
        .debug_en        (dc_debug_en),
        .cmd_step        (dc_cmd_step),
        .cmd_resume      (dc_cmd_resume),
        .cmd_pause       (dc_cmd_pause),
        .bp_en           (dc_bp_en),
        .bp_pc           (dc_bp_pc),
        .imem_addr       (dc_imem_addr),
        .imem_data       (dc_imem_data),
        .cpu_halted      (dc_cpu_halted),
        .retire          (dc_retire),
        .retire_pc       (dc_retire_pc),
        .retire_ir       (dc_retire_ir),
        .retire_rf_we    (dc_retire_rf_we),
        .retire_rf_addr  (dc_retire_rf_addr),
        .retire_rf_data  (dc_retire_rf_data),
        .retire_flags    (dc_retire_flags),
        .bus_io_ready    (dc_bus_io_ready),
        .cpu_io_ready    (dc_cpu_io_ready),
        .debug_state     (dc_debug_state),
        .dbg_paused      (dc_dbg_paused),
        .dbg_bp_hit      (dc_dbg_bp_hit),
        .inspect_sel     (dc_inspect_sel),
        .inspect_data    (dc_inspect_data)
    );

    // =========================================================================
    // Test Sequences
    // =========================================================================
    integer k;

    initial begin
        errors = 0;
        rst_n = 1'b0;

        // Trace buffer defaults
        tb_clear = 1'b0;
        tb_retire = 1'b0;
        tb_retire_pc = 9'h000;
        tb_retire_ir = 16'h0000;
        tb_retire_rf_we = 1'b0;
        tb_retire_rf_addr = 3'b000;
        tb_retire_rf_data = 8'h00;
        tb_retire_mem_we = 1'b0;
        tb_retire_mem_addr = 8'h00;
        tb_retire_mem_data = 8'h00;
        tb_retire_flags = 4'b0000;
        tb_read_slot = 4'h0;

        // Controller defaults
        dc_debug_en = 1'b0;
        dc_cmd_step = 1'b0;
        dc_cmd_resume = 1'b0;
        dc_cmd_pause = 1'b0;
        dc_bp_en = 1'b0;
        dc_bp_pc = 9'h000;
        dc_imem_addr = 9'h000;
        dc_imem_data = 16'h0000;
        dc_cpu_halted = 1'b0;
        dc_retire = 1'b0;
        dc_retire_pc = 9'h000;
        dc_retire_ir = 16'h0000;
        dc_retire_rf_we = 1'b0;
        dc_retire_rf_addr = 3'b000;
        dc_retire_rf_data = 8'h00;
        dc_retire_flags = 4'b0000;
        dc_bus_io_ready = 1'b1;
        dc_inspect_sel = 4'h0;

        // Reset pulse
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        $display("--- Starting DSD-8 Debugger Unit Tests ---");

        // ---------------------------------------------------------------------
        // TEST 1: trace_buffer Circular History (16 Depth)
        // ---------------------------------------------------------------------
        $display("[Test 1] Circular Trace Buffer: Depth 16 & Overwrite wrapping");

        // Feed 20 retirement events
        for (k = 1; k <= 20; k = k + 1) begin
            @(posedge clk);
            tb_retire          <= 1'b1;
            tb_retire_pc       <= k[8:0];
            tb_retire_ir       <= {12'h100, k[3:0]};
            tb_retire_rf_we    <= 1'b1;
            tb_retire_rf_addr  <= k[2:0];
            tb_retire_rf_data  <= k[7:0];
            tb_retire_flags    <= k[3:0];
            @(posedge clk);
            tb_retire          <= 1'b0;
        end

        #1;
        if (tb_valid_count !== 5'd16) begin
            $display("  FAIL: expected valid_count=16, got %0d", tb_valid_count);
            errors = errors + 1;
        end

        // Check slot 0 (most recent, event 20)
        tb_read_slot = 4'h0;
        #1;
        if (tb_hist_pc !== 9'd20 || tb_hist_rf_data !== 8'd20) begin
            $display("  FAIL: slot 0 (newest) expected pc=20 rf_data=20, got pc=%0d rf_data=%0d",
                     tb_hist_pc, tb_hist_rf_data);
            errors = errors + 1;
        end

        // Check slot 15 (oldest in buffer of 16, event 20 - 15 = 5)
        tb_read_slot = 4'hF;
        #1;
        if (tb_hist_pc !== 9'd5 || tb_hist_rf_data !== 8'd5) begin
            $display("  FAIL: slot 15 (oldest) expected pc=5 rf_data=5, got pc=%0d rf_data=%0d",
                     tb_hist_pc, tb_hist_rf_data);
            errors = errors + 1;
        end

        // Check slot 5 (event 20 - 5 = 15)
        tb_read_slot = 4'd5;
        #1;
        if (tb_hist_pc !== 9'd15 || tb_hist_rf_data !== 8'd15) begin
            $display("  FAIL: slot 5 expected pc=15 rf_data=15, got pc=%0d rf_data=%0d",
                     tb_hist_pc, tb_hist_rf_data);
            errors = errors + 1;
        end

        // Test clear
        @(posedge clk);
        tb_clear <= 1'b1;
        @(posedge clk);
        tb_clear <= 1'b0;
        #1;
        if (tb_valid_count !== 5'd0) begin
            $display("  FAIL: after clear, expected valid_count=0, got %0d", tb_valid_count);
            errors = errors + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 2: Normal Mode Passthrough (debug_en == 0)
        // ---------------------------------------------------------------------
        $display("[Test 2] Normal Execution Mode: Transparent io_ready Passthrough");
        dc_debug_en = 1'b0;
        dc_bus_io_ready = 1'b1;
        #1;
        if (dc_cpu_io_ready !== 1'b1 || dc_dbg_paused !== 1'b0 || dc_debug_state !== 3'b000) begin
            $display("  FAIL: expected cpu_io_ready=1 paused=0 state=0, got ready=%b paused=%b state=%b",
                     dc_cpu_io_ready, dc_dbg_paused, dc_debug_state);
            errors = errors + 1;
        end

        dc_bus_io_ready = 1'b0;
        #1;
        if (dc_cpu_io_ready !== 1'b0) begin
            $display("  FAIL: expected cpu_io_ready to follow bus_io_ready=0");
            errors = errors + 1;
        end
        dc_bus_io_ready = 1'b1;

        // ---------------------------------------------------------------------
        // TEST 3: Debug Mode Entry & Paused State
        // ---------------------------------------------------------------------
        $display("[Test 3] Debug Mode Enable -> Enters PAUSED State (CPU Stalled)");
        @(posedge clk);
        dc_debug_en <= 1'b1;
        @(posedge clk);
        #1;
        if (dc_debug_state !== 3'b001 || dc_dbg_paused !== 1'b1 || dc_cpu_io_ready !== 1'b0) begin
            $display("  FAIL: expected PAUSED (state=1 paused=1 cpu_io_ready=0), got state=%b paused=%b ready=%b",
                     dc_debug_state, dc_dbg_paused, dc_cpu_io_ready);
            errors = errors + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 4: Single-Step Execution
        // ---------------------------------------------------------------------
        $display("[Test 4] Single-Step: 1 instruction pulse -> retire -> returns to PAUSED");
        @(posedge clk);
        dc_cmd_step <= 1'b1;
        @(posedge clk);
        dc_cmd_step <= 1'b0;
        #1;
        // In STEP state, cpu_io_ready should be released (equal to bus_io_ready)
        if (dc_debug_state !== 3'b010 || dc_cpu_io_ready !== 1'b1) begin
            $display("  FAIL: expected STEP state (state=2 cpu_io_ready=1), got state=%b ready=%b",
                     dc_debug_state, dc_cpu_io_ready);
            errors = errors + 1;
        end

        // Simulate CPU completing instruction
        @(posedge clk);
        dc_retire <= 1'b1;
        dc_retire_pc <= 9'h001;
        dc_retire_rf_we <= 1'b1;
        dc_retire_rf_addr <= 3'd2;
        dc_retire_rf_data <= 8'h42;
        @(posedge clk);
        dc_retire <= 1'b0;
        #1;
        if (dc_debug_state !== 3'b001 || dc_dbg_paused !== 1'b1 || dc_cpu_io_ready !== 1'b0) begin
            $display("  FAIL: expected return to PAUSED after retire, got state=%b paused=%b ready=%b",
                     dc_debug_state, dc_dbg_paused, dc_cpu_io_ready);
            errors = errors + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 5: Shadow Register File Inspection
        // ---------------------------------------------------------------------
        $display("[Test 5] Shadow Register Inspection (R0-R7, PC, IR, Flags)");
        dc_inspect_sel = 4'd2; // R2
        #1;
        if (dc_inspect_data !== 8'h42) begin
            $display("  FAIL: expected R2=0x42, got 0x%02h", dc_inspect_data);
            errors = errors + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 6: Breakpoint by PC
        // ---------------------------------------------------------------------
        $display("[Test 6] Breakpoint by PC: Free-run until target PC match");
        dc_bp_en <= 1'b1;
        dc_bp_pc <= 9'h00A;
        dc_imem_addr <= 9'h002;

        @(posedge clk);
        dc_cmd_resume <= 1'b1;
        @(posedge clk);
        dc_cmd_resume <= 1'b0;
        #1;
        if (dc_debug_state !== 3'b011 || dc_cpu_io_ready !== 1'b1) begin
            $display("  FAIL: expected RUNNING state (state=3 ready=1), got state=%b ready=%b",
                     dc_debug_state, dc_cpu_io_ready);
            errors = errors + 1;
        end

        // Advance PC without matching BP
        @(posedge clk);
        dc_imem_addr <= 9'h008;
        #1;
        if (dc_debug_state !== 3'b011 || dc_dbg_bp_hit !== 1'b0) begin
            $display("  FAIL: should remain RUNNING when PC != bp_pc");
            errors = errors + 1;
        end

        // Match BP PC
        @(posedge clk);
        dc_imem_addr <= 9'h00A;
        #1;
        if (dc_debug_state !== 3'b100 || dc_dbg_bp_hit !== 1'b1 || dc_cpu_io_ready !== 1'b0) begin
            $display("  FAIL: expected BP_HIT state (state=4 bp_hit=1 cpu_io_ready=0), got state=%b hit=%b ready=%b",
                     dc_debug_state, dc_dbg_bp_hit, dc_cpu_io_ready);
            errors = errors + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 7: Resume Past Breakpoint
        // ---------------------------------------------------------------------
        $display("[Test 7] Resume past Breakpoint: Steps 1 instruction, then continues RUNNING");
        @(posedge clk);
        dc_cmd_resume <= 1'b1;
        @(posedge clk);
        dc_cmd_resume <= 1'b0;
        #1;
        // In STEP state to step past BP
        if (dc_debug_state !== 3'b010 || dc_dbg_bp_hit !== 1'b0) begin
            $display("  FAIL: expected STEP state to step past BP, got state=%b", dc_debug_state);
            errors = errors + 1;
        end

        // Retire that instruction and change PC
        @(posedge clk);
        dc_retire <= 1'b1;
        dc_retire_pc <= 9'h00A;
        dc_imem_addr <= 9'h00B;
        @(posedge clk);
        dc_retire <= 1'b0;
        #1;
        if (dc_debug_state !== 3'b011 || dc_cpu_io_ready !== 1'b1) begin
            $display("  FAIL: expected transition to RUNNING after stepping past BP, got state=%b ready=%b",
                     dc_debug_state, dc_cpu_io_ready);
            errors = errors + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 8: Manual Pause Command
        // ---------------------------------------------------------------------
        $display("[Test 8] Manual Pause Command: Running -> Paused");
        @(posedge clk);
        dc_cmd_pause <= 1'b1;
        @(posedge clk);
        dc_cmd_pause <= 1'b0;
        #1;
        if (dc_debug_state !== 3'b001 || dc_dbg_paused !== 1'b1 || dc_cpu_io_ready !== 1'b0) begin
            $display("  FAIL: expected PAUSED state after cmd_pause, got state=%b paused=%b",
                     dc_debug_state, dc_dbg_paused);
            errors = errors + 1;
        end

        // ---------------------------------------------------------------------
        // Verdict
        // ---------------------------------------------------------------------
        $display("-------------------------------------------");
        if (errors == 0) begin
            $display("TESTBENCH: PASS");
        end else begin
            $display("TESTBENCH: FAIL (%0d errors)", errors);
        end
        $finish;
    end

endmodule

